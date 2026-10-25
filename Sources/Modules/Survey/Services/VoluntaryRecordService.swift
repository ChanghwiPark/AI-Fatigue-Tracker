import Foundation
import AppKit

/// 자발적 피로 기록 시 수집되는 화면 캡처 및 직전 작업 맥락 정보
public struct VoluntaryCaptureContext: Codable {
    public var appName: String
    public var bundleId: String?
    public var windowTitle: String?
    public var url: String?
    public var capturedAt: Date
    public var sessionId: UUID?
    public var sessionTitle: String?
    public var localImagePath: String?
    public var isFromNudge: Bool
    public var customTitle: String?
    public var customSubtitle: String?

    public init(
        appName: String = "알 수 없음",
        bundleId: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        capturedAt: Date = Date(),
        sessionId: UUID? = nil,
        sessionTitle: String? = nil,
        localImagePath: String? = nil,
        isFromNudge: Bool = false,
        customTitle: String? = nil,
        customSubtitle: String? = nil
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.url = url
        self.capturedAt = capturedAt
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        self.localImagePath = localImagePath
        self.isFromNudge = isFromNudge
        self.customTitle = customTitle
        self.customSubtitle = customSubtitle
    }
}

/// 자발적 피로 기록(단축키 ⌥⌘S 또는 메뉴 막대 클릭) 플로우 및 화면 캡처 오케스트레이터
public final class VoluntaryRecordService {
    public static let shared = VoluntaryRecordService()

