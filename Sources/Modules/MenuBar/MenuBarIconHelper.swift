import AppKit

/// macOS 메뉴 막대(Status Item)에 표시할 C-2 디자인(세로 로우 배터리 × 테라코타 프롬프트 말풍선) 벡터 NSImage를 생성합니다.
/// - 타 앱의 시각적 볼륨과 높이에 맞춘 볼드하고 선명한 크기(24×18)
/// - 라이트/다크 메뉴 막대 환경에 맞춰 외곽선이 자동으로 짙은 잉크(#1D1D1F) 또는 화이트(#F5F5F7)로 적응
/// - 세션 기록 중에는 경과 시간(예: "8:54")을 표시하고, 대기 중에는 텍스트 없이 단독 아이콘으로 미니멀하게 렌더링
/// - 가장 최근 체크된 피로도(1~5점)에 따라 배터리 잔량(90%~15%) 및 색상(초록~레드)을 동적 반영
public enum MenuBarIconHelper {
    private static let orangeColor = CGColor(red: 0.91, green: 0.33, blue: 0.16, alpha: 1.0) // #E0522A

    /// C-2 아이콘 단독 NSImage 생성 (기본 24×18)
    public static func makeIcon(fatigueScore: Int? = nil) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let isDark = isCurrentAppearanceDark()
            drawIconComponents(in: ctx, isDark: isDark, offsetX: 0, fatigueScore: fatigueScore)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// C-2 아이콘 + 세션 경과 시간 결합 벡터 NSImage 생성
    /// - 세션 기록 중: 경과 시간(예: "8:54", "12:30")을 가독성 높은 모노스페이스 볼드 폰트로 렌더링
    /// - 대기 중: 불필요한 "OFF" 텍스트 없이 단독 아이콘(24×18)만 미니멀하게 렌더링
    /// - 아이콘과 텍스트 간격을 2.9pt(x: 25.5)로 밀착하여 시각적 일체감 향상
    /// - 최근 응답한 피로도(fatigueScore: 1~5점)를 배터리 잔량 및 색상으로 동적 반영
    public static func makeStatusIcon(
        duration: String? = nil,
        isRecording: Bool,
        fatigueScore: Int? = nil
    ) -> NSImage {
        // 대기(미기록) 상태: 텍스트 없이 단독 아이콘(24×18)만 미니멀하게 렌더링
        guard isRecording else {
            return makeIcon(fatigueScore: fatigueScore)
        }

        let isDark = isCurrentAppearanceDark()
        let startX: CGFloat = 25.5 // 말풍선(22.6)과의 여백을 2.9pt로 최적화
        let displayText = duration ?? "0:00"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        let textColor = isDark
            ? NSColor(white: 0.96, alpha: 0.98)
            : NSColor(white: 0.11, alpha: 0.98)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let str = displayText as NSString
        let textSize = str.size(withAttributes: attrs)

        let totalWidth = max(24.0, ceil(startX + textSize.width + 1.5))
        let size = NSSize(width: totalWidth, height: 18.0)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let dark = isCurrentAppearanceDark()

            // 1. 좌측 C-2 배터리 & 말풍선 아이콘 렌더링 (피로도에 따른 배터리 레벨 및 말풍선 일체화 색상 반영)
            drawIconComponents(in: ctx, isDark: dark, offsetX: 0, fatigueScore: fatigueScore)

            // 2. 우측 세션 시간 텍스트 렌더링 (간격 2.9pt 밀착, startX: 25.5)
            let curTextColor = dark ? NSColor(white: 0.96, alpha: 0.98) : NSColor(white: 0.11, alpha: 0.98)
            let curAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: curTextColor
            ]
            let curStr = displayText as NSString
            let curSize = curStr.size(withAttributes: curAttrs)
            let textY = (18.0 - curSize.height) / 2.0
            let textRect = CGRect(x: startX, y: textY, width: curSize.width + 1.0, height: curSize.height)
            curStr.draw(in: textRect, withAttributes: curAttrs)

