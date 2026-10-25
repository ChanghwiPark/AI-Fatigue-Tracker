import SwiftUI
import Speech
import AVFoundation

// MARK: - 1. 공통 헤더 컴포넌트
/// 설문 창 최상단 헤더: 아이콘 배지와 16.5pt 강조 타이포그래피, AI 도구명 시각적 하이라이트로 내부 문항과 확실히 구분
public struct SurveyHeaderView: View {
    public let title: String
    public let toolName: String?
    public let surveyType: SurveyType?

    public init(title: String, toolName: String? = nil, surveyType: SurveyType? = nil) {
        self.title = title
        self.toolName = toolName
        self.surveyType = surveyType
    }

    private var headerIcon: String {
        switch surveyType {
        case .start: return "play.circle.fill"
        case .mid: return "pause.circle.fill"
        case .end: return "checkmark.circle.fill"
        case .diary: return "square.and.pencil"
        case .nudge: return "bell.badge.fill"
        case .none: return "play.circle.fill"
        }
    }

    private var iconColor: Color {
        // 모든 상황별 팝업의 헤더 아이콘 배지 색상을 일관된 주황 테마로 통일
        return Color(hex: Config.Colors.accentHex)
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 헤더 아이콘 배지 (서베이 팝업 타이틀임을 명확히 인지하도록 구분)
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: headerIcon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(iconColor)
            }

            // 타이틀 텍스트 (문항 텍스트와 뚜렷이 대비되는 16.5pt 크기 및 AI 도구명 강조)
            titleTextView
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .contentShape(Rectangle())
        .overlay(WindowDragArea())
    }

    @ViewBuilder
    private var titleTextView: some View {
        if let tool = toolName, !tool.isEmpty, title.contains(tool) {
            let parts = title.components(separatedBy: tool)
            let prefix = parts.first ?? ""
            let suffix = parts.count > 1 ? parts[1] : ""

            (Text(prefix)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Config.Colors.ink)
            + Text(tool)
                .font(.system(size: 16.5, weight: .heavy))
                .foregroundColor(Color(hex: Config.Colors.accentHex))
            + Text(suffix)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Config.Colors.ink))
        } else {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Config.Colors.ink)
        }
    }
}

// MARK: - 2. 피로 척도 컴포넌트
/// 라벨 "AI로 인한 피로", 0~10 버튼, 양끝 "0 전혀 없음" / "10 매우 심함". 고르면 주황색.
public struct FatigueScaleView: View {
    @Binding public var score: Int?

    public init(score: Binding<Int?>) {
        self._score = score
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI로 인한 피로")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(Config.Colors.ink)

            // 0 ~ 10 버튼 (11개)
            HStack(spacing: 3) {
                ForEach(0...10, id: \.self) { val in
                    let isSelected = (score == val)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            score = val
                        }
                    }) {
                        Text("\(val)")
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : Config.Colors.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isSelected ? Color(hex: Config.Colors.accentHex) : Config.Colors.paper)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(isSelected ? Color.clear : Config.Colors.line, lineWidth: 0.8)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // 양끝 라벨
            HStack {
                Text("0 전혀 없음")
                    .font(.system(size: 10))
                    .foregroundColor(Config.Colors.mute)
                Spacer()
                Text("10 매우 심함")
                    .font(.system(size: 10))
                    .foregroundColor(Config.Colors.mute)
            }
        }
    }
}

// MARK: - 3. 유용성 척도 컴포넌트
/// 라벨 "AI가 도움이 된다고 느끼는 정도", 1~5 버튼, 양끝 "1 전혀 유용하지 않음" / "5 매우 유용함". 고르면 초록색(#5D7A63).
public struct UsefulnessScaleView: View {
    @Binding public var score: Int?

    public init(score: Binding<Int?>) {
        self._score = score
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI가 도움이 된다고 느끼는 정도")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(Config.Colors.ink)

            // 1 ~ 5 버튼 (5개)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { val in
                    let isSelected = (score == val)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            score = val
                        }
                    }) {
                        Text("\(val)")
                            .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : Config.Colors.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isSelected ? Color(hex: Config.Colors.sageHex) : Config.Colors.paper)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(isSelected ? Color.clear : Config.Colors.line, lineWidth: 0.8)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // 양끝 라벨
            HStack {
                Text("1 전혀 유용하지 않음")
                    .font(.system(size: 10))
                    .foregroundColor(Config.Colors.mute)
                Spacer()
                Text("5 매우 유용함")
                    .font(.system(size: 10))
                    .foregroundColor(Config.Colors.mute)
            }
        }
    }
}

