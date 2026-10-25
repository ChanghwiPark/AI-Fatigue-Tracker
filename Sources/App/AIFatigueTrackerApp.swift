import SwiftUI
import AppKit
import Speech
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 아이콘 없는 백그라운드/액세서리 앱 설정
        NSApplication.shared.setActivationPolicy(.accessory)

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
