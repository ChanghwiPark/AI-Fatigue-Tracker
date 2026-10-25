import Foundation
import AppKit

/// 터미널(Terminal, iTerm2, Warp, Ghostty 등)에서 실행 중인 명령어 및 AI CLI 도구(Claude Code, Aider 등) 추적기
public final class TerminalTracker {
    public static let shared = TerminalTracker()

    public struct TerminalInfo {
        public let appName: String
        public let windowTitle: String
        public let activeCommand: String
        public let commandDetails: String?
        public let isAI: Bool
        public let aiTool: String?
        public let tty: String?
        public let threadKey: String
        public let displayTitle: String
    }

    private let appleTerminalScript: NSAppleScript? = {
        let source = """
        tell application "Terminal"
            if running and (count of windows) > 0 then
                tell front window
                    set wName to name
                    set tTab to selected tab
                    set tProcs to processes of tTab
                    set tCustom to custom title of tTab
                    set tTty to tty of tTab
                    set AppleScript's text item delimiters to ", "
                    set procsStr to (tProcs as string)
                    return wName & "|||" & tCustom & "|||" & tTty & "|||" & procsStr
                end tell
            end if
        end tell
        """
        return NSAppleScript(source: source)
    }()

    private let itermScript: NSAppleScript? = {
        let source = """
        tell application "iTerm2"
            if running and (count of windows) > 0 then
                tell current session of current window
                    return name & "|||" & (current command) & "|||" & tty
                end tell
            end if
        end tell
        """
        return NSAppleScript(source: source)
    }()

    private var cachedInfo: TerminalInfo?
    private var lastFetchTime: Date = .distantPast
    private let cacheInterval: TimeInterval = 0.8

    private init() {}

    /// 활성 터미널의 현재 실행 명령 및 AI 도구 정보 획득
    public func fetchActiveTerminalInfo(
        for bundleId: String,
        appName: String,
        pid: pid_t,
        rawWindowTitle: String
    ) -> TerminalInfo {
        let now = Date()
        if let cached = cachedInfo,
           now.timeIntervalSince(lastFetchTime) < cacheInterval,
           cached.appName == appName {
            return cached
        }

        var activeCommand = "zsh"
        var commandDetails: String? = nil
        var tty: String? = nil
        var extractedWindowTitle = rawWindowTitle

        if bundleId == "com.apple.Terminal" {
            if let result = executeAppleScript(appleTerminalScript) {
                let parts = result.components(separatedBy: "|||")
                if parts.count >= 4 {
                    let wName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let customTitle = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    tty = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                    let procsRaw = parts[3]

                    if !wName.isEmpty { extractedWindowTitle = wName }
                    else if !customTitle.isEmpty { extractedWindowTitle = customTitle }

                    // processes 파싱 (예: "login, -zsh, Python" 또는 "login, -zsh, claude")
                    let procs = procsRaw.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                        .filter { !$0.isEmpty && !isShellInfrastructure($0) }

                    if let lastCmd = procs.last {
                        activeCommand = lastCmd
                    } else {
                        activeCommand = "zsh (명령 대기)"
                    }
                }
            }
        } else if bundleId == "com.googlecode.iterm2" {
            if let result = executeAppleScript(itermScript) {
                let parts = result.components(separatedBy: "|||")
                if parts.count >= 3 {
                    let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let currCmd = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    tty = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)

                    if !name.isEmpty { extractedWindowTitle = name }
                    if !currCmd.isEmpty && !isShellInfrastructure(currCmd) {
                        activeCommand = currCmd
                    } else {
                        activeCommand = "zsh (명령 대기)"
                    }
                }
            }
        }

        // TTY가 확인되면 ps를 통해 상세 명령어 인자 보강 (예: "claude", "git status", "python train.py")
        if let ttyDevice = tty, !ttyDevice.isEmpty {
            let ttyShort = ttyDevice.replacingOccurrences(of: "/dev/", with: "")
            if let detailedCmd = fetchCommandFromTTY(ttyShort) {
                commandDetails = detailedCmd
                let firstWord = detailedCmd.components(separatedBy: " ").first?.lowercased() ?? ""
                let baseName = URL(fileURLWithPath: firstWord).lastPathComponent
                if !baseName.isEmpty && !isShellInfrastructure(baseName) {
                    activeCommand = baseName
                }
            }
        } else {
            // TTY를 못 얻은 터미널의 경우 PID 기반 하위 프로세스 조회
            if let childCmd = fetchChildProcessCommand(for: pid) {
                commandDetails = childCmd
                let firstWord = childCmd.components(separatedBy: " ").first?.lowercased() ?? ""
                let baseName = URL(fileURLWithPath: firstWord).lastPathComponent
                if !baseName.isEmpty && !isShellInfrastructure(baseName) {
                    activeCommand = baseName
                }
            }
        }

        // 터미널 창 제목 폴백: 창 제목이 "user — Python -q — 80x24" 형태인 경우 명령 추출
        if activeCommand.contains("대기") || isShellInfrastructure(activeCommand) {
            let titleParts = extractedWindowTitle.components(separatedBy: "—")
            if titleParts.count >= 3 {
                let candidate = titleParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && !isShellInfrastructure(candidate) {
                    commandDetails = candidate
                    let firstWord = candidate.components(separatedBy: " ").first?.lowercased() ?? ""
                    let baseName = URL(fileURLWithPath: firstWord).lastPathComponent
                    if !baseName.isEmpty && !isShellInfrastructure(baseName) {
                        activeCommand = baseName
                    }
                }
            }
        }

        // AI 도구 판별
        let (isAI, aiTool) = determineAI(activeCommand: activeCommand, commandDetails: commandDetails)

