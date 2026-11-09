import SwiftUI
import AppKit

/// MenuBarExtra(.window) 스타일에 맞춘 드롭다운 패널 뷰 (mockup.html 장면 05 기반)
public struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var syncManager: SupabaseSyncManager = .shared
    @ObservedObject var sessionManager: SessionManager = .shared
    @ObservedObject var surveyLogStore: SurveyLogStore = .shared

    private let panelWidth: CGFloat
    private let showDebugMenu: Bool
    @State private var currentTime = Date()
    private let countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init(
        panelWidth: CGFloat = Config.Survey.menuBarDefaultWidth,
        showDebugMenu: Bool = Config.DebugConfig.showDebugMonitor
    ) {
        self.panelWidth = panelWidth
        self.showDebugMenu = showDebugMenu
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 연구 완료 감사 배너 (14일 경과 시에도 상태 줄 및 기록 버튼과 함께 표시, 닫기 가능)
            if appState.isStudyCompleted && !appState.isStudyCompletedBannerDismissed {
                studyCompletedBanner
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 2. 실시간 상태 줄
            statusHeaderView
                .padding(.horizontal, 14)
                .padding(.top, (appState.isStudyCompleted && !appState.isStudyCompletedBannerDismissed) ? 4 : 12)
                .padding(.bottom, 10)

            // 3. "AI 피로 기록하기" 주요 액션 버튼 (계속해서 사용 가능)
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

            if showDebugMenu || NSEvent.modifierFlags.contains(.option) {
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
        .frame(width: panelWidth)
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

    // MARK: - 0. 연구 종료 감사 배너 (닫기/지우기 지원 - 우측 상단 소형 X 및 여유 있는 위아래 간격)
    private var studyCompletedBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("☺️")
                .font(.system(size: 16))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("참여해주셔서 감사합니다 🧡")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(Config.Colors.ink)
                Text("14일 연구 완료 · 계속해서 자유롭게 사용하실 수 있어요")
                    .font(.system(size: 10))
                    .foregroundColor(Config.Colors.mute)
                    .lineSpacing(1.5)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.dismissStudyCompletedBanner()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(Config.Colors.mute.opacity(0.85))
                    .frame(width: 14, height: 14)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .help("배너 닫기")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 11)
        .background(Color.green.opacity(0.12))
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.green.opacity(0.25), lineWidth: 0.8))
    }

    // MARK: - 1. 맨 위 상태 줄 (포커스된 창 기준 실시간 노출)
    private var statusHeaderView: some View {
        let hasFocusedSession = sessionManager.focusedSession != nil

        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                if let focused = sessionManager.focusedSession {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: Config.Colors.accentHex))
                            .frame(width: 7, height: 7)
                        Text("\(focused.toolName) 사용 중")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                            .lineLimit(1)
                    }
                    Text("이번 세션 \(focused.formattedFocusedDuration)")
                        .font(.system(size: 11.5))
                        .foregroundColor(Config.Colors.mute)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: 7, height: 7)
                        Text("대기 중")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Config.Colors.ink)
                    }
                    Text("AI를 쓰면 자동으로 기록돼요. 안 되면 [시작]을 눌러주세요.")
                        .font(.system(size: 11))
                        .foregroundColor(Config.Colors.mute)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)

            sessionControlButtonsView(hasFocusedSession: hasFocusedSession)
        }
    }

    // MARK: - 1-2. 세션 제어 버튼 (포커스된 창 기준: 시작 / 종료 2개 분리)
    private func sessionControlButtonsView(hasFocusedSession: Bool) -> some View {
        HStack(spacing: 5) {
            // 시작 버튼 (현재 포커스 창에 활성 세션이 없을 때 언제든 수동 시작 가능, 비AI 앱 포함)
            Button {
                print("[MenuBar] '시작' 버튼 클릭됨 -> 포커스된 창 기준 세션 시작")
                dismiss()
                MenuBarAccessHelper.closeMenuBarExtra()
                SessionManager.shared.manualStartSessionForCurrentWindow()
            } label: {
                Text("시작")
                    .font(.system(size: 11, weight: !hasFocusedSession ? .semibold : .regular))
                    .foregroundColor(!hasFocusedSession ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute.opacity(0.35))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(!hasFocusedSession ? Color(hex: Config.Colors.accentHex).opacity(0.12) : Config.Colors.cardBackground.opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(
                                !hasFocusedSession ? Color(hex: Config.Colors.accentHex).opacity(0.3) : Config.Colors.line.opacity(0.7),
                                lineWidth: 0.8
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(hasFocusedSession)
            .help(!hasFocusedSession ? "현재 포커스된 창에서 새 작업 시작하기" : "현재 창에서 이미 세션이 진행 중입니다")

            // 종료 버튼 (현재 포커스 창에 활성 세션이 있을 때만 종료 가능)
            Button {
                print("[MenuBar] '종료' 버튼 클릭됨 -> 포커스된 창 세션 종료")
                dismiss()
                MenuBarAccessHelper.closeMenuBarExtra()
                SessionManager.shared.manualEndCurrentSessionAndPrepareNewTask()
            } label: {
                Text("종료")
                    .font(.system(size: 11, weight: hasFocusedSession ? .semibold : .regular))
                    .foregroundColor(hasFocusedSession ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute.opacity(0.35))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(hasFocusedSession ? Color(hex: Config.Colors.accentHex).opacity(0.12) : Config.Colors.cardBackground.opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(
                                hasFocusedSession ? Color(hex: Config.Colors.accentHex).opacity(0.3) : Config.Colors.line.opacity(0.7),
                                lineWidth: 0.8
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasFocusedSession)
            .help(hasFocusedSession ? "현재 창의 세션 종료하고 평가하기" : "현재 포커스된 창에 종료할 세션이 없습니다")
        }
    }

    // MARK: - 2. "AI 피로 기록하기" 버튼
    private var recordNowButton: some View {
        Button {
            print("[MenuBar] AI 피로 기록하기 클릭됨 -> 메뉴 접기 및 캡처 시작")
            dismiss()
            MenuBarAccessHelper.closeMenuBarExtra()
            VoluntaryRecordService.shared.startFlow()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 피로 기록하기")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)

                    Text("피로가 느껴질 때 언제든 눌러주세요")
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

            // 3가지 KPI 타일 (방안 A: 롤링 카운터 & +1 상승 플로팅 피드백 적용)
            HStack(spacing: 6) {
                KPIRollingCardView(
                    valueText: aiHoursString,
                    rawValue: totalAIHours,
                    label: "누적 사용",
                    unit: "h",
                    precision: 1,
                    storageKey: "kpi_last_seen_ai_hours"
                )
                KPIRollingCardView(
                    valueText: "\(totalSessions)",
                    rawValue: Double(totalSessions),
                    label: "세션",
                    unit: "",
                    precision: 0,
                    storageKey: "kpi_last_seen_sessions"
                )
                KPIRollingCardView(
                    valueText: "\(totalRecords)",
                    rawValue: Double(totalRecords),
                    label: "기록",
                    unit: "",
                    precision: 0,
                    storageKey: "kpi_last_seen_records"
                )
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
                .padding(.vertical, 16)
            }
            .frame(height: 92)

            // 참여 인원 안내: Supabase 활성 참여자 수가 성공적으로 조회된 경우에만 노출 (실패 시 완전히 숨김)
            if let activeCount = syncManager.activeParticipantsCount, activeCount > 0 {
                HStack(spacing: 6) {
                    Text("\(activeCount)명이 함께 참여하고 있어요")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Config.Colors.mute)
                }
                .padding(.top, 2)
            }
        }
    }

    private func kpiCard(title: String, label: String) -> some View {
        KPIRollingCardView(valueText: title, rawValue: 0, label: label)
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

// MARK: - 방안 A: 롤링 카운터 & +1 상승 플로팅 피드백 컴포넌트
public struct KPIRollingCardView: View {
    public let valueText: String
    public let rawValue: Double
    public let label: String
    public let unit: String
    public let precision: Int
    public var previewFloatingBadge: String? = nil
    public var storageKey: String? = nil

    @State private var displayedValueText: String = ""
    @State private var currentRawValue: Double = 0
    @State private var isPulsing: Bool = false
    @State private var floatingText: String? = nil
    @State private var floatingOffset: CGFloat = 0
    @State private var floatingOpacity: Double = 0
    @State private var floatingScale: CGFloat = 1.0

    public init(
        valueText: String,
        rawValue: Double,
        label: String,
        unit: String = "",
        precision: Int = 0,
        previewFloatingBadge: String? = nil,
        storageKey: String? = nil
    ) {
        self.valueText = valueText
        self.rawValue = rawValue
        self.label = label
        self.unit = unit
        self.precision = precision
        self.previewFloatingBadge = previewFloatingBadge
        self.storageKey = storageKey
    }

    private var activeFloatingText: String? {
        previewFloatingBadge ?? floatingText
    }

    private var activePulsing: Bool {
        previewFloatingBadge != nil || isPulsing
    }

    private var effectiveText: String {
        displayedValueText.isEmpty ? valueText : displayedValueText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(effectiveText)
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(response: 0.52, dampingFraction: 0.78), value: effectiveText)
                    .foregroundColor(activePulsing ? Color(hex: Config.Colors.accentHex) : Config.Colors.ink)
                    .scaleEffect(activePulsing ? 1.06 : 1.0, anchor: .bottomLeading)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: activePulsing)

                if let fText = activeFloatingText {
                    Text(fText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(Color(hex: Config.Colors.accentHex).opacity(0.18))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: Config.Colors.accentHex).opacity(0.38), lineWidth: 0.8)
                        )
                        .offset(y: previewFloatingBadge != nil ? -4 : floatingOffset)
                        .opacity(previewFloatingBadge != nil ? 1.0 : floatingOpacity)
                        .scaleEffect(previewFloatingBadge != nil ? 1.0 : floatingScale)
                }

                Spacer(minLength: 0)
            }

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Config.Colors.mute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(activePulsing ? Color(hex: Config.Colors.accentHex).opacity(0.08) : Config.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            activePulsing ? Color(hex: Config.Colors.accentHex).opacity(0.75) : Config.Colors.line,
                            lineWidth: activePulsing ? 1.0 : 0.8
                        )
                )
                .animation(.easeInOut(duration: 0.35), value: activePulsing)
        )
        .onAppear {
            setupInitialState()
        }
        .onChange(of: rawValue) { oldVal, newVal in
            handleRawValueChange(newVal: newVal)
        }
    }

    private func setupInitialState() {
        guard previewFloatingBadge == nil else {
            displayedValueText = valueText
            currentRawValue = rawValue
            return
        }

        if let key = storageKey {
            let userDefaults = UserDefaults.standard
            if let saved = userDefaults.object(forKey: key) as? Double {
                if rawValue > saved {
                    // 직전 상태에서 수치 상승 감지됨:
                    // 1단계: 먼저 이전 값을 보여주어 사용자가 기존 수치를 인지할 여유 제공
                    let oldText = (precision == 0) ? "\(Int(saved))" : String(format: "%.1f%@", saved, unit)
                    displayedValueText = oldText
                    currentRawValue = saved

                    // 2단계: "시작을 보자마자 뜨는 게 아니라 조금 있다가(0.4초 뒤)" 롤링 및 플로팅 피드백 작동!
                    let diff = rawValue - saved
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        triggerIncrementFeedback(newVal: rawValue, newText: valueText, diff: diff)
                        userDefaults.set(rawValue, forKey: key)
                    }
                    return
                }
            }
            userDefaults.set(rawValue, forKey: key)
        }

        displayedValueText = valueText
        currentRawValue = rawValue
    }

    private func handleRawValueChange(newVal: Double) {
        guard previewFloatingBadge == nil else { return }
        if newVal > currentRawValue {
            let diff = newVal - currentRawValue
            // 사용자가 변경 직전의 수치를 잠시 인지한 후(0.35초 뒤) 롤링과 피드백 실행
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                triggerIncrementFeedback(newVal: newVal, newText: valueText, diff: diff)
                if let key = storageKey {
                    UserDefaults.standard.set(newVal, forKey: key)
                }
            }
        } else {
            displayedValueText = valueText
            currentRawValue = newVal
            if let key = storageKey {
                UserDefaults.standard.set(newVal, forKey: key)
            }
        }
    }

    private func triggerIncrementFeedback(newVal: Double, newText: String, diff: Double) {
        if precision == 1 && diff < 0.05 {
            displayedValueText = newText
            currentRawValue = newVal
            return
        }

        let badgeText: String
        if precision == 0 {
            let intDiff = max(1, Int(round(diff)))
            badgeText = "+\(intDiff)"
        } else {
            badgeText = String(format: "+%.1f%@", diff, unit)
        }

        // 1. 숫자 롤링 및 오렌지 펄스 테두리 작동 (산뜻하고 경쾌한 0.52초 스프링)
        withAnimation(.spring(response: 0.52, dampingFraction: 0.78)) {
            displayedValueText = newText
            currentRawValue = newVal
            isPulsing = true
        }

        // 2. +1 배지 톡 튀어나오며 등장
        floatingText = badgeText
        floatingOffset = 0
        floatingOpacity = 1.0
        floatingScale = 1.2

        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
            floatingScale = 1.0
        }

        // 3. 0.45초간 또렷하게 머문 뒤, 0.65초 동안 가볍고 부드럽게 위로 페이드아웃 (늘어지지 않고 신속히 마무리)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeInOut(duration: 0.65)) {
                floatingOffset = -14
                floatingOpacity = 0.0
                floatingScale = 0.95
            }
        }

        // 4. 카드 테두리 오렌지 펄스 복귀
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.45)) {
                isPulsing = false
            }
        }

        // 5. 배지 상태 정리
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if !isPulsing {
                floatingText = nil
            }
        }
    }
}
