import SwiftUI
import AppKit

/// docs/mockup.html 06 장면 자발적 피로 기록(Diary) 전용 팝업 뷰
/// - [헤더] 제목 "AI 때문에 피로한 순간, 바로 남겨요", 안내 "캡처한 영역이 함께 저장돼요"
/// - [캡처 카드] 썸네일 + "앱 이름 · 시각 캡처" + "다시 캡처" 버튼
/// - [공통 척도] 피로 척도 (0~10, 주황색), 유용성 척도 (1~5, 초록색)
/// - [피로 6점 이상] 붉은 배경(#FBE6DD, #F2C4B2)
///   1) "어떤 점이 피곤하게 느껴졌나요? (복수 선택)" (6대 카테고리)
///   2) "어떻게 하면 덜 피곤할까요? (선택)" 주관식 + "AI가…", "내가…" 문장 시작 버튼
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
    @State private var howToReduceText: String = ""
    @State private var innerContentHeight: CGFloat = 360.0
    @FocusState private var isHowToReduceFocused: Bool
    @ObservedObject private var speechManager = SpeechInputManager.shared

    private let cardWidth: CGFloat = Config.Survey.popupDefaultWidth // 372px

    public init(
        context: VoluntaryCaptureContext,
        maxContentHeight: CGFloat = 520,
        onHeightChanged: ((CGFloat) -> Void)? = nil,
        onRetakeCapture: (((@escaping (String?) -> Void) -> Void))? = nil,
        onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping (VoluntaryCaptureContext, [String: String]) -> Void
    ) {
        self._context = State(initialValue: context)
        self.maxContentHeight = maxContentHeight
        self.onHeightChanged = onHeightChanged
        self.onRetakeCapture = onRetakeCapture
        self.onRetakeAreaCapture = onRetakeAreaCapture
        self.onCancel = onCancel
        self.onSave = onSave

        let initF = (CommandLine.arguments.contains("--test-diary-popup-high-fatigue") || CommandLine.arguments.contains("--test-high-fatigue")) ? 9 : nil
        let state = SurveyFormState(fatigueScore: initF, usefulnessScore: nil)
        if initF != nil {
            state.selectedFatigueCategories = ["overload", "physicalTired"]
            self._howToReduceText = State(initialValue: "AI가 핵심만 먼저 요약해주면 좋겠어요.")
        }
        self._formState = StateObject(wrappedValue: state)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: context.capturedAt)
    }

    /// 필수 문항 (피로도 척도) 응답 여부 검증
    private var isFormValid: Bool {
        formState.fatigueScore != nil
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
                    // 캡처 썸네일 카드
                    captureThumbnailSection

                    Divider()

                    // 1. 피로 척도 (0~10)
                    FatigueScaleView(score: $formState.fatigueScore)

                    // 피로 6점 이상일 때 붉은 배경 심층 질문 전개 (피로 질문 바로 아래, 절제된 부드러운 페이드 인)
                    if formState.isHighFatigue {
                        voluntaryDeepFatigueSection
                            .transition(.opacity)
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
    }

    // MARK: - 1. 헤더 뷰 (드래그하여 창 이동 가능)
    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: Config.Colors.accentHex).opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: context.isFromNudge ? "book.fill" : "square.and.pencil")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: Config.Colors.accentHex))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(context.customTitle ?? (context.isFromNudge ? "오늘의 AI 피로 기록" : "AI 때문에 피로한 순간, 바로 남겨요"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                Text(context.customSubtitle ?? (context.isFromNudge ? "떠오르는 순간을 기록해요" : "화면 전체가 함께 저장돼요"))
                    .font(.system(size: 11.5))
                    .foregroundColor(Config.Colors.mute)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(WindowDragArea())
    }

    // MARK: - 2. 캡처 썸네일 카드 섹션
    @ViewBuilder
    private var captureThumbnailSection: some View {
        if let path = context.localImagePath,
           let image = NSImage(contentsOfFile: path) {
            VStack(alignment: .leading, spacing: 6) {
                // 썸네일 이미지
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 120)
                    .background(Color.black.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Config.Colors.line, lineWidth: 0.8)
                    )

                // 하단 정보 및 다시 캡처 버튼
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11))
                            .foregroundColor(Config.Colors.mute)
                        Text(context.isFromNudge ? "화면 캡처 첨부됨" : "\(context.appName) · \(timeString) 전체화면 캡처")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Config.Colors.mute)
                            .lineLimit(1)
                    }

                    Spacer()

                    if context.isFromNudge {
                        // 영역 재캡처 버튼
                        Button(action: {
                            print("[VoluntaryRecordPopupView] 영역 재캡처 버튼 클릭됨")
                            onRetakeAreaCapture? { newPath in
                                if let newPath = newPath {
                                    self.context.localImagePath = newPath
                                }
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "crop")
                                    .font(.system(size: 10))
                                Text("영역 재캡처")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color(hex: Config.Colors.accentHex).opacity(0.1))
                            .cornerRadius(5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())

                        // 캡처 삭제 버튼
                        Button(action: {
                            print("[VoluntaryRecordPopupView] 캡처 삭제 클릭됨")
                            context.localImagePath = nil
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("삭제")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Config.Colors.mute)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Config.Colors.cardBackground)
                            .cornerRadius(5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    } else {
                        Button(action: {
                            print("[VoluntaryRecordPopupView] 전체화면 다시 캡처 버튼 클릭됨")
                            onRetakeCapture? { newPath in
                                if let newPath = newPath {
                                    self.context.localImagePath = newPath
                                }
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                Text("다시 캡처")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color(hex: Config.Colors.accentHex).opacity(0.1))
                            .cornerRadius(5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
            }
        } else if context.isFromNudge {
            // 미기록 넛지에서 온 경우: 선택적 영역 캡처 안내 카드
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: Config.Colors.accentHex).opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("참고 화면 캡처 첨부 (선택)")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)
                    Text("원하는 화면 영역을 직접 지정하여 첨부할 수 있어요")
                        .font(.system(size: 10.5))
                        .foregroundColor(Config.Colors.mute)
                }

                Spacer()

                Button(action: {
                    print("[VoluntaryRecordPopupView] 영역 캡처 버튼 클릭됨 -> onRetakeAreaCapture 호출")
                    onRetakeAreaCapture? { newPath in
                        if let newPath = newPath {
                            print("[VoluntaryRecordPopupView] 새 캡처 경로 수신: \(newPath)")
                            self.context.localImagePath = newPath
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "crop")
                            .font(.system(size: 11, weight: .semibold))
                        Text("영역 캡처")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: Config.Colors.accentHex))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Config.Colors.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Config.Colors.line, style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
            )
        } else {
            // 화면 캡처가 없을 때 (권한 필요 또는 재시도)
            Button(action: {
                if #available(macOS 11.0, *), !CGPreflightScreenCaptureAccess() {
                    PermissionsManager.shared.requestScreenCapture()
                } else {
                    onRetakeCapture? { newPath in
                        if let newPath = newPath {
                            self.context.localImagePath = newPath
                        }
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.badge.ellipsis")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                    Text("전체화면 캡처 다시 시도")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                    Spacer()
                    Text(PermissionsManager.shared.isScreenCaptureGranted ? "탭하여 캡처" : "화면 기록 권한 필요")
                        .font(.system(size: 10.5))
                        .foregroundColor(Config.Colors.mute)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Config.Colors.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Config.Colors.line, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 3. 피로 6점 이상 심층 영역
    private var voluntaryDeepFatigueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 문항 1. 어떤 점이 피곤하게 느껴졌나요? (선택)
            Text("어떤 점이 피곤하게 느껴졌나요? (선택)")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(Config.Colors.highFatigueTitle)

            VStack(spacing: 8) {
                ForEach(FatigueReasonCategory.allCategories) { category in
                    categoryRow(category: category)
                }
            }

            Divider()
                .background(Config.Colors.highFatigueBorder)

            // 문항 2. 어떻게 하면 덜 피곤할까요? (선택)
            howToReduceFatigueSection
        }
        .padding(12)
        .background(Config.Colors.highFatigueBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Config.Colors.highFatigueBorder, lineWidth: 1.0)
        )
    }

    // 피로 원인 카테고리 행
    private func categoryRow(category: FatigueReasonCategory) -> some View {
        let isSelected = formState.selectedFatigueCategories.contains(category.id)

        return VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    formState.toggleFatigueCategory(id: category.id)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute)

                    Text(category.displayTitle)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundColor(Config.Colors.highFatigueInk)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Config.Colors.highFatigueCardBg : Config.Colors.highFatigueCardBgUnselected)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color(hex: Config.Colors.accentHex) : Config.Colors.highFatigueBorder, lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)

            if isSelected {
                VStack(alignment: .leading, spacing: 4) {
                    SubjectiveInputFieldView(
                        label: "어떤 점에서요? (선택)",
                        placeholder: "더 자세한 이유나 상황을 적어주세요.",
                        fieldKey: "diary_fatigue_\(category.id)",
                        chipOptions: category.chipOptions,
                        isSingleLine: true,
                        isDisabled: false,
                        answer: Binding(
                            get: { formState.fatigueCategoryDetails[category.id] ?? SubjectiveAnswer() },
                            set: { formState.fatigueCategoryDetails[category.id] = $0 }
                        )
                    )
                }
                .padding(.leading, 12)
                .padding(.top, 2)
            }
        }
    }

    // "어떻게 하면 덜 피곤할까요? (선택)" + "AI가…", "내가…" 문장 시작 버튼
    private var howToReduceFatigueSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("어떻게 하면 덜 피곤할까요? (선택)")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(Config.Colors.highFatigueTitle)

            // 주관식 칸 + 마이크 버튼
            HStack(alignment: .top, spacing: 6) {
                TextField("생각나는 해결책이나 바람을 적어주세요.", text: $howToReduceText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Config.Colors.highFatigueInk)
                    .lineLimit(1...5)
                    .padding(.vertical, 3)
                    .focused($isHowToReduceFocused)

                // 선 마이크 버튼
                Button(action: {
                    speechManager.toggleRecording(
                        fieldKey: "how_to_reduce",
                        currentText: howToReduceText
                    ) { updated in
                        howToReduceText = updated
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(speechManager.isRecording && speechManager.activeFieldKey == "how_to_reduce" ? Color(hex: Config.Colors.accentHex) : Color.clear)
                            .frame(width: 24, height: 24)
                        Image(systemName: speechManager.isRecording && speechManager.activeFieldKey == "how_to_reduce" ? "mic.fill" : "mic")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(speechManager.isRecording && speechManager.activeFieldKey == "how_to_reduce" ? .white : Config.Colors.mute)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Config.Colors.highFatigueCardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Config.Colors.highFatigueBorder, lineWidth: 0.8)
                    )
            )

            // 문장 시작 버튼: "AI가…", "내가…" (누르면 그 말로 칸이 시작되고 커서가 끝에 놓임)
            HStack(spacing: 6) {
                sentenceStarterButton(prefix: "AI가")
                sentenceStarterButton(prefix: "내가")
                Spacer()
            }
        }
    }

    private func sentenceStarterButton(prefix: String) -> some View {
        let labelText = "\(prefix)…"
        return Button(action: {
            insertSentenceStarter(prefix)
        }) {
            HStack(spacing: 3) {
                Text("+")
                    .font(.system(size: 10, weight: .bold))
                Text(labelText)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(Color(hex: Config.Colors.accentHex))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Config.Colors.highFatigueCardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Config.Colors.highFatigueBorder, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func insertSentenceStarter(_ prefix: String) {
        var trimmed = howToReduceText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 끝에 이미 마침표나 쉼표가 있다면 정리
        while trimmed.hasSuffix(".") || trimmed.hasSuffix(",") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmed.isEmpty {
            howToReduceText = "\(prefix) "
        } else {
            howToReduceText = "\(trimmed), \(prefix) "
        }

        // 커서 이동을 위해 포커스 부여
        isHowToReduceFocused = true
    }

    // MARK: - 4. 하단 액션 버튼 바 (취소, 저장)
    private var footerActionSection: some View {
        HStack(spacing: 10) {
            // 취소 버튼
            Button(action: {
                print("[VoluntaryRecord] 취소 버튼(또는 Esc) 클릭됨 -> 팝업 닫기 요청")
                SpeechInputManager.shared.stopRecording()
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

            Spacer()

            // 저장 버튼 (피로도 척도 선택 시 활성화)
            Button(action: {
                guard isFormValid else { return }
                saveAction()
            }) {
                Text("저장")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isFormValid ? .white : Config.Colors.mute.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    .background(isFormValid ? Color(hex: Config.Colors.accentHex) : Color.gray.opacity(0.18))
                    .cornerRadius(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .disabled(!isFormValid)
        }
    }

    private func saveAction() {
        var payload = formState.toResponsePayload(type: .diary)

        // 자발적 기록 맥락 정보 직렬화
        if let p = context.localImagePath {
            payload["capture_local_path"] = p
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

        // 어떻게 하면 덜 피곤할까요? 답변
        let trimmedReduce = howToReduceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReduce.isEmpty {
            payload["how_to_reduce_fatigue"] = trimmedReduce
            if trimmedReduce.hasPrefix("AI가") {
                payload["reduction_starter"] = "AI"
            } else if trimmedReduce.hasPrefix("내가") {
                payload["reduction_starter"] = "self"
            }
        }

        onSave(context, payload)
    }
}
