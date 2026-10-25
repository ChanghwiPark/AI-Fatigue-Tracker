import SwiftUI

/// docs/mockup.html 01~04 장면에 맞춘 정밀 구현 설문 팝업 뷰
/// - [공통] 헤더(주황 점 + 'AI 피로 기록', 우상단 요소 없음), 피로 척도(0~10), 유용성 척도(1~5)
/// - [start] AI 사용 목적 주관식 + '특별한 목적 없음' 비활성화 칩
/// - [mid] 상태 점검 전용 (폭 340px, 피로·유용성 척도)
/// - [end] NASA-TLX 6개 슬라이더 (0~100, step 5) + 유용성 4점 이상 후속 질문
/// - [피로 6점 이상 공통] 연한 붉은 배경(#FBE6DD, 테두리 #F2C4B2, 모서리 12px) 아래로 펼쳐지는 6대 심층 원인 문항
/// - [음성 입력] ko-KR Speech-to-Text 마이크 연동 (음성 파일 미저장)
/// - [상태 보존] 점수 재선택 시에도 입력 내용 100% 보존
public struct SurveyPopupView: View {
    public let surveyType: SurveyType
    public let sessionTitle: String?
    public let aiTool: String?
    public let maxContentHeight: CGFloat
    public let onHeightChanged: ((CGFloat) -> Void)?
    public let onAction: (SurveyAction, [String: String]?) -> Void

    // 화면 재렌더링 시에도 사용자가 써 둔 답변이 지워지지 않도록 StateObject로 보존
    @StateObject private var formState: SurveyFormState
    @ObservedObject private var speechManager = SpeechInputManager.shared

    @State private var remainingSeconds: Int = Int(Config.Scheduler.autoDismissDuration)
    @State private var timer: Timer? = nil
    @State private var innerContentHeight: CGFloat

    public init(
        surveyType: SurveyType,
        sessionTitle: String? = nil,
        aiTool: String? = nil,
        initialFatigue: Int? = nil,
        initialUsefulness: Int? = nil,
        maxContentHeight: CGFloat = 520,
        onHeightChanged: ((CGFloat) -> Void)? = nil,
        onAction: @escaping (SurveyAction, [String: String]?) -> Void
    ) {
        self.surveyType = surveyType
        self.sessionTitle = sessionTitle
        self.aiTool = aiTool
        self.maxContentHeight = maxContentHeight
        self.onHeightChanged = onHeightChanged
        self.onAction = onAction

        let defaultEstimatedHeight: CGFloat = {
            switch surveyType {
            case .mid: return 120.0
            case .start: return 230.0
            case .end: return 480.0
            case .diary, .nudge: return 120.0
            }
        }()
        self._innerContentHeight = State(initialValue: defaultEstimatedHeight)

        let initF = initialFatigue ?? (CommandLine.arguments.contains("--test-high-fatigue") ? 8 : nil)
        // AI 유용성 질문은 [end] AI 세션 종료 설문 전용
        let initU = (surveyType == .end) ? (initialUsefulness ?? ((CommandLine.arguments.contains("--test-high-usefulness") || CommandLine.arguments.contains("--test-high-fatigue")) ? 4 : nil)) : nil
        let state = SurveyFormState(fatigueScore: initF, usefulnessScore: initU)
        if CommandLine.arguments.contains("--test-high-fatigue") {
            state.selectedFatigueCategories = ["overload", "physicalTired"]
            state.fatigueCategoryDetails["physicalTired"] = SubjectiveAnswer(
                selectedChips: ["화면을 많이 읽어 눈이 피로해요", "오래 붙잡고 있어 지쳤어요"],
                customText: "화면을 많이 읽어 눈이 피로해요, 오래 붙잡고 있어 지쳤어요"
            )
        }
        self._formState = StateObject(wrappedValue: state)
    }

    /// [mid] 및 [nudge] 화면은 340px, 그 외 [start], [end], [diary]는 372px
    private var cardWidth: CGFloat {
        (surveyType == .mid || surveyType == .nudge) ? Config.Survey.popupMidWidth : Config.Survey.popupDefaultWidth
    }

