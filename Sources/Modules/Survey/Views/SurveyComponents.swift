import SwiftUI
import Speech
import AVFoundation

// MARK: - 0. 공통 섹션 카드 컨테이너 (비주얼 하이어라키 & 그룹핑)
/// 설문 문항들을 테마별로 시각적 그룹핑하여 인지 부하를 줄이고 계층 구조를 명확히 하는 카드 컨테이너
/// - 상단 우측에 단계/제목 인디케이터([1/3 작업 맥락])가 들어가므로, 카드 자체는 중복 제목/번호 없이 본문 콘텐츠만 깔끔하게 노출
public struct SurveySectionCard<Content: View>: View {
    public let badgeNumber: String?
    public let title: String?
    public let isRequired: Bool
    public let content: Content

    public init(
        badgeNumber: String? = nil,
        title: String? = nil,
        isRequired: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.badgeNumber = badgeNumber
        self.title = title
        self.isRequired = isRequired
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: (title != nil && !title!.isEmpty) ? 12 : 0) {
            // 카드 헤더 (명시적으로 타이틀이 지정된 경우에만 노출, 기본은 헤더 생략)
            if let t = title, !t.isEmpty {
                HStack(alignment: .center, spacing: 8) {
                    if let b = badgeNumber, !b.isEmpty {
                        Text(b)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(Color(hex: Config.Colors.accentHex).opacity(0.12))
                            )
                    }

                    Text(t)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    Spacer()

                    Text(isRequired ? "필수" : "선택")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isRequired ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill(isRequired ? Color(hex: Config.Colors.accentHex).opacity(0.12) : Color.gray.opacity(0.12))
                        )
                }
            }

            // 본문 콘텐츠
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Config.Colors.cardBackground)
                .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Config.Colors.line.opacity(0.65), lineWidth: 0.8)
        )
    }
}

// MARK: - 1. 공통 헤더 컴포넌트
/// 설문 창 최상단 헤더: 아이콘 배지와 16.5pt 강조 타이포그래피, AI 도구명 시각적 하이라이트, 우측 단계 인디케이터 배지
public struct SurveyHeaderView: View {
    public let title: String
    public let toolName: String?
    public let surveyType: SurveyType?
    public let currentStep: Int?
    public let totalSteps: Int?
    public let stepTitle: String?
    public let isContinuingDraft: Bool

    public init(
        title: String,
        toolName: String? = nil,
        surveyType: SurveyType? = nil,
        currentStep: Int? = nil,
        totalSteps: Int? = nil,
        stepTitle: String? = nil,
        isContinuingDraft: Bool = false
    ) {
        self.title = title
        self.toolName = toolName
        self.surveyType = surveyType
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.stepTitle = stepTitle
        self.isContinuingDraft = isContinuingDraft
    }

    private var headerIcon: String {
        switch surveyType {
        case .start: return "play.circle.fill"
        case .mid: return "pause.circle.fill"
        case .end: return "checkmark.circle.fill"
        case .diary: return "square.and.pencil"
        case .nudge: return "bell.badge.fill"
        case .followUp: return "clock.arrow.circlepath"
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
                    .offset(y: headerIcon == "square.and.pencil" ? -1.2 : 0)
            }

            // 타이틀 텍스트 (문항 텍스트와 뚜렷이 대비되는 16.5pt 크기 및 AI 도구명 강조)
            titleTextView
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            // 우측 상단 단계 인디케이터 캡슐 배지 (페이징 시 몇 단계인지 명확히 노출, 스누즈 이어서 작성 시 배지 표시)
            if let cur = currentStep, let tot = totalSteps, tot > 1 {
                HStack(spacing: 4) {
                    if isContinuingDraft {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                    }

                    Text("\(cur)/\(tot)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))

                    if let st = stepTitle, !st.isEmpty {
                        Text(st)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(Config.Colors.ink)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(Color(hex: Config.Colors.accentHex).opacity(0.1))
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: Config.Colors.accentHex).opacity(0.25), lineWidth: 0.8)
                        )
                )
            }
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
                .font(.system(size: 16, weight: .heavy))
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

// MARK: - 2-0. 툴팁 화살표 모양 Shape (하위 호환)
public struct TooltipArrowShape: Shape {
    public let pointingUp: Bool

