import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import Speech
import CoreGraphics
import ScreenCaptureKit

/// 앱 구동에 필요한 3대 권한 상태를 확인하고 요청합니다.
public final class PermissionsManager: ObservableObject {
    public static let shared = PermissionsManager()

    @Published public var isAccessibilityGranted: Bool = false
    @Published public var isScreenCaptureGranted: Bool = false
    @Published public var isMicrophoneGranted: Bool = false
    @Published public var isSpeechRecognitionGranted: Bool = false

    private var pollTimer: Timer?

    public var isBrowserAutomationGranted: Bool {
        let installed = installedBrowsers
        guard !installed.isEmpty else { return true }
        return installed.contains { browserAutomationStatuses[$0.bundleId] == true }
    }

    /// 설치된 모든 브라우저의 자동화 권한이 완료되었는지 확인
    public var isAllBrowserAutomationGranted: Bool {
        let installed = installedBrowsers
        guard !installed.isEmpty else { return true }
        return installed.allSatisfy { browserAutomationStatuses[$0.bundleId] == true }
    }

    public var grantedCount: Int {
        var count = 0
        if isAccessibilityGranted { count += 1 }
        if isScreenCaptureGranted { count += 1 }
        if isBrowserAutomationGranted { count += 1 }
        if isMicrophoneGranted { count += 1 }
        return count
    }

    public var isEssentialGranted: Bool {
        return isAccessibilityGranted && isScreenCaptureGranted && isBrowserAutomationGranted
    }

    public var isAllGranted: Bool {
        return isAccessibilityGranted && isScreenCaptureGranted && isBrowserAutomationGranted && isMicrophoneGranted
    }

    private init() {
        refreshAll()
    }

    /// 모든 권한 상태 최신화
    public func refreshAll() {
        checkAccessibility()
        checkScreenCapture()
        checkMicrophone()
        checkSpeechRecognition()
        checkAllBrowserAutomation()
    }

