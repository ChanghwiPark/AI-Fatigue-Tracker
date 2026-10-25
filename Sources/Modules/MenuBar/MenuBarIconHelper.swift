import AppKit

/// macOS 메뉴 막대(Status Item)에 표시할 고화질 비트맵/벡터 NSImage를 생성합니다.
public enum MenuBarIconHelper {
    public static func makeIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            // 1. 외곽 원 (다크/라이트 모드 자동 적응)
            let outerRect = NSRect(x: 2, y: 2, width: 14, height: 14)
            let outerPath = NSBezierPath(ovalIn: outerRect)
            outerPath.lineWidth = 1.6
            NSColor.labelColor.withAlphaComponent(0.85).setStroke()
            outerPath.stroke()

            // 2. 내부 주황색 점 (#E0522A)
            let innerRect = NSRect(x: 6, y: 6, width: 6, height: 6)
            let innerPath = NSBezierPath(ovalIn: innerRect)
            NSColor(hex: Config.Colors.accentHex).setFill()
            innerPath.fill()

            return true
        }
        image.isTemplate = false // 주황색 점 고유 색상 유지
        return image
    }
}
