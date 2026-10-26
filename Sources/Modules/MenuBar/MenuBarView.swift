import SwiftUI
import AppKit

/// MenuBarExtra(.window) 스타일에 맞춘 드롭다운 패널 뷰 (mockup.html 장면 05 기반)
public struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var syncManager: SupabaseSyncManager = .shared
    @ObservedObject var sessionManager: SessionManager = .shared
    @ObservedObject var surveyLogStore: SurveyLogStore = .shared

    @State private var currentTime = Date()
    private let countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 연구 완료 감사 배너 (14일 경과 시에도 상태 줄 및 기록 버튼과 함께 표시)
            if appState.isStudyCompleted {
                studyCompletedBanner
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }

            // 2. 실시간 상태 줄
            statusHeaderView
                .padding(.horizontal, 14)
                .padding(.top, appState.isStudyCompleted ? 6 : 12)
                .padding(.bottom, 10)

            // 3. "지금 피로 기록하기" 주요 액션 버튼 (계속해서 사용 가능)
            recordNowButton
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            // 3. "나의 AI 사용" 영역 (자리잡기)
            myUsageSectionView
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            // 4. 하단 메뉴 옵션
            bottomActionRow(
                title: mutePopup1HourMenuTitle,
                icon: appState.isPopupMutedForOneHour ? "bell.fill" : "bell.slash",
                isHighlighted: appState.isPopupMutedForOneHour
            ) {
                appState.toggleMuteOneHour()
            }

            bottomActionRow(
                title: pauseRecordingMenuTitle,
                icon: appState.isRecordingPaused15Min ? "play.circle.fill" : "pause.circle",
                isHighlighted: appState.isRecordingPaused15Min
            ) {
                appState.togglePauseRecording15Min()
            }

            if Config.DebugConfig.showDebugMonitor || NSEvent.modifierFlags.contains(.option) {
                bottomActionRow(
                    title: "디버그 모니터",
                    icon: "waveform.path.ecg"
                ) {
                    dismiss()
                    MenuBarAccessHelper.closeMenuBarExtra()
                    DebugWindowManager.shared.showDebugWindow()
                }

                bottomActionRow(
                    title: "온보딩 화면 열기",
                    icon: "arrow.counterclockwise"
                ) {
                    dismiss()
                    MenuBarAccessHelper.closeMenuBarExtra()
                    OnboardingWindowManager.shared.showOnboardingWindow()
                }
            }

            bottomActionRow(
                title: "설정",
                icon: "gearshape"
            ) {
                dismiss()
                MenuBarAccessHelper.closeMenuBarExtra()
                SettingsWindowManager.shared.showSettingsWindow()
            }

            // 시스템 사용 강제: 종료 대신 앱 재시작 버튼 제공
            bottomActionRow(
                title: "앱 재시작",
                icon: "arrow.clockwise"
            ) {
                restartApp()
            }
            .padding(.bottom, 8)
        }
        .frame(width: 320)
        .background(Config.Colors.popupBg)
        .onReceive(countdownTimer) { _ in
            if appState.isPopupMutedForOneHour || appState.isRecordingPaused15Min {
                currentTime = Date()
            }
        }
    }

    private var mutePopup1HourMenuTitle: String {
        _ = currentTime
        if appState.isPopupMutedForOneHour, let end = appState.popupMuteEndTime {
            let remain = max(0, Int(end.timeIntervalSinceNow))
            let min = remain / 60
            let sec = remain % 60
            return "팝업 끄기 해제 (1시간 묵음: \(String(format: "%02d:%02d", min, sec)))"
        } else if appState.isPopupMutedForOneHour {
            return "팝업 끄기 해제 (1시간 묵음 중)"
        } else {
            return "1시간 동안 팝업 끄기"
        }
    }

    private var pauseRecordingMenuTitle: String {
        _ = currentTime
        if appState.isRecordingPaused15Min, let end = appState.recordingPauseEndTime {
            let remain = max(0, Int(end.timeIntervalSinceNow))
            let min = remain / 60
            let sec = remain % 60
            return "기록 재개하기 (15분 일시정지: \(String(format: "%02d:%02d", min, sec)))"
        } else if appState.isRecordingPaused15Min {
            return "기록 재개하기 (15분 일시정지 중)"
        } else {
            return "15분 동안 기록 멈추기"
        }
    }

    private func restartApp() {
        var reopenArg: String? = nil
        if DebugWindowManager.shared.isVisible {
            reopenArg = "--debug-window"
        } else if SettingsWindowManager.shared.isVisible {
            reopenArg = "--settings"
        } else if OnboardingWindowManager.shared.isVisible {
            reopenArg = "--onboarding"
        } else if !appState.hasCompletedOnboarding {
            reopenArg = "--onboarding"
        }

        if let arg = reopenArg {
            UserDefaults.standard.set(arg, forKey: "reopen_after_restart")
        } else {
            UserDefaults.standard.removeObject(forKey: "reopen_after_restart")
        }
        UserDefaults.standard.synchronize()

        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            if let arg = reopenArg {
                config.arguments = [arg]
            }
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            if let arg = reopenArg {
                task.arguments = [arg]
            }
            try? task.run()
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - 0. 연구 종료 감사 배너
    private var studyCompletedBanner: some View {
        HStack(spacing: 8) {
            Text("☺️")
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text("참여해주셔서 감사합니다 ☺️")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(Config.Colors.ink)
                Text("14일 연구 완료 · 계속해서 자유롭게 사용하실 수 있어요")
                    .font(.system(size: 10))
                    .foregroundColor(Config.Colors.mute)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.green.opacity(0.12))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.25), lineWidth: 0.8))
    }

    // MARK: - 1. 맨 위 상태 줄
    private var statusHeaderView: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                if let apps = appState.activeSessionAppNames, let duration = appState.activeSessionDurationString {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: Config.Colors.accentHex))
                            .frame(width: 7, height: 7)
                        Text("기록 중 · \(apps)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }
                    Text("현재 세션 \(duration)")
                        .font(.system(size: 11.5))
                        .foregroundColor(Config.Colors.mute)
                } else {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: 7, height: 7)
                        Text("대기 중 · AI 도구 감지 중")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Config.Colors.ink)
                    }
                    Text("Claude, ChatGPT, 터미널 등을 열면 자동 감지됩니다.")
                        .font(.system(size: 11))
                        .foregroundColor(Config.Colors.mute)
                }
            }
            Spacer()
        }
    }

    // MARK: - 2. "지금 피로 기록하기" 버튼
    private var recordNowButton: some View {
        Button {
            print("[MenuBar] 지금 피로 기록하기 클릭됨 -> 메뉴 접기 및 캡처 시작")
            dismiss()
            MenuBarAccessHelper.closeMenuBarExtra()
            VoluntaryRecordService.shared.startFlow()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("지금 피로 기록하기")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)

                    Text("화면이 함께 캡처돼요")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.85))
                }

                Spacer()

                Text("⌥⌘S")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: Config.Colors.accentHex))
            .cornerRadius(8)
            .shadow(color: Color(hex: Config.Colors.accentHex).opacity(0.4), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. "나의 AI 사용" 영역 (로컬 데이터 기반 실시간 계산)
    private var myUsageSectionView: some View {
        let studyDay = LocalDatabase.shared.getStudyDay()

        // 1. 누적 AI 사용 시간 (초 -> 시간 변환)
        let liveSec = sessionManager.sessions.reduce(0) { $0 + Int($1.accumulatedFocusedDuration) }
        let dbSec = LocalDatabase.shared.getCumulativeAISeconds()
        let totalAIHours = Double(max(liveSec, dbSec)) / 3600.0
        let aiHoursString = String(format: "%.1fh", totalAIHours)

        // 2. 세션 수
        let totalSessions = max(sessionManager.sessions.count, LocalDatabase.shared.getSessionCount())

        // 3. 설문 및 다이어리 기록 수
        let liveRecords = surveyLogStore.events.filter { $0.action == .response }.count
        let dbRecords = LocalDatabase.shared.getSurveyRecordCount()
        let totalRecords = max(liveRecords, dbRecords)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("나의 AI 사용")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                Spacer()

                Text("\(studyDay)일째 · 2주 중")
                    .font(.system(size: 11))
                    .foregroundColor(Config.Colors.mute)
            }

            // 3가지 KPI 타일 (로컬 데이터로 계산)
            HStack(spacing: 6) {
                kpiCard(title: aiHoursString, label: "누적 사용")
                kpiCard(title: "\(totalSessions)", label: "세션")
                kpiCard(title: "\(totalRecords)", label: "기록")
            }

            // 고정 예시 미리보기 카드 (연구 기간 동안 본인 실제 피로 점수는 비공개 - 자기보고 편향 방지)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Config.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Config.Colors.line, lineWidth: 0.8)
                    )

                // 배경 블러 막대 그래픽 느낌
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach([0.3, 0.6, 0.4, 0.8, 0.5, 0.7, 0.4], id: \.self) { h in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: Config.Colors.accentHex).opacity(0.25))
                            .frame(height: 36 * h)
                    }
                }
                .blur(radius: 2)
                .opacity(0.7)

                // 잠금 오버레이
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(Config.Colors.cardBackground)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Config.Colors.line, lineWidth: 0.8))
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Config.Colors.ink)
                    }

                    Text("2주 뒤 나만의 AI 리포트가 완성돼요")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    Text("기록이 쌓일수록 더 정확해져요")
                        .font(.system(size: 10))
                        .foregroundColor(Config.Colors.mute)
                }
                .padding(.vertical, 12)
            }
            .frame(height: 84)

            // 참여 인원 안내: Supabase 활성 참여자 수가 성공적으로 조회된 경우에만 노출 (실패 시 완전히 숨김)
            if let activeCount = syncManager.activeParticipantsCount, activeCount > 0 {
                HStack(spacing: 6) {
                    // 실시간 연결 라이브 상태 닷 (초록색 펄스 점)
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#34C759").opacity(0.25))
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(Color(hex: "#34C759"))
                            .frame(width: 6, height: 6)
                    }

                    Text("\(activeCount)명이 함께 참여하고 있어요")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Config.Colors.mute)
                }
                .padding(.top, 2)
            }
        }
    }

    private func kpiCard(title: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Config.Colors.ink)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Config.Colors.mute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Config.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Config.Colors.line, lineWidth: 0.8)
                )
        )
    }

    // MARK: - 하단 메뉴 항목
    private func bottomActionRow(
        title: String,
        icon: String,
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isHighlighted ? .semibold : .regular))
                    .frame(width: 16)
                    .foregroundColor(isHighlighted ? Color(hex: Config.Colors.accentHex) : Config.Colors.ink)

                Text(title)
                    .font(.system(size: 12.5, weight: isHighlighted ? .semibold : .regular))
                    .foregroundColor(isHighlighted ? Color(hex: Config.Colors.accentHex) : Config.Colors.ink)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isHighlighted
                    ? RoundedRectangle(cornerRadius: 6).fill(Color(hex: Config.Colors.accentSoftHex).opacity(0.55))
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}