// MARK: - 4. 주관식 입력칸 + 마이크 음성 입력 + '+ 문장' 칩 컴포넌트
public struct SubjectiveInputFieldView: View {
    public let label: String?
    public let placeholder: String
    public let fieldKey: String
    public let chipOptions: [String]
    public let isSingleLine: Bool
    public let isDisabled: Bool
    public var onFocusChanged: ((Bool) -> Void)? = nil

    @Binding public var answer: SubjectiveAnswer
    @ObservedObject private var speechManager = SpeechInputManager.shared
    @FocusState private var isFocused: Bool
    @State private var blinkState: Bool = false

    public init(
        label: String? = nil,
        placeholder: String = "직접 입력하거나 음성으로 말해보세요...",
        fieldKey: String,
        chipOptions: [String],
        isSingleLine: Bool = true,
        isDisabled: Bool = false,
        onFocusChanged: ((Bool) -> Void)? = nil,
        answer: Binding<SubjectiveAnswer>
    ) {
        self.label = label
        self.placeholder = placeholder
        self.fieldKey = fieldKey
        self.chipOptions = chipOptions
        self.isSingleLine = isSingleLine
        self.isDisabled = isDisabled
        self.onFocusChanged = onFocusChanged
        self._answer = answer
    }

    private var isRecordingThisField: Bool {
        speechManager.isRecording && speechManager.activeFieldKey == fieldKey
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lbl = label, !lbl.isEmpty {
                Text(lbl)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Config.Colors.ink)
            }

            // 텍스트 필드 + 마이크 버튼 (긴 문장 및 복수 칩 선택 시 잘림 없이 볼 수 있도록 자동 세로 줄바꿈 지원)
            HStack(alignment: .top, spacing: 6) {
                TextField(placeholder, text: $answer.customText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1...5)
                    .padding(.vertical, 3)
                    .focused($isFocused)
                    .onChange(of: isFocused) { _, focused in
                        onFocusChanged?(focused)
                    }
                    .disabled(isDisabled)

                // 선으로 그린 마이크 아이콘 버튼 (이모티콘 금지)
                Button(action: {
                    toggleSpeech()
                }) {
                    ZStack {
                        Circle()
                            .fill(isRecordingThisField ? Color(hex: Config.Colors.accentHex) : Color.clear)
                            .frame(width: 24, height: 24)

                        Image(systemName: isRecordingThisField ? "mic.fill" : "mic")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(isRecordingThisField ? .white : Config.Colors.mute)
                    }
                    .opacity(isRecordingThisField ? (blinkState ? 0.35 : 1.0) : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .padding(.top, 1)
                .help("클릭하여 한국어 음성으로 입력")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Config.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecordingThisField ? Color(hex: Config.Colors.accentHex) : Config.Colors.line, lineWidth: isRecordingThisField ? 1.4 : 0.8)
                    )
            )
            .opacity(isDisabled ? 0.45 : 1.0)

            // 음성 인식 중 안내 문구
            if isRecordingThisField {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: Config.Colors.accentHex))
                        .frame(width: 6, height: 6)
                    Text("음성을 듣고 있습니다... 말씀이 끝나면 자동으로 완료됩니다.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                }
                .padding(.leading, 2)
                .onAppear {
                    withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        blinkState = true
                    }
                }
                .onDisappear {
                    blinkState = false
                }
            }

            // 아래 '+ 문장' 칩 목록
            if !chipOptions.isEmpty {
                chipListView
                    .opacity(isDisabled ? 0.45 : 1.0)
            }
        }
    }

    private var chipListView: some View {
        FlowLayout(spacing: 5) {
            ForEach(chipOptions, id: \.self) { chip in
                let isSelected = answer.selectedChips.contains(chip)
                Button(action: {
                    guard !isDisabled else { return }
                    toggleChip(chip)
                }) {
                    HStack(spacing: 3) {
                        Text(isSelected ? "✓" : "+")
                            .font(.system(size: 10, weight: .bold))
                        Text(chip)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(isSelected ? Color(hex: Config.Colors.accentHex) : Config.Colors.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected ? Color(hex: Config.Colors.accentHex).opacity(0.12) : Config.Colors.paper)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isSelected ? Color(hex: Config.Colors.accentHex) : Config.Colors.line, lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
    }

    private func toggleChip(_ chip: String) {
        if let idx = answer.selectedChips.firstIndex(of: chip) {
            answer.selectedChips.remove(at: idx)
        } else {
            answer.selectedChips.append(chip)
        }

        // 텍스트 필드 동기화
        if answer.customText.isEmpty {
            answer.customText = chip
        } else if !answer.customText.contains(chip) {
            answer.customText += ", " + chip
        }
    }

    private func toggleSpeech() {
        guard !isDisabled else { return }
        speechManager.toggleRecording(
            fieldKey: fieldKey,
            currentText: answer.customText
        ) { updatedText in
            answer.customText = updatedText
        }
    }
}

// MARK: - 5. NASA-TLX 6개 슬라이더 컴포넌트
public struct TLXSliderSectionView: View {
    @Binding public var tlx: NASA_TLXScores
    public var onModified: (() -> Void)? = nil
    @State private var modifiedFields: Set<String> = []

    public init(tlx: Binding<NASA_TLXScores>, onModified: (() -> Void)? = nil) {
        self._tlx = tlx
        self.onModified = onModified
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("이번 작업은 어땠나요?")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Config.Colors.ink)
            }

            VStack(spacing: 6) {
                tlxSliderRow(key: "mental", label: "정신적 요구", value: $tlx.mentalDemand)
                tlxSliderRow(key: "physical", label: "신체적 요구", value: $tlx.physicalDemand)
                tlxSliderRow(key: "temporal", label: "시간 압박", value: $tlx.temporalDemand)
                tlxSliderRow(key: "performance", label: "성과 만족", value: $tlx.performance)
                tlxSliderRow(key: "effort", label: "노력", value: $tlx.effort)
                tlxSliderRow(key: "frustration", label: "좌절감", value: $tlx.frustration)
            }
            .padding(10)
            .background(Config.Colors.cardBackground)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))
        }
    }

    private func tlxSliderRow(key: String, label: String, value: Binding<Int>) -> some View {
        let isTouched = modifiedFields.contains(key)

        return VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Config.Colors.ink)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(isTouched ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute)
            }

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { newVal in
                        // 0~100 범위, 5 단위로 스냅
                        let stepped = Int(round(newVal / 5.0) * 5.0)
                        value.wrappedValue = max(0, min(100, stepped))
                        modifiedFields.insert(key)
                        onModified?()
                    }
                ),
                in: 0...100,
                step: 5,
                onEditingChanged: { isEditing in
                    if isEditing {
                        modifiedFields.insert(key)
                        onModified?()
                    }
                }
            )
            .controlSize(.mini)
            .tint(Color(hex: Config.Colors.accentHex))
        }
    }
}