            return true
        }
        image.isTemplate = false
        return image
    }

    /// 하위 호환용 편의 메서드
    public static func makeStatusIcon(isRecording: Bool) -> NSImage {
        makeStatusIcon(duration: nil, isRecording: isRecording, fatigueScore: nil)
    }

    // MARK: - Private Drawing Helpers

    private static func isCurrentAppearanceDark() -> Bool {
        let drawingApp = NSAppearance.currentDrawing()
        let match = drawingApp.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        return (match == .darkAqua || match == .vibrantDark || drawingApp.name.rawValue.lowercased().contains("dark"))
    }

    private static func drawIconComponents(in ctx: CGContext, isDark: Bool, offsetX: CGFloat, fatigueScore: Int? = nil) {
        // 라이트 메뉴 막대에서는 짙은 차콜(#1A1A1C), 다크 메뉴 막대에서는 화이트(#F5F5F7) 적용
        let strokeColor = isDark
            ? CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.98)
            : CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.98)

        let chamberFill = isDark
            ? CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.14)
            : CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.09)

        // 1. 좌측: 세로형 배터리 (Vertical Low Battery)
        let outerBatRect = CGRect(x: offsetX + 1.0, y: 1.6, width: 7.4, height: 13.8)
        let outerBatPath = CGPath(roundedRect: outerBatRect, cornerWidth: 2.2, cornerHeight: 2.2, transform: nil)

        // 상단 단자 캡 (+)
        let capRect = CGRect(x: outerBatRect.midX - 1.8, y: 15.4, width: 3.6, height: 1.4)
        ctx.setFillColor(strokeColor)
        ctx.addPath(CGPath(roundedRect: capRect, cornerWidth: 0.7, cornerHeight: 0.7, transform: nil))
        ctx.fillPath()

        // 배터리 빈 챔버 반투명 배경 채움
        ctx.setFillColor(chamberFill)
        ctx.addPath(outerBatPath)
        ctx.fillPath()

        // 배터리 내부 게이지 전용 Inset 캐비티 (테두리 침범 원천 방지: 좌우상하 1.35pt 인셋)
        let innerBatRect = outerBatRect.insetBy(dx: 1.35, dy: 1.35)
        let innerBatPath = CGPath(roundedRect: innerBatRect, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil)

        // 배터리 충전/방전 레벨 (내부 캐비티 높이 11.1pt 기준 역산 게이지 및 말풍선 일체화 색상)
        // 1점(전혀): 90% 만충 선명한 초록 (#34C759, 9.8pt)
        // 2점(약간): 70% 충전 싱그러운 연두/라임 (#6BC747, 7.7pt)
        // 3점(어느 정도): 50% 반충 따뜻한 옐로우/앰버 (#FF9F0A, 5.5pt)
        // 4점(많이): 32% 로우 배터리 테라코타 오렌지 (#E0522A, 3.5pt, 기본값)
        // 5점(매우): 16% 위험 방전 브라이트 레드 (#FF453A, 1.8pt)
        let (levelHeight, batteryColor): (CGFloat, CGColor) = {
            switch fatigueScore {
            case 1:
                return (9.8, CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)) // #34C759
            case 2:
                return (7.7, CGColor(red: 0.42, green: 0.78, blue: 0.28, alpha: 1.0))  // #6BC747 (연두/라임)
            case 3:
                return (5.5, CGColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1.0))   // #FF9F0A
            case 4:
                return (3.5, CGColor(red: 0.91, green: 0.33, blue: 0.16, alpha: 1.0))  // #E0522A
            case 5:
                return (1.8, CGColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0))   // #FF453A
            default:
                return (3.5, CGColor(red: 0.91, green: 0.33, blue: 0.16, alpha: 1.0))  // 기본 32% 테라코타
            }
        }()

        // 내부 게이지 액체 채움 (innerBatPath에 클리핑하여 테두리 밖으로 전혀 넘치지 않음)
        ctx.saveGState()
        ctx.addPath(innerBatPath)
        ctx.clip()
        let fillRect = CGRect(x: innerBatRect.minX, y: innerBatRect.minY, width: innerBatRect.width, height: levelHeight)
        ctx.setFillColor(batteryColor)
        ctx.fill(fillRect)
        ctx.restoreGState()

        // 배터리 외곽선 (게이지 위에 얹어 선명하고 완벽한 테두리 보장)
        ctx.setLineWidth(1.3)
        ctx.setStrokeColor(strokeColor)
        ctx.addPath(outerBatPath)
        ctx.strokePath()

        // 2. 우측: 프롬프트 말풍선 (12.6 × 12.6pt 볼드 버블) - 배터리 피로도 색상과 일체화
        let bubRect = CGRect(x: offsetX + 10.0, y: 2.8, width: 12.6, height: 12.6)
        let bubR: CGFloat = 3.6

        let bubP = CGMutablePath()
        let minX = bubRect.minX
        let maxX = bubRect.maxX
        let minY = bubRect.minY
        let maxY = bubRect.maxY

        bubP.move(to: CGPoint(x: minX + bubR, y: maxY))
        bubP.addLine(to: CGPoint(x: maxX - bubR, y: maxY))
        bubP.addArc(center: CGPoint(x: maxX - bubR, y: maxY - bubR), radius: bubR, startAngle: .pi/2, endAngle: 0, clockwise: true)
        bubP.addLine(to: CGPoint(x: maxX, y: minY + bubR))
        bubP.addArc(center: CGPoint(x: maxX - bubR, y: minY + bubR), radius: bubR, startAngle: 0, endAngle: -.pi/2, clockwise: true)
        bubP.addLine(to: CGPoint(x: minX + bubR, y: minY))
        bubP.addArc(center: CGPoint(x: minX + bubR, y: minY + bubR), radius: bubR, startAngle: -.pi/2, endAngle: .pi, clockwise: true)

        // 배터리를 향하는 말풍선 꼬리
        let tailCenterY: CGFloat = 8.8
        bubP.addLine(to: CGPoint(x: minX, y: tailCenterY - 2.0))
        bubP.addLine(to: CGPoint(x: minX - 2.0, y: tailCenterY))
        bubP.addLine(to: CGPoint(x: minX, y: tailCenterY + 2.0))

        bubP.addLine(to: CGPoint(x: minX, y: maxY - bubR))
        bubP.addArc(center: CGPoint(x: minX + bubR, y: maxY - bubR), radius: bubR, startAngle: .pi, endAngle: .pi/2, clockwise: true)
        bubP.closeSubpath()

        // 말풍선 배경 채움: 배터리 피로도 색상(batteryColor)과 완벽한 일체화
        ctx.setFillColor(batteryColor)
        ctx.addPath(bubP)
        ctx.fillPath()

        // 내부 순백의 볼드 프롬프트 쉐브론 ( > )
        let cPath = CGMutablePath()
        cPath.move(to: CGPoint(x: bubRect.midX - 2.8, y: bubRect.midY + 2.9))
        cPath.addLine(to: CGPoint(x: bubRect.midX + 0.9, y: bubRect.midY))
        cPath.addLine(to: CGPoint(x: bubRect.midX - 2.8, y: bubRect.midY - 2.9))
        ctx.setLineWidth(1.7)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.99))
        ctx.addPath(cPath)
        ctx.strokePath()

        // 내부 볼드 프롬프트 커서 ( _ )
        let curPath = CGMutablePath()
        curPath.move(to: CGPoint(x: bubRect.midX + 2.0, y: bubRect.midY - 2.2))
        curPath.addLine(to: CGPoint(x: bubRect.midX + 4.3, y: bubRect.midY - 2.2))
        ctx.setLineWidth(1.4)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
        ctx.addPath(curPath)
        ctx.strokePath()
    }
}
