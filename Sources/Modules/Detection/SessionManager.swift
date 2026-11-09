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

    /// 사용자가 메뉴바에서 명시적으로 "새 작업 시작 / 세션 종료"를 눌러 종료된 세션 ID 목록
    /// (이 세션들은 같은 URL/대화명이더라도 재개하지 않고 완전히 새로운 세션으로 분리)
    public private(set) var manualCompletedSessionIds: Set<UUID> = []

    // MARK: - 수동 시작 세션 추적 모델
    public struct ManualSessionTarget {
        public let sessionId: UUID
        public let appName: String
        public let bundleId: String
        public let windowTitle: String
        public let url: String?
        public let toolName: String

        public init(sessionId: UUID, appName: String, bundleId: String, windowTitle: String, url: String?, toolName: String) {
            self.sessionId = sessionId
            self.appName = appName
            self.bundleId = bundleId
            self.windowTitle = windowTitle
            self.url = url
            self.toolName = toolName
        }
    }

    /// 수동으로 "시작" 버튼을 눌러 개설된 활성 세션 목록 (창을 AI로 인식하지 못하더라도 사용자가 수동 시작한 경우 활성 상태 유지)
    public private(set) var manualActiveSessions: [UUID: ManualSessionTarget] = [:]

    /// 특정 창/앱이 현재 수동 시작된 활성 AI 세션인지 판별
    public func manualActiveTool(for bundleId: String, appName: String, windowTitle: String = "", url: String? = nil) -> String? {
        let bLower = bundleId.lowercased()
        let aLower = appName.lowercased()
        let wLower = windowTitle.lowercased()

        for (sid, target) in manualActiveSessions {
            guard sessions.contains(where: { $0.sessionId == sid && $0.state != .close }) else {
                continue
            }
            if let targetUrl = target.url, !targetUrl.isEmpty {
                // 웹 브라우저 기반 수동 세션: URL 또는 탭 제목이 일치할 때만 매칭
                if let u = url, !u.isEmpty {
                    if u == targetUrl || u.contains(targetUrl) || targetUrl.contains(u) {
                        return target.toolName
                    }
                }
                if !target.windowTitle.isEmpty && !wLower.isEmpty {
                    if wLower.contains(target.windowTitle.lowercased()) || target.windowTitle.lowercased().contains(wLower) {
                        return target.toolName
                    }
                }
                continue
            }

            // 데스크톱 앱 기반 수동 세션: 번들 ID, 앱 이름 또는 창 제목 매칭
            if !target.bundleId.isEmpty && !bLower.isEmpty && (target.bundleId.lowercased() == bLower || bLower.contains(target.bundleId.lowercased())) {
                return target.toolName
            }
            if !target.appName.isEmpty && !aLower.isEmpty && (target.appName.lowercased() == aLower || aLower.contains(target.appName.lowercased())) {
                return target.toolName
            }
            if !target.windowTitle.isEmpty && !wLower.isEmpty && (wLower.contains(target.windowTitle.lowercased()) || target.windowTitle.lowercased().contains(wLower)) {
                return target.toolName
            }
        }
        return nil
    }

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
            } else if let mostRecent = activeSessions.first {
                event.sessionId = mostRecent.sessionId
            }
            if event.eventType == .suspend || event.eventType == .idleStart {
                recordInterleavingActivity(event: event, now: now, elapsed: elapsed)
            }
            updateAppState()
            return
        }

        // 포커스 이탈 (.focusOut)
        if event.eventType == .focusOut {
            if let activeId = activeFocusedSessionId {
                event.sessionId = activeId
                unfocusSession(withId: activeId, now: now, elapsed: elapsed)
                activeFocusedSessionId = nil
            } else if let threadKey = event.threadKey, let idx = sessions.firstIndex(where: { $0.threadKey == threadKey }) {
                event.sessionId = sessions[idx].sessionId
            } else if let mostRecent = activeSessions.first {
                event.sessionId = mostRecent.sessionId
            }
            recordInterleavingActivity(event: event, now: now, elapsed: elapsed)
            updateAppState()
            return
        }

        // 세션 종료 / 창 종료 (.close: 이벤트 로그에는 앱/창 종료 기록, AI 세션은 close 상태로 보존)
        if event.eventType == .close {
            let isBrowser = Config.Detection.supportedBrowsers.keys.contains(event.bundleId) ||
                            event.bundleId.lowercased().contains("chrome") ||
                            event.bundleId.lowercased().contains("safari") ||
                            event.bundleId.lowercased().contains("browser") ||
                            event.bundleId.lowercased().contains("dia") ||
                            event.appName.lowercased().contains("dia") ||
                            event.appName.lowercased().contains("chrome") ||
                            event.appName.lowercased().contains("safari")

            // 0. 브라우저에서 닫힌 탭이 명시적으로 비AI 탭이거나, 인증/로그인 페이지인 경우 기존 AI 세션을 닫으면 안 됨!
            let isAuthClose = BrowserTracker.isAuthOrLoginPage(url: event.url, title: event.threadTitle ?? event.windowTitle)
            if isBrowser && (!event.isAI || isAuthClose) {
                event.sessionId = nil
                event.isAI = false
                event.aiTool = nil
                recordInterleavingActivity(event: event, now: now, elapsed: elapsed)
                updateAppState()
                return
            }

            // 1. 해당 닫기 이벤트와 매칭되는 활성 AI 세션 검색
            let targetSessionId: UUID? = {
                // (1) 포커스된 활성 AI 세션이 있고, 닫힌 앱이나 창/스레드가 해당 세션과 일치하거나 이벤트 자체가 AI인 경우
                if let activeId = activeFocusedSessionId,
                   let activeSession = sessions.first(where: { $0.sessionId == activeId && $0.state != .close }) {
                    let appMatch = activeSession.appName.lowercased() == event.appName.lowercased() ||
                                   activeSession.threadKey.lowercased().contains(event.bundleId.lowercased()) ||
                                   event.bundleId.lowercased().contains(activeSession.appName.lowercased())
                    let titleMatch = (event.threadTitle != nil && !event.threadTitle!.isEmpty && (event.threadTitle == activeSession.title || activeSession.title.contains(event.threadTitle!))) ||
                                     (!event.windowTitle.isEmpty && event.windowTitle.contains(activeSession.title))
                    if isBrowser {
                        // 웹 브라우저는 탭 기반이므로 단순히 같은 브라우저 앱이라는 이유(appMatch)만으로 활성 세션을 닫으면 안 됨!
                        // 반드시 threadKey가 일치하거나 명확한 titleMatch가 있을 때만 활성 세션 닫기
                        if (event.threadKey != nil && event.threadKey == activeSession.threadKey) || (event.isAI && titleMatch) {
                            return activeId
                        }
                    } else {
                        // 데스크톱 전용 AI 앱(ChatGPT, Claude 데스크톱 등)은 창/앱 종료 시 일치
                        if event.isAI || appMatch || titleMatch || (event.threadKey != nil && event.threadKey == activeSession.threadKey) {
                            return activeId
                        }
                    }
                }
                // (2) threadKey로 직접 매칭되는 활성 세션 검색
                if let threadKey = event.threadKey,
                   let matched = sessions.first(where: { $0.threadKey == threadKey && $0.state != .close }) {
                    return matched.sessionId
                }
                // (3) 닫힌 창/탭 제목(threadTitle 또는 windowTitle)과 일치하는 활성 세션 검색 (이벤트가 AI인 경우에만)
                if event.isAI, let tTitle = event.threadTitle, !tTitle.isEmpty,
                   let matched = sessions.first(where: { ($0.title == tTitle || tTitle.contains($0.title) || $0.title.contains(tTitle)) && $0.state != .close }) {
                    return matched.sessionId
                }
                // (4) 앱 이름이 일치하는 가장 최근 활성 세션 (단, 브라우저가 아닌 데스크톱 전용 AI 앱에만 적용!)
                if !isBrowser {
                    if let matched = activeSessions.first(where: { $0.appName.lowercased() == event.appName.lowercased() }) {
                        return matched.sessionId
                    }
                }
                // (5) 이벤트 자체가 isAI이면서 threadTitle이 일치할 때만
                if event.isAI, let t = event.threadTitle, !t.isEmpty,
                   let matched = activeSessions.first(where: { $0.title == t || t.contains($0.title) || $0.title.contains(t) }) {
                    return matched.sessionId
                }
                return nil
            }()

            if let sid = targetSessionId, let session = sessions.first(where: { $0.sessionId == sid }) {
                // AI 세션 닫힘 확정: 이벤트 속성 동기화 및 세션 보존(close) 처리
                event.sessionId = sid
                event.isAI = true
                event.aiTool = event.aiTool ?? session.toolName
                if event.threadTitle == nil || event.threadTitle!.isEmpty {
                    event.threadTitle = session.title
                }
                closeSession(withId: sid, now: now, detail: "창/탭 닫힘 — 세션 보존", skipStoreEvent: true)
                if activeFocusedSessionId == sid {
                    activeFocusedSessionId = nil
                }
            } else {
                // 비AI 앱/창 종료: 세션 ID를 AI 세션으로 매핑하지 않고 순수 비AI 작업(일반 탭/창 닫기)으로 분리
                event.sessionId = nil
                event.isAI = false
                event.aiTool = nil
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
        // [빈 대기 화면(홈/랜딩 페이지) 상태 감지]
        // 웹이나 앱을 켜기만 하고 아직 프롬프트를 입력해 대화를 시작하지 않은 빈 화면인 경우:
        // 세션을 생성하거나 설문 팝업을 띄우지 않고 대기 상태로 유지합니다.
        // 기존에 진행 중이던 세션이 있다면 세션을 닫지(close) 않고 일시중지(unfocus)로 전환하여 보존합니다.
        if isBlankStandbyAIPage(url: event.url, title: title, appName: event.appName, bundleId: event.bundleId, toolName: event.aiTool) {
            if let activeId = activeFocusedSessionId {
                unfocusSession(withId: activeId, now: now, elapsed: elapsed, detail: "대화 일시중지 (새 탭/빈 대기 화면 전환)")
                activeFocusedSessionId = nil
            }
            event.sessionId = nil
            return
        }

        // [기존 대화 세션 탐색: 3단계 다중 매칭]
        // 1순위: threadKey 완전 일치
        // 2순위: 동일 AI 도구/앱 내에서 대화 제목(Title / originalTitle) 일치 (사이드바 복귀 핵심)
        // 3순위: 웹 브라우저 URL 경로(호스트 + 고유 패스) 정규화 매칭 (쿼리, 슬래시 차이 극복)
        let cleanIncomingTitle = Self.normalizeConversationTitle(title)
        let isIncomingTitleGeneric = isGenericPlaceholderTitle(title, appName: event.appName, toolName: event.aiTool, url: event.url)

        let matchedSessionIndex: Int? = {
            // 1순위: threadKey 완전 일치 (수동 종료된 세션은 제외)
            if let idx = sessions.firstIndex(where: {
                $0.threadKey == threadKey && !(self.manualCompletedSessionIds.contains($0.sessionId) && $0.state == .close)
            }) {
                return idx
            }

            // 2순위: 동일 AI 도구/앱 내에서 대화 제목(Title) 일치 (사이드바 복귀 핵심)
            // (단, '새 대화', 'ChatGPT', 'Claude' 등 일반적인 플레이스홀더 제목은 제외)
            if !isIncomingTitleGeneric && !cleanIncomingTitle.isEmpty {
                // (2-1) 현재 열려 있는 활성 세션(activeSessions)에서 우선 검색
                if let idx = sessions.firstIndex(where: { s in
                    guard s.state != .close else { return false }
                    let appMatch = s.appName.lowercased() == event.appName.lowercased() ||
                                   (event.aiTool != nil && s.toolName.lowercased() == event.aiTool!.lowercased()) ||
                                   s.threadKey.hasPrefix(event.bundleId) ||
                                   threadKey.hasPrefix(s.appName.lowercased())
                    guard appMatch else { return false }
                    let sTitle = Self.normalizeConversationTitle(s.originalTitle ?? s.title)
                    let sRawTitle = Self.normalizeConversationTitle(s.title)
                    return sTitle == cleanIncomingTitle || sRawTitle == cleanIncomingTitle
                }) {
                    return idx
                }

                // (2-2) 보존된 세션(closedSessions)을 포함한 전체 세션에서 검색 (수동 종료된 세션은 제외)
                if let idx = sessions.firstIndex(where: { s in
                    guard !(self.manualCompletedSessionIds.contains(s.sessionId) && s.state == .close) else { return false }
                    let appMatch = s.appName.lowercased() == event.appName.lowercased() ||
                                   (event.aiTool != nil && s.toolName.lowercased() == event.aiTool!.lowercased()) ||
                                   s.threadKey.hasPrefix(event.bundleId) ||
                                   threadKey.hasPrefix(s.appName.lowercased())
                    guard appMatch else { return false }
                    let sTitle = Self.normalizeConversationTitle(s.originalTitle ?? s.title)
                    let sRawTitle = Self.normalizeConversationTitle(s.title)
                    return sTitle == cleanIncomingTitle || sRawTitle == cleanIncomingTitle
                }) {
                    return idx
                }
            }

            // 3순위: 웹 브라우저 URL 경로(호스트 + 고유 패스) 정규화 매칭
            // (예: https://chatgpt.com/c/672a... 와 threadKey: chatgpt.com/c/672a... 매칭, 쿼리/끝 슬래시 무시)
            if let eventURL = event.url, let normEventPath = Self.normalizeURLPath(eventURL) {
                if let idx = sessions.firstIndex(where: { s in
                    guard !(self.manualCompletedSessionIds.contains(s.sessionId) && s.state == .close) else { return false }
                    if let sURL = s.url, let normSPath = Self.normalizeURLPath(sURL), normSPath == normEventPath {
                        return true
                    }
                    if let normSKeyPath = Self.normalizeURLPath(s.threadKey), normSKeyPath == normEventPath {
                        return true
                    }
                    return false
                }) {
                    return idx
                }
            }

            return nil
        }()

        if let index = matchedSessionIndex {
            let previousState = sessions[index].state

            // 이전 포커스 세션이 다른 세션이었다면, 이전 세션을 unfocus로 전이 (누적시간 일시중지)
            if let activeId = activeFocusedSessionId, activeId != sessions[index].sessionId {
                unfocusSession(withId: activeId, now: now, elapsed: elapsed)
            }

            // threadKey 최신화 (사이드바 복귀나 URL/제목 정규화로 매칭된 경우 최신 threadKey 동기화)
            if sessions[index].threadKey != threadKey {
                sessions[index].threadKey = threadKey
                if let u = event.url, !u.isEmpty {
                    sessions[index].url = u
                }
                LocalDatabase.shared.recordSession(sessions[index])
            }

            // 원본 대화명 보존/동기화
            if !isIncomingTitleGeneric && !title.isEmpty {
                if sessions[index].originalTitle == nil || sessions[index].originalTitle?.isEmpty == true {
                    sessions[index].originalTitle = title
                }
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

                // 순수 활성 누적 시간 기준 중간 설문(mid) 발생 여부 검사
                SurveyScheduler.shared.checkMidSurveyEligibility(for: sessions[index])
            }

            if !title.isEmpty && title != "새 대화" {
                if let curIdx = sessions.firstIndex(where: { $0.sessionId == event.sessionId }) {
                    sessions[curIdx].title = title
                    sessions[curIdx].originalTitle = title
                }
            }
        } else {
            // [현재 활성 세션의 제목 승격/확정 검사]
            // 예: "ChatGPT" 기본 앱명 상태에서 사용자가 첫 프롬프트를 입력했거나,
            // ChatGPT가 첫 프롬프트("나한테 말을 걸라")로 설정했던 창 제목을 3~10초 후 AI 대화 요약 제목("나에게 말 걸기")으로 확정하는 경우:
            // 새 세션을 또 만들지 않고 기존 세션의 제목과 threadKey를 갱신하여 1개의 세션으로 유지
            if let activeId = activeFocusedSessionId,
               let activeIdx = sessions.firstIndex(where: { $0.sessionId == activeId }),
               shouldRenameActiveSession(sessions[activeIdx], newTitle: title, newKey: threadKey, event: event, now: now) {
                renameSession(at: activeIdx, newTitle: title, newKey: threadKey, event: &event, now: now)
                return
            }

            // [완전 신규 AI 대화 진입 / 세션 생성: open 이벤트 기록 후 focus_in으로 전환]
            if let activeId = activeFocusedSessionId {
                unfocusSession(withId: activeId, now: now, elapsed: elapsed)
            }

            let isIDE = event.bundleId.contains("antigravity") ||
                        event.bundleId.contains("cursor") ||
                        event.bundleId.contains("windsurf") ||
                        event.bundleId.contains("VSCode")
            let sanitizedTitle = Self.sanitizeAIPromptTitle(title, tool: event.aiTool ?? "AI", isIDE: isIDE)

            let newSessionId = UUID()
            let newSession = AISession(
                sessionId: newSessionId,
                threadKey: threadKey,
                title: sanitizedTitle,
                originalTitle: title,
                toolName: event.aiTool ?? "AI",
                appName: event.appName,
                url: event.url,
                windowId: event.windowId,
                hasFinalizedTitle: false,
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
                event.windowTitle = sanitizedTitle
                event.threadTitle = sanitizedTitle
            } else {
                // focus_in이나 navigate 등으로 신규 대화에 진입한 경우:
                // 새로운 창/탭/문서 생성과 마찬가지로 먼저 open 이벤트를 로그에 기록하고, 현재 이벤트는 focus_in으로 전환
                var openEvent = event
                openEvent.eventType = .open
                openEvent.sessionId = newSessionId
                openEvent.duration = nil
                let openTitle = "새 대화 시작: \(sanitizedTitle)"
                openEvent.windowTitle = openTitle
                openEvent.threadTitle = sanitizedTitle
                openEvent.navType = "new_session"
                DebugLogStore.shared.addEvent(openEvent)
                LocalDatabase.shared.recordActivityEvent(openEvent)

                event.eventType = .focusIn
                event.sessionId = newSessionId
                event.duration = nil
                event.windowTitle = sanitizedTitle
                event.threadTitle = sanitizedTitle
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

    // MARK: - 4-2. 수동 세션 시작 및 종료 (포커스된 창 기준)
    /// 메뉴바 "시작" 버튼 클릭 시 호출:
    /// - 현재 포커스된 창(AI 여부 무관)에 대해 새로운 세션을 시작하고 시작 설문(.start)을 표시
    @discardableResult
    public func manualStartSessionForCurrentWindow() -> AISession {
        let info = ActivityDetector.shared.getCurrentlyFocusedWindowInfo()
        let now = Date()

        let toolName: String = {
            if let t = info.aiTool, !t.isEmpty { return t }
            if let u = info.url, !u.isEmpty {
                let (isWebAI, webTool) = BrowserTracker.shared.checkWebAI(url: u)
                if isWebAI, let wt = webTool { return wt }
                if let host = URL(string: u)?.host, !host.isEmpty {
                    return host
                }
            }
            if !info.appName.isEmpty && info.appName != "Unknown" {
                return info.appName
            }
            return "AI 작업"
        }()

        let sanitizedTitle: String = {
            if !info.windowTitle.isEmpty { return info.windowTitle }
            return "\(toolName) 작업"
        }()

        let threadKey: String = {
            if let u = info.url, !u.isEmpty { return u }
            if let wid = info.windowId { return "\(info.bundleId):win_\(wid)" }
            return "\(info.bundleId):\(sanitizedTitle)"
        }()

        let newSessionId = UUID()
        let newSession = AISession(
            sessionId: newSessionId,
            threadKey: threadKey,
            title: sanitizedTitle,
            originalTitle: info.windowTitle,
            toolName: toolName,
            appName: info.appName,
            url: info.url,
            windowId: info.windowId,
            hasFinalizedTitle: false,
            state: .focusIn,
            openedAt: now,
            closedAt: nil,
            accumulatedFocusedDuration: 0,
            accumulatedUnfocusedDuration: 0,
            lastStateChangedAt: now,
            lifecycleHistory: [
                SessionLifecycleNode(timestamp: now, state: .open, detail: "사용자 수동 세션 시작 (메뉴바)"),
                SessionLifecycleNode(timestamp: now, state: .focusIn, detail: "대화 포커스 활성화")
            ],
            interleavingActivities: []
        )

        // 기존에 혹시 포커스되어 있던 다른 세션이 있다면 일시중지(unfocus)
        if let activeId = activeFocusedSessionId, activeId != newSessionId {
            unfocusSession(withId: activeId, now: now, elapsed: 0)
        }

        sessions.insert(newSession, at: 0)
        activeFocusedSessionId = newSessionId

        // 수동 등록 활성 세션으로 등록 (창을 AI로 인식하지 못하더라도 유지 기간 동안 항상 AI로 취급)
        manualActiveSessions[newSessionId] = ManualSessionTarget(
            sessionId: newSessionId,
            appName: info.appName,
            bundleId: info.bundleId,
            windowTitle: sanitizedTitle,
            url: info.url,
            toolName: toolName
        )

        LocalDatabase.shared.recordSession(newSession)

        // open 및 focusIn 이벤트 발행
        var openEvent = ActivityEvent(
            eventType: .open,
            appName: info.appName,
            bundleId: info.bundleId,
            windowTitle: sanitizedTitle,
            url: info.url,
            isAI: true,
            aiTool: toolName,
            navType: "manual_start"
        )
        openEvent.sessionId = newSessionId
        DebugLogStore.shared.addEvent(openEvent)
        LocalDatabase.shared.recordActivityEvent(openEvent)

        var focusEvent = ActivityEvent(
            eventType: .focusIn,
            appName: info.appName,
            bundleId: info.bundleId,
            windowTitle: sanitizedTitle,
            url: info.url,
            isAI: true,
            aiTool: toolName,
            navType: "manual_start"
        )
        focusEvent.sessionId = newSessionId
        DebugLogStore.shared.addEvent(focusEvent)
        LocalDatabase.shared.recordActivityEvent(focusEvent)

        // 설문 스케줄러 쿨다운 리셋 후 시작 설문(.start) 즉시 호출
        SurveyScheduler.shared.resetCooldown()
        SurveyScheduler.shared.handleSessionStarted(newSession)

        updateAppState()

        print("[SessionManager] 포커스 창 기준 수동 세션 시작: [\(toolName)] \(sanitizedTitle) (\(newSessionId))")
        return newSession
    }

    /// 메뉴바 "종료" 버튼 클릭 시 호출:
    /// - 현재 포커스된 창의 세션을 종료하고, 작업 종료 팝업(.end)을 띄움
    @discardableResult
    public func manualEndCurrentSessionAndPrepareNewTask() -> AISession? {
        let now = Date()
        let targetSession = focusedSession ?? activeSessions.first

        // 세션 간 쿨다운 리셋 (다음 AI 사용 시 30분 쿨다운 없이 시작 설문 가능)
        SurveyScheduler.shared.resetCooldown()

        if let session = targetSession {
            print("[SessionManager] 사용자에 의한 포커스 창 세션 종료: \(session.title) (\(session.sessionId))")
            manualCompletedSessionIds.insert(session.sessionId)
            manualActiveSessions.removeValue(forKey: session.sessionId)

            closeSession(withId: session.sessionId, now: now, detail: "사용자 메뉴바 '세션 종료' 클릭")

            // 작업 종료 팝업(.end) 강제 표시 (규칙 우회하여 즉시 평가 가능)
            _ = SurveyScheduler.shared.requestSurvey(type: .end, session: session, force: true)

            activeFocusedSessionId = nil
            updateAppState()
            return session
        } else {
            print("[SessionManager] 현재 포커스된 활성 세션 없음")
            activeFocusedSessionId = nil
            SaveConfirmationToast.shared.show(
                message: "새 작업 준비 완료",
                detail: "다음 AI 사용 시 새로운 세션으로 기록됩니다."
            )
            updateAppState()
            return nil
        }
    }

    /// 테스트 환경용 수동 완료 세션 초기화
    public func resetManualCompletedSessions() {
        manualCompletedSessionIds.removeAll()
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
                    event.bundleId.contains("windsurf") ||
                    event.bundleId.contains("VSCode") ||
                    (event.appName.lowercased().contains("antigravity")) ||
                    (event.appName.lowercased().contains("cursor")) ||
                    (event.appName.lowercased().contains("windsurf")) ||
                    (event.aiTool?.lowercased().contains("antigravity") == true) ||
                    (event.aiTool?.lowercased().contains("windsurf") == true)

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

                        let p1IsChatOrExtension = p1.lowercased().contains("copilot") || p1.lowercased().contains("chat") || p1.lowercased().contains("extension")
                        let p2IsChatOrExtension = p2.lowercased().contains("copilot") || p2.lowercased().contains("chat") || p2.lowercased().contains("extension")

                        if p1IsChatOrExtension && !p2IsChatOrExtension {
                            matchedWorkspace = p2
                        } else if p2IsChatOrExtension && !p1IsChatOrExtension {
                            matchedWorkspace = p1
                        } else if p2IsFile && !p1IsFile {
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

        var cleanTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" - Claude Code", " · Claude Code", " - Claude", " · Claude", " - ChatGPT", " | ChatGPT", " - Perplexity"] {
            if cleanTitle.hasSuffix(suffix) {
                cleanTitle = String(cleanTitle.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for prefix in ["Claude Code - ", "ChatGPT - ", "Claude - "] {
            if cleanTitle.hasPrefix(prefix) {
                cleanTitle = String(cleanTitle.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let titleKey = cleanTitle.isEmpty ? (event.aiTool ?? "Default") : cleanTitle
        let key = "\(appKey)_\(titleKey)"
        return (key, titleKey)
    }

    // MARK: - 5-A. 임시 프롬프트 -> AI 자동 요약 제목 승격 및 갱신 헬퍼
    private func isGenericPlaceholderTitle(
        _ title: String,
        appName: String,
        toolName: String?,
        url: String? = nil
    ) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }

        // [AI 대화] 마스킹 접두어가 붙어있는 세션은 이미 활성화된 대화이므로 플레이스홀더가 아님
        if t.hasPrefix("[ai 대화]") || t.hasPrefix("[ai 세션]") {
            return false
        }

        let app = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tool = (toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. 단순 일치 검사 (앱 이름, 도구 이름과 동일한 경우)
        if t == app || (!tool.isEmpty && t == tool) { return true }

        // 2. 도구명 및 접미사를 제거한 순수 제목 추출
        var pureTitle = t
        for suffix in [" - claude code", " · claude code", " - chatgpt", " · chatgpt", " | chatgpt", " - claude", " · claude", " | claude", " - gemini", " · gemini", " - perplexity", " · perplexity", " - copilot", " · copilot"] {
            if pureTitle.hasSuffix(suffix) {
                pureTitle = String(pureTitle.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for prefix in ["claude code - ", "chatgpt - ", "claude - ", "gemini - ", "perplexity - ", "copilot - "] {
            if pureTitle.hasPrefix(prefix) {
                pureTitle = String(pureTitle.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        pureTitle = pureTitle.trimmingCharacters(in: CharacterSet(charactersIn: " -·|:—/"))

        // 도구명만 단독으로 있거나 회사명(Microsoft, Google, OpenAI 등)만 붙어 있는 경우 홈 화면으로 판정
        let genericCompanyNames = ["microsoft", "google", "openai", "anthropic", "meta", "naver", "네이버", "wrtn", "뤼튼"]
        if pureTitle.isEmpty || pureTitle == app || pureTitle == tool || genericCompanyNames.contains(pureTitle) {
            return true
        }

        // 전체 제목이 generic company + tool 인 경우 (예: "microsoft copilot", "google gemini", "openai chatgpt")
        for comp in genericCompanyNames {
            if t == "\(comp) \(tool)" || t == "\(tool) \(comp)" || t == "\(comp) \(app)" || t == "\(app) \(comp)" {
                return true
            }
        }

        // 3. 사용자 등록 커스텀 AI 도메인/앱 명칭 대조 (CustomAITargetManager)
        for target in CustomAITargetManager.shared.customDomains + CustomAITargetManager.shared.customApps {
            let dName = target.displayName.lowercased()
            let val = target.value.lowercased()
            if t == dName || t == val || pureTitle == dName || pureTitle == val { return true }
        }

        // 4. URL의 호스트명 대조 (예: title이 "chatgpt.com" 또는 "copilot.microsoft.com"인 경우)
        if let uStr = url, let uObj = URL(string: uStr), let host = uObj.host?.lowercased() {
            if t == host || pureTitle == host { return true }
        }

        // 5. 일반적인 플레이스홀더 및 AI 포털/기관 브랜딩 키워드 (예: "KAIST AI대학", "사내 AI 포털" 등)
        let genericPortalKeywords = ["포털", "portal", "대학교", "대학원", "university", "college", "institute", "kaist", "ai대학", "ai연구원", "어시스턴트", "assistant"]
        for pkw in genericPortalKeywords {
            if t.contains(pkw) || pureTitle.contains(pkw) {
                return true
            }
        }

        // 6. 일반적인 플레이스홀더 어구들
        let exactGenericPhrases = [
            "새 대화", "new chat", "새로운 대화", "untitled", "새 작업공간",
            "default", "chat", "welcome", "home", "홈", "대화 시작", "새 대화 시작", "start",
            "sign in", "signin", "sign-in", "log in", "login", "log-in",
            "로그인", "회원가입", "계정 만들기", "인증", "sign up", "signup",
            "dia tab", "new tab"
        ]
        if exactGenericPhrases.contains(t) || exactGenericPhrases.contains(pureTitle) { return true }
        if t.hasPrefix("새 대화 시작") || t.hasPrefix("새 창·문서 생성") { return true }

        return false
    }

    // MARK: - 5-B. 프롬프트 전송 전 '빈 대기 화면(홈/랜딩 페이지, 로그인/인증 화면)' 감지 헬퍼
    private func isBlankStandbyAIPage(
        url: String?,
        title: String,
        appName: String,
        bundleId: String,
        toolName: String?
    ) -> Bool {
        // 0. 로그인, 회원가입, 계정 인증 페이지 (웹/앱 공통)
        // 로그인/인증 단계는 실제 AI 대화가 시작된 것이 아니므로 세션을 개설하지 않고 대기 처리
        if BrowserTracker.isAuthOrLoginPage(url: url, title: title) {
            return true
        }

        let isBrowser = Config.Detection.supportedBrowsers.keys.contains(bundleId) ||
                        bundleId.lowercased().contains("chrome") ||
                        bundleId.lowercased().contains("safari") ||
                        bundleId.lowercased().contains("browser") ||
                        bundleId.lowercased().contains("dia") ||
                        bundleId.lowercased().contains("arc") ||
                        bundleId.lowercased().contains("edge") ||
                        bundleId.lowercased().contains("firefox") ||
                        bundleId.lowercased().contains("mozilla") ||
                        bundleId.lowercased().contains("zen") ||
                        bundleId.lowercased().contains("orion")

        // 1. 데스크톱 AI 전용 앱인 경우 (예: ChatGPT, Claude Mac 데스크톱 앱)
        if !isBrowser {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let app = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let tool = (toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // 앱 최초 실행 직후 아직 프롬프트를 전송하지 않아 창 제목이 단순 앱 이름("ChatGPT")인 경우
            if t == app || (!tool.isEmpty && t == tool) || t == "new chat" || t == "새 대화" {
                return true
            }
            return isGenericPlaceholderTitle(title, appName: appName, toolName: toolName, url: url)
        }

        // 2. 웹 브라우저 AI 사이트인 경우 (모든 퍼블릭 AI 웹 및 사용자 등록 커스텀 도메인 공통)
        guard let urlStr = url, let urlObj = URL(string: urlStr) else {
            return isGenericPlaceholderTitle(title, appName: appName, toolName: toolName, url: url)
        }

        // 2-1. URL에 고유 대화 ID, 에이전트 세션 ID, 또는 UUID가 포함되어 있는 경우 -> 이미 실제 대화 중이므로 대기 화면이 아님!
        if hasSpecificChatPathOrQuery(url: urlObj) {
            return false
        }

        // 2-2. URL 경로가 루트(/), /new, /en, /home 등 초기 대기 경로이고 특정 대화 ID가 없는 경우:
        let path = urlObj.path.lowercased()
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rootStandbySegments = [
            "", "new", "home", "start", "app", "chats", "explore",
            "dashboard", "workspace", "agent", "agents", "en", "ko", "main", "portal"
        ]
        let isRootStandbyPath = rootStandbySegments.contains(cleanPath) ||
                                (cleanPath.hasPrefix("en/") == false && cleanPath.hasPrefix("ko/") == false && cleanPath.components(separatedBy: "/").count <= 1)

        if isRootStandbyPath {
            // [AI 대화] 마스킹 접두어가 이미 붙은 세션은 기존에 대화가 시작되어 승격된 세션이므로 유지
            if title.hasPrefix("[AI 대화]") || title.hasPrefix("[AI 세션]") {
                return false
            }
            // 루트/초기 진입 URL에서는 사용자가 프롬프트를 전송하여 실제 대화(URL 변경 or UUID 생성)로 진입하기 전까지는 대기 화면으로 판정
            return true
        }

        // 2-3. URL에 대화 ID가 없는 일반 경로인 경우 제목 플레이스홀더 검사
        let isPlaceholder = isGenericPlaceholderTitle(title, appName: appName, toolName: toolName, url: urlStr)
        if isPlaceholder {
            return true
        }

        return false
    }

    /// URL이 특정 대화/채팅 세션 ID를 포함하는 구체적 대화 경로인지 판별
    private func hasSpecificChatPathOrQuery(url: URL) -> Bool {
        if BrowserTracker.isAuthOrLoginPage(url: url.absoluteString, title: "") {
            return false
        }

        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""

        // 1. UUID 패턴 매칭 (경로 내 36자리 UUID가 포함된 경우: 예: 7d83727d-13c8-41a3-b1e6-bb91678bee7e)
        let uuidRegex = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        if path.range(of: uuidRegex, options: .regularExpression) != nil {
            return true
        }

        // 2. 주요 AI 서비스 및 에이전트 플랫폼들의 특정 대화/에이전트 경로 패턴
        let chatPathPrefixes = [
            "/c/", "/chat/", "/chats/", "/search/", "/notebook/",
            "/thread/", "/threads/", "/session/", "/sessions/",
            "/conversation/", "/conversations/", "/t/", "/p/",
            "/project/", "/workspace/", "/a/chat/s/", "/dialog/", "/dialogs/",
            "/room/", "/rooms/", "/talk/", "/messages/", "/prompt/", "/ask/", "/q/",
            "/agent/", "/agents/", "/bot/", "/bots/", "/assistant/", "/assistants/",
            "/workflow/", "/workflows/", "/run/"
        ]
        for prefix in chatPathPrefixes {
            if path.contains(prefix) {
                let comps = path.components(separatedBy: prefix)
                if comps.count > 1 && !comps[1].isEmpty && comps[1] != "/" {
                    let sub = comps[1]
                    if sub.hasPrefix("login") || sub.hasPrefix("auth") || sub.hasPrefix("signin") {
                        return false
                    }
                    return true
                }
            }
        }

        // 3. /app/{chat_id} (Gemini 등)
        if path.hasPrefix("/app/") {
            let sub = path.dropFirst("/app/".count)
            if !sub.isEmpty && sub != "/" && !sub.hasPrefix("auth") && !sub.hasPrefix("login") {
                return true
            }
        }

        // 4. 쿼리 파라미터에 대화 ID가 들어있는 경우 (예: ?id=..., ?chat_id=..., ?thread=...)
        let chatQueryKeys = ["id=", "chat_id=", "thread_id=", "conversation_id=", "c=", "thread=", "session_id=", "room_id=", "agent_id=", "bot_id="]
        for q in chatQueryKeys {
            if query.contains(q) {
                return true
            }
        }

        return false
    }

    private func shouldRenameActiveSession(
        _ session: AISession,
        newTitle: String,
        newKey: String,
        event: ActivityEvent,
        now: Date
    ) -> Bool {
        // 1. 새 제목이 비어있거나 플레이스홀더인 경우는 이름 확정/승격이 아님
        if isGenericPlaceholderTitle(newTitle, appName: event.appName, toolName: event.aiTool, url: event.url) {
            return false
        }

        // 2. 동일 앱/도구인지 확인 (ChatGPT -> ChatGPT, Claude -> Claude 등)
        let isSameApp = (session.appName == event.appName) ||
                        (session.toolName == (event.aiTool ?? "")) ||
                        (session.threadKey.hasPrefix(event.bundleId))
        guard isSameApp else { return false }

        // 3. 이미 AI 요약 제목 등으로 최종 확정(finalized)된 세션은 사이드바 전환 시 덮어쓰지 않음
        if session.hasFinalizedTitle == true {
            return false
        }

        // 4. 기존 세션 제목이 "ChatGPT" 등 플레이스홀더였던 경우: 첫 질문 입력 시 즉시 승격
        if isGenericPlaceholderTitle(session.title, appName: session.appName, toolName: session.toolName, url: session.url) {
            return true
        }

        // 5. 세션 시작 후 단시간(180초 이내) 내에 발생한 타이틀 변경 (프롬프트 -> AI 자동 요약 제목)
        // 단, 대화 간 전환(navigate 또는 navType == "chat")은 사이드바/URL을 통한 새 대화 이동이므로 리네임 배제!
        if event.eventType == .navigate || event.navType == "chat" {
            return false
        }

        let span = now.timeIntervalSince(session.openedAt)
        if span < 180 {
            // 동일 윈도우 ID인 경우
            if let winId = event.windowId, let sessWinId = session.windowId, winId == sessWinId {
                return true
            }
            // 직전 타이틀(fromTitle)이 세션 타이틀과 일치하는 경우
            if let from = event.fromTitle, from == session.title {
                return true
            }
            // 활성 포커스 유지 중 발생한 타이틀 변경인 경우
            if session.state == .focusIn {
                return true
            }
        }

        return false
    }

    private func renameSession(
        at index: Int,
        newTitle: String,
        newKey: String,
        event: inout ActivityEvent,
        now: Date
    ) {
        let oldTitle = sessions[index].title
        let sessionId = sessions[index].sessionId

        let isIDE = sessions[index].appName.lowercased().contains("antigravity") ||
                    sessions[index].appName.lowercased().contains("cursor") ||
                    sessions[index].appName.lowercased().contains("windsurf") ||
                    sessions[index].appName.lowercased().contains("visual studio code")
        let sanitizedNewTitle = Self.sanitizeAIPromptTitle(newTitle, tool: sessions[index].toolName, isIDE: isIDE)

        sessions[index].title = sanitizedNewTitle
        sessions[index].originalTitle = newTitle
        sessions[index].threadKey = newKey
        sessions[index].lastStateChangedAt = now
        if let wid = event.windowId {
            sessions[index].windowId = wid
        }

        // 기존 제목이 플레이스홀더가 아니었다면 (즉, 이미 프롬프트가 들어간 상태에서 AI가 지어준 제목으로 바뀐 것이라면)
        // 제목이 최종 확정된 것으로 표시
        let wasGeneric = isGenericPlaceholderTitle(oldTitle, appName: sessions[index].appName, toolName: sessions[index].toolName)
        if !wasGeneric {
            sessions[index].hasFinalizedTitle = true
        }

        sessions[index].lifecycleHistory.append(
            SessionLifecycleNode(timestamp: now, state: .focusIn, detail: "대화 제목 확정 (\(oldTitle) ➔ \(sanitizedNewTitle))")
        )

        // DB 세션 레코드 갱신 (INSERT OR REPLACE로 제목 업데이트)
        LocalDatabase.shared.recordSession(sessions[index])

        // 기존 open 이벤트 제목 갱신
        DebugLogStore.shared.updateSessionOpenEventTitle(sessionId: sessionId, newTitle: sanitizedNewTitle)
        LocalDatabase.shared.updateSessionOpenEventTitle(sessionId: sessionId, newTitle: sanitizedNewTitle)

        // 현재 이벤트 매핑 (중복 open 이벤트 발행 금지)
        activeFocusedSessionId = sessionId
        event.sessionId = sessionId
        event.threadKey = newKey
        event.threadTitle = sanitizedNewTitle
        event.windowTitle = sanitizedNewTitle
        if event.eventType != .navigate {
            event.eventType = .focusIn
        }
    }

    /// 프라이버시 보호를 위해 AI 창 제목에서 개인 프롬프트 내용을 마스킹
    public static func sanitizeAIPromptTitle(_ rawTitle: String, tool: String, isIDE: Bool) -> String {
        let t = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == tool || t == "새 대화" || t == "New chat" {
            return "[AI 대화] \(tool)"
        }
        // IDE 작업공간명(예: "LogSystem_Test2_Mac")이나 파일명은 프롬프트가 아니므로 그대로 보존
        if isIDE && !t.contains("대화") && !t.contains("Chat") && !t.contains("chat") {
            return t
        }
        // AI 챗봇 창 제목에 사용자가 입력한 프롬프트 내용이 그대로 노출되는 경우 마스킹하여 개인정보/대화내용 유출 방지
        return "[AI 대화] \(tool)"
    }

    /// 대화 제목 정규화 헬퍼 (공백, 대소문자, 접두어/접미사 완벽 제거 후 순수 대화명 추출)
    public static func normalizeConversationTitle(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return "" }

        // 1. 접두어 제거
        let prefixes = [
            "[ai 대화] ", "[ai 세션] ", "새 창·문서 생성: ", "새 대화: ", "새 작업공간: ",
            "claude code - ", "chatgpt - ", "claude - ", "gemini - ", "perplexity - ", "copilot - ",
            "💼: ", "🎶 ", "● ", "* "
        ]
        for prefix in prefixes {
            if t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 2. 브라우저 및 AI 도구 접미사 제거
        let suffixes = [
            " - claude code", " · claude code", " | claude code",
            " - claude", " · claude", " | claude",
            " - chatgpt", " · chatgpt", " | chatgpt",
            " - gemini", " · gemini", " | gemini", " - google gemini",
            " - perplexity", " · perplexity",
            " - dia", " · dia",
            " - cursor", " - antigravity", " - visual studio code"
        ]
        for suffix in suffixes {
            if t.hasSuffix(suffix) {
                t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 3. 앞뒤 특수문자 및 공백 정제
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " -·|:—/ \t\n"))
    }

    /// URL 경로 정규화 (호스트 + 고유 패스 추출, 쿼리 및 트레일링 슬래시 제거)
    public static func normalizeURLPath(_ urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            // URL 형태가 아닌 경우(예: threadKey 자체가 "chatgpt.com/c/123" 형태인 경우)
            var s = trimmed.lowercased()
            if let qIdx = s.firstIndex(of: "?") { s = String(s[..<qIdx]) }
            if let fIdx = s.firstIndex(of: "#") { s = String(s[..<fIdx]) }
            while s.hasSuffix("/") { s.removeLast() }
            return s.isEmpty ? nil : s
        }

        var path = url.path
        if let qIdx = path.firstIndex(of: "?") { path = String(path[..<qIdx]) }
        while path.hasSuffix("/") && path.count > 1 {
            path.removeLast()
        }
        if path.isEmpty || path == "/" {
            return "\(host)/new"
        }
        return "\(host)\(path)"
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

    public func isBlankStandbyAIPageForTest(url: String?, title: String, appName: String, bundleId: String, toolName: String?) -> Bool {
        return isBlankStandbyAIPage(url: url, title: title, appName: appName, bundleId: bundleId, toolName: toolName)
    }

    public func resolveThreadForTest(bundleId: String, appName: String, windowTitle: String, url: String?, isAI: Bool, aiTool: String?) -> (threadKey: String, title: String) {
        let dummy = ActivityEvent(
            eventType: .focusIn,
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            url: url,
            isAI: isAI,
            aiTool: aiTool
        )
        return resolveThread(for: dummy)
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

                // 순수 활성 누적 시간 기준 중간 설문(mid) 발생 여부 검사
                SurveyScheduler.shared.checkMidSurveyEligibility(for: self.sessions[idx])
            }
        }
    }

    private func updateAppState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 포커스된 창 기준: 실제 AI 창에 포커스되어 있을 때만 해당 세션 및 시간 노출
            if let focused = self.focusedSession {
                AppState.shared.activeAIAppName = focused.toolName
                AppState.shared.activeSessionAppNames = focused.toolName
                AppState.shared.activeSessionDurationString = focused.formattedFocusedDuration
            } else {
                AppState.shared.activeAIAppName = nil
                AppState.shared.activeSessionAppNames = nil
                AppState.shared.activeSessionDurationString = nil
            }
        }
    }
}
