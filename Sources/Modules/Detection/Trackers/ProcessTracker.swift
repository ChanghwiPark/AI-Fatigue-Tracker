import Foundation
import Darwin

/// 터미널(Terminal, iTerm2, Warp, Ghostty) 활성 상태에서 claude, codex 등 AI CLI 프로세스가 돌고 있는지 감지합니다.
public final class ProcessTracker {
    public static let shared = ProcessTracker()

    private var cachedResult: (isRunning: Bool, tool: String?) = (false, nil)
    private var lastCheckTime: Date = .distantPast
    private let cacheInterval: TimeInterval = 2.0

    private init() {}

    /// AI CLI 프로세스 실행 여부 확인
    public func checkAIProcessRunning() -> (isRunning: Bool, tool: String?) {
        let now = Date()
        if now.timeIntervalSince(lastCheckTime) < cacheInterval {
            return cachedResult
        }

        lastCheckTime = now

        for keyword in Config.Detection.aiProcessKeywords {
            if isProcessRunning(named: keyword) {
                let toolName: String
                if keyword == "claude" {
                    toolName = "Claude Code"
                } else if keyword.contains("copilot") {
                    toolName = "GitHub Copilot"
                } else if keyword == "agy" || keyword == "antigravity" {
                    toolName = "Antigravity CLI"
                } else if keyword == "cline" {
                    toolName = "Cline CLI"
                } else if keyword == "roo" {
                    toolName = "Roo Code CLI"
                } else {
                    toolName = keyword.capitalized
                }
                cachedResult = (true, toolName)
                return cachedResult
            }
        }

        cachedResult = (false, nil)
        return cachedResult
    }

    /// libproc API를 활용한 가볍고 빠른 프로세스 명 및 경로 검색
    private func isProcessRunning(named keyword: String) -> Bool {
        let numberOfProcesses = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard numberOfProcesses > 0 else { return false }

        var pids = [pid_t](repeating: 0, count: Int(numberOfProcesses))
        let bytesCopied = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, numberOfProcesses * Int32(MemoryLayout<pid_t>.size))

        let count = Int(bytesCopied) / MemoryLayout<pid_t>.size
        var nameBuffer = [CChar](repeating: 0, count: 1024)
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let kwLower = keyword.lowercased()

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }


            // 2. 전체 실행 파일 경로 검사 (예: ~/.local/bin/claude)
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            if pathLength > 0 {
                let path = String(cString: pathBuffer).lowercased()
                // 데스크톱 GUI 앱(Claude.app, ChatGPT.app 등)은 bundleID로 별도 감지되므로 제외
                if path.contains("/applications/claude.app") ||
                   path.contains("/applications/chatgpt.app") ||
                   path.contains("/applications/cursor.app") {
                    continue
                }

                let fileName = URL(fileURLWithPath: path).lastPathComponent
                if fileName == kwLower || fileName.hasPrefix(kwLower) {
                    return true
                }
            }

            // 1. 프로세스 이름 검사 (경로가 GUI 앱이 아닌 경우에만)
            let length = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            if length > 0 {
                let name = String(cString: nameBuffer).lowercased()
                if (name == kwLower || name.contains(kwLower)) && !name.contains("helper") {
                    return true
                }
            }
        }

        // 3. 커맨드라인 인자 검사 (node, python, bun 등 래퍼 하위 실행 CLI 대응)
        if checkProcessArguments(named: kwLower) {
            return true
        }

        return false
    }

    private func checkProcessArguments(named keyword: String) -> Bool {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-fli", keyword]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let lines = output.split(separator: "\n").filter {
                    let lower = $0.lowercased()
                    return !lower.contains("aifatiguetracker") &&
                           !lower.contains("pgrep") &&
                           !lower.contains("/applications/claude.app") &&
                           !lower.contains("/applications/chatgpt.app") &&
                           !lower.contains("/applications/cursor.app") &&
                           !lower.contains("helper")
                }
                return !lines.isEmpty
            }
        } catch {
            return false
        }
        return false
    }
}