// MARK: - 6. [피로 6점 이상일 때] 심층 원인 질문 컴포넌트
/// 같은 카드 안에서 아래로 펼쳐짐.
/// 연한 붉은 배경(#FBE6DD, 테두리 #F2C4B2, 모서리 12px)
public struct DeepFatigueSectionView: View {
    @ObservedObject public var formState: SurveyFormState

    public init(formState: SurveyFormState) {
        self.formState = formState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 헤더 질문
            Text("어떤 점이 피곤하게 느껴졌나요? (선택)")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(Config.Colors.highFatigueTitle)

            // 6개 카테고리 항목
            VStack(spacing: 8) {
                ForEach(FatigueReasonCategory.allCategories) { category in
                    categoryRow(category: category)
                }
            }
        }
        .padding(12)
        .background(Config.Colors.highFatigueBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Config.Colors.highFatigueBorder, lineWidth: 1.0)
        )
    }

    private func categoryRow(category: FatigueReasonCategory) -> some View {
        let isSelected = formState.selectedFatigueCategories.contains(category.id)

        return VStack(alignment: .leading, spacing: 6) {
            // 카테고리 토글 버튼
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
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

            // 선택 시 아래에 "어떤 점에서요? (선택)" 주관식과 칩 열림
            if isSelected {
                VStack(alignment: .leading, spacing: 4) {
                    SubjectiveInputFieldView(
                        label: "어떤 점에서요? (선택)",
                        placeholder: "더 자세한 이유나 상황을 적어주세요.",
                        fieldKey: "fatigue_\(category.id)",
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
                .transition(.opacity)
            }
        }
    }
}

// MARK: - 7. 가변 칩 줄바꿈 레이아웃 (FlowLayout)
public struct FlowLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - 7. [유용성 4점 이상일 때] 후속 질문 컴포넌트
/// 유용성 질문 바로 아래에 펼쳐짐
public struct UsefulnessHelpSectionView: View {
    @ObservedObject public var formState: SurveyFormState

    public init(formState: SurveyFormState) {
        self.formState = formState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("어떤 도움이 된다고 느꼈나요? (선택)")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(Config.Colors.highUsefulnessTitle)

            SubjectiveInputFieldView(
                label: nil,
                placeholder: "어떤 점이 도움이 됐는지 느낀 점을 적어주세요",
                fieldKey: "end_usefulness_help",
                chipOptions: UsefulnessChipOptions.items,
                isSingleLine: true,
                isDisabled: false,
                onFocusChanged: { isFocused in
                    formState.isTextFieldFocused = isFocused
                },
                answer: $formState.endUsefulnessHelp
            )
        }
        .padding(12)
        .background(Config.Colors.highUsefulnessBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Config.Colors.highUsefulnessBorder, lineWidth: 1.0)
        )
    }
}

