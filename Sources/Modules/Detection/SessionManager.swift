import Foundation
import Combine

/// AI 대화(Chat / Thread / Context Window) 단위의 세션 생명주기 관리자
/// - 규칙: open → close가 하나의 세션.
/// - 그 사이 비활성화(unfocus)되면 누적시간이 일시중지되고, 다시 활성화(focus)되면 누적시간을 이어서 계산합니다.
public final class SessionManager: ObservableObject {
    public static let shared = SessionManager()

    /// 등록된 모든 AI 대화 세션 목록 (최신 활동 순)
    @Published public private(set) var sessions: [AISession] = []

    /// 현재 활성(focus) 상태인 세션 ID (없으면 nil)
    @Published public private(set) var activeFocusedSessionId: UUID? = nil

    private var previousEventTime: Date = Date()
    private var tickerTimer: Timer?

    private init() {
        startTicker()
    }

    // MARK: - 편의 조회 프로퍼티
    /// 현재 열려 있는 (종료되지 않은) 활성 세션 목록
    public var activeSessions: [AISession] {
        sessions.filter { $0.state != .close }
    }

    /// 종료된 세션 목록
    public var closedSessions: [AISession] {
        sessions.filter { $0.state == .close }
    }

    /// 현재 사용자가 화면을 보고 대화 중인 세션
    public var focusedSession: AISession? {
        guard let id = activeFocusedSessionId else { return nil }
        return sessions.first(where: { $0.sessionId == id && $0.state == .focus })
    }

    /// 하위 호환용 프로퍼티
    public var currentSession: AISession? {
        focusedSession ?? activeSessions.first
    }

    // MARK: - 1. 핵심 활동 이벤트 처리 (open, close, navigate, idle_start, idle_end, suspend, resume)
    public func processEvent(_ event: inout ActivityEvent) {
        let now = event.timestamp
        let elapsed = max(0, now.timeIntervalSince(previousEventTime))
        previousEventTime = now

        // 시스템 중단 (suspend), 유휴 시작 (idleStart): 활성 세션 포커스 일시중지 및 사이 작업 기록
        if event.eventType == .suspend || event.eventType == .idleStart || event.eventType == .appDeactivated {
            if let activeId = activeFocusedSessionId {
                event.sessionId = activeId
                unfocusSession(withId: activeId, now: now, elapsed: elapsed)
                activeFocusedSessionId = nil
            }
            if event.eventType == .suspend || event.eventType == .idleStart {
                recordInterleavingActivity(event: event, now: now, elapsed: elapsed)
            }
            updateAppState()
            return
        }

        // 포커스 이탈 (.focusOut) - 하위 호환
        if event.eventType == .focusOut {
            if let activeId = activeFocusedSessionId {
                event.sessionId = activeId
                unfocusSession(withId: activeId, now: now, elapsed: elapsed)
                activeFocusedSessionId = nil
            }
            recordInterleavingActivity(event: event, now: now, elapsed: elapsed)
            updateAppState()
            return
        }

        // 세션 종료 / 창 종료 (.close: 이벤트 로그에는 앱/창 종료 기록, AI 세션은 close 상태로 보존)
        if event.eventType == .close {
            if event.isAI {
                // AI 앱/창/탭 종료: AI 세션을 close(보존 대기)로 전환
                // 일시중지 누적 시간(accumulatedUnfocusedDuration)에 앱/창이 닫힌 이후 시간이 합산되지 않도록 정지
                // 세션 데이터 및 누적 집중 시간(accumulatedFocusedDuration)은 영구 보존됨
                if let activeId = activeFocusedSessionId {
                    event.sessionId = activeId
                    closeSession(withId: activeId, now: now, detail: "창/탭 닫힘 — 세션 보존", skipStoreEvent: true)
                    activeFocusedSessionId = nil
                } else if let threadKey = event.threadKey,
                          let idx = sessions.firstIndex(where: { $0.threadKey == threadKey && $0.state != .close }) {
                    event.sessionId = sessions[idx].sessionId
                    closeSession(withId: sessions[idx].sessionId, now: now, detail: "창/탭 닫힘 — 세션 보존", skipStoreEvent: true)
                }
            } else {
                // 비AI 앱/창 종료: 현재 열려있는 대화 세션의 사이 작업 내역(close)으로 기록
                recordInterleavingActivity(event: event, now: now, elapsed: elapsed)
            }
            updateAppState()
            return
        }

        if event.isAI {
            // AI 활동 발생: 해당 대화 스레드 식별
            let (threadKey, title) = resolveThread(for: event)
            event.threadKey = threadKey
            event.threadTitle = title

            handleAITrigger(threadKey: threadKey, title: title, event: &event, now: now, elapsed: elapsed)
        } else {
            // 비AI 활동 발생 (브라우저 일반 서핑, 타 앱 전환, 입력 복귀, 절전 해제 등)
            handleNonAITrigger(event: &event, now: now, elapsed: elapsed)
        }

        updateAppState()
    }