    public init(pointingUp: Bool = true) {
        self.pointingUp = pointingUp
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointingUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - 2-0. 통합 툴팁 방향 및 일체형 말풍선 셰이프 (Unified Seamless Tooltip Bubble Shape)
public enum TooltipArrowDirection: Sendable {
    case up     // 툴팁이 타겟 아래에 위치하여 화살표가 위쪽(▲)을 가리킴
    case down   // 툴팁이 타겟 위에 위치하여 화살표가 아래쪽(▼)을 가리킴
}

public struct TooltipBubbleShape: Shape {
    public var arrowDirection: TooltipArrowDirection
    public var arrowX: CGFloat
    public var cornerRadius: CGFloat = 6
    public var arrowWidth: CGFloat = 10
    public var arrowHeight: CGFloat = 5

    public init(
        arrowDirection: TooltipArrowDirection,
        arrowX: CGFloat,
        cornerRadius: CGFloat = 6,
        arrowWidth: CGFloat = 10,
        arrowHeight: CGFloat = 5
    ) {
        self.arrowDirection = arrowDirection
        self.arrowX = arrowX
        self.cornerRadius = cornerRadius
        self.arrowWidth = arrowWidth
        self.arrowHeight = arrowHeight
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius
        let halfArrow = arrowWidth / 2.0

        if arrowDirection == .up {
            let bodyMinY = rect.minY + arrowHeight
            let bodyMaxY = rect.maxY
            let bodyMinX = rect.minX
            let bodyMaxX = rect.maxX

            let clampedArrowX = min(max(arrowX, bodyMinX + r + halfArrow), bodyMaxX - r - halfArrow)

            path.move(to: CGPoint(x: bodyMinX + r, y: bodyMinY))
            path.addLine(to: CGPoint(x: clampedArrowX - halfArrow, y: bodyMinY))
            path.addLine(to: CGPoint(x: clampedArrowX, y: rect.minY))
            path.addLine(to: CGPoint(x: clampedArrowX + halfArrow, y: bodyMinY))

            path.addArc(
                tangent1End: CGPoint(x: bodyMaxX, y: bodyMinY),
                tangent2End: CGPoint(x: bodyMaxX, y: bodyMaxY),
                radius: r
            )
            path.addArc(
                tangent1End: CGPoint(x: bodyMaxX, y: bodyMaxY),
                tangent2End: CGPoint(x: bodyMinX, y: bodyMaxY),
                radius: r
            )
            path.addArc(
                tangent1End: CGPoint(x: bodyMinX, y: bodyMaxY),
                tangent2End: CGPoint(x: bodyMinX, y: bodyMinY),
                radius: r
            )
            path.addArc(
                tangent1End: CGPoint(x: bodyMinX, y: bodyMinY),
                tangent2End: CGPoint(x: clampedArrowX, y: bodyMinY),
                radius: r
            )
            path.closeSubpath()

        } else {
            let bodyMinY = rect.minY
            let bodyMaxY = rect.maxY - arrowHeight
            let bodyMinX = rect.minX
            let bodyMaxX = rect.maxX

            let clampedArrowX = min(max(arrowX, bodyMinX + r + halfArrow), bodyMaxX - r - halfArrow)

            path.move(to: CGPoint(x: bodyMinX + r, y: bodyMinY))
            path.addArc(
                tangent1End: CGPoint(x: bodyMaxX, y: bodyMinY),
                tangent2End: CGPoint(x: bodyMaxX, y: bodyMaxY),
                radius: r
            )
            path.addArc(
                tangent1End: CGPoint(x: bodyMaxX, y: bodyMaxY),
                tangent2End: CGPoint(x: clampedArrowX, y: bodyMaxY),
                radius: r
            )

            path.addLine(to: CGPoint(x: clampedArrowX + halfArrow, y: bodyMaxY))
            path.addLine(to: CGPoint(x: clampedArrowX, y: rect.maxY))
            path.addLine(to: CGPoint(x: clampedArrowX - halfArrow, y: bodyMaxY))

            path.addArc(
                tangent1End: CGPoint(x: bodyMinX, y: bodyMaxY),
                tangent2End: CGPoint(x: bodyMinX, y: bodyMinY),
                radius: r
            )
            path.addArc(
                tangent1End: CGPoint(x: bodyMinX, y: bodyMinY),
                tangent2End: CGPoint(x: bodyMaxX, y: bodyMinY),
                radius: r
            )
            path.closeSubpath()
        }

        return path
    }
}

// MARK: - 2-0. 앱 전역 통일 툴팁 말풍선 컴포넌트 (Unified Tooltip View)
public struct UnifiedTooltipView: View {
    public let text: String
    public var arrowDirection: TooltipArrowDirection = .down
    public var arrowX: CGFloat = 20
    public var width: CGFloat? = nil
    public var textAlignment: TextAlignment = .center

    public init(
        text: String,
        arrowDirection: TooltipArrowDirection = .down,
        arrowX: CGFloat = 20,
        width: CGFloat? = nil,
        textAlignment: TextAlignment = .center
    ) {
        self.text = text
        self.arrowDirection = arrowDirection
        self.arrowX = arrowX
        self.width = width
        self.textAlignment = textAlignment
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(3)
            .multilineTextAlignment(textAlignment)
            .fixedSize(horizontal: width == nil, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .padding(.top, arrowDirection == .up ? 5.5 : 0)
            .padding(.bottom, arrowDirection == .down ? 5.5 : 0)
            .frame(width: width)
            .background(
                TooltipBubbleShape(
                    arrowDirection: arrowDirection,
                    arrowX: arrowX,
                    cornerRadius: 6,
                    arrowWidth: 10,
                    arrowHeight: 5
                )
                .fill(Color(hex: "#1E1E22"))
            )
            .overlay(
                TooltipBubbleShape(
                    arrowDirection: arrowDirection,
                    arrowX: arrowX,
                    cornerRadius: 6,
                    arrowWidth: 10,
                    arrowHeight: 5
                )
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: arrowDirection == .up ? 2.5 : -2)
    }
}

// MARK: - 2-0. 리커트 척도 호버 말풍선 툴팁 뷰 (통일 툴팁 적용)
public struct LikertScaleTooltipView: View {
    public let text: String
    public let targetIndex: Int
    public let totalCount: Int
    public let containerWidth: CGFloat
    public var arrowDirection: TooltipArrowDirection = .up

    private let tooltipWidth: CGFloat = 210

    public init(
        text: String,
        targetIndex: Int,
        totalCount: Int,
        containerWidth: CGFloat,
        arrowDirection: TooltipArrowDirection = .up
    ) {
        self.text = text
        self.targetIndex = targetIndex
        self.totalCount = totalCount
        self.containerWidth = containerWidth
        self.arrowDirection = arrowDirection
    }

    public var body: some View {
        let buttonWidth = (containerWidth - CGFloat(max(1, totalCount - 1)) * 5.0) / CGFloat(max(1, totalCount))
        let buttonCenterX = CGFloat(targetIndex) * (buttonWidth + 5.0) + (buttonWidth / 2.0)

        // 툴팁 박스가 컨테이너 좌우(0 ~ containerWidth)를 벗어나지 않도록 clamp
        let idealLeft = buttonCenterX - (tooltipWidth / 2.0)
        let minLeft: CGFloat = 0
        let maxLeft: CGFloat = max(0, containerWidth - tooltipWidth)
        let boxLeft = min(max(idealLeft, minLeft), maxLeft)

        // 화살표가 툴팁 박스 모서리(cornerRadius)를 벗어나지 않고 버튼 중심을 가리키도록 clamp
        let rawArrowX = buttonCenterX - boxLeft
        let arrowX = min(max(rawArrowX, 16), tooltipWidth - 16)

        UnifiedTooltipView(
            text: text,
            arrowDirection: arrowDirection,
            arrowX: arrowX,
            width: tooltipWidth,
            textAlignment: .center
        )
        .offset(x: boxLeft)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: boxLeft)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: arrowX)
        .allowsHitTesting(false)
    }
}

private struct LikertScaleWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 308
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 1-2. 후속 질문 L자 / T자 트리 분기 브랜치 셰이프 (│ └── / │ ├──)
public struct TreeBranchConnectorShape: Shape {
    public var cornerRadius: CGFloat
    public var isThrough: Bool

    public init(cornerRadius: CGFloat = 4, isThrough: Bool = false) {
        self.cornerRadius = cornerRadius
        self.isThrough = isThrough
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let startX = rect.minX + 3
        let startY = rect.minY
        let cornerY = rect.maxY - 2
        let endX = rect.maxX

        if isThrough {
            // T자 분기선 (├──): 상단에서 하단까지 수직으로 통과
            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(x: startX, y: rect.maxY))

            // 우측으로 분기 (↳ 방향)
            path.move(to: CGPoint(x: startX, y: max(startY, cornerY - cornerRadius)))
            path.addQuadCurve(
                to: CGPoint(x: startX + cornerRadius, y: cornerY),
                control: CGPoint(x: startX, y: cornerY)
            )
            path.addLine(to: CGPoint(x: endX, y: cornerY))
        } else {
            // L자 분기선 (└──): 상단에서 내려와 우측으로 꺾임
            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(x: startX, y: max(startY, cornerY - cornerRadius)))
            path.addQuadCurve(
                to: CGPoint(x: startX + cornerRadius, y: cornerY),
                control: CGPoint(x: startX, y: cornerY)
            )
            path.addLine(to: CGPoint(x: endX, y: cornerY))
        }
        return path
    }
}

// MARK: - 2. 리커트 5점 척도 컴포넌트 (라벨 선택 및 호버 말풍선 툴팁)
/// 질문 문구, 5개 라벨 버튼(전혀/약간/어느정도/많이/매우), 마우스 호버 시 즉각 뜨는 말풍선 툴팁
public struct LikertScaleView: View {
    public let title: String
    public let options: [LikertScaleOption]
    @Binding public var selectedValue: Int?
    public var previewHoveredValue: Int? = nil
    public var isFollowUp: Bool = false
    public var hasFollowUpBelow: Bool = false
    public var showArrowPrefix: Bool = false
    public var isInsideCard: Bool = false

    @State private var hoveredValue: Int? = nil
    @State private var containerWidth: CGFloat = 308

