import AppKit

public enum MenuBarAccessHelper {
    /// 앱 시작 시 또는 프로그래밍 방식으로 메뉴 막대 패널(MenuBarView)을 펼칩니다.
    public static func openMenuBarExtra(delay: TimeInterval = 0.5, retryCount: Int = 8) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // 이미 열려있는지 확인
            let isAlreadyOpen = NSApp.windows.contains { w in
                let cls = String(describing: type(of: w))
                return cls.contains("MenuBarExtraWindow") && w.isVisible
            }
            if isAlreadyOpen {
                return
            }

            // NSStatusBarWindow 내의 NSStatusBarButton 탐색 후 클릭 수행
            for window in NSApp.windows {
                let cls = String(describing: type(of: window))
                if cls.contains("NSStatusBarWindow") {
                    if let btn = findStatusBarButton(in: window.contentView) {
                        btn.performClick(nil)
                        return
                    }
                }
            }

            // 창이 아직 생성되지 않은 초기 로딩 단계라면 잠시 후 재시도
            if retryCount > 0 {
                openMenuBarExtra(delay: 0.25, retryCount: retryCount - 1)
            }
        }
    }

    private static func findStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view = view else { return nil }
        if let btn = view as? NSStatusBarButton {
            return btn
        }
        for sub in view.subviews {
            if let btn = findStatusBarButton(in: sub) {
                return btn
            }
        }
        return nil
    }

    /// 메뉴 막대 패널(MenuBarView)을 즉시 닫고 화면에서 숨깁니다.
    public static func closeMenuBarExtra() {
        DispatchQueue.main.async {
            for window in NSApp.windows {
                let cls = String(describing: type(of: window))
                if cls.contains("MenuBarExtra") {
                    window.alphaValue = 0.0
                    window.orderOut(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        window.alphaValue = 1.0
                    }
                }
            }
        }
    }
}
