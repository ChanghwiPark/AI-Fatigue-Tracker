import Foundation
import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

/// 모든 컴퓨터 활동(앱 전환, 창 제목, 브라우저 탭 URL, 유휴, 화면 잠금)을 상시 모니터링하고 AI 세션 규칙에 전달합니다.
public final class ActivityDetector {
    public static let shared = ActivityDetector()

    private var currentApp: NSRunningApplication?
    private var currentWindowTitle: String = ""
    private var currentBrowserURL: String = ""
    private var currentChatKey: String = ""
    private var currentAppIsAI: Bool = false
    private var currentAppAITool: String? = nil
    private var lastBrowserTabCount: Int? = nil
    private var lastBrowserTabId: String? = nil
    private var lastTerminalCommand: String = ""
    private var lastEventTime: Date = Date()
    private var lastEvent: ActivityEvent?
    private var lastAppActivationTime: Date = .distantPast

    private var pollingTimer: Timer?
    private var isMonitoring: Bool = false

    /// 활성 창 식별 및 신규 창 감지 상태
    private var knownWindowIds: Set<Int> = []
    private var currentWindowId: Int?
    private var appWindowCounts: [pid_t: Int] = [:]

    private init() {}

    /// 전체 모니터링 시작
    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        setupWorkspaceNotifications()
        setupIdleTracker()
        setupSystemEventTracker()
        startWindowPolling()

