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
    public let snoozeCount: Int
    public let maxContentHeight: CGFloat
    public let onHeightChanged: ((CGFloat) -> Void)?
    public let onAction: (SurveyAction, [String: String]?) -> Void

    // 화면 재렌더링 시에도 사용자가 써 둔 답변이 지워지지 않도록 StateObject로 보존
    @StateObject private var formState: SurveyFormState
    @ObservedObject private var speechManager = SpeechInputManager.shared

    @State private var remainingSeconds: Int = Int(Config.Scheduler.autoDismissDuration)
    @State private var timer: Timer? = nil
    @State private var innerContentHeight: CGFloat
    @State private var isActionProcessed: Bool = false
    @State private var currentStep: Int = 1 // 페이징(Wizard) 현재 단계

    private var canSnooze: Bool {
        snoozeCount < Config.Scheduler.maxSnoozeCount
    }

    private let onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))?

    public init(
        surveyType: SurveyType,
        sessionTitle: String? = nil,
        aiTool: String? = nil,
        snoozeCount: Int = 0,
        initialStep: Int = 1,
        draftState: SurveyDraftState? = nil,
        initialSituation: String? = nil,
        initialFatigue: Int? = nil,
        initialAIFatigueImpact: Int? = nil,
        initialUsefulness: Int? = nil,
        initialSelectedCategories: Set<String> = [],
        initialCapturePath: String? = nil,
        maxContentHeight: CGFloat = 520,
        onHeightChanged: ((CGFloat) -> Void)? = nil,
        onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))? = nil,
        onAction: @escaping (SurveyAction, [String: String]?) -> Void
    ) {
        self.surveyType = surveyType
        self.sessionTitle = sessionTitle
        self.aiTool = aiTool
        self.snoozeCount = snoozeCount
        self.maxContentHeight = maxContentHeight
        self.onHeightChanged = onHeightChanged
        self.onRetakeAreaCapture = onRetakeAreaCapture
        self.onAction = onAction

        // 스누즈 재알림(snoozeCount > 0) 또는 전달된 draftState가 있는 경우 임시 저장본 우선 복원
        let resolvedDraft = draftState ?? (snoozeCount > 0 ? SurveyDraftStore.shared.getDraft(for: surveyType) : nil)
        let resolvedStep = resolvedDraft?.currentStep ?? initialStep
        self._currentStep = State(initialValue: resolvedStep)

        let defaultEstimatedHeight: CGFloat = {
            switch surveyType {
            case .mid: return 320.0
            case .start: return 220.0
            case .end: return 520.0
            case .diary, .nudge: return 220.0
            case .followUp: return 340.0
            }
        }()
        self._innerContentHeight = State(initialValue: defaultEstimatedHeight)

        let isTestHigh = CommandLine.arguments.contains("--test-high-fatigue")
        let initF = initialFatigue ?? (isTestHigh ? 4 : nil)
        let initImpact = initialAIFatigueImpact ?? (isTestHigh ? 3 : nil)
        let initU = (surveyType == .end || surveyType == .mid) ? (initialUsefulness ?? ((CommandLine.arguments.contains("--test-high-usefulness") || isTestHigh) ? 4 : nil)) : nil
        let state = SurveyFormState(
            fatigueScore: initF,
            aiFatigueImpactScore: initImpact,
            usefulnessScore: initU,
            capturedImagePath: initialCapturePath
        )
        if let sit = initialSituation, !sit.isEmpty {
            state.situationAnswer = SubjectiveAnswer(customText: sit)
            state.taskPurpose = SubjectiveAnswer(customText: sit)
        }
        if !initialSelectedCategories.isEmpty {
            state.selectedFatigueCategories = initialSelectedCategories
        } else if isTestHigh {
            state.selectedFatigueCategories = ["overload", "physicalTired"]
        }

        // 임시 저장된 Draft가 있다면 모든 입력 데이터(텍스트, 점수, 칩 등) 복원
        if let draft = resolvedDraft {
            state.restore(from: draft)
            print("[SurveyPopupView] [\(surveyType.rawValue)] 임시 저장본 복원 완료: 단계 \(resolvedStep), 피로도 \(String(describing: draft.fatigueScore))")
        }

        self._formState = StateObject(wrappedValue: state)
    }

    private var cardWidth: CGFloat {
        surveyType == .nudge ? Config.Survey.popupMidWidth : Config.Survey.popupDefaultWidth
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
            return "\(detectedToolName)로 새 작업을 시작했네요"
        case .mid:
            return "잠깐, 지금 상태를 알려주세요"
        case .end:
            return "세션을 마쳤네요"
        case .diary:
            return "오늘의 AI 피로 기록"
        case .nudge:
            return "오늘은 AI 때문에 피로한 순간이 있었나요?"
        case .followUp:
            return "피로를 느낀 지 30분이 지났네요"
        }
    }

    /// 필수 문항 답변 여부 검증 (미완료 시 저장 불가)
    private var isFormValid: Bool {
        formState.isFormValid(for: surveyType)
    }

    /// 페이징(Wizard) 총 단계 수
    private var totalSteps: Int {
        switch surveyType {
        case .start: return 2
        case .mid: return 3
        case .end: return 3
        case .diary: return 2
        case .followUp: return 1
        case .nudge: return 1
        }
    }

    /// 현재 단계의 서브 타이틀 (우측 상단 인디케이터용)
    private var currentStepTitle: String {
        switch surveyType {
        case .start:
            return currentStep == 1 ? "작업 맥락" : "피로도 점검"
        case .mid:
            switch currentStep {
            case 1: return "작업 맥락"
            case 2: return "피로도 평가"
            default: return "유용성 평가"
            }
        case .end:
            switch currentStep {
            case 1: return "피로도 평가"
            case 2: return "유용성 평가"
            default: return "작업 부하 평가"
            }
        case .diary:
            return currentStep == 1 ? "작업 맥락" : "피로도 평가"
        case .followUp:
            return "피로 점검"
        case .nudge:
            return "알림"
        }
    }

    /// 현재 단계의 필수 입력 완료 여부 (다음 버튼 활성화 기준)
    private var isCurrentStepValid: Bool {
        formState.isStepValid(for: surveyType, step: currentStep)
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
                    performAction(.response, [
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
                .disabled(isActionProcessed)

                Button {
                    // "기록하기" -> 팝업 닫고 미기록 넛지 전용 회고 다이어리(선택적 영역 캡처) 열기
                    performAction(.skip, ["nudge_choice": "record"])
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
                .disabled(isActionProcessed)
            }
        }
        .padding(16)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Config.Colors.popupBg)
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1.5)
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 5)
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
            // 1. 헤더 (주 제목 노출, AI 도구명 및 아이콘 배지, 우상단 단계 인디케이터, 스누즈 이어서 작성 배지)
            SurveyHeaderView(
                title: sceneTitle,
                toolName: detectedToolName,
                surveyType: surveyType,
                currentStep: currentStep,
                totalSteps: totalSteps,
                stepTitle: currentStepTitle,
                isContinuingDraft: (snoozeCount > 0 && SurveyDraftStore.shared.hasDraft(for: surveyType))
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .background(Config.Colors.line)

            // 2. 본문 영역 (단계별 단일 카드 뷰 - 화면 초과 시에만 내부 스크롤)
            ScrollView(.vertical, showsIndicators: isOverflowing) {
                VStack(alignment: .leading, spacing: 16) {
                    contentBySurveyType
                }
                .padding(16)
                .animation(.easeInOut(duration: 0.22), value: currentStep)
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

            // 3. 하단 액션 버튼 바 및 카운트다운 (방안 1: 좌측 건너뛰기 고정, 우측 [이전][다음/완료] 페어링)
            footerActionSection
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 22)
        }
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Config.Colors.popupBg)
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1.5)
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 5)
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
        case .followUp:
            followUpContent
        }
    }

    // MARK: - [start] 장면 01 시작 콘텐츠 (사용 목적, AI가 하는 일, 내가 하는 일, 피로도, 그 외의 이유)
    @ViewBuilder
    private var startSurveyContent: some View {
        if currentStep == 1 {
            SurveySectionCard(
                badgeNumber: "01",
                title: "작업 맥락 & 역할 분담",
                isRequired: true
            ) {
                TaskRoleDivisionSectionView(
                    surveyType: .start,
                    taskPurpose: $formState.taskPurpose,
                    aiRole: $formState.aiRole,
                    myRole: $formState.myRole,
                    capturedImagePath: $formState.capturedImagePath,
                    onRetakeAreaCapture: onRetakeAreaCapture,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    }
                )
            }
            .transition(.opacity)
        } else {
            SurveySectionCard(
                badgeNumber: "02",
                title: "피로도 점검",
                isRequired: true
            ) {
                FatigueAndAIReasonSectionView(
                    surveyType: .start,
                    fatigueScore: $formState.fatigueScore,
                    aiFatigueImpactScore: $formState.aiFatigueImpactScore,
                    fatigueReasonAI: $formState.fatigueReasonAI,
                    fatigueReasonNonAI: $formState.fatigueReasonNonAI,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    }
                )
            }
            .transition(.opacity)
        }
    }

    // MARK: - [mid] 장면 02 중간 콘텐츠 (사용 목적/캡처, AI·내 역할, 피로도, AI 피로도 & 이유, 그 외 이유, AI 유용성 & 이유)
    @ViewBuilder
    private var midSurveyContent: some View {
        switch currentStep {
        case 1:
            SurveySectionCard(
                badgeNumber: "01",
                title: "작업 맥락 & 역할 분담",
                isRequired: true
            ) {
                TaskRoleDivisionSectionView(
                    surveyType: .mid,
                    taskPurpose: $formState.taskPurpose,
                    aiRole: $formState.aiRole,
                    myRole: $formState.myRole,
                    capturedImagePath: $formState.capturedImagePath,
                    onRetakeAreaCapture: onRetakeAreaCapture,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    }
                )
            }
            .transition(.opacity)
        case 2:
            SurveySectionCard(
                badgeNumber: "02",
                title: "피로도 평가",
                isRequired: true
            ) {
                FatigueAndAIReasonSectionView(
                    surveyType: .mid,
                    fatigueScore: $formState.fatigueScore,
                    aiFatigueImpactScore: $formState.aiFatigueImpactScore,
                    fatigueReasonAI: $formState.fatigueReasonAI,
                    fatigueReasonNonAI: $formState.fatigueReasonNonAI,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    }
                )
            }
            .transition(.opacity)
        default:
            SurveySectionCard(
                badgeNumber: "03",
                title: "AI 유용성 평가",
                isRequired: true
            ) {
                AIUsefulnessAndReasonSectionView(
                    surveyType: .mid,
                    usefulnessScore: $formState.usefulnessScore,
                    usefulnessReason: $formState.usefulnessReason,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    }
                )
            }
            .transition(.opacity)
        }
    }

    // MARK: - [end] 장면 03 종료 콘텐츠 (피로도, AI 피로도 & 이유, 그 외 이유, AI 유용성 & 이유, NASA-TLX)
    @ViewBuilder
    private var endSurveyContent: some View {
        switch currentStep {
        case 1:
            SurveySectionCard(
                badgeNumber: "01",
                title: "피로도 평가",
                isRequired: true
            ) {
                FatigueAndAIReasonSectionView(
                    surveyType: .end,
                    fatigueScore: $formState.fatigueScore,
                    aiFatigueImpactScore: $formState.aiFatigueImpactScore,
                    fatigueReasonAI: $formState.fatigueReasonAI,
                    fatigueReasonNonAI: $formState.fatigueReasonNonAI,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    }
                )
            }
            .transition(.opacity)
        case 2:
            SurveySectionCard(
                badgeNumber: "02",
                title: "AI 유용성 평가",
                isRequired: true
            ) {
                AIUsefulnessAndReasonSectionView(
                    surveyType: .end,
                    usefulnessScore: $formState.usefulnessScore,
                    usefulnessReason: $formState.usefulnessReason,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    }
                )
            }
            .transition(.opacity)
        default:
            SurveySectionCard(
                badgeNumber: "03",
                title: "작업 부하 및 수행 평가 (NASA-TLX)",
                isRequired: true
            ) {
                TLXSliderSectionView(tlx: $formState.endTLX, onModified: {
                    formState.isTLXModified = true
                })
            }
            .transition(.opacity)
        }
    }

    // MARK: - [diary / nudge] 다이어리 및 넛지용 콘텐츠 (사용 목적/캡처, AI·내 역할, 피로도, AI 피로도 & 이유, 그 외 이유)
    @ViewBuilder
    private var diaryOrNudgeContent: some View {
        if currentStep == 1 {
            SurveySectionCard(
                badgeNumber: "01",
                title: "작업 맥락 & 역할 분담",
                isRequired: true
            ) {
                TaskRoleDivisionSectionView(
                    surveyType: .diary,
                    taskPurpose: $formState.taskPurpose,
                    aiRole: $formState.aiRole,
                    myRole: $formState.myRole,
                    capturedImagePath: $formState.capturedImagePath,
                    onRetakeAreaCapture: onRetakeAreaCapture,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    }
                )
            }
            .transition(.opacity)
        } else {
            SurveySectionCard(
                badgeNumber: "02",
                title: "피로도 평가",
                isRequired: true
            ) {
                FatigueAndAIReasonSectionView(
                    surveyType: .diary,
                    fatigueScore: $formState.fatigueScore,
                    aiFatigueImpactScore: $formState.aiFatigueImpactScore,
                    fatigueReasonAI: $formState.fatigueReasonAI,
                    fatigueReasonNonAI: $formState.fatigueReasonNonAI,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    }
                )
            }
            .transition(.opacity)
        }
    }

    // MARK: - [followUp] 응답 30분 뒤 피로 영향 및 대처 점검 콘텐츠
    private var followUpContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SurveySectionCard(
                badgeNumber: "01",
                title: "피로의 영향 및 대처 점검",
                isRequired: true
            ) {
                FollowUp30MinSectionView(
                    fatigueImpactOnWork: $formState.fatigueImpactOnWork,
                    isNoImpactOnWork: $formState.isNoImpactOnWork,
                    copingStrategy: $formState.copingStrategy,
                    isNoCopingStrategy: $formState.isNoCopingStrategy,
                    improvementIdea: $formState.improvementIdea,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    }
                )
            }
        }
    }

    // MARK: - 3. 하단 액션 바 (방안 1: 건너뛰기 좌측 고정, 우측 [이전][다음/완료] 페어링)
    private var footerActionSection: some View {
        HStack(spacing: 8) {
            // 건너뛰기 버튼 (좌측 구석 영구 고정)
            Button(action: {
                performAction(.skip, nil)
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
            .disabled(isActionProcessed)

            // 5분 뒤에 버튼 (최대 2회, 클릭 시 현재 입력 상태 및 단계 임시 저장)
            Button(action: {
                guard canSnooze, !isActionProcessed else { return }
                // 1. 현재 작성 중이던 모든 폼 상태와 단계(currentStep) 임시 저장
                let draft = formState.createDraft(currentStep: currentStep)
                SurveyDraftStore.shared.saveDraft(for: surveyType, draft: draft)
                print("[SurveyPopupView] '5분 뒤에' 클릭 -> 현재 \(currentStep)단계 및 입력 데이터 임시 저장 완료")

                // 2. 스누즈 페이로드 생성
                var payload = formState.toResponsePayload(type: surveyType)
                payload["is_snoozed_draft"] = "true"
                payload["draft_step"] = "\(currentStep)"
                performAction(.snooze, payload)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10.5))
                    Text("5분 뒤에")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(canSnooze ? .orange : Config.Colors.mute.opacity(0.4))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(canSnooze ? Color.orange.opacity(0.12) : Color.gray.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(!canSnooze || isActionProcessed)
            .help(canSnooze ? "현재 작성 중인 내용을 임시 저장하고 5분 뒤에 이어서 작성합니다 (최대 2회, 현재 \(snoozeCount)/\(Config.Scheduler.maxSnoozeCount))" : "스누즈 한도(최대 2회)에 도달했습니다")

            Spacer()

            // 카운트다운 타이머: 아무 입력 없을 때만 표시
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

            // [방안 1] 우측 네비게이션 페어링: [이전] [다음 ➔] 또는 [✓ 완료]
            if totalSteps > 1 {
                // 이전 버튼 (1단계에서는 비활성화하여 오클릭 방지)
                Button(action: {
                    guard currentStep > 1, !isActionProcessed else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        currentStep -= 1
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("이전")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(currentStep > 1 ? Config.Colors.ink : Config.Colors.mute.opacity(0.4))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(currentStep > 1 ? Color.gray.opacity(0.12) : Color.gray.opacity(0.06))
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(currentStep <= 1 || isActionProcessed)
            }

            // 다음 또는 완료(저장) 버튼
            if currentStep < totalSteps {
                // [다음 ➔] 버튼 (현재 단계의 필수 입력 충족 시 활성화)
                Button(action: {
                    guard isCurrentStepValid, !isActionProcessed else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        currentStep += 1
                    }
                }) {
                    HStack(spacing: 3) {
                        Text("다음")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isCurrentStepValid ? .white : Config.Colors.mute.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        isCurrentStepValid ? Color(hex: Config.Colors.accentHex) : Color.gray.opacity(0.18)
                    )
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(!isCurrentStepValid || isActionProcessed)
            } else {
                // [✓ 완료] 버튼 (마지막 단계: 전체 필수 문항 충족 시 활성화)
                Button(action: {
                    guard isFormValid, !isActionProcessed else { return }
                    let payload = formState.toResponsePayload(type: surveyType)
                    performAction(.response, payload)
                }) {
                    HStack(spacing: 4) {
                        if isActionProcessed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("저장됨")
                        } else {
                            Text("완료")
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isFormValid ? .white : Config.Colors.mute.opacity(0.8))
                    .padding(.horizontal, isActionProcessed ? 14 : 16)
                    .padding(.vertical, 7)
                    .background(
                        isActionProcessed
                            ? Color(hex: Config.Colors.accentHex)
                            : (isFormValid ? Color(hex: Config.Colors.accentHex) : Color.gray.opacity(0.18))
                    )
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(!isFormValid || isActionProcessed)
            }
        }
    }

    // MARK: - 중앙 액션 디스패치 (중복 클릭 및 다중 트리거 원천 방지)
    private func performAction(_ action: SurveyAction, _ payload: [String: String]? = nil) {
        guard !isActionProcessed else { return }
        isActionProcessed = true
        stopCountdown()
        if speechManager.isRecording {
            SpeechInputManager.shared.stopRecording()
        }
        if action == .response || action == .skip {
            SurveyDraftStore.shared.clearDraft(for: surveyType)
        }
        onAction(action, payload)
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
                performAction(.noResponse, nil)
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
