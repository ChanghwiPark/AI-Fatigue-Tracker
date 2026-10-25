import SwiftUI

/// 모니터에서 실시간으로 스케줄러 간격, 타이머, 감지 임계값을 변경할 수 있는 설정 뷰
public struct ConfigSettingsSectionView: View {
    @ObservedObject var config: ConfigManager = .shared
    @State private var isExpanded: Bool = true
    @State private var toastMessage: String? = nil

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 헤더 및 프리셋 퀵 액션
            headerView

            if isExpanded {
                VStack(spacing: 12) {
                    // 상단 알림 토스트 (프리셋 적용 등 알림)
                    if let msg = toastMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(msg)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Config.Colors.ink)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(6)
                    }

                    // 4개 영역 그리드
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        // 1. 무응답 자동 닫힘 (Auto-dismiss)
                        settingCard(
                            icon: "timer",
                            iconColor: Color(hex: Config.Colors.accentHex),
                            title: "무응답 자동 닫힘 (Auto-dismiss)",
                            description: "팝업 발생 후 응답이 없을 때 자동으로 닫히는 시간",
                            currentValueString: ConfigManager.formatDuration(config.autoDismissDuration)
                        ) {
                            HStack(spacing: 6) {
                                quickDurationButton(label: "30초", seconds: 30, current: config.autoDismissDuration) {
                                    config.autoDismissDuration = 30
                                }
                                quickDurationButton(label: "1분", seconds: 60, current: config.autoDismissDuration) {
                                    config.autoDismissDuration = 60
                                }
                                quickDurationButton(label: "2분", seconds: 120, current: config.autoDismissDuration) {
                                    config.autoDismissDuration = 120
                                }
                                quickDurationButton(label: "3분", seconds: 180, current: config.autoDismissDuration) {
                                    config.autoDismissDuration = 180
                                }
                                quickDurationButton(label: "5분 (표준)", seconds: 300, current: config.autoDismissDuration) {
                                    config.autoDismissDuration = 300
                                }
                                quickDurationButton(label: "10분", seconds: 600, current: config.autoDismissDuration) {
                                    config.autoDismissDuration = 600
                                }
                            }

                            HStack(spacing: 8) {
                                Stepper(value: Binding(
                                    get: { config.autoDismissDuration },
                                    set: { config.autoDismissDuration = max(10, $0) }
                                ), step: 30) {
                                    Text("±30초 미세 조정: \(Int(config.autoDismissDuration))초")
                                        .font(.system(size: 11))
                                        .foregroundColor(Config.Colors.mute)
                                }
                            }
                        }

                        // 2. 세션 간 최소 쿨다운 (Session Cooldown)
                        settingCard(
                            icon: "shield.lefthalf.filled",
                            iconColor: .blue,
                            title: "세션 간 팝업 쿨다운 (Cooldown)",
                            description: "종료 팝업 뒤 30분 동안은 새 세션이 감지되어도 시작 팝업을 띄우지 않음 (세션 내 팝업은 쿨다운 무관)",
                            currentValueString: config.minPopupCooldown == 0 ? "0초 (해제됨)" : ConfigManager.formatDuration(config.minPopupCooldown)
                        ) {
                            HStack(spacing: 6) {
                                quickDurationButton(label: "0초 (해제)", seconds: 0, current: config.minPopupCooldown) {
                                    config.minPopupCooldown = 0
                                }
                                quickDurationButton(label: "1분", seconds: 60, current: config.minPopupCooldown) {
                                    config.minPopupCooldown = 60
                                }
                                quickDurationButton(label: "5분", seconds: 300, current: config.minPopupCooldown) {
                                    config.minPopupCooldown = 300
                                }
                                quickDurationButton(label: "15분", seconds: 900, current: config.minPopupCooldown) {
                                    config.minPopupCooldown = 900
                                }
                                quickDurationButton(label: "30분 (표준)", seconds: 1800, current: config.minPopupCooldown) {
                                    config.minPopupCooldown = 1800
                                }
                                quickDurationButton(label: "60분", seconds: 3600, current: config.minPopupCooldown) {
                                    config.minPopupCooldown = 3600
                                }
                            }

                            HStack(spacing: 8) {
                                Stepper(value: Binding(
                                    get: { config.minPopupCooldown },
                                    set: { config.minPopupCooldown = max(0, $0) }
                                ), step: 300) {
                                    Text("±5분 미세 조정: \(Int(config.minPopupCooldown / 60))분")
                                        .font(.system(size: 11))
                                        .foregroundColor(Config.Colors.mute)
                                }
                            }
                        }

