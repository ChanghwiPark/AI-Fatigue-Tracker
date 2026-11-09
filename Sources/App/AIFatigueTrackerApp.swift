import SwiftUI
import AppKit
import Speech
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--run-detection-tests") {
            _ = DetectionSessionTestSuite.runAllTests()
            exit(0)
        }

        if CommandLine.arguments.contains("--render-theme-previews") {
            ThemePreviewRenderer.renderAllThemePreviews()
            exit(0)
        }

        // Dock 아이콘 없는 백그라운드/액세서리 앱 설정
        NSApplication.shared.setActivationPolicy(.accessory)

        // 시스템 유휴 상태나 창 닫힘 시 macOS TAL/자동 종료에 의해 조용히 프로세스가 종료되는 것 원천 방지
        ProcessInfo.processInfo.disableAutomaticTermination("AI 피로 기록 백그라운드 상시 수집 및 세션 추적")
        ProcessInfo.processInfo.disableSuddenTermination()

        // 상시 전체 컴퓨터 활동 감지 및 AI 세션 추적 시작
        ActivityDetector.shared.start()

        // 1분 주기 Supabase 배치 동기화 및 네트워크 모니터링 활성화
        _ = SupabaseSyncManager.shared

        // 재시작 혹은 macOS 권한 허용 후 '종료 및 다시 열기' 시 이전에 보고 있던 화면 자동 복원
        let reopenTarget = UserDefaults.standard.string(forKey: "reopen_after_restart")
        let activeWindow = UserDefaults.standard.string(forKey: "active_window_identifier")
        UserDefaults.standard.removeObject(forKey: "reopen_after_restart")
        UserDefaults.standard.removeObject(forKey: "active_window_identifier")

        let restoreTarget = reopenTarget ?? activeWindow

        // 첫 실행 온보딩이 완료되지 않았을 때만 안내창 자동 팝업
        if !AppState.shared.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                OnboardingWindowManager.shared.showOnboardingWindow()
            }
        }

        // 프로그램 시작 시 메뉴 막대 패널(MenuBarView) 자동 열기 (일반 시작일 때)
        let isSpecificWindowLaunch = CommandLine.arguments.contains("--debug-window") ||
            CommandLine.arguments.contains("--survey-tab") ||
            CommandLine.arguments.contains("--gantt-tab") ||
            CommandLine.arguments.contains("--log-tab") ||
            CommandLine.arguments.contains("--onboarding") ||
            CommandLine.arguments.contains("--settings") ||
            CommandLine.arguments.contains("--test-diary-popup") ||
            CommandLine.arguments.contains("--test-survey") ||
            restoreTarget != nil

        if !isSpecificWindowLaunch && AppState.shared.hasCompletedOnboarding {
            MenuBarAccessHelper.openMenuBarExtra(delay: 0.5)
        }

        // 전역 단축키 ⌥⌘S (Option + Command + S) 등록: 자발적 피로 기록 플로우 실행
        HotKeyManager.shared.register {
            print("[HotKey] ⌥⌘S 단축키 입력 감지됨 -> 자발적 피로 기록 시작")
            VoluntaryRecordService.shared.startFlow()
        }

        // --debug-window, --survey-tab, --gantt-tab, --log-tab 옵션 또는 재시작 전 debug 창이었던 경우 즉시 실행
        if CommandLine.arguments.contains("--debug-window") ||
           CommandLine.arguments.contains("--survey-tab") ||
           CommandLine.arguments.contains("--gantt-tab") ||
           CommandLine.arguments.contains("--log-tab") ||
           restoreTarget == "--debug-window" ||
           restoreTarget == "debug" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                DebugWindowManager.shared.showDebugWindow()
            }
        }

        // --onboarding 옵션이거나 재시작 전 onboarding 창이었던 경우 즉시 실행
        if CommandLine.arguments.contains("--onboarding") ||
           restoreTarget == "--onboarding" ||
           restoreTarget == "onboarding" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                OnboardingWindowManager.shared.showOnboardingWindow()
            }
        }

        // --settings 옵션이거나 재시작 전 settings 창이었던 경우 즉시 실행
        if CommandLine.arguments.contains("--settings") ||
           restoreTarget == "--settings" ||
           restoreTarget == "settings" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                SettingsWindowManager.shared.showSettingsWindow()
            }
        }

        // --test-diary-popup 옵션이 주어지면 테스트 캡처 이미지를 첨부하여 자발적 피로 기록 팝업 즉시 실행
        if CommandLine.arguments.contains("--test-diary-popup") {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let testImgPath = appSupport.appendingPathComponent("AIFatigueTracker/Captures/test_preview.png").path
            let context = VoluntaryCaptureContext(
                appName: "Claude",
                bundleId: "com.anthropic.claude",
                windowTitle: "AI 피로 연구 대화 세션",
                url: "https://claude.ai/chat/123",
                capturedAt: Date(),
                sessionId: SessionManager.shared.currentSession?.sessionId ?? UUID(),
                sessionTitle: "새 작업공간 (Claude)",
                localImagePath: FileManager.default.fileExists(atPath: testImgPath) ? testImgPath : nil
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                SurveyWindowManager.shared.showVoluntaryPopup(context: context)
            }
        }

        // --test-survey <type> 옵션이 주어지면 지정된 팝업 강제 실행
        if let idx = CommandLine.arguments.firstIndex(of: "--test-survey"), idx + 1 < CommandLine.arguments.count {
            let typeStr = CommandLine.arguments[idx + 1]
            if typeStr == "diary" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    VoluntaryRecordService.shared.startFlow()
                }
            } else if typeStr == "nudge_diary" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    VoluntaryRecordService.shared.startNudgeReflectionFlow()
                }
            } else if let type = SurveyType(rawValue: typeStr) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    SurveyScheduler.shared.forceTrigger(type: type)
                }
            }
        }

        // --check-speech: 음성 인식 및 마이크 권한 진단 출력 후 종료
        if CommandLine.arguments.contains("--check-speech") {
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
            print("[SpeechCheck] SFSpeechRecognizer authStatus: \(speechStatus.rawValue) (0:notDetermined, 1:denied, 2:restricted, 3:authorized)")
            print("[SpeechCheck] AVCaptureDevice mic authStatus: \(micStatus.rawValue) (0:notDetermined, 1:restricted, 2:denied, 3:authorized)")
            print("[SpeechCheck] ko-KR recognizer isAvailable: \(recognizer?.isAvailable ?? false)")
            print("[SpeechCheck] supportsOnDevice: \(recognizer?.supportsOnDeviceRecognition ?? false)")
            exit(0)
        }

        // --test-speech-engine: 음성 인식 엔진 실제 시작, 빠른 토글, 필드 전환, 안전 정지 종합 검증
        if CommandLine.arguments.contains("--test-speech-engine") {
            let status = SFSpeechRecognizer.authorizationStatus()
            guard status == .authorized else {
                print("[SpeechTest] ⚠️ 시스템 음성 인식 권한 대기 중 (status: \(status.rawValue)). 터미널 환경 대신 실행 중인 앱의 설문 화면에서 마이크 버튼을 눌러 권한을 허용하시면 즉시 정상 작동합니다.")
                exit(0)
            }
            print("[SpeechTest] 🚀 SpeechInputManager 음성 인식 종합 시나리오 테스트 시작")

            // 시나리오 1: 단일 필드 녹음 시작
            print("[SpeechTest] [시나리오 1] 필드 'field_A' 음성 인식 시작...")
            SpeechInputManager.shared.startRecording(fieldKey: "field_A", currentText: "기존 텍스트") { updated in
                print("[SpeechTest] 🗣️ 실시간 콜백 수신: \"\(updated)\"")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            let s1Recording = SpeechInputManager.shared.isRecording
            let s1Active = SpeechInputManager.shared.activeFieldKey
            print("[SpeechTest] 📊 시나리오 1 결과 -> isRecording: \(s1Recording), activeFieldKey: \(s1Active ?? "nil")")

            // 시나리오 2: 필드 간 전환 ('field_A' -> 'field_B')
            print("[SpeechTest] [시나리오 2] 필드 'field_B'로 전환...")
            SpeechInputManager.shared.toggleRecording(fieldKey: "field_B", currentText: "") { _ in }
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            let s2Active = SpeechInputManager.shared.activeFieldKey
            print("[SpeechTest] 📊 시나리오 2 결과 -> activeFieldKey: \(s2Active ?? "nil")")

            // 시나리오 3: 빠른 연타 (동일 필드 연속 토글)
            print("[SpeechTest] [시나리오 3] 동일 필드 빠른 연속 토글 (스트레스 테스트)...")
            SpeechInputManager.shared.toggleRecording(fieldKey: "field_B", currentText: "") { _ in }
            SpeechInputManager.shared.toggleRecording(fieldKey: "field_B", currentText: "") { _ in }
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            print("[SpeechTest] 📊 시나리오 3 완료 -> 예외/크래시 없이 정상 처리")

            // 시나리오 4: 최종 안전 정지 및 리소스 해제 검증
            print("[SpeechTest] [시나리오 4] 녹음 완전 정지 및 리소스 정리 검증...")
            SpeechInputManager.shared.stopRecording()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let s4Recording = SpeechInputManager.shared.isRecording
            let s4Active = SpeechInputManager.shared.activeFieldKey
            print("[SpeechTest] 📊 시나리오 4 결과 -> isRecording: \(s4Recording), activeFieldKey: \(s4Active ?? "nil")")

            let allPassed = !s4Recording && (s4Active == nil)
            print("[SpeechTest] 🎉 종합 음성 테스트 결과: \(allPassed ? "PASS" : "FAIL")")
            exit(allPassed ? 0 : 1)
        }
    }

    /// 사용자가 Finder나 Launchpad에서 앱을 다시 클릭했을 때 반응
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        print("[AppDelegate] applicationShouldHandleReopen 호출됨 (hasVisibleWindows: \(flag))")
        if !AppState.shared.hasCompletedOnboarding {
            OnboardingWindowManager.shared.showOnboardingWindow()
            return true
        }
        if flag {
            for window in sender.windows where window.isVisible && !window.className.contains("MenuBar") && !window.className.contains("StatusBar") {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return true
            }
        }
        MenuBarAccessHelper.openMenuBarExtra(delay: 0.1)
        return true
    }

    /// 창이 모두 닫혀도 백그라운드 상주 및 메뉴바 앱 유지를 위해 앱을 절대 종료하지 않음
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct AIFatigueTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        // 메뉴 막대 상주 아이콘 및 윈도우 스타일 패널
        MenuBarExtra(isInserted: .constant(true)) {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarLabelView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
