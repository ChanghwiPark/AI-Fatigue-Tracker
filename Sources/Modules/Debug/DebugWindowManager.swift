import AppKit
import SwiftUI

/// 디버그 모니터 윈도우 컨트롤러 매니저
public final class DebugWindowManager: NSObject, NSWindowDelegate {
    public static let shared = DebugWindowManager()

    private var windowController: NSWindowController?

    public var isVisible: Bool {
        return windowController?.window?.isVisible == true
    }

    private override init() {
        super.init()
    }

    public func showDebugWindow() {
        NSApp.setActivationPolicy(.regular)
        UserDefaults.standard.set("debug", forKey: "active_window_identifier")

        if let existing = windowController, existing.window?.isVisible == true {
            existing.window?.orderFrontRegardless()
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: DebugWindowView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "AI 피로 기록 — 실시간 활동 & AI 세션 디버그 모니터"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.setFrameAutosaveName("AIDebugMonitorWindow")
        window.minSize = NSSize(width: 960, height: 640)
        window.delegate = self
        window.backgroundColor = NSColor(name: nil, dynamicProvider: { app in
            app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: "#1A1816")
                : NSColor(hex: Config.Colors.paperHex)
        })

        let controller = NSWindowController(window: window)
        self.windowController = controller

        controller.showWindow(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        if UserDefaults.standard.string(forKey: "active_window_identifier") == "debug" {
            UserDefaults.standard.removeObject(forKey: "active_window_identifier")
        }
        if !SettingsWindowManager.shared.isVisible && !OnboardingWindowManager.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    public func closeDebugWindow() {
        windowController?.close()
        windowController = nil
        if UserDefaults.standard.string(forKey: "active_window_identifier") == "debug" {
            UserDefaults.standard.removeObject(forKey: "active_window_identifier")
        }
        if !SettingsWindowManager.shared.isVisible && !OnboardingWindowManager.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