    /// 사용자가 시스템 설정에서 토글할 때 즉각 반영되도록 실시간 0.6초 주기 감지
    public func startPolling() {
        stopPolling()
        refreshAll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// 미승인된 권한을 순서대로 요청 (마법사 기능)
    public func requestNextMissing() {
        if !isAccessibilityGranted {
            requestAccessibility()
        } else if !isScreenCaptureGranted {
            requestScreenCapture()
        } else if !isBrowserAutomationGranted {
            requestAllBrowserAutomation()
        } else if !isMicrophoneGranted {
            requestMicrophone()
        }
    }

    // MARK: - 1. 손쉬운 사용 (Accessibility - 창 제목 및 포커스 감지)
    public func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async {
            if self.isAccessibilityGranted != trusted {
                self.isAccessibilityGranted = trusted
            }
        }
    }

    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            DispatchQueue.main.async {
                self.isAccessibilityGranted = true
            }
        } else {
            openSystemSettings(pane: "Privacy_Accessibility")
        }
    }

    // MARK: - 2. 화면 기록 (Screen Capture - 자발적 피로 기록 시 영역 캡처)
    public func checkScreenCapture() {
        if #available(macOS 11.0, *) {
            let granted = CGPreflightScreenCaptureAccess()
            DispatchQueue.main.async {
                if self.isScreenCaptureGranted != granted {
                    self.isScreenCaptureGranted = granted
                }
            }
        } else {
            DispatchQueue.main.async {
                if !self.isScreenCaptureGranted {
                    self.isScreenCaptureGranted = true
                }
            }
        }
    }

    public func requestScreenCapture() {
        if #available(macOS 11.0, *) {
            let alreadyGranted = CGRequestScreenCaptureAccess()
            if alreadyGranted {
                DispatchQueue.main.async {
                    self.isScreenCaptureGranted = true
                }
                return
            }
        }
        openSystemSettings(pane: "Privacy_ScreenCapture")
    }

    // MARK: - 3. 마이크 및 음성 인식 (음성 입력)
    public func checkMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        DispatchQueue.main.async {
            let granted = (status == .authorized)
            if self.isMicrophoneGranted != granted {
                self.isMicrophoneGranted = granted
            }
        }
    }

    public func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                if self.isMicrophoneGranted != granted {
                    self.isMicrophoneGranted = granted
                }
            }
        }
    }

    public func checkSpeechRecognition() {
        let status = SFSpeechRecognizer.authorizationStatus()
        DispatchQueue.main.async {
            let granted = (status == .authorized)
            if self.isSpeechRecognitionGranted != granted {
                self.isSpeechRecognitionGranted = granted
            }
        }
    }

    public func requestSpeechRecognition() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                let granted = (status == .authorized)
                if self.isSpeechRecognitionGranted != granted {
                    self.isSpeechRecognitionGranted = granted
                }
            }
        }
    }

    // MARK: - 4. 브라우저별 자동화 (Automation / AppleEvents - URL 추적 권한)
    @Published public var browserAutomationStatuses: [String: Bool] = [:]

    public struct BrowserItem: Identifiable, Hashable {
        public let bundleId: String
        public let name: String
        public var id: String { bundleId }

        public init(bundleId: String, name: String) {
            self.bundleId = bundleId
            self.name = name
        }
    }

    /// 연동 가능한 지원 브라우저 전체 마스터 목록
    public let targetBrowsers: [BrowserItem] = [
        BrowserItem(bundleId: "com.google.Chrome", name: "Google Chrome"),
        BrowserItem(bundleId: "com.apple.Safari", name: "Safari"),
        BrowserItem(bundleId: "com.brave.Browser", name: "Brave"),
        BrowserItem(bundleId: "company.thebrowser.Browser", name: "Arc"),
        BrowserItem(bundleId: "com.microsoft.edgemac", name: "Microsoft Edge"),
        BrowserItem(bundleId: "com.naver.whale", name: "Whale"),
        BrowserItem(bundleId: "org.mozilla.firefox", name: "Firefox"),
        BrowserItem(bundleId: "com.operasoftware.Opera", name: "Opera"),
        BrowserItem(bundleId: "com.vivaldi.Vivaldi", name: "Vivaldi")
    ]

    /// 사용자의 Mac에 실제로 설치되어 있는 웹 브라우저 목록만 동적으로 필터링
    public var installedBrowsers: [BrowserItem] {
        let installed = targetBrowsers.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) != nil
        }
        return installed.isEmpty ? [BrowserItem(bundleId: "com.apple.Safari", name: "Safari")] : installed
    }

    public func checkAllBrowserAutomation() {
        for b in installedBrowsers {
            checkBrowserAutomation(bundleId: b.bundleId)
        }
    }

    public func checkBrowserAutomation(bundleId: String) {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil else {
            DispatchQueue.main.async {
                if self.browserAutomationStatuses[bundleId] != false {
                    self.browserAutomationStatuses[bundleId] = false
                }
            }
            return
        }

        var desc = AEAddressDesc()
        guard let cBundleId = (bundleId as NSString).utf8String else { return }
        AECreateDesc(DescType(typeApplicationBundleID), cBundleId, strlen(cBundleId), &desc)
        let status = AEDeterminePermissionToAutomateTarget(&desc, typeWildCard, typeWildCard, false)
        AEDisposeDesc(&desc)

        let granted = (status == noErr)
        DispatchQueue.main.async {
            if self.browserAutomationStatuses[bundleId] != granted {
                self.browserAutomationStatuses[bundleId] = granted
            }
        }
    }

    public func requestBrowserAutomation(bundleId: String, openSettings: Bool = true) {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil else { return }

        var desc = AEAddressDesc()
        if let cBundleId = (bundleId as NSString).utf8String {
            AECreateDesc(DescType(typeApplicationBundleID), cBundleId, strlen(cBundleId), &desc)
            let status = AEDeterminePermissionToAutomateTarget(&desc, typeWildCard, typeWildCard, true)
            AEDisposeDesc(&desc)
            if status == noErr {
                DispatchQueue.main.async {
                    if self.browserAutomationStatuses[bundleId] != true {
                        self.browserAutomationStatuses[bundleId] = true
                    }
                }
                if !openSettings { return }
            }
        }

        let scriptSource = """
        tell application id "\(bundleId)"
            count windows
        end tell
        """
        if let script = NSAppleScript(source: scriptSource) {
            var errorDict: NSDictionary?
            _ = script.executeAndReturnError(&errorDict)
            let errorNum = errorDict?[NSAppleScript.errorNumber] as? Int
            let granted = (errorDict == nil || errorNum != -1743)
            DispatchQueue.main.async {
                if self.browserAutomationStatuses[bundleId] != granted {
                    self.browserAutomationStatuses[bundleId] = granted
                }
            }
        }
        if openSettings {
            openSystemSettings(pane: "Privacy_Automation")
        }
    }

    /// 설치된 모든 브라우저를 백그라운드 큐에서 안전하게 일괄 요청 및 시스템 설정 자동화 탭 열기
    public func requestAllBrowserAutomation() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            for b in self.installedBrowsers {
                self.requestBrowserAutomation(bundleId: b.bundleId, openSettings: false)
            }
            self.checkAllBrowserAutomation()
            DispatchQueue.main.async {
                self.openSystemSettings(pane: "Privacy_Automation")
            }
        }
    }

    // MARK: - 시스템 설정 열기 유틸
    public func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