    // MARK: - 2. AI 스레드 이벤트 분기 (focus_in, navigate)
    private func handleAITrigger(
        threadKey: String,
        title: String,
        event: inout ActivityEvent,
        now: Date,
        elapsed: TimeInterval
    ) {
        // 기존 대화(열려 있거나 창/앱이 닫혀 보존된 세션 모두 포함) 검색
        if let index = sessions.firstIndex(where: { $0.threadKey == threadKey }) {
            let previousState = sessions[index].state

            // 이전 포커스 세션이 다른 세션이었다면, 이전 세션을 unfocus로 전이 (누적시간 일시중지)
            if let activeId = activeFocusedSessionId, activeId != sessions[index].sessionId {
                unfocusSession(withId: activeId, now: now, elapsed: elapsed)
            }

            if previousState == .close {
                // [보존된 세션 재개: 창 다시 열림, 앱 다시 실행]
                // 앱/창이 닫혀 있던 시간은 일시중지 누적 시간에 합산하지 않고, 즉시 focus_in으로 전환하여 기존 집중 누적 시간에 이어서 계산
                sessions[index].state = .focusIn
                sessions[index].closedAt = nil
                sessions[index].lastStateChangedAt = now
                sessions[index].lifecycleHistory.append(
                    SessionLifecycleNode(timestamp: now, state: .focusIn, detail: "대화 세션 재개 (\(event.eventType.rawValue))")
                )
                if event.eventType != .navigate {
                    event.eventType = .focusIn
                }

                // 가장 최근 활동 세션을 상단으로 이동
                let resumedSession = sessions.remove(at: index)
                sessions.insert(resumedSession, at: 0)

                activeFocusedSessionId = resumedSession.sessionId
                event.sessionId = resumedSession.sessionId
            } else if previousState != .focusIn {
                // focus_out -> focus_in 상태 전이: 활성화되면 누적시간 이어서 계산
                sessions[index].state = .focusIn
                let unfocusedSpan = max(0, now.timeIntervalSince(sessions[index].lastStateChangedAt))
                sessions[index].accumulatedUnfocusedDuration += unfocusedSpan
                sessions[index].lastStateChangedAt = now
                sessions[index].lifecycleHistory.append(
                    SessionLifecycleNode(timestamp: now, state: .focusIn, detail: "대화로 복귀 (\(event.eventType.rawValue))")
                )
                if event.eventType != .navigate {
                    event.eventType = .focusIn
                }

                activeFocusedSessionId = sessions[index].sessionId
                event.sessionId = sessions[index].sessionId
            } else {
                // 이미 focus 상태 유지 중: 누적시간 가산
                sessions[index].accumulatedFocusedDuration += elapsed
                if event.eventType != .navigate {
                    event.eventType = .focusIn
                }

                activeFocusedSessionId = sessions[index].sessionId
                event.sessionId = sessions[index].sessionId
            }

            if !title.isEmpty && title != "새 대화" {
                if let curIdx = sessions.firstIndex(where: { $0.sessionId == event.sessionId }) {
                    sessions[curIdx].title = title
                }
            }
        } else {
            // [완전 신규 AI 대화 진입 / 세션 생성: open 이벤트 기록 후 focus_in으로 전환]
            if let activeId = activeFocusedSessionId {
                unfocusSession(withId: activeId, now: now, elapsed: elapsed)
            }

            let newSessionId = UUID()
            let newSession = AISession(
                sessionId: newSessionId,
                threadKey: threadKey,
                title: title,
                toolName: event.aiTool ?? "AI",
                appName: event.appName,
                url: event.url,
                state: .focusIn, // 열리면서 즉시 포커스
                openedAt: now,
                closedAt: nil,
                accumulatedFocusedDuration: 0,
                accumulatedUnfocusedDuration: 0,
                lastStateChangedAt: now,
                lifecycleHistory: [
                    SessionLifecycleNode(timestamp: now, state: .open, detail: "새로운 대화 시작 (open)"),
                    SessionLifecycleNode(timestamp: now, state: .focusIn, detail: "대화 포커스 활성화 (focus_in)")
                ],
                interleavingActivities: []
            )

            sessions.insert(newSession, at: 0)
            activeFocusedSessionId = newSessionId
            LocalDatabase.shared.recordSession(newSession)

            // AI 세션 시작 직후 설문 스케줄러 통지 (start 팝업 및 mid 타이머 등록)
            SurveyScheduler.shared.handleSessionStarted(newSession)

            // 새 AI 대화 진입 시: 새 창/탭 생성과 동일하게 open 이벤트 발행
            if event.eventType == .open {
                // 이미 open 이벤트인 경우 (새 창/새 탭/앱 최초 실행 등)
                event.sessionId = newSessionId
                event.duration = nil
            } else {
                // focus_in이나 navigate 등으로 신규 대화에 진입한 경우:
                // 새로운 창/탭/문서 생성과 마찬가지로 먼저 open 이벤트를 로그에 기록하고, 현재 이벤트는 focus_in으로 전환
                var openEvent = event
                openEvent.eventType = .open
                openEvent.sessionId = newSessionId
                openEvent.duration = nil
                let openTitle = (title.isEmpty || title == "새 대화") ? "\(event.aiTool ?? "AI") 새 대화 시작" : "새 대화 시작: \(title)"
                openEvent.windowTitle = openTitle
                openEvent.navType = "new_session"
                DebugLogStore.shared.addEvent(openEvent)
                LocalDatabase.shared.recordActivityEvent(openEvent)

                event.eventType = .focusIn
                event.sessionId = newSessionId
                event.duration = nil
            }
        }
    }

