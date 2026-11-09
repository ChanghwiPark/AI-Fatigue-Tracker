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
        return installed.allSatisfy { browserAutomationStatuses[$0.bundleId] == true }
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
        return isAccessibilityGranted && isBrowserAutomationGranted
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

    /// 미승인된 권한을 순서대로 요청 (마법사 기능 - 필수 권한 우선)
    public func requestNextMissing(from source: String = "onboarding") {
        if !isAccessibilityGranted {
            requestAccessibility(from: source)
        } else if !isBrowserAutomationGranted {
            requestAllBrowserAutomation(from: source)
        } else if !isScreenCaptureGranted {
            requestScreenCapture(from: source)
        } else if !isMicrophoneGranted || !isSpeechRecognitionGranted {
            requestMicrophoneAndSpeech(from: source)
        }
    }

    // MARK: - 재시작 및 Quit & Reopen 복구 상태 저장
    public func saveReopenTarget(source: String) {
        UserDefaults.standard.set(source, forKey: "reopen_after_restart")
        UserDefaults.standard.set(source, forKey: "active_window_identifier")
        if source == "onboarding" {
            UserDefaults.standard.set(2, forKey: "onboarding_current_step")
        }
        UserDefaults.standard.synchronize()
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

    public func requestAccessibility(openSettingsAlways: Bool = false, from source: String = "onboarding") {
        saveReopenTarget(source: source)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            DispatchQueue.main.async {
                self.isAccessibilityGranted = true
            }
            if openSettingsAlways {
                openSystemSettings(pane: "Privacy_Accessibility", from: source)
            }
        } else {
            openSystemSettings(pane: "Privacy_Accessibility", from: source)
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

    public func requestScreenCapture(openSettingsAlways: Bool = false, from source: String = "onboarding") {
        // macOS '종료 및 다시 열기(Quit & Reopen)'에 대비하여 복귀 대상 화면 및 온보딩 2단계 사전 영구 저장
        saveReopenTarget(source: source)

        if #available(macOS 11.0, *) {
            let alreadyGranted = CGRequestScreenCaptureAccess()
            if alreadyGranted {
                DispatchQueue.main.async {
                    self.isScreenCaptureGranted = true
                }
                if openSettingsAlways {
                    openSystemSettings(pane: "Privacy_ScreenCapture", from: source)
                }
                return
            }
        }
        openSystemSettings(pane: "Privacy_ScreenCapture", from: source)
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

    public func requestMicrophone(openSettingsAlways: Bool = false, from source: String = "onboarding") {
        saveReopenTarget(source: source)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isMicrophoneGranted = granted
                    if !granted {
                        self?.openSystemSettings(pane: "Privacy_Microphone", from: source)
                    }
                }
            }
        } else if status == .authorized {
            DispatchQueue.main.async {
                self.isMicrophoneGranted = true
            }
            if openSettingsAlways {
                openSystemSettings(pane: "Privacy_Microphone", from: source)
            }
        } else {
            openSystemSettings(pane: "Privacy_Microphone", from: source)
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

    public func requestSpeechRecognition(openSettingsAlways: Bool = false, from source: String = "onboarding") {
        saveReopenTarget(source: source)
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
                DispatchQueue.main.async {
                    let granted = (authStatus == .authorized)
                    self?.isSpeechRecognitionGranted = granted
                    if !granted {
                        self?.openSystemSettings(pane: "Privacy_SpeechRecognition", from: source)
                    }
                }
            }
        } else if status == .authorized {
            DispatchQueue.main.async {
                self.isSpeechRecognitionGranted = true
            }
            if openSettingsAlways {
                openSystemSettings(pane: "Privacy_SpeechRecognition", from: source)
            }
        } else {
            openSystemSettings(pane: "Privacy_SpeechRecognition", from: source)
        }
    }

    /// 마이크와 음성 인식 권한을 순차적으로 안전하게 요청 (시스템 모달 팝업 충돌 방지 및 Quit & Reopen 대비)
    public func requestMicrophoneAndSpeech(from source: String = "onboarding") {
        saveReopenTarget(source: source)

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isMicrophoneGranted = granted
                    // 마이크 응답 완료 후 음성 인식 권한 순차 요청
                    self?.requestSpeechRecognitionInternal(from: source)
                }
            }
        } else {
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            if speechStatus == .notDetermined {
                requestSpeechRecognitionInternal(from: source)
            } else {
                // 이미 결정된 상태(denied 등)라면 미허용된 설정 창 열기
                if micStatus != .authorized {
                    openSystemSettings(pane: "Privacy_Microphone", from: source)
                } else if speechStatus != .authorized {
                    openSystemSettings(pane: "Privacy_SpeechRecognition", from: source)
                }
            }
        }
    }

    private func requestSpeechRecognitionInternal(from source: String = "onboarding") {
        saveReopenTarget(source: source)
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isSpeechRecognitionGranted = (status == .authorized)
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

    /// 연동 가능한 지원 브라우저 전체 마스터 목록 (Chromium 및 WebKit/Safari 계열)
    public let targetBrowsers: [BrowserItem] = [
        BrowserItem(bundleId: "com.google.Chrome", name: "Google Chrome"),
        BrowserItem(bundleId: "com.apple.Safari", name: "Safari"),
        BrowserItem(bundleId: "company.thebrowser.dia", name: "Dia"),
        BrowserItem(bundleId: "company.thebrowser.Browser", name: "Arc"),
        BrowserItem(bundleId: "com.brave.Browser", name: "Brave"),
        BrowserItem(bundleId: "com.microsoft.edgemac", name: "Microsoft Edge"),
        BrowserItem(bundleId: "com.naver.whale", name: "Whale"),
        BrowserItem(bundleId: "com.operasoftware.Opera", name: "Opera"),
        BrowserItem(bundleId: "com.vivaldi.Vivaldi", name: "Vivaldi")
    ]

    /// 사용자의 Mac에 실제로 설치되어 있는 웹 브라우저 목록만 동적으로 필터링
    public var installedBrowsers: [BrowserItem] {
        let installed = targetBrowsers.filter { item in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleId) else {
                return false
            }
            let path = url.path
            guard FileManager.default.fileExists(atPath: path) else { return false }
            // 휴지통(.Trash)이나 임시 마운트 볼륨(/Volumes)에 있는 파일은 설치된 브라우저에서 제외
            if path.contains("/.Trash/") || path.hasPrefix("/Volumes/") { return false }
            return true
        }
        return installed.isEmpty ? [BrowserItem(bundleId: "com.apple.Safari", name: "Safari")] : installed
    }

    public func checkAllBrowserAutomation() {
        for b in installedBrowsers {
            checkBrowserAutomation(bundleId: b.bundleId)
        }
    }

    public func checkBrowserAutomation(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              FileManager.default.fileExists(atPath: url.path) else {
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
        defer { AEDisposeDesc(&desc) }

        // false: 시스템 팝업을 띄우지 않고 현재 TCC 권한 허용 여부만 정확히 검사
        let status = AEDeterminePermissionToAutomateTarget(&desc, typeWildCard, typeWildCard, false)
        let granted = (status == noErr)

        DispatchQueue.main.async {
            if self.browserAutomationStatuses[bundleId] != granted {
                self.browserAutomationStatuses[bundleId] = granted
            }
        }
    }

    public func requestBrowserAutomation(bundleId: String, openSettings: Bool = true, from source: String = "onboarding") {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              FileManager.default.fileExists(atPath: url.path) else { return }

        saveReopenTarget(source: source)

        // 1. Apple 공식 API로 시스템 권한 요청 팝업 유도 (askUserIfNeeded: true)
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

        // 2. AppleScript 이벤트 발송을 통해 macOS TCC 시스템 권한 확인/프롬프트 트리거
        let scriptSource = """
        tell application id "\(bundleId)"
            count windows
        end tell
        """
        if let script = NSAppleScript(source: scriptSource) {
            var errorDict: NSDictionary?
            _ = script.executeAndReturnError(&errorDict)
            // 실제 에러 없이 정상 실행 완료되었을 때만 즉시 true 반영
            if errorDict == nil {
                DispatchQueue.main.async {
                    if self.browserAutomationStatuses[bundleId] != true {
                        self.browserAutomationStatuses[bundleId] = true
                    }
                }
            }
        }

        // 3. 최신 TCC 권한 상태 재확인
        checkBrowserAutomation(bundleId: bundleId)

        if openSettings {
            openSystemSettings(pane: "Privacy_Automation", from: source)
        }
    }

    /// 설치된 모든 브라우저를 백그라운드 큐에서 안전하게 일괄 요청 및 시스템 설정 자동화 탭 열기
    public func requestAllBrowserAutomation(from source: String = "onboarding") {
        saveReopenTarget(source: source)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            for b in self.installedBrowsers {
                self.requestBrowserAutomation(bundleId: b.bundleId, openSettings: false, from: source)
            }
            self.checkAllBrowserAutomation()
            DispatchQueue.main.async {
                self.openSystemSettings(pane: "Privacy_Automation", from: source)
            }
        }
    }

    // MARK: - 시스템 설정 열기 유틸
    public func openSystemSettings(pane: String, from source: String? = nil) {
        let actualSource = source ?? (OnboardingWindowManager.shared.isVisible ? "onboarding" : (SettingsWindowManager.shared.isVisible ? "settings" : nil))
        if let s = actualSource {
            saveReopenTarget(source: s)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
        }
    }
}