        // 시작 시점의 포그라운드 앱 초기 캡처
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            handleAppActivated(frontmost)
        }
    }

    public func stop() {
        isMonitoring = false
        pollingTimer?.invalidate()
        pollingTimer = nil
        IdleTracker.shared.stopMonitoring()
    }

    // MARK: - 1. NSWorkspace 앱 전환 노티피케이션
    private func setupWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleAppActivated(app)
        }

        center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleAppDeactivated(app)
        }

        center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleAppLaunched(app)
        }

        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleAppTerminated(app)
        }
    }

    private func handleAppActivated(_ app: NSRunningApplication) {
        let bundleId = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? "Unknown"

        // 같은 프로세스(앱) 재진입인 경우 무시
        if let prevApp = self.currentApp, prevApp.processIdentifier == app.processIdentifier {
            return
        }

        self.lastAppActivationTime = Date()
        let previousAppName = self.currentApp?.localizedName
        let previousTitle = self.currentWindowTitle
        let prevApp = self.currentApp

        self.currentApp = app
        let (windowTitle, winId, winCount) = fetchActiveWindowInfo(for: app.processIdentifier)
        self.currentWindowTitle = windowTitle
        self.currentWindowId = winId
        let isBrandNewWindow = (winId != nil && !knownWindowIds.contains(winId!))
        if let wid = winId {
            knownWindowIds.insert(wid)
        }
        appWindowCounts[app.processIdentifier] = winCount

        // 1. 이전 앱에서 포커스 이탈 (.focusOut) 기록 (포커스 사라진 부분에 대한 정보만)
        if let prev = prevApp, prev.processIdentifier != app.processIdentifier {
            let (wasAI, prevTool) = checkAI(for: prev.bundleIdentifier ?? "", windowTitle: previousTitle, appName: previousAppName ?? "")
            emitEvent(
                type: .focusOut,
                appName: previousAppName ?? "Unknown",
                bundleId: prev.bundleIdentifier ?? "unknown",
                windowTitle: previousTitle,
                isAI: wasAI,
                aiTool: prevTool,
                navType: "app"
            )
        }

        // 프라이버시 및 개인 제외 앱 검사
        if Config.Detection.privacyExcludedBundleIDs.contains(bundleId) || PersonalExclusionManager.shared.isExcluded(bundleId: bundleId) {
            if let prev = prevApp, prev.processIdentifier != app.processIdentifier {
                emitEvent(
                    type: .navigate,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: "[보호된 앱]",
                    fromApp: previousAppName,
                    fromTitle: previousTitle,
                    toApp: appName,
                    toTitle: "[보호된 앱]",
                    navType: "app"
                )
            }
            emitEvent(
                type: .focusIn,
                appName: appName,
                bundleId: bundleId,
                windowTitle: "[보호된 앱]",
                navType: "app"
            )
            return
        }

        // 1. 터미널 앱인 경우 활성 명령 및 AI CLI 분석
        if Config.Detection.terminalBundleIDs.contains(bundleId) {
            let termInfo = TerminalTracker.shared.fetchActiveTerminalInfo(
                for: bundleId,
                appName: appName,
                pid: app.processIdentifier,
                rawWindowTitle: windowTitle
            )
            self.lastTerminalCommand = termInfo.activeCommand
            self.currentWindowTitle = termInfo.displayTitle
            self.currentAppIsAI = termInfo.isAI
            self.currentAppAITool = termInfo.aiTool

            if let prev = prevApp, prev.processIdentifier != app.processIdentifier {
                emitEvent(
                    type: .navigate,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: termInfo.displayTitle,
                    isAI: termInfo.isAI,
                    aiTool: termInfo.aiTool,
                    fromApp: previousAppName,
                    fromTitle: previousTitle,
                    toApp: appName,
                    toTitle: termInfo.displayTitle,
                    navType: "app"
                )
            }

            emitEvent(
                type: .focusIn,
                appName: appName,
                bundleId: bundleId,
                windowTitle: termInfo.windowTitle.isEmpty ? termInfo.displayTitle : termInfo.windowTitle,
                isAI: termInfo.isAI,
                aiTool: termInfo.aiTool,
                threadKey: termInfo.threadKey,
                threadTitle: termInfo.displayTitle,
                navType: "app"
            )
            return
        }

        // 2. 브라우저인 경우 활성 탭 즉시 분석하여 전환 및 focus_in 이벤트 발행
        if isBrowserApp(bundleId: bundleId, appName: appName) {
            let tabInfo = BrowserTracker.shared.fetchActiveTab(for: bundleId, pid: app.processIdentifier)
            let tabURL = tabInfo?.url ?? ""
            let tabTitle = (tabInfo?.title.isEmpty == false) ? tabInfo!.title : (windowTitle.isEmpty ? appName : windowTitle)
            let isAI = tabInfo?.isAI ?? false
            let aiTool = tabInfo?.aiTool
            let threadKey = tabInfo?.threadKey
            let threadTitle = tabInfo?.threadTitle

            self.currentBrowserURL = tabURL
            self.currentWindowTitle = tabTitle
            self.currentAppIsAI = isAI
            self.currentAppAITool = aiTool
            self.currentChatKey = threadKey ?? ""
            self.lastBrowserTabCount = tabInfo?.tabCount
            self.lastBrowserTabId = tabInfo?.tabId

            if let prev = prevApp, prev.processIdentifier != app.processIdentifier {
                emitEvent(
                    type: .navigate,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: tabTitle,
                    url: tabURL.isEmpty ? nil : tabURL,
                    isAI: isAI,
                    aiTool: aiTool,
                    threadKey: threadKey,
                    threadTitle: threadTitle,
                    fromApp: previousAppName,
                    fromTitle: previousTitle,
                    toApp: appName,
                    toTitle: tabTitle,
                    navType: "app",
                    fromDomain: URL(string: currentBrowserURL)?.host,
                    toDomain: URL(string: tabURL)?.host
                )
            }

            emitEvent(
                type: .focusIn,
                appName: appName,
                bundleId: bundleId,
                windowTitle: tabTitle,
                url: tabURL.isEmpty ? nil : tabURL,
                isAI: isAI,
                aiTool: aiTool,
                threadKey: threadKey,
                threadTitle: threadTitle,
                navType: "app"
            )
            return
        }

        // 3. 일반 데스크톱 앱 (AI 전용 IDE, 사내 메신저 봇, 일반 앱 등)
        let (isAI, aiTool) = checkAI(for: bundleId, windowTitle: windowTitle, appName: appName)
        self.currentAppIsAI = isAI
        self.currentAppAITool = aiTool

        if let prev = prevApp, prev.processIdentifier != app.processIdentifier {
            emitEvent(
                type: .navigate,
                appName: appName,
                bundleId: bundleId,
                windowTitle: windowTitle,
                isAI: isAI,
                aiTool: aiTool,
                fromApp: previousAppName,
                fromTitle: previousTitle,
                toApp: appName,
                toTitle: windowTitle,
                navType: "app"
            )
        }

        if isBrandNewWindow && isAI {
            emitEvent(
                type: .open,
                appName: appName,
                bundleId: bundleId,
                windowTitle: windowTitle,
                isAI: isAI,
                aiTool: aiTool,
                toApp: appName,
                toTitle: windowTitle,
                navType: "new_window",
                windowId: self.currentWindowId
            )
        }

        emitEvent(
            type: .focusIn,
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            isAI: isAI,
            aiTool: aiTool,
            navType: "app",
            windowId: self.currentWindowId
        )
    }

    private func handleAppDeactivated(_ app: NSRunningApplication) {
        // 앱 비활성화 알림 시에는 활성 창 타이틀(currentWindowTitle)을 비활성화된 앱의 타이틀로 덮어쓰지 않음
        // (handleAppActivated가 활성 창 맥락을 온전히 캡처하며 오염을 방지함)
    }

    private func handleAppLaunched(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        let bundleId = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? "Unknown"

        if Config.Detection.privacyExcludedBundleIDs.contains(bundleId) || PersonalExclusionManager.shared.isExcluded(bundleId: bundleId) { return }

        let (isAI, aiTool) = checkAI(for: bundleId, windowTitle: "", appName: appName)

        emitEvent(
            type: .open,
            appName: appName,
            bundleId: bundleId,
            windowTitle: "앱 실행: \(appName)",
            isAI: isAI,
            aiTool: aiTool
        )
    }

    private func handleAppTerminated(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular || Config.Detection.supportedBrowsers.keys.contains(app.bundleIdentifier ?? "") else { return }
        let bundleId = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? "Unknown"
        let (isAI, aiTool) = checkAI(for: bundleId, windowTitle: "", appName: appName)

        SessionManager.shared.handleAppTerminated(bundleId: bundleId)

        emitEvent(
            type: .close,
            appName: appName,
            bundleId: bundleId,
            windowTitle: "앱 종료: \(appName)",
            isAI: isAI,
            aiTool: aiTool
        )
    }

    // MARK: - 2. 창 제목 변경 폴링 & 브라우저 탭 폴링
    private func startWindowPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: Config.Detection.windowPollingInterval, repeats: true) { [weak self] _ in
            self?.pollActiveWindowAndBrowser()
        }
    }

    private func pollActiveWindowAndBrowser() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundleId = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? "Unknown"

        if Config.Detection.privacyExcludedBundleIDs.contains(bundleId) || PersonalExclusionManager.shared.isExcluded(bundleId: bundleId) {
            return
        }

        // 앱이 바뀐 경우: 폴러에서 창 전환으로 오인하지 않고 handleAppActivated로 위임
        if let current = self.currentApp, current.processIdentifier != app.processIdentifier {
            handleAppActivated(app)
            return
        }
        if self.currentApp == nil {
            handleAppActivated(app)
            return
        }

        // 1. 브라우저인 경우 활성 탭 검사 (URL 변경 시 page_visit)
        if isBrowserApp(bundleId: bundleId, appName: appName) {
            checkBrowserTab(for: bundleId, appName: appName, pid: app.processIdentifier)
            return
        }

        // 2. 터미널인 경우 실행 중인 명령어 및 AI CLI(claude, aider 등) 변화 동적 감지
        if Config.Detection.terminalBundleIDs.contains(bundleId) {
            checkTerminalState(for: bundleId, appName: appName, pid: app.processIdentifier)
            return
        }

        // 3. 같은 앱 안에서 창 제목이 바뀌었거나 새 창이 열렸을 때 / 창이 닫혔을 때
        let (newTitle, newWinId, winCount) = fetchActiveWindowInfo(for: app.processIdentifier)
        let (isAI, aiTool) = checkAI(for: bundleId, windowTitle: newTitle, appName: appName)
        let isIDE = isAI || bundleId.contains("antigravity") || bundleId.contains("cursor") || bundleId.contains("VSCode")
        let isNewDoc = isNewDocumentTitle(newTitle, appName: appName, isIDE: isIDE)

        let isBrandNewWindow = (newWinId != nil && !knownWindowIds.contains(newWinId!))
        let previousCount = appWindowCounts[app.processIdentifier] ?? 0
        let windowCountIncreased = winCount > previousCount && previousCount > 0

        if isBrandNewWindow || (windowCountIncreased && (isNewDoc || newTitle != currentWindowTitle)) {
            // [새 창/새 문서/새 세션 생성: open 즉시 발행 후 focus_in으로 전환]
            if let wid = newWinId {
                knownWindowIds.insert(wid)
                self.currentWindowId = wid
            }
            appWindowCounts[app.processIdentifier] = winCount
            let oldTitle = currentWindowTitle
            self.currentWindowTitle = newTitle

            let displayTitle = isNewDoc ? "새 창·문서 생성: \(newTitle)" : newTitle

            emitEvent(
                type: .open,
                appName: appName,
                bundleId: bundleId,
                windowTitle: displayTitle,
                isAI: isAI,
                aiTool: aiTool,
                fromTitle: oldTitle,
                toTitle: newTitle,
                navType: "new_window",
                windowId: newWinId
            )
            emitEvent(
                type: .focusIn,
                appName: appName,
                bundleId: bundleId,
                windowTitle: newTitle,
                isAI: isAI,
                aiTool: aiTool,
                fromTitle: oldTitle,
                toTitle: newTitle,
                navType: "focus_in",
                windowId: newWinId
            )
        } else if (!newTitle.isEmpty && newTitle != currentWindowTitle) || (newWinId != nil && newWinId != currentWindowId) {
            // [기존 창 간 전환 또는 창 제목 변경]
            // 앱 활성화 직후 1.0초 이내에는 창 제목 지연 로딩으로 인한 중복 창 전환(navigate) 발생을 억제하고 현재 제목만 갱신
            if Date().timeIntervalSince(lastAppActivationTime) < 1.0 {
                if let wid = newWinId {
                    knownWindowIds.insert(wid)
                    self.currentWindowId = wid
                }
                self.currentWindowTitle = newTitle
                appWindowCounts[app.processIdentifier] = winCount
                return
            }

            if let wid = newWinId {
                knownWindowIds.insert(wid)
                self.currentWindowId = wid
            }
            appWindowCounts[app.processIdentifier] = winCount
            let oldTitle = currentWindowTitle
            self.currentWindowTitle = newTitle

            // 동일 앱 내에서의 실질적인 창/문서 전환인 경우에만 navigate 및 focus_in 발행
            if !oldTitle.isEmpty && oldTitle != newTitle {
                emitEvent(
                    type: .navigate,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: newTitle,
                    isAI: isAI,
                    aiTool: aiTool,
                    fromTitle: oldTitle,
                    toTitle: newTitle,
                    navType: "window",
                    windowId: newWinId
                )
                emitEvent(
                    type: .focusIn,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: newTitle,
                    isAI: isAI,
                    aiTool: aiTool,
                    windowId: newWinId
                )
            }
        } else if winCount == 0 && !currentWindowTitle.isEmpty {
            // 앱의 모든 창이 실제로 닫혔을 때만 close 발행 (CoreGraphics Layer 0 윈도우 부재 확인)
            let closedTitle = currentWindowTitle
            self.currentWindowTitle = ""
            self.currentWindowId = nil
            appWindowCounts[app.processIdentifier] = 0

            emitEvent(
                type: .close,
                appName: appName,
                bundleId: bundleId,
                windowTitle: "창 종료: \(closedTitle)",
                isAI: isAI,
                aiTool: aiTool
            )
        }
    }

    private func isBrowserApp(bundleId: String, appName: String) -> Bool {
        if Config.Detection.supportedBrowsers.keys.contains(bundleId) { return true }
        let bLower = bundleId.lowercased()
        let aLower = appName.lowercased()
        return bLower.contains("browser") || bLower.contains("firefox") || bLower.contains("orion") ||
               bLower.contains("zen-browser") || aLower.contains("browser") || aLower.contains("firefox") ||
               aLower.contains("whale") || aLower.contains("safari") || aLower.contains("chrome") || aLower.contains("dia")
    }

    private func isNewTabURL(_ url: String?, title: String) -> Bool {
        if let u = url?.lowercased() {
            if u.contains("newtab") || u == "about:blank" || u.contains("favorites://") || u.contains("chrome://new-tab-page") {
                return true
            }
        }
        let t = title.lowercased()
        return t == "새 탭" || t == "new tab"
    }

    private func isNewDocumentTitle(_ title: String, appName: String = "", isIDE: Bool = false) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t == "무제" || t == "untitled" || t == "새로운 메모" || t == "새로운 문서" || t == "new document" {
            return true
        }
        if t.hasPrefix("untitled-") || t.hasPrefix("● untitled-") || t.hasPrefix("* untitled-") {
            return true
        }
        if isIDE {
            let appLower = appName.lowercased()
            if t == appLower || t == "antigravity ide" || t == "antigravity" || t == "cursor" || t == "visual studio code" || t == "welcome" || t == "welcome - antigravity ide" {
                return true
            }
        }
        return false
    }

    private var lastBrowserCheckTime: Date = Date.distantPast

    private func checkBrowserTab(for bundleId: String, appName: String, pid: pid_t) {
        guard let tabInfo = BrowserTracker.shared.fetchActiveTab(for: bundleId, pid: pid) else {
            // 브라우저 탭 정보를 못 얻은 경우, 실제 화면에 창이 없는지(진짜 닫혔는지) 엄격히 검증
            if !hasOpenWindows(for: pid) {
                if !currentBrowserURL.isEmpty || !currentWindowTitle.isEmpty {
                    let closedTitle = currentWindowTitle.isEmpty ? appName : currentWindowTitle
                    let closedURL = currentBrowserURL
                    let wasAI = currentAppIsAI
                    let tool = currentAppAITool
                    let chatKey = currentChatKey

                    self.currentBrowserURL = ""
                    self.currentWindowTitle = ""
                    self.currentChatKey = ""
                    self.lastBrowserTabCount = nil
                    self.lastBrowserTabId = nil

                    emitEvent(
                        type: .close,
                        appName: appName,
                        bundleId: bundleId,
                        windowTitle: "창 종료: \(closedTitle)",
                        url: closedURL.isEmpty ? nil : closedURL,
                        isAI: wasAI,
                        aiTool: tool,
                        threadKey: chatKey.isEmpty ? nil : chatKey,
                        threadTitle: closedTitle,
                        navType: "window_close"
                    )
                }
            }
            return
        }

        // 개인 및 연구팀 제외 사이트/도메인 검사
        if PersonalExclusionManager.shared.isExcluded(bundleId: bundleId, url: tabInfo.url) {
            return
        }

        // 1. 탭 닫힘 검사 (Cmd + W 등으로 탭 개수가 감소한 경우)
        if let prevCount = lastBrowserTabCount, let currentCount = tabInfo.tabCount, currentCount < prevCount {
            let closedTitle = currentWindowTitle.isEmpty ? "탭" : currentWindowTitle
            emitEvent(
                type: .close,
                appName: appName,
                bundleId: bundleId,
                windowTitle: "탭 닫기: \(closedTitle)",
                url: currentBrowserURL.isEmpty ? nil : currentBrowserURL,
                isAI: currentAppIsAI,
                aiTool: currentAppAITool,
                threadKey: currentChatKey.isEmpty ? nil : currentChatKey,
                threadTitle: currentWindowTitle,
                navType: "tab_close"
            )
        }

        // 2. 새 탭 열림 및 변경 여부 판별
        let isNewTab = isNewTabURL(tabInfo.url, title: tabInfo.title)
        let tabCountIncreased = (lastBrowserTabCount != nil && tabInfo.tabCount != nil && tabInfo.tabCount! > lastBrowserTabCount!)
        let tabIdChanged = (lastBrowserTabId != nil && tabInfo.tabId != nil && tabInfo.tabId != lastBrowserTabId)
        let urlChanged = (tabInfo.url != currentBrowserURL)
        let titleChanged = (!tabInfo.title.isEmpty && tabInfo.title != currentWindowTitle)
        let chatChanged = (tabInfo.threadKey != nil && tabInfo.threadKey != currentChatKey)

        // 신규 탭 생성 여부: 탭 개수 증가, 새 탭 ID, 또는 기존 일반 URL에서 새 탭 화면으로 새로 전환된 경우 단 1회만 true
        let isBrandNewTab = isNewTab && (tabCountIncreased || tabIdChanged || !isNewTabURL(currentBrowserURL, title: currentWindowTitle))

        if isBrandNewTab || urlChanged || titleChanged || chatChanged {
            // 앱 활성화 직후 1.0초 이내에는 이미 handleAppActivated에서 전환을 처리했으므로 메타데이터만 동기화
            if Date().timeIntervalSince(lastAppActivationTime) < 1.0 {
                self.currentBrowserURL = tabInfo.url
                self.currentWindowTitle = tabInfo.title.isEmpty ? currentWindowTitle : tabInfo.title
                self.currentChatKey = tabInfo.threadKey ?? ""
                self.currentAppIsAI = tabInfo.isAI
                self.currentAppAITool = tabInfo.aiTool
                self.lastBrowserTabCount = tabInfo.tabCount
                self.lastBrowserTabId = tabInfo.tabId
                return
            }

            let fromDomain = URL(string: currentBrowserURL)?.host
            let toDomain = URL(string: tabInfo.url)?.host
            let fromChatId = currentChatKey
            let toChatId = tabInfo.threadKey

            let rawTitle = tabInfo.title.isEmpty ? currentWindowTitle : tabInfo.title
            let displayTitle = (isNewTab && (rawTitle.isEmpty || rawTitle == "새 탭" || rawTitle == "New Tab")) ? "새 탭 생성" : rawTitle

            // 실제 탭 제목을 상태로 저장하여 매 폴링 시 titleChanged가 무한 참이 되는 루프 방지
            self.currentBrowserURL = tabInfo.url
            self.currentWindowTitle = rawTitle
            self.currentChatKey = tabInfo.threadKey ?? ""
            self.currentAppIsAI = tabInfo.isAI
            self.currentAppAITool = tabInfo.aiTool

            if isBrandNewTab {
                // 새 탭이 열린 그 순간 단 1회만 open 발행 후 focus_in 연계
                emitEvent(
                    type: .open,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: displayTitle,
                    url: tabInfo.url.isEmpty ? nil : tabInfo.url,
                    isAI: tabInfo.isAI,
                    aiTool: tabInfo.aiTool,
                    threadKey: tabInfo.threadKey,
                    threadTitle: tabInfo.threadTitle,
                    navType: "new_window",
                    fromDomain: fromDomain,
                    toDomain: toDomain,
                    fromChatId: fromChatId,
                    toChatId: toChatId
                )
                emitEvent(
                    type: .focusIn,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: rawTitle.isEmpty ? "새 탭" : rawTitle,
                    url: tabInfo.url.isEmpty ? nil : tabInfo.url,
                    isAI: tabInfo.isAI,
                    aiTool: tabInfo.aiTool,
                    threadKey: tabInfo.threadKey,
                    threadTitle: tabInfo.threadTitle,
                    navType: "focus_in",
                    fromDomain: fromDomain,
                    toDomain: toDomain,
                    fromChatId: fromChatId,
                    toChatId: toChatId
                )
            } else if tabInfo.isAI {
                emitEvent(
                    type: .navigate,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: displayTitle,
                    url: tabInfo.url.isEmpty ? nil : tabInfo.url,
                    isAI: tabInfo.isAI,
                    aiTool: tabInfo.aiTool,
                    threadKey: tabInfo.threadKey,
                    threadTitle: tabInfo.threadTitle,
                    navType: "chat",
                    fromDomain: fromDomain,
                    toDomain: toDomain,
                    fromChatId: fromChatId,
                    toChatId: toChatId
                )
                emitEvent(
                    type: .focusIn,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: displayTitle,
                    url: tabInfo.url.isEmpty ? nil : tabInfo.url,
                    isAI: tabInfo.isAI,
                    aiTool: tabInfo.aiTool,
                    threadKey: tabInfo.threadKey,
                    threadTitle: tabInfo.threadTitle
                )
            } else {
                emitEvent(
                    type: .navigate,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: displayTitle,
                    url: tabInfo.url.isEmpty ? nil : tabInfo.url,
                    isAI: false,
                    aiTool: nil,
                    navType: "url",
                    fromDomain: fromDomain,
                    toDomain: toDomain,
                    fromChatId: fromChatId,
                    toChatId: toChatId
                )
                emitEvent(
                    type: .focusIn,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: displayTitle,
                    url: tabInfo.url.isEmpty ? nil : tabInfo.url,
                    isAI: false,
                    aiTool: nil
                )
            }
        }

        // 현재 탭 개수 및 ID 갱신 (다음 폴링 시 정확한 증감 및 변경 감지 보장)
        self.lastBrowserTabCount = tabInfo.tabCount
        self.lastBrowserTabId = tabInfo.tabId
    }

    private func checkTerminalState(for bundleId: String, appName: String, pid: pid_t) {
        let rawTitle = fetchWindowTitle(for: pid)
        let termInfo = TerminalTracker.shared.fetchActiveTerminalInfo(
            for: bundleId,
            appName: appName,
            pid: pid,
            rawWindowTitle: rawTitle
        )

        let titleChanged = (termInfo.displayTitle != currentWindowTitle)
        let commandChanged = (termInfo.activeCommand != lastTerminalCommand)
        let aiStateChanged = (termInfo.isAI != currentAppIsAI)

        if titleChanged || commandChanged || aiStateChanged {
            // 앱 활성화 직후 1.0초 이내에는 이미 handleAppActivated에서 전환을 처리했으므로 메타데이터만 동기화
            if Date().timeIntervalSince(lastAppActivationTime) < 1.0 {
                self.lastTerminalCommand = termInfo.activeCommand
                self.currentAppIsAI = termInfo.isAI
                self.currentAppAITool = termInfo.aiTool
                self.currentWindowTitle = termInfo.displayTitle
                return
            }

            let oldTitle = currentWindowTitle
            self.lastTerminalCommand = termInfo.activeCommand
            self.currentAppIsAI = termInfo.isAI
            self.currentAppAITool = termInfo.aiTool
            self.currentWindowTitle = termInfo.displayTitle

            emitEvent(
                type: .navigate,
                appName: appName,
                bundleId: bundleId,
                windowTitle: termInfo.windowTitle.isEmpty ? termInfo.displayTitle : termInfo.windowTitle,
                isAI: termInfo.isAI,
                aiTool: termInfo.aiTool,
                threadKey: termInfo.threadKey,
                threadTitle: termInfo.displayTitle,
                fromTitle: oldTitle,
                toTitle: termInfo.displayTitle,
                navType: termInfo.isAI ? "chat" : "window"
            )
            emitEvent(
                type: .focusIn,
                appName: appName,
                bundleId: bundleId,
                windowTitle: termInfo.windowTitle.isEmpty ? termInfo.displayTitle : termInfo.windowTitle,
                isAI: termInfo.isAI,
                aiTool: termInfo.aiTool,
                threadKey: termInfo.threadKey,
                threadTitle: termInfo.displayTitle
            )
        }
    }

    // MARK: - 3. 자리 비움(Idle) 트래킹 연동
    private func setupIdleTracker() {
        IdleTracker.shared.onIdleStart = { [weak self] in
            guard let self = self else { return }
            let appName = self.currentApp?.localizedName ?? "System"
            let bundleId = self.currentApp?.bundleIdentifier ?? "system"
            self.emitEvent(
                type: .idleStart,
                appName: appName,
                bundleId: bundleId,
                windowTitle: "2분 이상 입력 없음 (유휴 시작)"
            )
        }

        IdleTracker.shared.onIdleEnd = { [weak self] duration in
            guard let self = self else { return }
            let appName = self.currentApp?.localizedName ?? "System"
            let bundleId = self.currentApp?.bundleIdentifier ?? "system"
            self.emitEvent(
                type: .idleEnd,
                appName: appName,
                bundleId: bundleId,
                windowTitle: "사용자 입력 재개 (복귀)",
                idleDuration: duration
            )
            // 유휴 종료 복귀 시 보류된 설문 팝업 확인 및 노출
            SurveyScheduler.shared.handleUserReturned()
        }

        IdleTracker.shared.startMonitoring()
    }

    // MARK: - 4. 시스템 이벤트 (잠금, 잠자기) 연동
    private func setupSystemEventTracker() {
        SystemEventTracker.shared.onScreenLocked = { [weak self] in
            self?.emitEvent(
                type: .suspend,
                appName: "macOS",
                bundleId: "com.apple.loginwindow",
                windowTitle: "화면 잠금",
                suspendType: "lock"
            )
        }
        SystemEventTracker.shared.onScreenUnlocked = { [weak self] duration in
            self?.emitEvent(
                type: .resume,
                appName: "macOS",
                bundleId: "com.apple.loginwindow",
                windowTitle: "화면 잠금 해제",
                suspendType: "lock",
                suspendDuration: duration
            )
            // 화면 잠금 해제 복귀 시 보류된 설문 팝업 확인 및 노출
            SurveyScheduler.shared.handleUserReturned()
        }
        SystemEventTracker.shared.onSystemSleep = { [weak self] in
            self?.emitEvent(
                type: .suspend,
                appName: "macOS",
                bundleId: "com.apple.PowerManagement",
                windowTitle: "시스템 절전",
                suspendType: "sleep"
            )
        }
        SystemEventTracker.shared.onSystemWake = { [weak self] duration in
            self?.emitEvent(
                type: .resume,
                appName: "macOS",
                bundleId: "com.apple.PowerManagement",
                windowTitle: "시스템 기상",
                suspendType: "sleep",
                suspendDuration: duration
            )
            // 절전 해제 복귀 시 보류된 설문 팝업 확인 및 노출
            SurveyScheduler.shared.handleUserReturned()
        }
        SystemEventTracker.shared.startMonitoring()
    }

    // MARK: - 5. AI 판별 로직 (다계층 방어 체계: 정확한 번들 ID -> 퍼지/앱이름 매칭 -> 일반 IDE AI 기능 -> 메신저 봇)
    public func checkAI(for bundleId: String, windowTitle: String = "", appName: String = "") -> (isAI: Bool, aiTool: String?) {
        // 0. 사용자 직접 등록 커스텀 AI 앱 검사
        let (isCustomAI, customTool) = CustomAITargetManager.shared.isCustomAITarget(bundleId: bundleId, appName: appName, windowTitle: windowTitle)
        if isCustomAI {
            return (true, customTool ?? (appName.isEmpty ? "사용자 등록 AI" : appName))
        }

        // 1. 데스크톱 전용 AI 앱 (정확한 Bundle ID 매칭)
        if let toolName = Config.Detection.aiDesktopApps[bundleId] {
            return (true, toolName)
        }

        let bLower = bundleId.lowercased()
        let aLower = appName.lowercased()

        // 2. 데스크톱 전용 AI 앱 퍼지/키워드 방어 매칭 (Bundle ID 변형 또는 앱 이름 기준)
        // 번들 ID가 -ide 누락, com.anysphere.cursor 등 버전/패키징 차이로 변경되어도 100% 감지
        if bLower.contains("cursor") || aLower.contains("cursor") {
            return (true, "Cursor")
        }
        if bLower.contains("windsurf") || aLower.contains("windsurf") {
            return (true, "Windsurf")
        }
        if bLower.contains("antigravity") || aLower.contains("antigravity") {
            return (true, "Antigravity")
        }
        if (bLower.contains("openai") && (bLower.contains("chat") || bLower.contains("codex"))) || aLower == "chatgpt" || aLower.contains("chatgpt") {
            return (true, "ChatGPT")
        }
        if (bLower.contains("anthropic") && bLower.contains("claude")) || aLower == "claude" {
            return (true, "Claude")
        }
        if bLower.contains("lmstudio") || bLower.contains("lm-studio") || aLower.contains("lm studio") {
            return (true, "LM Studio")
        }
        if bLower.contains("ollama") || aLower == "ollama" {
            return (true, "Ollama")
        }
        if bLower.contains("jan") && (bLower.contains("janhq") || aLower == "jan") {
            return (true, "Jan")
        }
        if bLower.contains("trae") || aLower.contains("trae") {
            return (true, "Trae")
        }
        if bLower.contains("voideditor") || aLower == "void" {
            return (true, "Void")
        }
        if bLower.contains("cherry-studio") || aLower.contains("cherry studio") {
            return (true, "Cherry Studio")
        }
        if bLower.contains("chatbox") || aLower.contains("chatbox") {
            return (true, "Chatbox")
        }
        if bLower.contains("perplexity") || aLower.contains("perplexity") {
            return (true, "Perplexity")
        }
        if bLower.contains("poe") || aLower.contains("poe") {
            return (true, "Poe")
        }

        // 3. 사내 메신저(Slack, Teams, Discord, 카카오워크, 잔디 등) 내 AI 봇 대화 감지
        let isMessenger = bLower.contains("slack") ||
                          bLower.contains("teams") ||
                          bLower.contains("discord") ||
                          bLower.contains("kakaowork") ||
                          bLower.contains("jandi") ||
                          bLower.contains("lineworks")
        if isMessenger {
            let lowerTitle = windowTitle.lowercased()
            let botKeywords = ["claude", "chatgpt", "copilot", "ai bot", "챗봇", "인공지능", "gpt", "assistant", "ai 비서", "사내 ai", "ask-ai"]
            for botKeyword in botKeywords {
                if lowerTitle.contains(botKeyword) {
                    let appLabel = aLower.isEmpty ? "메신저" : appName
                    return (true, "\(appLabel) AI 봇 (\(botKeyword.capitalized))")
                }
            }
        }

        // 4. AI 터미널 판별 (Terminal, iTerm2, Warp, Ghostty 등)
        if Config.Detection.terminalBundleIDs.contains(bundleId) || bLower.contains("iterm") || bLower.contains("terminal") || bLower.contains("warp") {
            let lowerTitle = windowTitle.lowercased()
            for kw in Config.Detection.aiProcessKeywords {
                if lowerTitle.contains(kw) {
                    let toolName = (kw == "claude") ? "Claude Code" : (kw == "agy" || kw == "antigravity" ? "Antigravity CLI" : kw.capitalized)
                    return (true, toolName)
                }
            }
        }

        // 5. 일반 IDE (VS Code, VS Code Insiders, JetBrains 전 제품군, Xcode, Android Studio 등)
        let isGeneralIDE = bLower.contains("vscode") ||
                           bLower.contains("vscodium") ||
                           bLower.contains("jetbrains") ||
                           bLower.contains("android.studio") ||
                           bLower.contains("xcode") ||
                           aLower.contains("visual studio code") ||
                           aLower.contains("xcode") ||
                           aLower.contains("android studio") ||
                           aLower.contains("intellij") ||
                           aLower.contains("pycharm") ||
                           aLower.contains("webstorm") ||
                           aLower.contains("clion") ||
                           aLower.contains("goland") ||
                           aLower.contains("rider") ||
                           aLower.contains("rustrover")

        if isGeneralIDE {
            let lowerTitle = windowTitle.lowercased()
            // 5-A. 창 제목에 AI 어시스턴트 키워드가 들어있는 경우
            let aiKeywords = ["copilot", "chat", "cody", "continue", "supermaven", "tabnine", "cline", "roo", "ai assistant", "gemini"]
            for kw in aiKeywords {
                if lowerTitle.contains(kw) {
                    let toolName = (kw == "copilot") ? "GitHub Copilot" : kw.capitalized
                    return (true, toolName)
                }
            }

            // 5-B. 창 제목에 키워드가 없더라도 백그라운드에 Copilot / AI LSP가 돌고 있는 경우
            let (isProcRunning, procTool) = ProcessTracker.shared.checkAIProcessRunning()
            if isProcRunning, let tool = procTool {
                return (true, "\(tool) (IDE)")
            }
        }

        // 6. 웹 브라우저/PWA/웹뷰 창 제목 기반 AI 감지 (Firefox, Zen, Orion, PWA, Chrome 바로가기 창 등)
        let lowerTitle = windowTitle.lowercased()
        let webAIKeywords: [(kw: String, tool: String)] = [
            ("chatgpt", "ChatGPT"),
            ("claude", "Claude"),
            ("gemini", "Gemini"),
            ("perplexity", "Perplexity"),
            ("deepseek", "DeepSeek"),
            ("notebooklm", "NotebookLM"),
            ("copilot", "Copilot"),
            ("clova x", "Clova X"),
            ("뤼튼", "뤼튼 (Wrtn)"),
            ("wrtn", "뤼튼 (Wrtn)"),
            ("grok", "Grok"),
            ("mistral", "Mistral Le Chat"),
            ("poe", "Poe"),
            ("v0.dev", "v0.dev"),
            ("bolt.new", "Bolt.new"),
            ("lovable", "Lovable")
        ]
        for item in webAIKeywords {
            if lowerTitle.contains(item.kw) {
                return (true, item.tool)
            }
        }

        return (false, nil)
    }

    // MARK: - 6. 활성 창 정보 추출 (Accessibility 우선 + CoreGraphics 복합)
    private func fetchActiveWindowInfo(for pid: pid_t) -> (title: String, windowId: Int?, count: Int) {
        var axTitle = ""
        var axWinId: Int? = nil

        // 1. Accessibility API를 통해 실제 활성/포커스된 윈도우와 고유 ID 직접 조회 (100% 실시간 동기화)
        if AXIsProcessTrusted() {
            let appElement = AXUIElementCreateApplication(pid)

            // 1-A. Focused Window 시도
            var focusedVal: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedVal) == .success,
               let winElem = focusedVal as! AXUIElement? {
                if let t = extractTitle(from: winElem), !t.isEmpty {
                    axTitle = t
                }
                var wid: CGWindowID = 0
                if _AXUIElementGetWindow(winElem, &wid) == .success && wid > 0 {
                    axWinId = Int(wid)
                }
            }

            // 1-B. Main Window 시도
            if axTitle.isEmpty {
                var mainVal: AnyObject?
                if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainVal) == .success,
                   let winElem = mainVal as! AXUIElement? {
                    if let t = extractTitle(from: winElem), !t.isEmpty {
                        axTitle = t
                    }
                    if axWinId == nil {
                        var wid: CGWindowID = 0
                        if _AXUIElementGetWindow(winElem, &wid) == .success && wid > 0 {
                            axWinId = Int(wid)
                        }
                    }
                }
            }

            // 1-C. Focused UI Element의 상위 윈도우 시도 (모달 대화상자, 텍스트 입력창 포커스 대응)
            if axTitle.isEmpty {
                var focusedElemVal: AnyObject?
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElemVal) == .success,
                   let focusedElem = focusedElemVal as! AXUIElement? {
                    var parentWinVal: AnyObject?
                    if AXUIElementCopyAttributeValue(focusedElem, kAXWindowAttribute as CFString, &parentWinVal) == .success,
                       let parentWin = parentWinVal as! AXUIElement? {
                        if let t = extractTitle(from: parentWin), !t.isEmpty {
                            axTitle = t
                        }
                        if axWinId == nil {
                            var wid: CGWindowID = 0
                            if _AXUIElementGetWindow(parentWin, &wid) == .success && wid > 0 {
                                axWinId = Int(wid)
                            }
                        }
                    }
                }
            }

            // 1-D. 전체 창 목록(AXWindows)의 첫 번째 유효 창 시도
            if axTitle.isEmpty {
                var windowListValue: AnyObject?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue) == .success,
                   let windows = windowListValue as? [AXUIElement] {
                    for win in windows {
                        if let t = extractTitle(from: win), !t.isEmpty {
                            axTitle = t
                            if axWinId == nil {
                                var wid: CGWindowID = 0
                                if _AXUIElementGetWindow(win, &wid) == .success && wid > 0 {
                                    axWinId = Int(wid)
                                }
                            }
                            break
                        }
                    }
                }
            }
        }

        // 2. CoreGraphics Window List에서 해당 PID의 일반 화면 창(Layer 0, bounds > 60) 개수 및 폴백 정보 조회
        var cgWinCount = 0
        var topCgWinId: Int? = nil
        var topCgTitle = ""

        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in windowList {
                guard let ownerPid = info[kCGWindowOwnerPID as String] as? pid_t, ownerPid == pid else { continue }
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                      let height = boundsDict["Height"] as? CGFloat, height > 60,
                      let width = boundsDict["Width"] as? CGFloat, width > 60 else { continue }

                cgWinCount += 1
                if topCgWinId == nil {
                    topCgWinId = info[kCGWindowNumber as String] as? Int
                    topCgTitle = (info[kCGWindowName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        var chosenTitle = axTitle
        if chosenTitle.isEmpty {
            chosenTitle = topCgTitle
        }
        let chosenWinId = axWinId ?? topCgWinId
        let finalCount = max(cgWinCount, axWinId != nil ? 1 : 0)

        // 3. 창은 열려 있으나 제목이 완전히 비어 있는 경우 앱 명칭 기반 안전 기본값 부여 (빈 제목 방지)
        if chosenTitle.isEmpty && finalCount > 0 {
            if let runningApp = NSRunningApplication(processIdentifier: pid) {
                let name = runningApp.localizedName ?? "작업 앱"
                chosenTitle = "\(name) 작업 창"
            }
        }

        return (chosenTitle, chosenWinId, finalCount)
    }

    private func fetchWindowTitle(for pid: pid_t) -> String {
        return fetchActiveWindowInfo(for: pid).title
    }

    private func fetchWindowTitleAX(for pid: pid_t) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let appElement = AXUIElementCreateApplication(pid)

        // 1. Focused Window 시도
        var windowValue: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
           let windowElement = windowValue as! AXUIElement? {
            if let title = extractTitle(from: windowElement), !title.isEmpty {
                return title
            }
        }

        // 2. Main Window 시도
        var mainValue: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainValue) == .success,
           let mainWindowElement = mainValue as! AXUIElement? {
            if let title = extractTitle(from: mainWindowElement), !title.isEmpty {
                return title
            }
        }

        // 3. 전체 창 목록(AXWindows)의 첫 번째 창 시도
        var windowListValue: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue) == .success,
           let windows = windowListValue as? [AXUIElement] {
            for win in windows {
                if let title = extractTitle(from: win), !title.isEmpty {
                    return title
                }
            }
        }

        return ""
    }

    private func extractTitle(from windowElement: AXUIElement) -> String? {
        // 1. 기본 창 제목 (kAXTitleAttribute)
        var titleValue: AnyObject?
        if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        // 2. 문서 기반 앱(Preview, TextEdit, Pages, Xcode 등)의 AXDocument 파일 경로/URL 파싱
        var docValue: AnyObject?
        if AXUIElementCopyAttributeValue(windowElement, "AXDocument" as CFString, &docValue) == .success,
           let docStr = docValue as? String {
            let trimmed = docStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let url = URL(string: trimmed) {
                    let fname = url.lastPathComponent
                    if !fname.isEmpty { return fname }
                }
                let fname = (trimmed as NSString).lastPathComponent
                if !fname.isEmpty { return fname }
            }
        }

        // 3. 창 설명(kAXDescriptionAttribute)
        var descValue: AnyObject?
        if AXUIElementCopyAttributeValue(windowElement, kAXDescriptionAttribute as CFString, &descValue) == .success,
           let desc = descValue as? String {
            let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        // 4. 커스텀 타이틀바 앱(Obsidian, Figma, Electron 등)의 헤더 자식 요소 탐색
        var childrenVal: AnyObject?
        if AXUIElementCopyAttributeValue(windowElement, kAXChildrenAttribute as CFString, &childrenVal) == .success,
           let children = childrenVal as? [AXUIElement] {
            for child in children.prefix(6) {
                var childRole: AnyObject?
                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRole) == .success,
                   let role = childRole as? String, role == "AXStaticText" || role == "AXTextField" {
                    var childVal: AnyObject?
                    if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &childVal) == .success,
                       let text = childVal as? String {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed.count > 1 && trimmed.count < 120 {
                            return trimmed
                        }
                    }
                }
            }
        }

        return nil
    }

    private func hasOpenWindows(for pid: pid_t) -> Bool {
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in windowList {
                guard let ownerPid = info[kCGWindowOwnerPID as String] as? pid_t, ownerPid == pid else { continue }
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                      let height = boundsDict["Height"] as? CGFloat, height > 60,
                      let width = boundsDict["Width"] as? CGFloat, width > 60 else { continue }
                return true
            }
        }
        guard AXIsProcessTrusted() else { return true }
        let appElement = AXUIElementCreateApplication(pid)
        var windowListValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue)
        if result == .success, let windows = windowListValue as? [AXUIElement] {
            return !windows.isEmpty
        }
        return false
    }

    // MARK: - 7. 이벤트 발행 및 세션 매니저 전달
    public func emitEvent(
        type: ActivityEvent.EventType,
        appName: String,
        bundleId: String,
        windowTitle: String,
        url: String? = nil,
        isAI: Bool = false,
        aiTool: String? = nil,
        threadKey: String? = nil,
        threadTitle: String? = nil,
        fromApp: String? = nil,
        fromTitle: String? = nil,
        toApp: String? = nil,
        toTitle: String? = nil,
        navType: String? = nil,
        fromDomain: String? = nil,
        toDomain: String? = nil,
        fromChatId: String? = nil,
        toChatId: String? = nil,
        suspendType: String? = nil,
        idleDuration: TimeInterval? = nil,
        suspendDuration: TimeInterval? = nil,
        sessionId: UUID? = nil,
        windowId: Int? = nil
    ) {
        // 15분 동안 활동 기록 멈추기 활성화 시 일반 컴퓨터 활동 이벤트 기록 건너뜀 (정지/재개 자체 시스템 이벤트 및 팝업 끄기 이벤트는 예외)
        if AppState.shared.isRecordingPaused15Min && suspendType != "pause_15m" && suspendType != "mute_1h" {
            return
        }

        let now = Date()
        let duration = max(0, now.timeIntervalSince(lastEventTime))

        // 이전 이벤트의 지속 시간(머문 시간) 업데이트
        // (원칙: 머문 시간은 오직 실제 머물며 작업한 focus_in에만 부여됨. open, close, focus_out, navigate, idle_end 등은 시점성 전이 마일스톤)
        if var previous = lastEvent {
            if previous.eventType == .focusIn {
                previous.duration = duration
                self.lastEvent = previous
                DebugLogStore.shared.updateEventDuration(id: previous.id, duration: duration)
            }
        }
        lastEventTime = now

        var event = ActivityEvent(
            timestamp: now,
            eventType: type,
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            url: url,
            duration: nil,
            isAI: isAI,
            aiTool: aiTool,
            threadKey: threadKey,
            threadTitle: threadTitle,
            sessionId: sessionId,
            fromApp: fromApp,
            fromTitle: fromTitle,
            toApp: toApp,
            toTitle: toTitle,
            navType: navType,
            fromDomain: fromDomain,
            toDomain: toDomain,
            fromChatId: fromChatId,
            toChatId: toChatId,
            suspendType: suspendType,
            idleDuration: idleDuration,
            suspendDuration: suspendDuration,
            windowId: windowId
        )

        // 세션 매니저에 전달하여 세션 규칙 적용 및 sessionId 부여
        SessionManager.shared.processEvent(&event)
        self.lastEvent = event

        // 실시간 디버그 스토어에 추가
        DebugLogStore.shared.addEvent(event)

        // 로컬 SQLite 영구 보관 및 Supabase 오프라인 동기화 큐 저장
        LocalDatabase.shared.recordActivityEvent(event)
    }
}