    // MARK: - 3. 비AI 활동 처리 (사이 작업 기록 및 unfocus 전이)
    private func handleNonAITrigger(
        event: inout ActivityEvent,
        now: Date,
        elapsed: TimeInterval
    ) {
        // 활성 AI 세션이 있었다면 focus_out으로 전환 (누적시간 일시중지)
        if let activeId = activeFocusedSessionId {
            unfocusSession(withId: activeId, now: now, elapsed: elapsed)
            activeFocusedSessionId = nil
        }

        recordInterleavingActivity(event: event, now: now, elapsed: elapsed)
        if let mostRecent = activeSessions.first {
            event.sessionId = mostRecent.sessionId
        }
    }

    /// 대화 세션별 타임라인의 '사이 작업 내역'에 7대 표준 라벨(navigate, open, close, idle, suspend 등)로 기록
    private func recordInterleavingActivity(
        event: ActivityEvent,
        now: Date,
        elapsed: TimeInterval
    ) {
        guard let mostRecent = activeSessions.first, let idx = sessions.firstIndex(where: { $0.sessionId == mostRecent.sessionId }) else {
            return
        }

        let displayTarget: String = {
            if let from = event.fromApp, let to = event.toApp, from != to {
                if let toTitle = event.toTitle, !toTitle.isEmpty && toTitle != to {
                    return "\(from) ➔ \(to) (\(toTitle))"
                }
                return "\(from) ➔ \(to)"
            }
            if let url = event.url, !url.isEmpty {
                return url
            }
            return event.windowTitle.isEmpty ? event.appName : event.windowTitle
        }()

        let duration = event.duration ?? (event.idleDuration ?? (event.suspendDuration ?? elapsed))
        let actionCode = event.eventType.code

        let item = InterleavingActivity(
            timestamp: now,
            appName: event.appName,
            titleOrURL: displayTarget,
            duration: duration,
            action: actionCode,
            environment: event.environmentCategory.badgeLabel
        )
        sessions[idx].interleavingActivities.append(item)
        sessions[idx].accumulatedUnfocusedDuration += elapsed
    }

