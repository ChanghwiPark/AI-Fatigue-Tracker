import AppKit
import SwiftUI

/// 온보딩 전용 NSWindow를 띄우고 관리하는 윈도우 컨트롤러 매니저
public final class OnboardingWindowManager: NSObject, NSWindowDelegate {
    public static let shared = OnboardingWindowManager()

    private var windowController: NSWindowController?

    public var isVisible: Bool {
        return windowController?.window?.isVisible == true
    }

    private override init() {
        super.init()
    }

    public func showOnboardingWindow(appState: AppState = .shared) {
        NSApp.setActivationPolicy(.regular)
        UserDefaults.standard.set("onboarding", forKey: "active_window_identifier")

        if let win = windowController?.window {
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
            win.orderFrontRegardless()
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                win.orderFrontRegardless()
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        let hostingView = NSHostingView(rootView: OnboardingView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "AI 피로 기록 — 참여자 안내"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = NSColor(name: nil, dynamicProvider: { app in
            app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: "#1A1816")
                : NSColor(hex: Config.Colors.paperHex)
        })

        let controller = NSWindowController(window: window)
        self.windowController = controller
        appState.onboardingWindowController = controller

        controller.showWindow(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func windowWillClose(_ notification: Notification) {
        windowController = nil
        if UserDefaults.standard.string(forKey: "active_window_identifier") == "onboarding" {
            UserDefaults.standard.removeObject(forKey: "active_window_identifier")
        }
        if !DebugWindowManager.shared.isVisible && !SettingsWindowManager.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    public func closeOnboardingWindow() {
        windowController?.close()
        windowController = nil
        if UserDefaults.standard.string(forKey: "active_window_identifier") == "onboarding" {
            UserDefaults.standard.removeObject(forKey: "active_window_identifier")
        }
        if !DebugWindowManager.shared.isVisible && !SettingsWindowManager.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