    public init(
        title: String,
        options: [LikertScaleOption],
        selectedValue: Binding<Int?>,
        previewHoveredValue: Int? = nil,
        isFollowUp: Bool = false,
        hasFollowUpBelow: Bool = false,
        showArrowPrefix: Bool = false,
        isInsideCard: Bool = false
    ) {
        self.title = title
        self.options = options
        self._selectedValue = selectedValue
        self.previewHoveredValue = previewHoveredValue
        self.isFollowUp = isFollowUp
        self.hasFollowUpBelow = hasFollowUpBelow
        self.showArrowPrefix = showArrowPrefix
        self.isInsideCard = isInsideCard
    }

    private var effectiveHoveredValue: Int? {
        hoveredValue ?? previewHoveredValue
    }

    private var activeHoveredOption: LikertScaleOption? {
        if let h = effectiveHoveredValue, let opt = options.first(where: { $0.value == h }) {
            return opt
        }
        return nil
    }

    private var activeHoveredIndex: Int? {
        if let h = effectiveHoveredValue {
            return options.firstIndex(where: { $0.value == h })
        }
        return nil
    }

    public var body: some View {
        if isFollowUp {
            HStack(alignment: .top, spacing: 6) {
                // 후속 질문 분기선 컬럼 (L자 또는 T자)
                VStack(spacing: 0) {
                    TreeBranchConnectorShape(isThrough: hasFollowUpBelow)
                        .stroke(Config.Colors.mute.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 22)
                        .padding(.top, -6)

                    if hasFollowUpBelow {
                        Rectangle()
                            .fill(Config.Colors.mute.opacity(0.6))
                            .frame(width: 1.5)
                            .padding(.leading, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 12)
                .padding(.leading, 8)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4.5) {
                        Text("↳")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Config.Colors.ink)
                    }

                    buttonsAndTooltipView
                }
            }
        } else {
            VStack(alignment: .leading, spacing: isInsideCard ? 8 : 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4.5) {
                    if showArrowPrefix {
                        Text("↳")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                    }
                    Text(title)
                        .font(.system(size: isInsideCard ? 12 : 14, weight: isInsideCard ? .medium : .bold))
                        .foregroundColor(Config.Colors.ink)
                }

                buttonsAndTooltipView
            }
        }
    }

    private var buttonsAndTooltipView: some View {
        HStack(spacing: 5) {
            ForEach(options) { option in
                let isSelected = (selectedValue == option.value)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if selectedValue == option.value {
                            selectedValue = nil
                        } else {
                            selectedValue = option.value
                        }
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(isSelected ? .white : Config.Colors.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color(hex: Config.Colors.accentHex) : (isInsideCard ? Config.Colors.popupBg : Config.Colors.cardBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color(hex: Config.Colors.accentHex) : Config.Colors.line, lineWidth: isSelected ? 1.2 : 0.8)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    withAnimation(.easeOut(duration: 0.16)) {
                        if isHovered {
                            hoveredValue = option.value
                        } else if hoveredValue == option.value {
                            hoveredValue = nil
                        }
                    }
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: LikertScaleWidthPreferenceKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(LikertScaleWidthPreferenceKey.self) { newWidth in
            if newWidth > 0 && abs(self.containerWidth - newWidth) > 1.0 {
                self.containerWidth = newWidth
            }
        }
        .overlay(alignment: .topLeading) {
            // 호버 시 말풍선 툴팁: 버튼 위로 플로팅하며 하향 화살표(▼)로 호버된 버튼을 가리킴
            if let opt = activeHoveredOption, let index = activeHoveredIndex {
                ZStack(alignment: .bottomLeading) {
                    LikertScaleTooltipView(
                        text: opt.description,
                        targetIndex: index,
                        totalCount: options.count,
                        containerWidth: containerWidth,
                        arrowDirection: .down
                    )
                }
                .frame(width: containerWidth, height: 0, alignment: .bottomLeading)
                .offset(y: -4)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 2)),
                    removal: .opacity
                ))
                .allowsHitTesting(false)
                .zIndex(100)
            }
        }
        .zIndex(activeHoveredOption != nil ? 100 : 1)
    }
}

// MARK: - 2-1. 피로도 척도 컴포넌트 (하위 호환 래퍼)
public struct FatigueScaleView: View {
    @Binding public var score: Int?
    public var previewHoveredValue: Int? = nil

    public init(score: Binding<Int?>, previewHoveredValue: Int? = nil) {
        self._score = score
        self.previewHoveredValue = previewHoveredValue
    }

    public var body: some View {
        LikertScaleView(
            title: "지금 얼마나 피로한가요?",
            options: SurveyScaleDefinitions.fatigueScale,
            selectedValue: $score,
            previewHoveredValue: previewHoveredValue
        )
    }
}

// MARK: - 2-2. AI 피로 영향 후속 질문 컴포넌트 ("AI가 피로에 영향이 있었나요?")
public struct AIFatigueImpactFollowUpView: View {
    @Binding public var score: Int?
    public var previewHoveredValue: Int? = nil
    public var hasFollowUpBelow: Bool = false

    public init(
        score: Binding<Int?>,
        previewHoveredValue: Int? = nil,
        hasFollowUpBelow: Bool = false
    ) {
        self._score = score
        self.previewHoveredValue = previewHoveredValue
        self.hasFollowUpBelow = hasFollowUpBelow
    }

    public var body: some View {
        LikertScaleView(
            title: "지금 피로에 AI가 얼마나 영향을 주었나요?",
            options: SurveyScaleDefinitions.aiImpactScale,
            selectedValue: $score,
            previewHoveredValue: previewHoveredValue,
            isFollowUp: true,
            hasFollowUpBelow: hasFollowUpBelow
        )
    }
}

// MARK: - 2-3. AI 피로 후속 질문 통합 서브 카드 컨테이너 (유용성과 대칭을 이루는 주관식 + 칩 구조)
public struct AIFatigueFollowUpCardView: View {
    @ObservedObject public var formState: SurveyFormState
    public var previewHoveredValue: Int? = nil

    public init(formState: SurveyFormState, previewHoveredValue: Int? = nil) {
        self.formState = formState
        self.previewHoveredValue = previewHoveredValue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1층 (Q2): ↳ AI가 피로에 영향이 있었나요? (5점 척도)
            LikertScaleView(
                title: "AI가 피로에 영향이 있었나요?",
                options: SurveyScaleDefinitions.aiImpactScale,
                selectedValue: $formState.aiFatigueImpactScore,
                previewHoveredValue: previewHoveredValue,
                isFollowUp: false,
                showArrowPrefix: true,
                isInsideCard: true
            )

            // 2층 (Q3): AI 영향 2점 이상일 때 - 유용성 후속 질문과 동일한 주관식 입력창 + 추천 칩
            if formState.isFatigueTypeVisible {
                Divider()
                    .background(Config.Colors.line.opacity(0.4))

                SubjectiveInputFieldView(
                    label: nil,
                    placeholder: "피로하다고 느낀 점 (선택)",
                    fieldKey: "fatigue_reason",
                    chipOptions: FatigueReasonChipOptions.items,
                    isSingleLine: true,
                    isDisabled: false,
                    isInsideCard: true,
                    onFocusChanged: { isFocused in
                        formState.isTextFieldFocused = isFocused
                    },
                    answer: $formState.fatigueReasonAnswer
                )
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Config.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Config.Colors.line.opacity(0.35), lineWidth: 0.6)
                )
        )
    }
}

// MARK: - 3. 유용성 척도 컴포넌트 (하위 호환 래퍼)
public struct UsefulnessScaleView: View {
    @Binding public var score: Int?
    public var title: String = "AI가 얼마나 도움이 되고 있나요?"
    public var previewHoveredValue: Int? = nil