                        // 3. '10분 뒤에' 스누즈 대기 (Snooze Duration)
                        settingCard(
                            icon: "clock.arrow.circlepath",
                            iconColor: .orange,
                            title: "'10분 뒤에' 스누즈 (Snooze)",
                            description: "사용자가 '10분 뒤에' 버튼 클릭 시 재알림까지 대기 시간",
                            currentValueString: ConfigManager.formatDuration(config.snoozeDuration)
                        ) {
                            HStack(spacing: 6) {
                                quickDurationButton(label: "10초 (테스트)", seconds: 10, current: config.snoozeDuration) {
                                    config.snoozeDuration = 10
                                }
                                quickDurationButton(label: "1분", seconds: 60, current: config.snoozeDuration) {
                                    config.snoozeDuration = 60
                                }
                                quickDurationButton(label: "5분", seconds: 300, current: config.snoozeDuration) {
                                    config.snoozeDuration = 300
                                }
                                quickDurationButton(label: "10분 (표준)", seconds: 600, current: config.snoozeDuration) {
                                    config.snoozeDuration = 600
                                }
                                quickDurationButton(label: "15분", seconds: 900, current: config.snoozeDuration) {
                                    config.snoozeDuration = 900
                                }
                            }

                            HStack(spacing: 8) {
                                Stepper(value: Binding(
                                    get: { config.snoozeDuration },
                                    set: { config.snoozeDuration = max(5, $0) }
                                ), step: 60) {
                                    Text("±1분 미세 조정: \(Int(config.snoozeDuration / 60))분")
                                        .font(.system(size: 11))
                                        .foregroundColor(Config.Colors.mute)
                                }
                            }
                        }

                        // 4. 중간 팝업(mid) 발생 주기 (Mid Survey Interval)
                        settingCard(
                            icon: "repeat",
                            iconColor: .purple,
                            title: "중간 팝업(mid) 반복 주기",
                            description: "AI 세션이 이어지는 동안 무작위 간격(최소~최대)으로 발생",
                            currentValueString: "\(ConfigManager.formatDuration(config.midSurveyIntervalMin)) ~ \(ConfigManager.formatDuration(config.midSurveyIntervalMax))"
                        ) {
                            HStack(spacing: 6) {
                                Button("1~2분 (테스트)") {
                                    config.midSurveyIntervalMin = 60
                                    config.midSurveyIntervalMax = 120
                                }
                                .font(.system(size: 10.5))
                                .buttonStyle(QuickButtonStyle(isSelected: config.midSurveyIntervalMin == 60 && config.midSurveyIntervalMax == 120))

                                Button("15~30분") {
                                    config.midSurveyIntervalMin = 15 * 60
                                    config.midSurveyIntervalMax = 30 * 60
                                }
                                .font(.system(size: 10.5))
                                .buttonStyle(QuickButtonStyle(isSelected: config.midSurveyIntervalMin == 900 && config.midSurveyIntervalMax == 1800))

                                Button("30~45분") {
                                    config.midSurveyIntervalMin = 30 * 60
                                    config.midSurveyIntervalMax = 45 * 60
                                }
                                .font(.system(size: 10.5))
                                .buttonStyle(QuickButtonStyle(isSelected: config.midSurveyIntervalMin == 1800 && config.midSurveyIntervalMax == 2700))

                                Button("60~120분 (표준)") {
                                    config.midSurveyIntervalMin = 3600
                                    config.midSurveyIntervalMax = 7200
                                }
                                .font(.system(size: 10.5))
                                .buttonStyle(QuickButtonStyle(isSelected: config.midSurveyIntervalMin == 3600 && config.midSurveyIntervalMax == 7200))
                            }

                            HStack(spacing: 12) {
                                Stepper(value: Binding(
                                    get: { config.midSurveyIntervalMin },
                                    set: { config.midSurveyIntervalMin = max(60, min($0, config.midSurveyIntervalMax - 60)) }
                                ), step: 300) {
                                    Text("최소: \(Int(config.midSurveyIntervalMin / 60))분")
                                        .font(.system(size: 11))
                                        .foregroundColor(Config.Colors.mute)
                                }

                                Stepper(value: Binding(
                                    get: { config.midSurveyIntervalMax },
                                    set: { config.midSurveyIntervalMax = max(config.midSurveyIntervalMin + 60, $0) }
                                ), step: 300) {
                                    Text("최대: \(Int(config.midSurveyIntervalMax / 60))분")
                                        .font(.system(size: 11))
                                        .foregroundColor(Config.Colors.mute)
                                }
                            }
                        }