    private let capturesDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AIFatigueTracker/Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.capturesDirectory = dir
    }

    /// 자발적 기록 전체 플로우 시작 (즉시 피로 기록):
    /// 1) 화면 기록 권한 사전 점검
    /// 2) 직전 최상단 앱 및 세션 맥락 포착
    /// 3) 전체 화면 자동 캡처 실행 (screencapture -x)
    /// 4) 결과와 함께 우상단 자발적 피로 기록 팝업 띄움
    public func startFlow() {
        DispatchQueue.main.async {
            // 0. 열려 있는 메뉴 막대 패널이 있다면 즉시 닫음
            MenuBarAccessHelper.closeMenuBarExtra()

            // 1. 화면 기록 권한 확인 및 미허용 시 시스템 요청
            if #available(macOS 11.0, *) {
                if !CGPreflightScreenCaptureAccess() {
                    print("[VoluntaryRecord] 화면 기록 권한 미부여 -> 시스템 권한 요청 실행")
                    PermissionsManager.shared.requestScreenCapture()

                    let alert = NSAlert()
                    alert.messageText = "화면 기록 권한이 필요합니다"
                    alert.informativeText = "피로한 순간의 실제 앱 창을 캡처하여 함께 저장하려면 화면 기록 권한이 필요합니다.\n\n1. 열린 시스템 설정 창에서 'AIFatigueTracker.app'의 스위치를 켜주세요.\n2. macOS 안내창이 뜨면 '종료 및 다시 열기'를 눌러주세요."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "설정 확인")
                    alert.addButton(withTitle: "취소")
                    if alert.runModal() == .alertFirstButtonReturn {
                        PermissionsManager.shared.openSystemSettings(pane: "Privacy_ScreenCapture")
                    }
                    return
                }
            }

            // 2. 현재 직전 최상단 앱 및 브라우저 맥락 포착
            var context = self.captureActiveContext()
            context.isFromNudge = false

            // 3. 메뉴 막대 패널이 화면에서 완전히 접히고 그래픽 버퍼가 갱신되도록 200ms 딜레이 후 전체 화면 자동 캡처 시작
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                self.executeFullScreenCapture { capturedImagePath in
                    context.localImagePath = capturedImagePath

                    // 4. 우상단 자발적 피로 기록 팝업 띄움
                    SurveyWindowManager.shared.showVoluntaryPopup(context: context)
                }
            }
        }
    }

    /// 미기록 넛지("오늘은 AI 때문에 피로한 순간이 있었나요?")에서 "기록하기" 클릭 시 실행되는 회고 다이어리 플로우:
    /// - 캡처가 자동이 아니라 선택적으로 실행됨 (기본적으로 캡처 없이 즉시 열리며, 필요 시 원하는 부분 선택 캡처 가능)
    /// - 넛지 전용 제목("오늘의 AI 피로 기록") 적용
    public func startNudgeReflectionFlow() {
        DispatchQueue.main.async {
            var context = self.captureActiveContext()
            context.isFromNudge = true
            context.localImagePath = nil // 자동 캡처하지 않고 선택적으로 첨부하도록 함
            context.customTitle = "오늘의 AI 피로 기록"
            context.customSubtitle = "떠오르는 순간을 기록해요"

            SurveyWindowManager.shared.showVoluntaryPopup(context: context)
        }
    }

    /// "다시 캡처" 기능: 팝업을 잠시 숨긴 후 전체 화면을 다시 캡처하여 복귀
    public func retakeCapture(completion: @escaping (String?) -> Void) {
        if #available(macOS 11.0, *) {
            if !CGPreflightScreenCaptureAccess() {
                PermissionsManager.shared.requestScreenCapture()
                completion(nil)
                return
            }
        }
        // 창이 완전히 숨겨진 후 캡처되도록 150ms 딜레이 부여
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.executeFullScreenCapture(completion: completion)
        }
    }

    /// "원하는 부분(영역) 선택 캡처" 기능: 팝업을 잠시 숨긴 후 macOS 대화형 사각 드래그 캡처(-i -x) 실행
    public func retakeAreaCapture(completion: @escaping (String?) -> Void) {
        if #available(macOS 11.0, *) {
            if !CGPreflightScreenCaptureAccess() {
                PermissionsManager.shared.requestScreenCapture()
                completion(nil)
                return
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.executeAreaCapture(completion: completion)
        }
    }

    /// 원하는 영역 선택 캡처 (screencapture -i -x)
    public func executeAreaCapture(completion: @escaping (String?) -> Void) {
        let filename = "capture_area_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).png"
        let targetURL = self.capturesDirectory.appendingPathComponent(filename)
        let targetPath = targetURL.path

        DispatchQueue.global(qos: .userInteractive).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", targetPath]

            do {
                try process.run()
                process.waitUntilExit()

                if FileManager.default.fileExists(atPath: targetPath),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: targetPath),
                   let size = attrs[.size] as? UInt64, size > 100 {
                    print("[VoluntaryRecord] 영역 캡처 성공: \(targetPath) (\(size) bytes)")
                    DispatchQueue.main.async {
                        completion(targetPath)
                    }
                    return
                }
            } catch {
                print("[VoluntaryRecord] screencapture 서브프로세스 오류: \(error)")
            }

            // 사용자가 Esc 등으로 캡처를 취소했거나 실패한 경우
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }

    // MARK: - 내부 맥락 추출
    private func captureActiveContext() -> VoluntaryCaptureContext {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "데스크톱"
        let bundleId = frontApp?.bundleIdentifier

        var currentUrl: String? = nil
        var currentTitle: String? = nil

        // 브라우저인 경우 활성 탭 URL 추출 시도
        if let bid = bundleId {
            if let tab = BrowserTracker.shared.fetchActiveTab(for: bid, pid: frontApp?.processIdentifier) {
                currentUrl = tab.url
                currentTitle = tab.title
            }
        }

        // 현재 진행 중인 AI 세션 (없으면 nil)
        let session = SessionManager.shared.currentSession

        return VoluntaryCaptureContext(
            appName: appName,
            bundleId: bundleId,
            windowTitle: currentTitle,
            url: currentUrl,
            capturedAt: Date(),
            sessionId: session?.sessionId,
            sessionTitle: session?.title,
            localImagePath: nil
        )
    }

    // MARK: - 전체 화면 자동 캡처 (screencapture -x 및 네이티브 Fallback)
    private func executeFullScreenCapture(completion: @escaping (String?) -> Void) {
        let filename = "capture_full_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).png"
        let targetURL = self.capturesDirectory.appendingPathComponent(filename)
        let targetPath = targetURL.path

        DispatchQueue.global(qos: .userInteractive).async {
            // 1단계: /usr/sbin/screencapture -m -x (메인 모니터 무음 전체화면 즉시 캡처)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-m", "-x", targetPath]

            do {
                try process.run()
                process.waitUntilExit()

                if FileManager.default.fileExists(atPath: targetPath),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: targetPath),
                   let size = attrs[.size] as? UInt64, size > 1000 {
                    print("[VoluntaryRecord] 전체 화면 screencapture 성공: \(targetPath) (\(size) bytes)")
                    DispatchQueue.main.async {
                        completion(targetPath)
                    }
                    return
                }
            } catch {
                print("[VoluntaryRecord] screencapture 서브프로세스 오류: \(error)")
            }

            // 2단계: 네이티브 Fallback (CGDisplayCreateImage)
            if let cgImage = CGDisplayCreateImage(CGMainDisplayID()) {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let pngData = rep.representation(using: .png, properties: [:]) {
                    do {
                        try pngData.write(to: targetURL)
                        print("[VoluntaryRecord] CGDisplayCreateImage 네이티브 캡처 성공: \(targetPath)")
                        DispatchQueue.main.async {
                            completion(targetPath)
                        }
                        return
                    } catch {
                        print("[VoluntaryRecord] 네이티브 PNG 저장 실패: \(error)")
                    }
                }
            }

            // 캡처 실패 시 (권한 미부여 등)
            print("[VoluntaryRecord] 화면 캡처 실패 (화면 기록 권한 확인 필요)")
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }
}
