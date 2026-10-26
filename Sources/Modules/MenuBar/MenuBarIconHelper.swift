import AppKit

/// macOS 메뉴 막대(Status Item)에 표시할 고화질 비트맵/벡터 NSImage를 생성합니다.
public enum MenuBarIconHelper {
    public static func makeIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            // 1. 하단 보조 세이지 그린(#5D7A63) 잔물결 곡선
            let sagePath = NSBezierPath()
            sagePath.lineWidth = 1.6
            sagePath.lineCapStyle = .round
            sagePath.move(to: NSPoint(x: 3.5, y: 4.5))
            sagePath.curve(to: NSPoint(x: 14.5, y: 7.0),
                           controlPoint1: NSPoint(x: 7.5, y: 2.5),
                           controlPoint2: NSPoint(x: 11.5, y: 3.5))
            NSColor(hex: Config.Colors.sageHex).withAlphaComponent(0.85).setStroke()
            sagePath.stroke()

            // 2. 메인 스마일 웨이브 바디 (테라코타 주황 #E0522A)
            let wavePath = NSBezierPath()
            wavePath.lineWidth = 2.4
            wavePath.lineCapStyle = .round
            wavePath.lineJoinStyle = .round

            wavePath.move(to: NSPoint(x: 3.0, y: 7.5))
            wavePath.curve(to: NSPoint(x: 8.5, y: 13.5),
                           controlPoint1: NSPoint(x: 4.0, y: 12.0),
                           controlPoint2: NSPoint(x: 6.5, y: 13.5))
            wavePath.curve(to: NSPoint(x: 15.0, y: 9.5),
                           controlPoint1: NSPoint(x: 10.5, y: 13.5),
                           controlPoint2: NSPoint(x: 12.5, y: 6.5))

            NSColor(hex: Config.Colors.accentHex).setStroke()
            wavePath.stroke()

            // 3. 귀여운 두 눈 (점)
            NSColor.white.setFill()
            let leftEye = NSRect(x: 6.4, y: 10.6, width: 1.3, height: 1.3)
            let rightEye = NSRect(x: 9.2, y: 10.6, width: 1.3, height: 1.3)
            NSBezierPath(ovalIn: leftEye).fill()
            NSBezierPath(ovalIn: rightEye).fill()

            return true
        }
        image.isTemplate = false
        return image
    }
}