                        // 5. 사용자 자리 비움(Idle) 판정 기준 (Idle Threshold)
                        settingCard(
                            icon: "person.crop.circle.badge.clock",
                            iconColor: Color(hex: Config.Colors.sageHex),
                            title: "자리 비움(Idle) 판정 기준",
                            description: "입력 부재 시 비활성 보류로 전환하는 기준 시간",
                            currentValueString: ConfigManager.formatDuration(config.idleThreshold)
                        ) {
                            HStack(spacing: 6) {
                                quickDurationButton(label: "10초 (테스트)", seconds: 10, current: config.idleThreshold) {
                                    config.idleThreshold = 10
                                }
                                quickDurationButton(label: "30초", seconds: 30, current: config.idleThreshold) {
                                    config.idleThreshold = 30
                                }
                                quickDurationButton(label: "1분", seconds: 60, current: config.idleThreshold) {
                                    config.idleThreshold = 60
                                }
                                quickDurationButton(label: "2분 (표준)", seconds: 120, current: config.idleThreshold) {
                                    config.idleThreshold = 120
                                }
                                quickDurationButton(label: "5분", seconds: 300, current: config.idleThreshold) {
                                    config.idleThreshold = 300
                                }
                            }

                            HStack(spacing: 8) {
                                Stepper(value: Binding(
                                    get: { config.idleThreshold },
                                    set: { config.idleThreshold = max(5, $0) }
                                ), step: 10) {
                                    Text("±10초 미세 조정: \(Int(config.idleThreshold))초")
                                        .font(.system(size: 11))
                                        .foregroundColor(Config.Colors.mute)
                                }
                            }
                        }

                        // 6. 데일리 넛지(nudge) 발송 시각 & 음소거 지속시간
                        settingCard(
                            icon: "bell.badge",
                            iconColor: .indigo,
                            title: "데일리 넛지 시각 & 팝업 끄기 지속",
                            description: "당일 미기록 시 넛지 발송 시각 및 메뉴 막대 음소거 시간",
                            currentValueString: "\(String(format: "%02d:%02d", config.dailyNudgeHour, config.dailyNudgeMinute)) (음소거 \(Int(config.muteDuration / 60))분)"
                        ) {
                            HStack(spacing: 6) {
                                Button("18:30 (표준)") {
                                    config.dailyNudgeHour = 18
                                    config.dailyNudgeMinute = 30
                                }
                                .font(.system(size: 10.5))
                                .buttonStyle(QuickButtonStyle(isSelected: config.dailyNudgeHour == 18 && config.dailyNudgeMinute == 30))

                                Button("⚡ 현재+1분 뒤 (테스트)") {
                                    config.setNudgeToNextMinute()
                                    showToast("데일리 넛지가 1분 뒤로 설정되었습니다.")
                                }
                                .font(.system(size: 10.5))
                                .buttonStyle(QuickButtonStyle(isSelected: false))

                                Spacer()

                                quickDurationButton(label: "음소거 5분", seconds: 300, current: config.muteDuration) {
                                    config.muteDuration = 300
                                }
                                quickDurationButton(label: "음소거 60분", seconds: 3600, current: config.muteDuration) {
                                    config.muteDuration = 3600
                                }
                            }

                            HStack(spacing: 12) {
                                Stepper(value: Binding(
                                    get: { config.dailyNudgeHour },
                                    set: { config.dailyNudgeHour = ($0 + 24) % 24 }
                                ), in: 0...23) {
                                    Text("시(Hour): \(config.dailyNudgeHour)시")
                                        .font(.system(size: 11))
                                        .foregroundColor(Config.Colors.mute)
                                }

                                Stepper(value: Binding(
                                    get: { config.dailyNudgeMinute },
                                    set: { config.dailyNudgeMinute = ($0 + 60) % 60 }
                                ), in: 0...59) {
                                    Text("분(Min): \(config.dailyNudgeMinute)분")
                                        .font(.system(size: 11))
                                        .foregroundColor(Config.Colors.mute)
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Config.Colors.cardBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))
    }