    /// 감지된 AI 도구명 (기본값 ChatGPT)
    private var detectedToolName: String {
        if let tool = aiTool, !tool.isEmpty {
            return tool
        }
        if let active = SessionManager.shared.currentSession?.toolName, !active.isEmpty {
            return active
        }
        return "ChatGPT"
    }

    /// 장면별 주 제목
    private var sceneTitle: String {
        switch surveyType {
        case .start:
            return "\(detectedToolName) 사용을 시작했네요"
        case .mid:
            return "잠깐, 지금 상태를 알려주세요"
        case .end:
            return "세션을 마쳤어요. 어땠나요?"
        case .diary:
            return "오늘의 AI 피로 기록"
        case .nudge:
            return "오늘은 AI 때문에 피로한 순간이 있었나요?"
        }
    }

    /// 필수 문항 답변 여부 검증 (미완료 시 저장 불가)
    private var isFormValid: Bool {
        formState.isFormValid(for: surveyType)
    }

    public var body: some View {
        if surveyType == .nudge {
            nudgeScene07View
        } else {
            defaultSurveyView
        }
    }

    // MARK: - [nudge] docs/mockup.html 07 장면: 그날 자발적 기록 0건 알림 팝업 (폭 340px)
    private var nudgeScene07View: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 헤더 영역
            VStack(alignment: .leading, spacing: 4) {
                Text("오늘은 AI 때문에 피로한 순간이 있었나요?")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(Config.Colors.ink)
                Text("있었다면 떠오르는 대로 짧게 남겨주세요.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Config.Colors.mute)
            }
            .contentShape(Rectangle())
            .overlay(WindowDragArea())

            Divider()
                .background(Config.Colors.line)

            // 버튼 2개: "없었어요"(응답으로 기록) vs "기록하기"(5단계 흐름 열기)
            HStack(spacing: 8) {
                Button {
                    // "없었어요" -> 응답(answered)으로 기록하되 무응답(timeout)과 명확히 구분
                    stopCountdown()
                    onAction(.response, [
                        "nudge_response": "none",
                        "no_fatigue_moment": "true",
                        "fatigue_score": "0"
                    ])
                } label: {
                    Text("없었어요")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Config.Colors.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Config.Colors.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Config.Colors.line, lineWidth: 0.8)
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Button {
                    // "기록하기" -> 팝업 닫고 미기록 넛지 전용 회고 다이어리(선택적 영역 캡처) 열기
                    stopCountdown()
                    onAction(.skip, ["nudge_choice": "record"])
                } label: {
                    Text("기록하기")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: Config.Colors.accentHex))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .padding(16)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Config.Colors.popupBg)
                .shadow(color: Color.black.opacity(0.15), radius: 16, x: -2, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Config.Colors.line, lineWidth: 1.0)
                .allowsHitTesting(false)
        )
        .padding(6)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SurveyTotalHeightPreferenceKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(SurveyTotalHeightPreferenceKey.self) { totalH in
            if totalH > 0 {
                self.onHeightChanged?(totalH)
            }
        }
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            stopCountdown()
        }
    }

    private var defaultSurveyView: some View {
        let isOverflowing = innerContentHeight > maxContentHeight

        return VStack(spacing: 0) {
            // 1. 헤더 (주 제목 노출, AI 도구명 및 아이콘 배지로 문항과 시각적 차별화)
            SurveyHeaderView(
                title: sceneTitle,
                toolName: detectedToolName,
                surveyType: surveyType
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .background(Config.Colors.line)

            // 2. 본문 영역 (폼이 길지 않으면 스크롤 없이 전체 표시, 화면 초과 시에만 내부 스크롤)
            ScrollView(.vertical, showsIndicators: isOverflowing) {
                VStack(alignment: .leading, spacing: 14) {
                    contentBySurveyType
                }
                .padding(16)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: SurveyContentHeightPreferenceKey.self, value: geo.size.height)
                    }
                )
            }
            .frame(height: min(innerContentHeight, maxContentHeight))
            .scrollDisabled(!isOverflowing)
            .onPreferenceChange(SurveyContentHeightPreferenceKey.self) { newH in
                if newH > 0 && abs(self.innerContentHeight - newH) > 1.0 {
                    self.innerContentHeight = newH
                }
            }

            Divider()
                .background(Config.Colors.line)

            // 3. 하단 액션 버튼 바 및 카운트다운 (넉넉한 하단 22px 여백으로 둥근 모서리와 버튼 사이 충분한 공간 확보)
            footerActionSection
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 22)
        }
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Config.Colors.popupBg)
                .shadow(color: Color.black.opacity(0.15), radius: 16, x: -2, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Config.Colors.line, lineWidth: 1.0)
                .allowsHitTesting(false)
        )
        .padding(6)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SurveyTotalHeightPreferenceKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(SurveyTotalHeightPreferenceKey.self) { totalH in
            if totalH > 0 {
                self.onHeightChanged?(totalH)
            }
        }
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            stopCountdown()
        }
    }

    // MARK: - 설문 유형별 콘텐츠 분기

    @ViewBuilder
    private var contentBySurveyType: some View {
        switch surveyType {
        case .start:
            startSurveyContent
        case .mid:
            midSurveyContent
        case .end:
            endSurveyContent
        case .diary, .nudge:
            diaryOrNudgeContent
        }
    }

    // MARK: - [start] 장면 01 콘텐츠
    // 1. "무엇을 위해 AI를 사용하려 하나요?" 주관식 한 줄. 아래 "특별한 목적 없음" 칩 하나만 (누르면 비활성화).
    // 2. 피로 척도 (0~10)
    // 3. 유용성 척도 (1~5)
    private var startSurveyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 문항 1. 목적 주관식 + "특별한 목적 없음" 칩
            VStack(alignment: .leading, spacing: 6) {
                Text("무엇을 위해 AI를 사용하려 하나요?")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                SubjectiveInputFieldView(
                    label: nil,
                    placeholder: formState.startPurpose.isNoSpecificPurpose ? "특별한 목적 없음" : "작업 목표나 기대하는 결과물을 적어주세요.",
                    fieldKey: "start_purpose",
                    chipOptions: [],
                    isSingleLine: true,
                    isDisabled: formState.startPurpose.isNoSpecificPurpose,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    },
                    answer: $formState.startPurpose
                )

                // 아래 "특별한 목적 없음" 칩 하나만
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        formState.toggleNoSpecificPurpose()
                    }
                }) {
                    HStack(spacing: 4) {
                        if formState.startPurpose.isNoSpecificPurpose {
                            Text("✓")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text("특별한 목적 없음")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(formState.startPurpose.isNoSpecificPurpose ? Color(hex: Config.Colors.accentHex) : Config.Colors.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(formState.startPurpose.isNoSpecificPurpose ? Color(hex: Config.Colors.accentHex).opacity(0.12) : Config.Colors.paper)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(formState.startPurpose.isNoSpecificPurpose ? Color(hex: Config.Colors.accentHex) : Config.Colors.line, lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 문항 2. 피로 척도
            FatigueScaleView(score: $formState.fatigueScore)

            // 피로 6점 이상일 때 후속 질문 (피로 질문 바로 밑, 절제된 부드러운 페이드 인)
            if formState.isHighFatigue {
                DeepFatigueSectionView(formState: formState)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - [mid] 장면 02 콘텐츠
    // 폭 340px. 피로 척도만 (6점 이상 시 피로 후속 질문).
    private var midSurveyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. 피로 척도
            FatigueScaleView(score: $formState.fatigueScore)

            // 피로 6점 이상일 때 후속 질문 (피로 질문 바로 밑, 절제된 부드러운 페이드 인)
            if formState.isHighFatigue {
                DeepFatigueSectionView(formState: formState)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - [end] 장면 03 콘텐츠
    // 1. 피로 척도 (6점 이상 시 피로 후속 질문)
    // 2. 유용성 척도 (4점 이상 시 유용성 후속 질문) - 오직 [end] AI 세션 종료 설문 전용
    // 3. "이번 작업은 어땠나요?" 슬라이더 6개 (정신적 요구, 신체적 요구, 시간 압박, 성과 만족, 노력, 좌절감)
    private var endSurveyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. 피로 척도
            FatigueScaleView(score: $formState.fatigueScore)

            // 피로 6점 이상일 때 후속 질문 (피로 질문 바로 밑, 절제된 부드러운 페이드 인)
            if formState.isHighFatigue {
                DeepFatigueSectionView(formState: formState)
                    .transition(.opacity)
            }

            Divider()

            // 2. 유용성 척도 (AI가 도움이 된다고 느끼는 정도 - [end] 전용)
            UsefulnessScaleView(score: $formState.usefulnessScore)

            // 유용성 4점 이상일 때 후속 질문 (유용성 질문 바로 밑, 절제된 부드러운 페이드 인)
            if formState.isHighUsefulness {
                UsefulnessHelpSectionView(formState: formState)
                    .transition(.opacity)
            }

            Divider()

            // 3. 이번 작업은 어땠나요? (NASA-TLX 슬라이더 6개)
            TLXSliderSectionView(tlx: $formState.endTLX, onModified: {
                formState.isTLXModified = true
            })
        }
    }

    // MARK: - [diary / nudge] 다이어리 및 넛지용 콘텐츠
    private var diaryOrNudgeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. 피로 척도
            FatigueScaleView(score: $formState.fatigueScore)

            // 피로 6점 이상일 때 후속 질문 (피로 질문 바로 밑, 절제된 부드러운 페이드 인)
            if formState.isHighFatigue {
                DeepFatigueSectionView(formState: formState)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - 3. 하단 액션 바 (건너뛰기, 10분 뒤에, 로고+시간, 응답 - 단일 행 구성)
    private var footerActionSection: some View {
        HStack(spacing: 8) {
            // 건너뛰기 버튼
            Button(action: {
                stopCountdown()
                SpeechInputManager.shared.stopRecording()
                onAction(.skip, nil)
            }) {
                Text("건너뛰기")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Config.Colors.mute)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .keyboardShortcut(.cancelAction)

            // 10분 뒤에 버튼
            Button(action: {
                stopCountdown()
                onAction(.snooze, nil)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10.5))
                    Text("10분 뒤에")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Spacer()

            // 로고(시계 아이콘)와 시간: 아무것도 입력하지 않은 순수 무응답 대기 상태일 때만 카운트다운 표시
            if !formState.hasAnyInput && !speechManager.isRecording {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(remainingSeconds <= 20 ? .red : Color(hex: Config.Colors.accentHex))
                    Text(formattedCountdown)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundColor(remainingSeconds <= 20 ? .red : Config.Colors.mute)
                }
                .padding(.trailing, 2)
                .transition(.opacity)
            }

            // 저장 버튼 (필수 문항 완료 시 활성화)
            Button(action: {
                guard isFormValid else { return }
                stopCountdown()
                let payload = formState.toResponsePayload(type: surveyType)
                onAction(.response, payload)
            }) {
                Text("저장")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isFormValid ? .white : Config.Colors.mute.opacity(0.8))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(isFormValid ? Color(hex: Config.Colors.accentHex) : Color.gray.opacity(0.18))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(!isFormValid)
        }
    }

    // MARK: - 타이머 관리 (아무것도 입력하지 않는 동안에만 카운트다운 작동)
    private var formattedCountdown: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func startCountdown() {
        stopCountdown()
        remainingSeconds = Int(Config.Scheduler.autoDismissDuration)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // 사용자가 폼에 입력을 시작했거나 음성 녹음 중이면 무응답 자동 닫힘을 멈춤
            if formState.hasAnyInput || speechManager.isRecording {
                return
            }

            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                stopCountdown()
                onAction(.noResponse, nil)
            }
        }
    }

    private func stopCountdown() {
        timer?.invalidate()
        timer = nil
    }
}

/// 설문 본문 내용의 실제 높이를 동적으로 측정하는 PreferenceKey
public struct SurveyContentHeightPreferenceKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 설문 카드 전체(외곽 패딩 및 그림자 마진 포함)의 실제 높이를 측정하는 PreferenceKey
public struct SurveyTotalHeightPreferenceKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
