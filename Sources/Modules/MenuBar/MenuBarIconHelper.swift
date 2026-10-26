import AppKit

/// macOS 메뉴 막대(Status Item)에 표시할 C-2 디자인(세로 로우 배터리 × 테라코타 프롬프트 말풍선) 벡터 NSImage를 생성합니다.
public enum MenuBarIconHelper {
    public static func makeIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // 1. 좌측: 세로형 로우 배터리 (Vertical Low Battery)
            // 상단 단자 캡 (+)
            let capRect = CGRect(x: 2.7, y: 14.2, width: 2.6, height: 1.2)
            ctx.setFillColor(CGColor(red: 0.82, green: 0.78, blue: 0.72, alpha: 0.9))
            ctx.addPath(CGPath(roundedRect: capRect, cornerWidth: 0.5, cornerHeight: 0.5, transform: nil))
            ctx.fillPath()

            // 배터리 외곽 바디
            let batRect = CGRect(x: 1.5, y: 2.8, width: 5.0, height: 11.4)
            let batPath = CGPath(roundedRect: batRect, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil)

            // 배터리 챔버 반투명 배경
            ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.15))
            ctx.addPath(batPath)
            ctx.fillPath()

            // 배터리 외곽선
            ctx.setLineWidth(1.0)
            ctx.setStrokeColor(CGColor(red: 0.82, green: 0.78, blue: 0.72, alpha: 0.95))
            ctx.addPath(batPath)
            ctx.strokePath()

            // 배터리 하단 28% 방전 레벨 (Terracotta Orange #E0522A)
            ctx.saveGState()
            ctx.addPath(batPath)
            ctx.clip()
            let lowH: CGFloat = 3.6
            let lowRect = CGRect(x: batRect.minX, y: batRect.minY, width: batRect.width, height: lowH)
            ctx.setFillColor(CGColor(red: 0.88, green: 0.32, blue: 0.16, alpha: 1.0))
            ctx.fill(lowRect)
            ctx.restoreGState()

            // 2. 우측: 테라코타 프롬프트 말풍선 (Terracotta Prompt Bubble)
            let bubRect = CGRect(x: 7.6, y: 4.2, width: 9.0, height: 9.2)
            let bubR: CGFloat = 2.4

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
            let tailCenterY: CGFloat = 8.5
            bubP.addLine(to: CGPoint(x: minX, y: tailCenterY - 1.6))
            bubP.addLine(to: CGPoint(x: minX - 1.5, y: tailCenterY))
            bubP.addLine(to: CGPoint(x: minX, y: tailCenterY + 1.6))

            bubP.addLine(to: CGPoint(x: minX, y: maxY - bubR))
            bubP.addArc(center: CGPoint(x: minX + bubR, y: maxY - bubR), radius: bubR, startAngle: .pi, endAngle: .pi/2, clockwise: true)
            bubP.closeSubpath()

            ctx.setFillColor(CGColor(red: 0.88, green: 0.32, blue: 0.16, alpha: 1.0)) // #E0522A
            ctx.addPath(bubP)
            ctx.fillPath()

            // 내부 순백의 프롬프트 쉐브론 ( > )
            let cPath = CGMutablePath()
            cPath.move(to: CGPoint(x: bubRect.midX - 2.0, y: bubRect.midY + 2.0))
            cPath.addLine(to: CGPoint(x: bubRect.midX + 0.5, y: bubRect.midY))
            cPath.addLine(to: CGPoint(x: bubRect.midX - 2.0, y: bubRect.midY - 2.0))
            ctx.setLineWidth(1.1)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.98))
            ctx.addPath(cPath)
            ctx.strokePath()

            // 내부 프롬프트 커서 ( _ )
            let curPath = CGMutablePath()
            curPath.move(to: CGPoint(x: bubRect.midX + 1.5, y: bubRect.midY - 1.6))
            curPath.addLine(to: CGPoint(x: bubRect.midX + 3.0, y: bubRect.midY - 1.6))
            ctx.setLineWidth(0.9)
            ctx.setLineCap(.round)
            ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.90))
            ctx.addPath(curPath)
            ctx.strokePath()

            return true
        }
        image.isTemplate = false
        return image
    }
}