    // MARK: - 서브 뷰 컴포넌트

    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))

                    Text("⚙️ 연구 파라미터 & 스케줄러 실시간 설정")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)
                }
            }
            .buttonStyle(.plain)

            Text("(변경 즉시 반영 및 영구 보존)")
                .font(.system(size: 11))
                .foregroundColor(Config.Colors.mute)

            Spacer()

            // 퀵 프리셋 버튼들
            HStack(spacing: 6) {
                Button(action: {
                    config.toggleTimeWarp()
                    if config.isTimeWarpActive {
                        showToast("⏱️ 시간 배속(1분=30분, 30배속) 활성화! (쿨다운 1분, 간격 2~4분, 스누즈 20초)")
                    } else {
                        showToast("표준 배속으로 복원되었습니다.")
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: config.isTimeWarpActive ? "forward.fill" : "forward.frame")
                        Text(config.isTimeWarpActive ? "⏱️ 배속 30x (1분=30분) 켜짐" : "⏱️ 시간 배속 (1분=30분)")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(config.isTimeWarpActive ? .white : Color.purple)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(config.isTimeWarpActive ? Color.purple : Color.purple.opacity(0.12))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Button(action: {
                    config.resetToDefaults()
                    showToast("표준 연구 기본값으로 복원되었습니다. (쿨다운 30분, 타임아웃 5분, 스누즈 10분)")
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("표준 기본값 복원")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Config.Colors.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Button(action: {
                    config.applyFastTestPreset()
                    showToast("⚡ 고속 테스트 모드가 적용되었습니다! (쿨다운 0초, 타임아웃 30초, 스누즈 10초, 유휴 10초)")
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                        Text("고속 테스트 모드")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(hex: Config.Colors.accentHex))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func settingCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        currentValueString: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                Spacer()

                Text(currentValueString)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(iconColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(iconColor.opacity(0.1))
                    .cornerRadius(4)
            }

            Text(description)
                .font(.system(size: 10.5))
                .foregroundColor(Config.Colors.mute)
                .lineLimit(1)

            Divider()
                .padding(.vertical, 1)

            content()
        }
        .padding(10)
        .background(Config.Colors.panelBackground)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.6))
    }

    private func quickDurationButton(label: String, seconds: TimeInterval, current: TimeInterval, action: @escaping () -> Void) -> some View {
        let isSelected = abs(current - seconds) < 0.5
        return Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: isSelected ? .bold : .regular))
        }
        .buttonStyle(QuickButtonStyle(isSelected: isSelected))
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if toastMessage == message {
                withAnimation { toastMessage = nil }
            }
        }
    }
}

/// 퀵 설정 버튼 전용 스타일
private struct QuickButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isSelected ? .white : Config.Colors.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color(hex: Config.Colors.accentHex) : Config.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.clear : Config.Colors.line, lineWidth: 0.8)
                    )
            )
            .opacity(configuration.isPressed ? 0.75 : 1.0)
    }
}