    public init(
        score: Binding<Int?>,
        title: String = "AI가 얼마나 도움이 되고 있나요?",
        previewHoveredValue: Int? = nil
    ) {
        self._score = score
        self.title = title
        self.previewHoveredValue = previewHoveredValue
    }

    public var body: some View {
        LikertScaleView(
            title: title,
            options: SurveyScaleDefinitions.usefulnessScale,
            selectedValue: $score,
            previewHoveredValue: previewHoveredValue
        )
    }
}

// MARK: - 3-2. 참고 화면 캡처 첨부파일형 컴포넌트 (시작, 중간, 종료, 자발적 기록 공통)
public struct ScreenCaptureCardView: View {
    @Binding public var imagePath: String?
    public var appName: String
    public var previewHovered: Bool = false
    public var onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))? = nil

    @State private var isHovered: Bool = false

    public init(
        imagePath: Binding<String?>,
        appName: String = "AI 작업 화면",
        previewHovered: Bool = false,
        onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))? = nil
    ) {
        self._imagePath = imagePath
        self.appName = appName
        self.previewHovered = previewHovered
        self.onRetakeAreaCapture = onRetakeAreaCapture
    }

    private var effectiveHovered: Bool {
        isHovered || previewHovered
    }

    public var body: some View {
        if let path = imagePath,
           !path.isEmpty,
           let image = NSImage(contentsOfFile: path) {
            // 캡처 첨부 완료 상태: 미니 썸네일 + 캡처 완료 안내 + 재캡처 아이콘 + 삭제 아이콘 버튼
            HStack(spacing: 8) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 24)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Config.Colors.line, lineWidth: 0.8))
                    .clipped()

                // 재캡처 아이콘 버튼 (문구 없이 아이콘만 표시)
                Button(action: {
                    onRetakeAreaCapture? { newPath in
                        if let newPath = newPath {
                            self.imagePath = newPath
                        }
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Config.Colors.ink)
                        .frame(width: 22, height: 22)
                        .background(Config.Colors.paper)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Config.Colors.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("다시 캡처")

                // 삭제 버튼 (X)
                Button(action: {
                    self.imagePath = nil
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Config.Colors.mute)
                        .frame(width: 22, height: 22)
                        .background(Config.Colors.paper)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Config.Colors.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("첨부된 캡처 삭제")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(Config.Colors.cardBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Config.Colors.line, lineWidth: 0.8)
            )
        } else {
            // 미첨부 상태: 컴팩트한 첨부파일 버튼 바 형태 (회색 (선택) 표시 및 호버 시 즉각 안내 말풍선 툴팁 노출)
            Button(action: {
                if #available(macOS 11.0, *), !CGPreflightScreenCaptureAccess() {
                    PermissionsManager.shared.requestScreenCapture()
                }
                onRetakeAreaCapture? { newPath in
                    if let newPath = newPath {
                        self.imagePath = newPath
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Config.Colors.ink)
                        .frame(width: 14, height: 14, alignment: .center)

                    Text("화면 캡처")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Config.Colors.ink)

                    Text("(선택)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Config.Colors.mute)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(effectiveHovered ? Config.Colors.paper.opacity(0.6) : Config.Colors.cardBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(effectiveHovered ? Config.Colors.mute.opacity(0.8) : Config.Colors.line, style: StrokeStyle(lineWidth: 0.8, dash: [3]))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.16)) {
                    isHovered = hovering
                }
            }
            .help("작업 창이나 AI 답변이 있으면 상황이 더 잘 전해져요")
            .overlay(alignment: .topLeading) {
                if effectiveHovered {
                    UnifiedTooltipView(
                        text: "작업 창이나 AI 답변이 있으면 상황이 더 잘 전해져요",
                        arrowDirection: .down,
                        arrowX: 24
                    )
                    .frame(height: 0, alignment: .bottomLeading)
                    .offset(y: -4)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 2)),
                        removal: .opacity
                    ))
                    .allowsHitTesting(false)
                    .zIndex(100)
                }
            }
            .zIndex(100)
        }
    }
}

