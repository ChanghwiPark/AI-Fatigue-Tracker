import SwiftUI
import AppKit

/// "저장됨" 짧은 확인 알림 플로팅 토스트 패널
public final class SaveConfirmationToast {
    public static let shared = SaveConfirmationToast()

    private var toastPanel: NSPanel?

    private init() {}

    public func show(message: String = "저장됨", detail: String = "피로 순간 기록이 기록되었습니다.") {
        DispatchQueue.main.async {
            self.toastPanel?.orderOut(nil)
            self.toastPanel = nil

            guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
            let visibleFrame = screen.visibleFrame

            let toastWidth: CGFloat = 280.0
            let toastHeight: CGFloat = 64.0
            let rightMargin: CGFloat = 14.0
            let topMargin: CGFloat = 12.0

            let x = visibleFrame.maxX - rightMargin - toastWidth
            let y = visibleFrame.maxY - topMargin - toastHeight

            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: toastWidth, height: toastHeight),
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let toastView = ToastContentView(title: message, detail: detail)
            panel.contentView = NSHostingView(rootView: toastView)
            panel.alphaValue = 0.0
            panel.orderFrontRegardless()

            // 페이드 인
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 1.0
            }

            self.toastPanel = panel

            // 2초 후 부드럽게 페이드 아웃 후 닫기
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard let p = self.toastPanel, p == panel else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.35
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

private struct ToastContentView: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#10B981").opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#10B981"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Config.Colors.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Config.Colors.mute)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Config.Colors.popupBg)
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Config.Colors.line, lineWidth: 1.0)
        )
        .padding(4)
    }
}