        let safeTty = tty ?? (extractedWindowTitle.isEmpty ? "default" : extractedWindowTitle)
        let threadKey: String
        let displayTitle: String

        if isAI, let tool = aiTool {
            threadKey = "terminal_\(bundleId)_\(tool)_\(safeTty)"
            let clean = Self.cleanCommandLine(commandDetails ?? activeCommand)
            displayTitle = clean.isEmpty ? "\(tool) (터미널)" : "\(tool) [\(clean)]"
        } else {
            threadKey = "terminal_\(bundleId)_\(safeTty)"
            if activeCommand.contains("대기") || isShellInfrastructure(activeCommand) {
                displayTitle = "\(appName) (명령 대기)"
            } else {
                let clean = Self.cleanCommandLine(commandDetails ?? activeCommand)
                displayTitle = clean.isEmpty ? "\(appName) [\(activeCommand)]" : "\(appName) [\(clean)]"
            }
        }

        let info = TerminalInfo(
            appName: appName,
            windowTitle: extractedWindowTitle,
            activeCommand: activeCommand,
            commandDetails: commandDetails,
            isAI: isAI,
            aiTool: aiTool,
            tty: tty,
            threadKey: threadKey,
            displayTitle: displayTitle
        )

        self.cachedInfo = info
        self.lastFetchTime = now
        return info
    }

    // MARK: - 내부 헬퍼 로직

    /// 긴 절대 경로와 환경 래퍼(node, python, npx 등)를 정리하여 직관적인 명령줄 문자열로 변환
    public static func cleanCommandLine(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var tokens = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        guard let first = tokens.first else { return trimmed }

        let baseFirst = URL(fileURLWithPath: first).lastPathComponent
        tokens[0] = baseFirst

        let wrappers: Set<String> = ["node", "python", "python3", "sudo", "env", "bun", "npx", "sh", "bash"]
        if wrappers.contains(baseFirst.lowercased()) && tokens.count > 1 {
            let second = tokens[1]
            if !second.hasPrefix("-") {
                tokens[1] = URL(fileURLWithPath: second).lastPathComponent
            }
        }

        let cleaned = tokens.joined(separator: " ")
        if cleaned.count > 42 {
            return String(cleaned.prefix(39)) + "..."
        }
        return cleaned
    }

    private func isShellInfrastructure(_ name: String) -> Bool {
        let cleaned = URL(fileURLWithPath: name).lastPathComponent.lowercased()
        let shells: Set<String> = [
            "login", "zsh", "bash", "sh", "fish", "csh", "tcsh",
            "-zsh", "-bash", "-sh", "screen", "tmux"
        ]
        return shells.contains(cleaned)
    }

    private func determineAI(activeCommand: String, commandDetails: String?) -> (Bool, String?) {
        let cmdLower = activeCommand.lowercased()
        let fullLower = commandDetails?.lowercased() ?? ""

        // 키워드 매핑 테이블
        let aiMap: [String: String] = [
            "claude": "Claude Code",
            "codex": "OpenAI Codex",
            "aider": "Aider",
            "ollama": "Ollama",
            "gemini": "Gemini CLI",
            "copilot": "GitHub Copilot",
            "interpreter": "Open Interpreter",
            "open-interpreter": "Open Interpreter",
            "sgpt": "Shell GPT",
            "agy": "Antigravity CLI",
            "antigravity": "Antigravity CLI",
            "cursor-agent": "Cursor Agent",
            "cline": "Cline CLI",
            "roo": "Roo Code CLI",
            "goose": "Goose AI",
            "llm": "LLM CLI",
            "vllm": "vLLM",
            "plandex": "Plandex",
            "fabric": "Fabric CLI",
            "gptscript": "GPTScript",
            "mentat": "Mentat",
            "cody": "Sourcegraph Cody"
        ]

        // 키워드 매핑 테이블 (터미널 탭 자체의 명령어 및 커맨드라인 인자 검사)
        for (kw, name) in aiMap {
            if cmdLower == kw || cmdLower.contains(kw) || fullLower.contains(kw) {
                return (true, name)
            }
        }

        return (false, nil)
    }

    private func executeAppleScript(_ script: NSAppleScript?) -> String? {
        guard let script = script else { return nil }
        var errorDict: NSDictionary?
        let resultDescriptor = script.executeAndReturnError(&errorDict)
        if errorDict == nil, let stringValue = resultDescriptor.stringValue {
            return stringValue
        }
        return nil
    }

    private func fetchCommandFromTTY(_ ttyShort: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-t", ttyShort, "-o", "command="]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
                // login, shell 제외하고 가장 마지막에 실행된 커맨드 라인 반환
                for line in lines.reversed() {
                    let first = line.components(separatedBy: " ").first?.lowercased() ?? ""
                    let base = URL(fileURLWithPath: first).lastPathComponent
                    if !base.isEmpty && !isShellInfrastructure(base) {
                        return line
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func fetchChildProcessCommand(for pid: pid_t) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(pid)"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let pids = output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
                for childPid in pids {
                    // 손자 프로세스 검사 (쉘 아래에서 돌아가는 커맨드)
                    if let grandChildCmd = fetchChildProcessCommand(for: childPid) {
                        return grandChildCmd
                    }
                    if let cmd = fetchCommandForPid(childPid) {
                        let first = cmd.components(separatedBy: " ").first?.lowercased() ?? ""
                        let base = URL(fileURLWithPath: first).lastPathComponent
                        if !isShellInfrastructure(base) {
                            return cmd
                        }
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func fetchCommandForPid(_ pid: pid_t) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "command="]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        } catch {
            return nil
        }
        return nil
    }
}