// MARK: - 3-3. 상황 질문 전용 주관식-캡처 대체 일체형 섹션 컴포넌트 (안 1. 인라인 통합형)
public struct SituationInputOrCaptureSectionView: View {
    public var title: String
    public var placeholder: String
    @Binding public var situationAnswer: SubjectiveAnswer
    @Binding public var capturedImagePath: String?
    public var appName: String
    public var fieldKey: String
    public var onFocusChanged: ((Bool) -> Void)? = nil
    public var onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))? = nil

    @State private var isShowingAdditionalNote: Bool = false
    @State private var isCaptureHovered: Bool = false
    @ObservedObject private var speechManager = SpeechInputManager.shared
    @FocusState private var isFocused: Bool
    @State private var blinkState: Bool = false
    @State private var lastAttemptedThisField: Bool = false

    public init(
        title: String = "어떤 작업을 하고 있나요?",
        placeholder: String = "예: 관련 문헌 찾기, 논문 인트로 다듬기, 실험 데이터 분석",
        situationAnswer: Binding<SubjectiveAnswer>,
        capturedImagePath: Binding<String?>,
        appName: String = "AI 작업 화면",
        fieldKey: String = "task_purpose",
        onFocusChanged: ((Bool) -> Void)? = nil,
        onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._situationAnswer = situationAnswer
        self._capturedImagePath = capturedImagePath
        self.appName = appName
        self.fieldKey = fieldKey
        self.onFocusChanged = onFocusChanged
        self.onRetakeAreaCapture = onRetakeAreaCapture
    }

    private var hasCapture: Bool {
        if let p = capturedImagePath, !p.isEmpty {
            return true
        }
        return false
    }

    private var hasText: Bool {
        !situationAnswer.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isRecordingThisField: Bool {
        speechManager.isRecording && speechManager.activeFieldKey == fieldKey
    }

    private func toggleSpeech() {
        lastAttemptedThisField = true
        speechManager.toggleRecording(
            fieldKey: fieldKey,
            currentText: situationAnswer.customText
        ) { updatedText in
            situationAnswer.customText = updatedText
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 상단 헤더: 질문 타이틀만 깔끔하게 노출 ((필수) 표시 및 택 1 사족 텍스트 완전 배제)
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                Spacer()
            }

            if hasCapture, let path = capturedImagePath, let image = NSImage(contentsOfFile: path) {
                // 1) 캡처 첨부 완료 상태: 주관식 텍스트 필드를 완전히 대체하는 완료 카드 (미니멀 "✓")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 46, height: 32)
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: Config.Colors.accentHex).opacity(0.35), lineWidth: 0.8))
                            .clipped()

                        HStack(spacing: 4) {
                            Text("✓")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: Config.Colors.accentHex))
                        }

                        Spacer()

                        // 재캡처 및 삭제 아이콘 버튼 그룹 (간격 5pt로 축소)
                        HStack(spacing: 5) {
                            // 재캡처 버튼 (다시 아이콘)
                            Button(action: {
                                onRetakeAreaCapture? { newPath in
                                    if let newPath = newPath {
                                        self.capturedImagePath = newPath
                                    }
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(Config.Colors.ink)
                                    .frame(width: 24, height: 24)
                                    .background(Config.Colors.paper)
                                    .cornerRadius(5)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Config.Colors.line, lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                            .help("화면 다시 캡처")

                            // 삭제 버튼 (X)
                            Button(action: {
                                self.capturedImagePath = nil
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(Config.Colors.mute)
                                    .frame(width: 24, height: 24)
                                    .background(Config.Colors.paper)
                                    .cornerRadius(5)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Config.Colors.line, lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                            .help("캡처 삭제하고 글로 작성하기")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: Config.Colors.accentHex).opacity(0.06))
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(hex: Config.Colors.accentHex).opacity(0.25), lineWidth: 0.8))

                    // 보조 메모 옵션 (원할 경우 덧붙이기 가능)
                    if isShowingAdditionalNote || hasText {
                        HStack(spacing: 6) {
                            TextField("추가 메모나 코멘트 (선택)", text: Binding(
                                get: { situationAnswer.customText },
                                set: { situationAnswer = SubjectiveAnswer(customText: $0) }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundColor(Config.Colors.ink)

                            if !situationAnswer.customText.isEmpty {
                                Button {
                                    situationAnswer = SubjectiveAnswer(customText: "")
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Config.Colors.mute)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Config.Colors.paper)
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Config.Colors.line, lineWidth: 0.8))
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isShowingAdditionalNote = true
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("추가 메모 적기 (선택)")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundColor(Config.Colors.mute)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 2)
                        .padding(.top, 1)
                    }
                }
            } else {
                // 2) 캡처 미첨부 상태: 안 1. 인라인 원터치 캡처 통합형 바
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        TextField(placeholder, text: $situationAnswer.customText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .lineLimit(1...4)
                            .focused($isFocused)
                            .onChange(of: isFocused) { _, focused in
                                onFocusChanged?(focused)
                            }
                            .padding(.vertical, 2)

                        // 캡처 원터치 버튼 (주황색 테두리, fill 없음, 호버 시 툴팁 표시)
                        Button(action: {
                            if #available(macOS 11.0, *), !CGPreflightScreenCaptureAccess() {
                                PermissionsManager.shared.requestScreenCapture()
                            }
                            onRetakeAreaCapture? { newPath in
                                if let newPath = newPath {
                                    self.capturedImagePath = newPath
                                }
                            }
                        }) {
                            HStack(spacing: 3.5) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 10))
                                Text("캡처")
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                isCaptureHovered ? Color(hex: Config.Colors.accentHex).opacity(0.08) : Color.clear
                            )
                            .cornerRadius(4.5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4.5)
                                    .stroke(
                                        Color(hex: Config.Colors.accentHex).opacity(isCaptureHovered ? 0.9 : 0.6),
                                        lineWidth: 0.85
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.16)) {
                                isCaptureHovered = hovering
                            }
                        }
                        .help("작업 창이나 AI 답변을 남기면 상황이 더 잘 전해져요.")
                        .overlay(alignment: .topTrailing) {
                            if isCaptureHovered {
                                UnifiedTooltipView(
                                    text: "작업 창이나 AI 답변을 남기면 상황이 더 잘 전해져요.",
                                    arrowDirection: .down,
                                    arrowX: 30
                                )
                                .frame(height: 0, alignment: .bottomTrailing)
                                .offset(x: 10, y: -6)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                                .zIndex(100)
                            }
                        }

                        // 마이크 음성 입력 버튼
                        Button(action: {
                            toggleSpeech()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(isRecordingThisField ? Color(hex: Config.Colors.accentHex) : Color.clear)
                                    .frame(width: 22, height: 22)

                                Image(systemName: isRecordingThisField ? "mic.fill" : "mic")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(isRecordingThisField ? .white : Config.Colors.mute)
                            }
                            .opacity(isRecordingThisField ? (blinkState ? 0.35 : 1.0) : 1.0)
                        }
                        .buttonStyle(.plain)
                        .help("클릭하여 한국어 음성으로 입력")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Config.Colors.cardBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isRecordingThisField ? Color(hex: Config.Colors.accentHex) : (isFocused ? Color(hex: Config.Colors.accentHex).opacity(0.7) : Config.Colors.line),
                                lineWidth: (isRecordingThisField || isFocused) ? 1.2 : 0.8
                            )
                    )

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

                    // 음성 인식 에러 발생 시 안내 문구
                    if let err = speechManager.errorMessage, lastAttemptedThisField && !isRecordingThisField {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 10.5))
                            Text(err)
                                .font(.system(size: 10.5))
                        }
                        .foregroundColor(Color(hex: "#D9534F"))
                        .padding(.leading, 2)
                    }
                }
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
    public var isInsideCard: Bool = false
    public var onFocusChanged: ((Bool) -> Void)? = nil

    @Binding public var answer: SubjectiveAnswer
    @ObservedObject private var speechManager = SpeechInputManager.shared
    @FocusState private var isFocused: Bool
    @State private var blinkState: Bool = false
    @State private var lastAttemptedThisField: Bool = false

    public init(
        label: String? = nil,
        placeholder: String = "직접 입력하거나 음성으로 말해보세요...",
        fieldKey: String,
        chipOptions: [String],
        isSingleLine: Bool = true,
        isDisabled: Bool = false,
        isInsideCard: Bool = false,
        onFocusChanged: ((Bool) -> Void)? = nil,
        answer: Binding<SubjectiveAnswer>
    ) {
        self.label = label
        self.placeholder = placeholder
        self.fieldKey = fieldKey
        self.chipOptions = chipOptions
        self.isSingleLine = isSingleLine
        self.isDisabled = isDisabled
        self.isInsideCard = isInsideCard
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
                    .fill(isInsideCard ? Config.Colors.popupBg : Config.Colors.cardBackground)
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

            // 음성 인식 에러 발생 시 안내 문구
            if let err = speechManager.errorMessage, lastAttemptedThisField && !isRecordingThisField {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10.5))
                    Text(err)
                        .font(.system(size: 10.5))
                }
                .foregroundColor(Color(hex: "#D9534F"))
                .padding(.leading, 2)
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
        lastAttemptedThisField = true
        speechManager.toggleRecording(
            fieldKey: fieldKey,
            currentText: answer.customText
        ) { updatedText in
            answer.customText = updatedText
        }
    }
}

// MARK: - 5. NASA-TLX 6개 슬라이더 컴포넌트 (방안 1: 양끝 마이크로 앵커 + ⓘ 상세 툴팁)
public struct TLXSliderSectionView: View {
    @Binding public var tlx: NASA_TLXScores
    public var onModified: (() -> Void)? = nil
    @State private var modifiedFields: Set<String> = []
    @State private var hoveredFieldKey: String? = nil

