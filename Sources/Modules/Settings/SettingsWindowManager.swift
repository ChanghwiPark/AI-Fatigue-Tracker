import AppKit
import SwiftUI

/// 참여자 설정 및 프라이버시 관리 전용 NSWindow를 띄우고 제어하는 윈도우 컨트롤러 매니저
public final class SettingsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowManager()

    private var windowController: NSWindowController?

    public var isVisible: Bool {
        return windowController?.window?.isVisible == true
    }

    private override init() {
        super.init()
    }

    /// 설정 및 프라이버시 창 열기 (이미 열려 있다면 포커스 이동)
    public func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        UserDefaults.standard.set("settings", forKey: "active_window_identifier")

        if let existing = windowController, existing.window?.isVisible == true {
            existing.window?.orderFrontRegardless()
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 760, height: 540)
        window.center()
        window.title = "AI 피로 기록 — 설정 및 프라이버시"
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

        controller.showWindow(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        if UserDefaults.standard.string(forKey: "active_window_identifier") == "settings" {
            UserDefaults.standard.removeObject(forKey: "active_window_identifier")
        }
        if !DebugWindowManager.shared.isVisible && !OnboardingWindowManager.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// 설정 창 닫기
    public func closeSettingsWindow() {
        windowController?.close()
        windowController = nil
        if UserDefaults.standard.string(forKey: "active_window_identifier") == "settings" {
            UserDefaults.standard.removeObject(forKey: "active_window_identifier")
        }
        if !DebugWindowManager.shared.isVisible && !OnboardingWindowManager.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