    private func unfocusSession(withId sessionId: UUID, now: Date, elapsed: TimeInterval, detail: String = "대화 일시중지 (다른 작업으로 전환)") {
        guard let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) else { return }
        if sessions[index].state == .focusIn {
            sessions[index].state = .focusOut
            sessions[index].accumulatedFocusedDuration += elapsed
            let span = max(0, now.timeIntervalSince(sessions[index].lastStateChangedAt))
            sessions[index].lifecycleHistory.append(
                SessionLifecycleNode(timestamp: now, state: .focusOut, duration: span, detail: detail)
            )
            sessions[index].lastStateChangedAt = now
            // 중복 이벤트 방지: 통합 로그(DebugLogStore)의 focus_out은 ActivityDetector가 단일 창구로 발행함
            LocalDatabase.shared.recordSession(sessions[index])
        }
    }

    // MARK: - 4. 세션 종료 / 보존 (close: 창 닫기, 탭 닫기, 앱 종료 시 세션 보존)
    public func closeSession(withId sessionId: UUID, now: Date = Date(), detail: String = "대화 세션 보존 (창/앱 닫힘)", skipStoreEvent: Bool = false) {
        guard let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) else { return }
        guard sessions[index].state != .close else { return }

        let previousState = sessions[index].state
        let span = max(0, now.timeIntervalSince(sessions[index].lastStateChangedAt))

        if previousState == .focusIn {
            sessions[index].accumulatedFocusedDuration += span
        } else if previousState == .focusOut {
            sessions[index].accumulatedUnfocusedDuration += span
        }

        sessions[index].state = .close
        sessions[index].closedAt = now
        sessions[index].lastStateChangedAt = now
        sessions[index].lifecycleHistory.append(
            SessionLifecycleNode(timestamp: now, state: .close, duration: span, detail: detail)
        )

        let closedSession = sessions[index]
        LocalDatabase.shared.recordSession(closedSession)

        // AI 세션 종료 직후 설문 스케줄러 통지 (end 팝업 및 mid 타이머 해제)
        SurveyScheduler.shared.handleSessionEnded(closedSession)

        if activeFocusedSessionId == sessionId {
            activeFocusedSessionId = nil
        }

        // close 이벤트 로깅 (단독 호출 시에만 기록, emitEvent 경유 시 중복 방지)
        if !skipStoreEvent {
            let closeEvt = ActivityEvent(
                timestamp: now,
                eventType: .close,
                appName: sessions[index].appName,
                bundleId: sessions[index].threadKey,
                windowTitle: "대화 세션 보존: \(sessions[index].title)",
                url: sessions[index].url,
                isAI: true,
                aiTool: sessions[index].toolName,
                threadKey: sessions[index].threadKey,
                threadTitle: sessions[index].title,
                sessionId: sessionId
            )
            DebugLogStore.shared.addEvent(closeEvt)
            LocalDatabase.shared.recordActivityEvent(closeEvt)
        }

        updateAppState()
    }

    /// 특정 앱이 완전히 종료되었을 때 (Cmd+Q 등):
    /// 앱 종료 시 해당 앱의 AI 세션들을 close(보존 대기) 상태로 전환하여 일시중지 누적 시간 증가를 정지하고 세션 영구 보존
    public func handleAppTerminated(bundleId: String) {
        let bLower = bundleId.lowercased()
        let now = Date()

        for session in activeSessions {
            let sApp = session.appName.lowercased()
            let sKey = session.threadKey.lowercased()

            // 데스크톱 AI 앱 (Antigravity, Cursor, Claude 등)
            let isDesktopAppMatch = sKey.contains(bLower) || bLower.contains(sApp) || sApp.contains(bLower)

            // 브라우저 앱 (Chrome, Safari, Dia, Arc 등)
            let isBrowserMatch = Config.Detection.supportedBrowsers.keys.contains(bundleId) &&
                (sApp.contains("chrome") || sApp.contains("safari") || sApp.contains("edge") || sApp.contains("arc") || sApp.contains("brave") || sApp.contains("dia") || session.url != nil)

            if isDesktopAppMatch || isBrowserMatch {
                closeSession(withId: session.sessionId, now: now, detail: "앱 일시 종료 (Cmd+Q) — 세션 보존", skipStoreEvent: true)
            }
        }

        if let activeId = activeFocusedSessionId,
           let activeSession = sessions.first(where: { $0.sessionId == activeId }) {
            let sApp = activeSession.appName.lowercased()
            let sKey = activeSession.threadKey.lowercased()
            if sKey.contains(bLower) || bLower.contains(sApp) || sApp.contains(bLower) ||
               (Config.Detection.supportedBrowsers.keys.contains(bundleId) && (sApp.contains("chrome") || sApp.contains("safari") || sApp.contains("dia") || activeSession.url != nil)) {
                activeFocusedSessionId = nil
            }
        }

        updateAppState()
    }

    // MARK: - 5. 스레드 식별 헬퍼 (웹, 앱, 터미널, IDE 작업공간 구별)
    private func resolveThread(for event: ActivityEvent) -> (threadKey: String, title: String) {
        if let key = event.threadKey, !key.isEmpty {
            return (key, event.threadTitle ?? event.windowTitle)
        }

        if let url = event.url, !url.isEmpty {
            let (threadKey, threadTitle) = BrowserTracker.shared.extractThreadInfo(
                url: url,
                rawTitle: event.windowTitle,
                isAI: event.isAI,
                aiTool: event.aiTool
            )
            if let key = threadKey {
                return (key, threadTitle ?? event.windowTitle)
            }
        }

        let appKey = event.bundleId
        let rawTitle = event.windowTitle

        // 데스크톱 IDE (Antigravity IDE, Cursor, VS Code 등) 작업공간 단위 분리
        // 예: "LogSystem_Test2_Mac — ActivityEvent.swift" -> 작업공간: "LogSystem_Test2_Mac"
        let isIDE = event.bundleId.contains("antigravity") ||
                    event.bundleId.contains("cursor") ||
                    event.bundleId.contains("VSCode") ||
                    (event.appName.lowercased().contains("antigravity")) ||
                    (event.appName.lowercased().contains("cursor")) ||
                    (event.aiTool?.lowercased().contains("antigravity") == true)

        if isIDE {
            if rawTitle.isEmpty {
                let winSuffix = event.windowId != nil ? "_\(event.windowId!)" : ""
                let key = "\(appKey)_new_window\(winSuffix)"
                let title = "새 작업공간 (\(event.aiTool ?? event.appName))"
                return (key, title)
            }

            var clean = rawTitle
            if clean.hasPrefix("새 창·문서 생성: ") {
                clean = String(clean.dropFirst("새 창·문서 생성: ".count))
            }
            if clean.hasPrefix("● ") { clean.removeFirst(2) }
            if clean.hasPrefix("* ") { clean.removeFirst(2) }

            let separators = [" — ", " – ", " - "]
            var matchedWorkspace: String?

            for sep in separators {
                if clean.contains(sep) {
                    let parts = clean.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if parts.count >= 2 {
                        let p1 = parts[0]
                        let p2 = parts[1]
                        let fileExtensions = [".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".json", ".md", ".html", ".css", ".rs", ".go", ".c", ".cpp", ".h", ".m", ".sh"]
                        let p2IsFile = fileExtensions.contains { p2.hasSuffix($0) }
                        let p1IsFile = fileExtensions.contains { p1.hasSuffix($0) }

                        if p2IsFile && !p1IsFile {
                            matchedWorkspace = p1
                        } else if p1IsFile && !p2IsFile {
                            matchedWorkspace = p2
                        } else {
                            matchedWorkspace = p1
                        }
                        break
                    }
                }
            }

            if let ws = matchedWorkspace {
                // 이 창(windowId)에서 이전에 열린 임시 "새 작업공간" 세션이 있다면 해당 세션을 새 프로젝트 워크스페이스로 승격
                if let wid = event.windowId {
                    let tempKey = "\(appKey)_new_window_\(wid)"
                    if let tempIdx = sessions.firstIndex(where: { $0.threadKey == tempKey }) {
                        sessions[tempIdx].threadKey = "\(appKey)_\(ws)"
                        sessions[tempIdx].title = ws
                    }
                }
                let key = "\(appKey)_\(ws)"
                return (key, ws)
            }

            // 워크스페이스 분리자가 없는 단일 제목 처리 (예: "Antigravity IDE", "Welcome", "새 작업공간")
            let cleanLower = clean.lowercased()
            let isGenericAppTitle = cleanLower == event.appName.lowercased() ||
                                    cleanLower == (event.aiTool?.lowercased() ?? "") ||
                                    cleanLower.contains("antigravity") ||
                                    cleanLower.contains("cursor") ||
                                    cleanLower.contains("visual studio code") ||
                                    cleanLower == "welcome"

            if isGenericAppTitle {
                // 프로젝트가 아직 열리지 않은 신규 창/새 세션 분리 (고유 windowId 연동)
                let winSuffix = event.windowId != nil ? "_\(event.windowId!)" : ""
                let key = "\(appKey)_new_window\(winSuffix)"
                let title = "새 작업공간 (\(event.aiTool ?? event.appName))"
                return (key, title)
            } else {
                let key = "\(appKey)_\(clean)"
                return (key, clean)
            }
        }

        let titleKey = event.windowTitle.isEmpty ? (event.aiTool ?? "Default") : event.windowTitle
        let key = "\(appKey)_\(titleKey)"
        return (key, titleKey)
    }

    // MARK: - 6. 수동 제어 및 테스트 헬퍼
    public func startNewChat(toolName: String = "Claude", title: String = "새 연구 질문") {
        let fakeKey = "custom_\(toolName.lowercased())_\(UUID().uuidString.prefix(6))"
        var dummy = ActivityEvent(
            eventType: .focusIn,
            appName: toolName,
            bundleId: "com.anthropic.claudefordesktop",
            windowTitle: title,
            isAI: true,
            aiTool: toolName,
            threadKey: fakeKey,
            threadTitle: title
        )
        processEvent(&dummy)
        DebugLogStore.shared.addEvent(dummy)
    }

    public func clearAllSessions() {
        sessions.removeAll()
        activeFocusedSessionId = nil
        updateAppState()
    }

    // MARK: - 7. 1초 주기 타이머: 포커스 세션 누적시간 실시간 증가
    private func startTicker() {
        tickerTimer?.invalidate()
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            if let activeId = self.activeFocusedSessionId,
               let idx = self.sessions.firstIndex(where: { $0.sessionId == activeId && $0.state == .focus }) {
                let delta = max(0, now.timeIntervalSince(self.sessions[idx].lastStateChangedAt))
                self.sessions[idx].accumulatedFocusedDuration += delta
                self.sessions[idx].lastStateChangedAt = now
                self.updateAppState()
            }
        }
    }

    private func updateAppState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let focused = self.focusedSession {
                AppState.shared.activeSessionAppNames = "● \(focused.toolName) · \(focused.title)"
                AppState.shared.activeSessionDurationString = focused.formattedFocusedDuration
            } else if !self.activeSessions.isEmpty {
                AppState.shared.activeSessionAppNames = "대기 (\(self.activeSessions.count)개 세션)"
                AppState.shared.activeSessionDurationString = nil
            } else if !self.closedSessions.isEmpty {
                AppState.shared.activeSessionAppNames = "보존됨 (\(self.closedSessions.count)개 세션)"
                AppState.shared.activeSessionDurationString = nil
            } else {
                AppState.shared.activeSessionAppNames = nil
                AppState.shared.activeSessionDurationString = nil
            }
        }
    }
}