    public init(tlx: Binding<NASA_TLXScores>, onModified: (() -> Void)? = nil) {
        self._tlx = tlx
        self.onModified = onModified
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("지금까지의 작업을 돌아보며 평가해 주세요.")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                Text("[100점 척도: NASA-TLX]")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Config.Colors.mute)
            }
            .padding(.top, 2)

            VStack(spacing: 12) {
                tlxSliderRow(
                    key: "mental",
                    label: "정신적 부담",
                    tooltip: "머리를 얼마나 많이 써야 했나요?",
                    minLabel: "0 (매우 낮음)",
                    maxLabel: "100 (매우 높음)",
                    value: $tlx.mentalDemand
                )

                tlxSliderRow(
                    key: "physical",
                    label: "신체적 부담",
                    tooltip: "몸이 얼마나 힘들었나요?",
                    minLabel: "0 (매우 낮음)",
                    maxLabel: "100 (매우 높음)",
                    value: $tlx.physicalDemand
                )

                tlxSliderRow(
                    key: "temporal",
                    label: "시간 압박",
                    tooltip: "얼마나 시간에 쫓기며 작업했나요?",
                    minLabel: "0 (매우 낮음)",
                    maxLabel: "100 (매우 높음)",
                    value: $tlx.temporalDemand
                )

                tlxSliderRow(
                    key: "performance",
                    label: "결과 만족도",
                    tooltip: "하려던 일을 얼마나 잘 해냈나요?",
                    minLabel: "0 (매우 좋음)",
                    maxLabel: "100 (매우 나쁨)",
                    value: $tlx.performance
                )

                tlxSliderRow(
                    key: "effort",
                    label: "노력",
                    tooltip: "지금 결과를 내기까지 얼마나 애써야 했나요?",
                    minLabel: "0 (매우 낮음)",
                    maxLabel: "100 (매우 높음)",
                    value: $tlx.effort
                )

                tlxSliderRow(
                    key: "frustration",
                    label: "좌절감",
                    tooltip: "얼마나 불안하거나, 짜증 나거나, 스트레스를 받았나요?",
                    minLabel: "0 (매우 낮음)",
                    maxLabel: "100 (매우 높음)",
                    value: $tlx.frustration
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Config.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Config.Colors.line.opacity(0.4), lineWidth: 0.6)
                    )
            )
        }
    }

    private func tlxSliderRow(
        key: String,
        label: String,
        tooltip: String,
        minLabel: String,
        maxLabel: String,
        value: Binding<Int>
    ) -> some View {
        let isTouched = modifiedFields.contains(key)
        let isHovered = (hoveredFieldKey == key)

        return VStack(spacing: 3) {
            // 항목 라벨 + ⓘ 툴팁 아이콘 + 현재 점수
            HStack(alignment: .center, spacing: 4) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Config.Colors.ink)

                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundColor(isHovered ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute.opacity(0.8))
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        if hovering {
                            hoveredFieldKey = key
                        } else if hoveredFieldKey == key {
                            hoveredFieldKey = nil
                        }
                    }
                }
                .help(tooltip)
                .overlay(alignment: .topLeading) {
                    if isHovered {
                        UnifiedTooltipView(
                            text: tooltip,
                            arrowDirection: .down,
                            arrowX: 24
                        )
                        .frame(height: 0, alignment: .bottomLeading)
                        .offset(x: 10, y: -6)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .zIndex(200)
                    }
                }

                Spacer()

                Text("\(value.wrappedValue)")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(isTouched ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute)
                    .frame(width: 28, alignment: .trailing)
            }

            // 슬라이더 바
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

            // 양끝 척도 기준 안내 (방안 1: 슬라이더 바로 밑 마이크로 앵커)
            HStack {
                Text(minLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Config.Colors.mute.opacity(0.85))

                Spacer()

                Text(maxLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Config.Colors.mute.opacity(0.85))
            }
            .padding(.horizontal, 2)
            .padding(.top, -2)
        }
        .zIndex(isHovered ? 150 : 1)
    }
}

// MARK: - 6. [AI 영향 2점 이상일 때] 심층 원인 질문 컴포넌트 ("해당하는 것을 모두 골라주세요")
/// 상위 질문에서 이어진 L자 브랜치(└── ↳)를 통해 직관적으로 배치
public struct DeepFatigueSectionView: View {
    @ObservedObject public var formState: SurveyFormState

    public init(formState: SurveyFormState) {
        self.formState = formState
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // 후속 질문 L자 분기선 (└──)
            TreeBranchConnectorShape(isThrough: false)
                .stroke(Config.Colors.mute.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 22)
                .padding(.top, -6)
                .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 8) {
                // 헤더 질문 (↳ 해당하는 것을 모두 골라주세요)
                HStack(spacing: 4) {
                    Text("↳")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                    Text("해당하는 것을 모두 골라주세요")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Config.Colors.ink)
                }

                // 6개 카테고리 항목
                VStack(spacing: 6) {
                    ForEach(FatigueReasonCategory.allCategories) { category in
                        categoryRow(category: category)
                    }
                }
            }
        }
    }

    private func categoryRow(category: FatigueReasonCategory) -> some View {
        let isSelected = formState.selectedFatigueCategories.contains(category.id)

        return VStack(alignment: .leading, spacing: 6) {
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
                        .foregroundColor(Config.Colors.ink)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color(hex: Config.Colors.accentHex).opacity(0.10) : Config.Colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color(hex: Config.Colors.accentHex) : Config.Colors.line, lineWidth: isSelected ? 1.0 : 0.8)
                        )
                )
            }
            .buttonStyle(.plain)

            // 선택 시 아래에 주관식 직접 입력창과 추천 칩 열림
            if isSelected {
                VStack(alignment: .leading, spacing: 4) {
                    SubjectiveInputFieldView(
                        label: nil,
                        placeholder: category.id == "other" ? "피로하다고 느낀 점 (선택)" : "피로하다고 느낀 점 (선택)",
                        fieldKey: "fatigue_\(category.id)",
                        chipOptions: category.chipOptions,
                        isSingleLine: true,
                        isDisabled: false,
                        onFocusChanged: { isFocused in
                            formState.isTextFieldFocused = isFocused
                        },
                        answer: Binding(
                            get: { formState.fatigueCategoryDetails[category.id] ?? SubjectiveAnswer() },
                            set: { formState.fatigueCategoryDetails[category.id] = $0 }
                        )
                    )
                }
                .padding(.leading, 8)
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - 7. [유용성 4점 이상일 때] 후속 질문 컴포넌트
/// 유용성 질문 바로 아래에 펼쳐짐 (피로 추가 질문 구조와 동일한 서브 카드 컨테이너 적용)
public struct UsefulnessHelpSectionView: View {
    @ObservedObject public var formState: SurveyFormState

    public init(formState: SurveyFormState) {
        self.formState = formState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubjectiveInputFieldView(
                label: nil,
                placeholder: "도움이 된다고 느낀 점 (선택)",
                fieldKey: "usefulness_help",
                chipOptions: UsefulnessChipOptions.items,
                isSingleLine: true,
                isDisabled: false,
                isInsideCard: true,
                onFocusChanged: { isFocused in
                    formState.isTextFieldFocused = isFocused
                },
                answer: $formState.endUsefulnessHelp
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Config.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Config.Colors.line.opacity(0.35), lineWidth: 0.6)
                )
        )
    }
}

// MARK: - 8. 가변 칩 줄바꿈 레이아웃 (FlowLayout)
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

