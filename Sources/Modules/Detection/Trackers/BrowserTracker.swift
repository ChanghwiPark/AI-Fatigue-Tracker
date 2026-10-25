import Foundation
import AppKit

/// 활성 브라우저(Safari, Chrome, Arc, Edge, Brave, Dia)의 활성 탭 URL 및 페이지 제목, 대화 스레드 키를 추출합니다.
public final class BrowserTracker {
    public static let shared = BrowserTracker()

    public struct TabInfo {
        public let url: String
        public let title: String
        public let isAI: Bool
        public let aiTool: String?
        public let threadKey: String?
        public let threadTitle: String?
        public let tabId: String?
        public let tabCount: Int?
    }

    private init() {}

    /// 브라우저 활성 탭 정보 추출 (AppleScript 1차 + Accessibility API 2차 폴백)
    public func fetchActiveTab(for bundleId: String, pid: pid_t? = nil) -> TabInfo? {
        // 1. AppleScript 기반 정밀 추출 (URL, 탭 제목, 탭 수 등)
        if let scriptName = Config.Detection.supportedBrowsers[bundleId] {
            if let tabInfo = fetchViaAppleScript(bundleId: bundleId, scriptName: scriptName) {
                return tabInfo
            }
        }

        // 2. AppleScript 미지원 브라우저(Firefox, Zen 등) 또는 스크립트 실패/지연 시 Accessibility API 폴백
        let targetPid: pid_t? = pid ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.processIdentifier
        if let p = targetPid, let axInfo = fetchViaAccessibility(bundleId: bundleId, pid: p) {
            return axInfo
        }

        return nil
    }

    /// 1차: AppleScript를 통한 브라우저 탭 정보 추출
    private func fetchViaAppleScript(bundleId: String, scriptName: String) -> TabInfo? {
        let scriptSource: String
        if bundleId == "com.apple.Safari" || bundleId.contains("Safari") {
            scriptSource = """
            tell application "Safari"
                if (count of windows) > 0 then
                    set currentTab to current tab of front window
                    set tabUrl to ""
                    try
                        set tabUrl to URL of currentTab
                    end try
                    if tabUrl is missing value then set tabUrl to ""
                    
                    set tabTitle to ""
                    try
                        set tabTitle to name of currentTab
                    end try
                    if tabTitle is missing value then set tabTitle to ""
                    
                    set tabCnt to 0
                    try
                        set tabCnt to count of tabs of front window
                    end try
                    
                    set tabIdStr to ""
                    try
                        set tabIdStr to "" & (index of currentTab)
                    end try
                    
                    return {"" & tabUrl, "" & tabTitle, tabCnt, tabIdStr}
                end if
            end tell
            """
        } else {
            // Chromium 계열 (Chrome, Arc, Edge, Brave, Dia, Whale, Opera, Vivaldi 등)
            scriptSource = """
            tell application "\(scriptName)"
                if (count of windows) > 0 then
                    set activeTab to active tab of front window
                    set tabUrl to ""
                    try
                        set tabUrl to URL of activeTab
                    end try
                    if tabUrl is missing value then set tabUrl to ""
                    
                    set tabTitle to ""
                    try
                        set tabTitle to title of activeTab
                    on error
                        try
                            set tabTitle to name of activeTab
                        end try
                    end try
                    if tabTitle is missing value then set tabTitle to ""
                    
                    set tabCnt to 0
                    try
                        set tabCnt to count of tabs of front window
                    end try
                    
                    set tabIdStr to ""
                    try
                        set tabIdStr to "" & (id of activeTab)
                    on error
                        try
                            set tabIdStr to "" & (index of activeTab)
                        end try
                    end try
                    
                    return {"" & tabUrl, "" & tabTitle, tabCnt, tabIdStr}
                end if
            end tell
            """
        }

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        let descriptor = script.executeAndReturnError(&errorInfo)

        if errorInfo != nil || descriptor.numberOfItems < 2 {
            return nil
        }

        let rawURL = descriptor.atIndex(1)?.stringValue ?? ""
        let rawTitle = descriptor.atIndex(2)?.stringValue ?? ""
        let tabCount: Int? = descriptor.numberOfItems >= 3 ? Int(descriptor.atIndex(3)?.int32Value ?? 0) : nil
        let tabId: String? = descriptor.numberOfItems >= 4 ? descriptor.atIndex(4)?.stringValue : nil

        if rawURL.isEmpty && rawTitle.isEmpty {
            return nil
        }

        let cleanTitle = Self.cleanBrowserTabTitle(rawTitle)
        let sanitizedURL = rawURL.isEmpty ? "" : sanitizeURL(rawURL)

        let (isAI, aiTool) = rawURL.isEmpty ? checkWebAIFromTitle(cleanTitle) : checkWebAI(url: rawURL)
        let (threadKey, threadTitle) = extractThreadInfo(url: rawURL, rawTitle: cleanTitle, isAI: isAI, aiTool: aiTool)

        return TabInfo(
            url: sanitizedURL,
            title: cleanTitle,
            isAI: isAI,
            aiTool: aiTool,
            threadKey: threadKey,
            threadTitle: threadTitle,
            tabId: tabId,
            tabCount: tabCount
        )
    }

