import SwiftUI
import AppKit

/// docs/mockup.html 06 장면 자발적 피로 기록(Diary) 전용 팝업 뷰
/// - [헤더] 제목 "피로한 순간을 남겨주세요" (다른 팝업과 통일된 단일 타이틀 형태)
/// - [캡처 카드] 썸네일 + "앱 이름 · 시각 캡처" + "다시 캡처" 버튼
/// - [공통 척도] 피로 척도 (0~10, 주황색), 유용성 척도 (1~5, 초록색)
/// - [피로 6점 이상] 붉은 배경(#FBE6DD, #F2C4B2)
///   1) "어떤 점이 피곤하게 느껴졌나요? (복수 선택)" (6대 카테고리)
///   2) "어떻게 하면 덜 피곤할까요? (선택)" -> 'AI가 어떻게 해주면 좋을까요? ', '나는 무엇을 바꿔볼 수 있을까요?' 2개 질문 분리 및 확장 입력창
/// - [하단 액션] "취소" 및 "저장" 버튼
public struct VoluntaryRecordPopupView: View {
    @State public var context: VoluntaryCaptureContext
    public let maxContentHeight: CGFloat
    public let onHeightChanged: ((CGFloat) -> Void)?
    public let onRetakeCapture: (((@escaping (String?) -> Void) -> Void))?
    public let onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))?
    public let onCancel: () -> Void
    public let onSave: (VoluntaryCaptureContext, [String: String]) -> Void

    @StateObject private var formState: SurveyFormState = SurveyFormState()
    @State private var innerContentHeight: CGFloat = 360.0
    @State private var isActionProcessed: Bool = false
    @ObservedObject private var speechManager = SpeechInputManager.shared

    private let cardWidth: CGFloat = Config.Survey.popupDefaultWidth // 372px

    public init(
        context: VoluntaryCaptureContext,
        initialSituation: String? = nil,
        initialFatigue: Int? = nil,
        initialAIFatigueImpact: Int? = nil,
        initialCapturePath: String? = nil,
        maxContentHeight: CGFloat = 520,
        onHeightChanged: ((CGFloat) -> Void)? = nil,
        onRetakeCapture: (((@escaping (String?) -> Void) -> Void))? = nil,
        onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping (VoluntaryCaptureContext, [String: String]) -> Void
    ) {
        var mutableContext = context
        if let initialPath = initialCapturePath, mutableContext.localImagePath == nil {
            mutableContext.localImagePath = initialPath
        }
        self._context = State(initialValue: mutableContext)
        self.maxContentHeight = maxContentHeight
        self.onHeightChanged = onHeightChanged
        self.onRetakeCapture = onRetakeCapture
        self.onRetakeAreaCapture = onRetakeAreaCapture
        self.onCancel = onCancel
        self.onSave = onSave

        let isTestHigh = CommandLine.arguments.contains("--test-diary-popup-high-fatigue") || CommandLine.arguments.contains("--test-high-fatigue")
        let initF = initialFatigue ?? (isTestHigh ? 4 : nil)
        let initImpact = initialAIFatigueImpact ?? (isTestHigh ? 3 : nil)
        let state = SurveyFormState(
            fatigueScore: initF,
            aiFatigueImpactScore: initImpact,
            usefulnessScore: nil,
            capturedImagePath: mutableContext.localImagePath
        )
        if let sit = initialSituation, !sit.isEmpty {
            state.situationAnswer = SubjectiveAnswer(customText: sit)
        }
        if initF != nil {
            state.selectedFatigueCategories = ["overload", "physicalTired"]
        }
        self._formState = StateObject(wrappedValue: state)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: context.capturedAt)
    }

    /// 필수 문항 충족 여부 검증 (피로도 필수, 피로도 2점 이상일 시 AI 영향 필수)
    private var isFormValid: Bool {
        formState.isFormValid(for: .diary)
    }

    public var body: some View {
        let isOverflowing = innerContentHeight > maxContentHeight

        VStack(spacing: 0) {
            // 1. 헤더 (주 제목 + 안내 문구)
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()
                .background(Config.Colors.line)

            // 2. 본문 영역
            ScrollView(.vertical, showsIndicators: isOverflowing) {
                VStack(alignment: .leading, spacing: 14) {
                    // 문항 1. 작업 목적 및 역할 분담 (사용 목적/캡처, AI가 하는 일, 내가 하는 일)
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
                            capturedImagePath: Binding(
                                get: { formState.capturedImagePath ?? context.localImagePath },
                                set: { newPath in
                                    formState.capturedImagePath = newPath
                                    context.localImagePath = newPath
                                }
                            ),
                            onRetakeAreaCapture: onRetakeAreaCapture,
                            onFocusChanged: { isFocused in
                                formState.isTextFieldFocused = isFocused
                            }
                        )
                    }

                    // 문항 2. 피로도, AI 피로도 & 이유, 그 외 이유
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

            // 3. 하단 액션 버튼 바 (취소, 저장) - 넉넉한 22px 하단 여백 적용
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
    }

    // MARK: - 1. 헤더 뷰 (드래그하여 창 이동 가능 - 다른 설문 팝업과 통일된 단일 타이틀 형태)
    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: Config.Colors.accentHex).opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: context.isFromNudge ? "book.fill" : "square.and.pencil")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: Config.Colors.accentHex))
                    .offset(y: -1.2)
            }

            Text(context.customTitle ?? (context.isFromNudge ? "오늘의 AI 피로 기록" : "피로한 순간을 남겨주세요"))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Config.Colors.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(WindowDragArea())
    }

    // MARK: - 3. 하단 액션 버튼 바 (취소, 저장)
    private var footerActionSection: some View {
        HStack(spacing: 10) {
            // 취소 버튼
            Button(action: {
                guard !isActionProcessed else { return }
                isActionProcessed = true
                print("[VoluntaryRecord] 취소 버튼(또는 Esc) 클릭됨 -> 팝업 닫기 요청")
                if speechManager.isRecording {
                    SpeechInputManager.shared.stopRecording()
                }
                onCancel()
            }) {
                Text("취소")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Config.Colors.mute)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .keyboardShortcut(.cancelAction)
            .disabled(isActionProcessed)

            Spacer()

            // 저장 버튼 (피로도 척도 선택 시 활성화)
            Button(action: {
                guard isFormValid, !isActionProcessed else { return }
                isActionProcessed = true
                saveAction()
            }) {
                HStack(spacing: 4) {
                    if isActionProcessed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text("저장됨")
                    } else {
                        Text("저장")
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isFormValid ? .white : Config.Colors.mute.opacity(0.8))
                .padding(.horizontal, isActionProcessed ? 16 : 20)
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

    private func saveAction() {
        var payload = formState.toResponsePayload(type: .diary)

        // 자발적 기록 맥락 정보 직렬화
        if let p = context.localImagePath {
            payload["capture_local_path"] = p
            payload["capture_path"] = p
        }
        payload["capture_app_name"] = context.appName
        if let t = context.windowTitle {
            payload["capture_window_title"] = t
        }
        if let u = context.url {
            payload["capture_url"] = u
        }
        if let sId = context.sessionId {
            payload["session_id"] = sId.uuidString
        }
        if let sTitle = context.sessionTitle {
            payload["session_title"] = sTitle
        }

        print("[VoluntaryRecord] 자발적 피로 기록 저장: \(payload)")
        onSave(context, payload)
    }
}