// MARK: - 9. 2026 개편 작업 및 역할 분담 섹션 (Task & Role Division)
/// 3단계 역할 분담: 상단 '작업 목적' 전폭 입력 후, 'AI가 하는 일'과 '내가 하는 일'을 좌우 2열(Side-by-Side)로 배치하여 협업 구도를 한눈에 대조
public struct TaskRoleDivisionSectionView: View {
    public let surveyType: SurveyType
    @Binding public var taskPurpose: SubjectiveAnswer
    @Binding public var aiRole: SubjectiveAnswer
    @Binding public var myRole: SubjectiveAnswer
    @Binding public var capturedImagePath: String?
    public var onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))? = nil
    public var onFocusChanged: ((Bool) -> Void)? = nil

    public init(
        surveyType: SurveyType,
        taskPurpose: Binding<SubjectiveAnswer>,
        aiRole: Binding<SubjectiveAnswer>,
        myRole: Binding<SubjectiveAnswer>,
        capturedImagePath: Binding<String?>,
        onRetakeAreaCapture: (((@escaping (String?) -> Void) -> Void))? = nil,
        onFocusChanged: ((Bool) -> Void)? = nil
    ) {
        self.surveyType = surveyType
        self._taskPurpose = taskPurpose
        self._aiRole = aiRole
        self._myRole = myRole
        self._capturedImagePath = capturedImagePath
        self.onRetakeAreaCapture = onRetakeAreaCapture
        self.onFocusChanged = onFocusChanged
    }

    private var isStart: Bool { surveyType == .start }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 사용 목적 (시작/중간/자발적 공통) - 전폭 배치
            if surveyType == .mid || surveyType == .diary {
                SituationInputOrCaptureSectionView(
                    title: "어떤 작업을 하고 있나요?",
                    placeholder: "예: 관련 문헌 찾기, 논문 인트로 다듬기, 실험 데이터 분석",
                    situationAnswer: $taskPurpose,
                    capturedImagePath: $capturedImagePath,
                    appName: "AI 작업 화면",
                    fieldKey: "task_purpose",
                    onFocusChanged: onFocusChanged,
                    onRetakeAreaCapture: onRetakeAreaCapture
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isStart ? "어떤 작업을 하려고 하나요?" : "어떤 작업을 하고 있나요?")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    SubjectiveInputFieldView(
                        label: nil,
                        placeholder: "예: 관련 문헌 찾기, 논문 인트로 다듬기, 실험 데이터 분석",
                        fieldKey: "task_purpose",
                        chipOptions: [],
                        isSingleLine: false,
                        isInsideCard: true,
                        onFocusChanged: onFocusChanged,
                        answer: $taskPurpose
                    )
                }
            }

            // 2 & 3. 사이드 바이 사이드 2열 분할: 'AI가 하는 일' vs '내가 하는 일'
            HStack(alignment: .top, spacing: 10) {
                // 좌측 열: AI가 하는 일 (기대와 실제)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("🤖")
                            .font(.system(size: 11.5))
                        Text(isStart ? "AI가 할 일" : "AI가 하는 일")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Config.Colors.ink)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SubjectiveInputFieldView(
                        label: nil,
                        placeholder: isStart ? "예: 핵심만 빠르게 정리, 초안 틀 잡아주기" : "예: 핵심만 요약, 초안 작성 중",
                        fieldKey: "ai_role",
                        chipOptions: [],
                        isSingleLine: false,
                        isInsideCard: true,
                        onFocusChanged: onFocusChanged,
                        answer: $aiRole
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 우측 열: 내가 하는 일 (기대와 실제)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("👤")
                            .font(.system(size: 11.5))
                        Text(isStart ? "내가 할 일" : "내가 하는 일")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Config.Colors.ink)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SubjectiveInputFieldView(
                        label: nil,
                        placeholder: isStart ? "예: 요약이 맞는지 확인, 내 말투로 고치기" : "예: 요약 맞는지 확인, 수정 중",
                        fieldKey: "my_role",
                        chipOptions: [],
                        isSingleLine: false,
                        isInsideCard: true,
                        onFocusChanged: onFocusChanged,
                        answer: $myRole
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - 10. 피로도 및 AI 피로 영향 & 이유 섹션 (Side-by-Side Reasons)
/// 피로도 평가 섹션: 피로도 5점 척도, AI 피로도 5점 척도와 함께
/// 'AI로 인한 피로 이유'와 '그 외의 이유'를 사이드 바이 사이드(2열 스플릿)로 배치하여 직관적 대비 제공
public struct FatigueAndAIReasonSectionView: View {
    public let surveyType: SurveyType
    @Binding public var fatigueScore: Int?
    @Binding public var aiFatigueImpactScore: Int?
    @Binding public var fatigueReasonAI: SubjectiveAnswer
    @Binding public var fatigueReasonNonAI: SubjectiveAnswer
    public var onFocusChanged: ((Bool) -> Void)? = nil

    public init(
        surveyType: SurveyType,
        fatigueScore: Binding<Int?>,
        aiFatigueImpactScore: Binding<Int?>,
        fatigueReasonAI: Binding<SubjectiveAnswer>,
        fatigueReasonNonAI: Binding<SubjectiveAnswer>,
        onFocusChanged: ((Bool) -> Void)? = nil
    ) {
        self.surveyType = surveyType
        self._fatigueScore = fatigueScore
        self._aiFatigueImpactScore = aiFatigueImpactScore
        self._fatigueReasonAI = fatigueReasonAI
        self._fatigueReasonNonAI = fatigueReasonNonAI
        self.onFocusChanged = onFocusChanged
    }

    private var isStart: Bool { surveyType == .start }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. 피로도 5점 척도
            FatigueScaleView(score: $fatigueScore)

            // 2. 시작 설문 (.start) vs 중간/종료/자발적 분기
            if isStart {
                // 시작 설문: AI 피로도 없이 '그 외의 이유 (선택)' 단일 전폭 노출
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("어떤 점 때문에 피로하다고 느꼈나요?")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                        Spacer()
                        Text("선택")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(Config.Colors.mute)
                    }

                    SubjectiveInputFieldView(
                        label: nil,
                        placeholder: "예: 업무량, 마감, 수면 부족, 회의",
                        fieldKey: "fatigue_reason_start",
                        chipOptions: NonAIFatigueReasonChipOptions.items,
                        isSingleLine: false,
                        isInsideCard: true,
                        onFocusChanged: onFocusChanged,
                        answer: $fatigueReasonNonAI
                    )
                }
            } else {
                // 중간/종료/자발적: AI 피로 영향도 5점 척도
                LikertScaleView(
                    title: "지금 피로에 AI가 얼마나 영향을 주었나요?",
                    options: SurveyScaleDefinitions.aiImpactScale,
                    selectedValue: $aiFatigueImpactScore
                )

                // 3 & 4. [사이드 바이 사이드 2열 스플릿] AI로 인한 이유 vs 그 외의 이유
                let impact = aiFatigueImpactScore ?? 0
                let isHighImpact = impact >= 2 || aiFatigueImpactScore == nil

                HStack(alignment: .top, spacing: 10) {
                    // 좌측 (50%): AI로 인한 피로 이유 (조건부 인셋 카드)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("🤖")
                                .font(.system(size: 11.5))
                            Text(isHighImpact ? "AI로 인한 이유" : "AI 영향 없는 이유")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Config.Colors.ink)
                                .lineLimit(1)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 2)
                            Text("선택")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(Config.Colors.mute)
                        }

                        SubjectiveInputFieldView(
                            label: nil,
                            placeholder: isHighImpact
                                ? "예: 검증이 번거로움, 반복 요청, 결과 기다림"
                                : "예: 간단한 작업이라 신경 쓸 게 없었음",
                            fieldKey: isHighImpact ? "fatigue_reason_ai" : "fatigue_reason_ai_none",
                            chipOptions: isHighImpact ? FatigueReasonChipOptions.items : [],
                            isSingleLine: false,
                            isInsideCard: true,
                            onFocusChanged: onFocusChanged,
                            answer: $fatigueReasonAI
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: Config.Colors.accentHex).opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: Config.Colors.accentHex).opacity(0.18), lineWidth: 0.8)
                            )
                    )

                    // 우측 (50%): 그 외의 피로 이유 (뉴트럴 카드)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("☕️")
                                .font(.system(size: 11.5))
                            Text("그 외의 이유")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Config.Colors.ink)
                                .lineLimit(1)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 2)
                            Text("선택")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(Config.Colors.mute)
                        }

                        SubjectiveInputFieldView(
                            label: nil,
                            placeholder: "예: 업무량, 마감, 수면 부족, 회의",
                            fieldKey: "fatigue_reason_non_ai",
                            chipOptions: NonAIFatigueReasonChipOptions.items,
                            isSingleLine: false,
                            isInsideCard: true,
                            onFocusChanged: onFocusChanged,
                            answer: $fatigueReasonNonAI
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Config.Colors.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Config.Colors.line.opacity(0.5), lineWidth: 0.8)
                            )
                    )
                }
            }
        }
    }
}

