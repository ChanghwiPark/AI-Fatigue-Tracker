import SwiftUI
import AppKit

/// "저장됨" 초미니멀 확인 알림 플로팅 캡슐 패널
/// - 2줄 대형 박스 대신 슬림한 알약(Capsule) 뱃지 형태로 화면 우상단에 작고 깔끔하게 표시
/// - 1.1초 노출 후 부드럽게 페이드 아웃
public final class SaveConfirmationToast {
    public static let shared = SaveConfirmationToast()

    private var toastPanel: NSPanel?

    private init() {}

    public func show(
        message: String = "저장 완료",
        detail: String? = nil,
        icon: String = "checkmark",
        iconColor: Color? = nil
    ) {
        DispatchQueue.main.async {
            self.toastPanel?.orderOut(nil)
            self.toastPanel = nil

            guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
            let visibleFrame = screen.visibleFrame

            let rightMargin: CGFloat = 20.0
            let topMargin: CGFloat = 14.0

            let toastView = MinimalToastCapsuleView(
                title: message,
                icon: icon,
                iconColor: iconColor ?? Color(hex: Config.Colors.accentHex)
            )
            let hostingView = NSHostingView(rootView: toastView)

            // 텍스트 길이에 맞춘 정확한 고유 크기 측정 (자연스러운 캡슐 폭 자동 결정)
            let fittingSize = hostingView.fittingSize
            let toastWidth = max(116.0, fittingSize.width)
            let toastHeight = max(38.0, fittingSize.height)

            let x = visibleFrame.maxX - rightMargin - toastWidth
            let y = visibleFrame.maxY - topMargin - toastHeight

            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: toastWidth, height: toastHeight),
                styleMask: [
                    .nonactivatingPanel,
                    .borderless
                ],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.isReleasedWhenClosed = false
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = hostingView
            panel.alphaValue = 0.0
            panel.orderFrontRegardless()

            // 1. 빠른 스프링 페이드 인 (0.16초)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                panel.animator().alphaValue = 1.0
            }

            self.toastPanel = panel

            // 2. 1.1초 동안 미니멀하게 노출된 후 부드럽게 페이드 아웃 (0.22초)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                guard let p = self.toastPanel, p == panel else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.22
                    p.animator().alphaValue = 0.0
                }, completionHandler: {
                    p.orderOut(nil)
                    if self.toastPanel == p {
                        self.toastPanel = nil
                    }
                })
            }
        }
    }
}

/// 초미니멀 캡슐 HUD 뷰: 단일 행 [ ✓  저장 완료 ] 또는 [ ⏱️ 임시 저장됨 ] 형태
public struct MinimalToastCapsuleView: View {
    public let title: String
    public let icon: String
    public let iconColor: Color

    public init(
        title: String = "저장 완료",
        icon: String = "checkmark",
        iconColor: Color = Color(hex: Config.Colors.accentHex)
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(iconColor)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Config.Colors.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7.5)
        .background(
            Capsule()
                .fill(Config.Colors.popupBg)
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        )
        .overlay(
            Capsule()
                .stroke(Config.Colors.line.opacity(0.85), lineWidth: 0.8)
        )
        .padding(5)
    }
}