    /// 2차: Accessibility API를 통한 브라우저 탭 및 창 제목 추출 (모든 브라우저 호환)
    private func fetchViaAccessibility(bundleId: String, pid: pid_t) -> TabInfo? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)

        var winElement: AXUIElement?

        var focusedVal: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedVal) == .success,
           let win = focusedVal as! AXUIElement? {
            winElement = win
        } else {
            var mainVal: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainVal) == .success,
               let win = mainVal as! AXUIElement? {
                winElement = win
            }
        }

        guard let win = winElement else { return nil }

        var rawWinTitle = ""
        var titleVal: AnyObject?
        if AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleVal) == .success,
           let str = titleVal as? String {
            rawWinTitle = str.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let cleanTitle = Self.cleanBrowserTabTitle(rawWinTitle)
        if cleanTitle.isEmpty { return nil }

        // AXDocument 또는 주소창에서 URL 추출 시도
        var extractedURL = ""
        var docVal: AnyObject?
        if AXUIElementCopyAttributeValue(win, "AXDocument" as CFString, &docVal) == .success,
           let docStr = docVal as? String, docStr.hasPrefix("http") {
            extractedURL = docStr
        }

        if extractedURL.isEmpty {
            extractedURL = findURLFromAddressField(in: win) ?? ""
        }

        let sanitizedURL = extractedURL.isEmpty ? "" : sanitizeURL(extractedURL)

        let (isAI, aiTool) = !extractedURL.isEmpty ? checkWebAI(url: extractedURL) : checkWebAIFromTitle(cleanTitle)
        let (threadKey, threadTitle) = extractThreadInfo(
            url: extractedURL,
            rawTitle: cleanTitle,
            isAI: isAI,
            aiTool: aiTool
        )

        return TabInfo(
            url: sanitizedURL,
            title: cleanTitle,
            isAI: isAI,
            aiTool: aiTool,
            threadKey: threadKey ?? (isAI ? "\(aiTool?.lowercased() ?? "ai")_\(cleanTitle)" : nil),
            threadTitle: threadTitle ?? (isAI ? cleanTitle : nil),
            tabId: nil,
            tabCount: nil
        )
    }

    /// 브라우저 윈도우 UI 내부의 주소창(AXTextField) 검색
    private func findURLFromAddressField(in element: AXUIElement) -> String? {
        var childrenVal: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenVal) == .success,
              let children = childrenVal as? [AXUIElement] else { return nil }

        for child in children {
            var roleVal: AnyObject?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleVal) == .success,
               let role = roleVal as? String {
                if role == "AXTextField" {
                    var val: AnyObject?
                    if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &val) == .success,
                       let str = val as? String {
                        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                            return trimmed
                        }
                    }
                }
                if role == "AXGroup" || role == "AXSplitGroup" || role == "AXToolbar" {
                    var subChildrenVal: AnyObject?
                    if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &subChildrenVal) == .success,
                       let subChildren = subChildrenVal as? [AXUIElement] {
                        for sub in subChildren {
                            var subRole: AnyObject?
                            if AXUIElementCopyAttributeValue(sub, kAXRoleAttribute as CFString, &subRole) == .success,
                               let sRole = subRole as? String, sRole == "AXTextField" {
                                var val: AnyObject?
                                if AXUIElementCopyAttributeValue(sub, kAXValueAttribute as CFString, &val) == .success,
                                   let str = val as? String {
                                    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                                        return trimmed
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    /// 브라우저 명칭, 창 래퍼 및 프로필 접미사 제거 유틸리티
    public static func cleanBrowserTabTitle(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }

        let browserSuffixes = [
            " - Google Chrome",
            " - Chrome",
            " — Safari",
            " - Safari",
            " — Arc",
            " - Arc",
            " - Microsoft Edge",
            " - Brave",
            " - Dia",
            " - Whale",
            " — Mozilla Firefox",
            " - Mozilla Firefox",
            " - Firefox",
            " - Vivaldi",
            " - Opera",
            " - Orion",
            " - Zen Browser"
        ]

        for s in browserSuffixes {
            if let range = t.range(of: s) {
                t = String(t[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        for p in ["Safari — ", "Firefox — ", "Arc — "] {
            if t.hasPrefix(p) {
                t = String(t.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return t
    }

    /// 제목 키워드 기반 AI 판별 (URL이 없거나 AX 폴백 시 사용)
    public func checkWebAIFromTitle(_ title: String) -> (isAI: Bool, aiTool: String?) {
        let lower = title.lowercased()

        // 0. 사용자 직접 등록 커스텀 AI 도메인/앱 명칭 대조
        for target in CustomAITargetManager.shared.customDomains + CustomAITargetManager.shared.customApps {
            if lower.contains(target.value) || lower.contains(target.displayName.lowercased()) {
                return (true, target.displayName)
            }
        }

        let keywords: [(kw: String, tool: String)] = [
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
        for item in keywords {
            if lower.contains(item.kw) {
                return (true, item.tool)
            }
        }
        return (false, nil)
    }

    /// AI 웹 URL 및 탭 제목으로부터 스레드 식별키(threadKey) 및 제목(threadTitle) 추출
    public func extractThreadInfo(url urlString: String, rawTitle: String, isAI: Bool, aiTool: String?) -> (threadKey: String?, threadTitle: String?) {
        guard isAI else { return (nil, nil) }

        let t = Self.cleanBrowserTabTitle(rawTitle)
        var title = t
        for suffix in [" - Claude", " · Claude", " - ChatGPT", " | ChatGPT", " - Gemini", " - Perplexity"] {
            if title.hasSuffix(suffix) {
                title = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for prefix in ["ChatGPT - ", "Claude - ", "Gemini - "] {
            if title.hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let cleanTitle = title.isEmpty ? (aiTool ?? "Web AI") : title

        if let url = URL(string: urlString), let host = url.host?.lowercased() {
            let path = url.path
            let threadKey: String
            if path.isEmpty || path == "/" {
                threadKey = "\(host)/new"
            } else {
                threadKey = "\(host)\(path)"
            }
            return (threadKey, cleanTitle)
        } else {
            let toolKey = (aiTool ?? "web_ai").lowercased().replacingOccurrences(of: " ", with: "_")
            let threadKey = "\(toolKey)_\(cleanTitle)"
            return (threadKey, cleanTitle)
        }
    }

    /// URL 모드에 따른 정제 ("domain" or "full" without query parameters)
    public func sanitizeURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }

        if Config.Detection.urlMode == "domain" {
            return url.host ?? urlString
        } else {
            // "full": 쿼리 스트링(?...)과 프래그먼트(#...) 제외한 전체 주소
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.query = nil
            components?.fragment = nil
            return components?.string ?? urlString
        }
    }

    /// AI 웹 도메인 목록, 커스텀 사내 도메인, 브라우저 확장 및 사내 AI 패턴과 대조하여 AI 여부 및 도구명 판별
    public func checkWebAI(url urlString: String) -> (isAI: Bool, aiTool: String?) {
        // 1. 크롬 익스텐션 전용 URL 감지 (chrome-extension://...)
        if urlString.hasPrefix("chrome-extension://") {
            return (true, "브라우저 AI 확장")
        }

        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return (false, nil)
        }

        // 2. 등록된 퍼블릭 AI 웹 도메인 검사
        for aiDomain in Config.Detection.aiWebDomains {
            if host == aiDomain || host.hasSuffix("." + aiDomain) {
                let toolName = aiDisplayName(for: aiDomain)
                return (true, toolName)
            }
        }

        // 3. 사용자 직접 등록 사내 AI / 커스텀 AI 도메인 검사 (CustomAITargetManager)
        let (isCustomDomain, customDomainTool) = CustomAITargetManager.shared.isCustomAIDomain(urlOrHost: host)
        if isCustomDomain {
            return (true, customDomainTool ?? "사용자 등록 AI (\(host))")
        }

        // 4. 사내 AI 포털 휴리스틱 패턴 매칭 (예: ai.corp.com, llm.company.internal, gpt.mycompany 등)
        if host.hasPrefix("ai.") || host.hasPrefix("llm.") || host.hasPrefix("gpt.") ||
           host.hasPrefix("chatgpt.") || host.hasPrefix("chat-ai.") ||
           host.contains("-ai.") || host.contains(".ai.") {
            return (true, "사내 AI 포털 (\(host))")
        }

        // 5. Hugging Face Chat 등 특정 서브패스 AI
        if host == "huggingface.co" && url.path.hasPrefix("/chat") {
            return (true, "Hugging Face Chat")
        }

        return (false, nil)
    }

    public func aiDisplayName(for domain: String) -> String {
        switch domain {
        case "claude.ai": return "Claude"
        case "chatgpt.com", "chat.openai.com": return "ChatGPT"
        case "gemini.google.com": return "Gemini"
        case "perplexity.ai": return "Perplexity"
        case "copilot.microsoft.com": return "Copilot"
        case "deepseek.com": return "DeepSeek"
        case "clova-x.naver.com": return "Clova X"
        case "wrtn.ai": return "뤼튼 (Wrtn)"
        case "chat.mistral.ai": return "Mistral Le Chat"
        case "poe.com": return "Poe"
        case "groq.com": return "Groq"
        case "v0.dev": return "v0.dev"
        case "genspark.ai": return "Genspark"
        case "notebooklm.google.com": return "NotebookLM"
        case "bolt.new": return "Bolt.new"
        case "lovable.dev": return "Lovable"
        case "grok.com", "x.ai": return "Grok"
        case "phind.com": return "Phind"
        case "cursor.com", "cursor.directory": return "Cursor Web"
        case "monica.im": return "Monica AI"
        case "sider.ai": return "Sider AI"
        case "harpa.ai": return "Harpa AI"
        case "liner.ai": return "Liner AI"
        default: return domain
        }
    }
}