// MARK: - 11. AI 유용성 및 이유 섹션
public struct AIUsefulnessAndReasonSectionView: View {
    public let surveyType: SurveyType
    @Binding public var usefulnessScore: Int?
    @Binding public var usefulnessReason: SubjectiveAnswer
    public var onFocusChanged: ((Bool) -> Void)? = nil

    public init(
        surveyType: SurveyType,
        usefulnessScore: Binding<Int?>,
        usefulnessReason: Binding<SubjectiveAnswer>,
        onFocusChanged: ((Bool) -> Void)? = nil
    ) {
        self.surveyType = surveyType
        self._usefulnessScore = usefulnessScore
        self._usefulnessReason = usefulnessReason
        self.onFocusChanged = onFocusChanged
    }

    private var questionTitle: String {
        surveyType == .end ? "AI가 얼마나 도움이 되었나요?" : "AI가 얼마나 도움이 되고 있나요?"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UsefulnessScaleView(
                score: $usefulnessScore,
                title: questionTitle
            )

            if let u = usefulnessScore {
                if u >= 2 {
                    // 유용성 조금 ~ 매우 (2~5점)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("AI가 도움이 된 이유")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Config.Colors.ink)
                            Spacer()
                            Text("선택")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(Config.Colors.mute)
                        }

                        SubjectiveInputFieldView(
                            label: nil,
                            placeholder: "예: 초안을 빨리 받았어요, 자료 찾는 시간이 줄었어요",
                            fieldKey: "usefulness_reason_positive",
                            chipOptions: UsefulnessChipOptions.items,
                            isSingleLine: false,
                            isInsideCard: true,
                            onFocusChanged: onFocusChanged,
                            answer: $usefulnessReason
                        )
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green.opacity(0.2), lineWidth: 0.8)
                            )
                    )
                } else {
                    // 유용성 전혀 (1점)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("AI가 도움이 되지 않은 이유")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Config.Colors.ink)
                            Spacer()
                            Text("선택")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(Config.Colors.mute)
                        }

                        SubjectiveInputFieldView(
                            label: nil,
                            placeholder: "예: 결국 내가 다시 써야 했어요, 원하는 답이 끝까지 안 나왔어요",
                            fieldKey: "usefulness_reason_negative",
                            chipOptions: [],
                            isSingleLine: false,
                            isInsideCard: true,
                            onFocusChanged: onFocusChanged,
                            answer: $usefulnessReason
                        )
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Config.Colors.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Config.Colors.line.opacity(0.4), lineWidth: 0.8)
                            )
                    )
                }
            }
        }
    }
}

// MARK: - 12. 30분 후 피로 영향 및 대처 점검 섹션 (Follow-up)
public struct FollowUp30MinSectionView: View {
    @Binding public var fatigueImpactOnWork: String
    @Binding public var isNoImpactOnWork: Bool
    @Binding public var copingStrategy: String
    @Binding public var isNoCopingStrategy: Bool
    @Binding public var improvementIdea: String
    public var onFocusChanged: ((Bool) -> Void)? = nil

    public init(
        fatigueImpactOnWork: Binding<String>,
        isNoImpactOnWork: Binding<Bool>,
        copingStrategy: Binding<String>,
        isNoCopingStrategy: Binding<Bool>,
        improvementIdea: Binding<String>,
        onFocusChanged: ((Bool) -> Void)? = nil
    ) {
        self._fatigueImpactOnWork = fatigueImpactOnWork
        self._isNoImpactOnWork = isNoImpactOnWork
        self._copingStrategy = copingStrategy
        self._isNoCopingStrategy = isNoCopingStrategy
        self._improvementIdea = improvementIdea
        self.onFocusChanged = onFocusChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 문항 1. 피로의 영향 (필수 ●)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text("피로를 느낀 뒤, 작업하는 방식이 달라진 점이 있나요?")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 6)

                    Toggle(isOn: $isNoImpactOnWork) {
                        Text("없음")
                            .font(.system(size: 11.5, weight: isNoImpactOnWork ? .bold : .regular))
                            .foregroundColor(isNoImpactOnWork ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute)
                    }
                    .toggleStyle(.checkbox)
                }

                if !isNoImpactOnWork {
                    FollowUpCustomTextEditor(
                        text: $fatigueImpactOnWork,
                        placeholder: "예: AI 답을 확인 없이 그대로 썼어요, 작업을 맡기고 놀았어요",
                        onFocusChanged: onFocusChanged
                    )
                }
            }

            Divider()
                .background(Config.Colors.line.opacity(0.4))

            // 문항 2. 대처 방식 (필수 ●)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text("그 사이 피로를 줄이려고 해 본 것이 있나요?")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 6)

                    Toggle(isOn: $isNoCopingStrategy) {
                        Text("없음")
                            .font(.system(size: 11.5, weight: isNoCopingStrategy ? .bold : .regular))
                            .foregroundColor(isNoCopingStrategy ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute)
                    }
                    .toggleStyle(.checkbox)
                }

                if !isNoCopingStrategy {
                    FollowUpCustomTextEditor(
                        text: $copingStrategy,
                        placeholder: "예: 프롬프트를 짧게 나눠서 물어봤어요, AI 없이 먼저 구상했어요, 잠깐 쉬었다 왔어요",
                        onFocusChanged: onFocusChanged
                    )
                }
            }

            Divider()
                .background(Config.Colors.line.opacity(0.4))

            // 문항 3. 개선 방안 (선택 ○)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text("무엇이 달랐다면 덜 피로했을까요?")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Text("선택")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Config.Colors.mute)
                }

                FollowUpCustomTextEditor(
                    text: $improvementIdea,
                    placeholder: "예: 내가 지쳤을 때는 AI가 답을 짧고 천천히 줬으면, AI를 쓰기 전에 목표와 시간을 미리 정해 뒀으면",
                    onFocusChanged: onFocusChanged
                )
            }
        }
    }
}

public struct FollowUpCustomTextEditor: View {
    @Binding public var text: String
    public let placeholder: String
    public var onFocusChanged: ((Bool) -> Void)? = nil
    @FocusState private var isFocused: Bool

    public init(text: Binding<String>, placeholder: String, onFocusChanged: ((Bool) -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.onFocusChanged = onFocusChanged
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundColor(Config.Colors.mute.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .font(.system(size: 12))
                .foregroundColor(Config.Colors.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    onFocusChanged?(focused)
                }
        }
        .frame(minHeight: 56, maxHeight: 90)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Config.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isFocused ? Color(hex: Config.Colors.accentHex) : Config.Colors.line, lineWidth: isFocused ? 1.2 : 0.8)
                )
        )
    }
}


