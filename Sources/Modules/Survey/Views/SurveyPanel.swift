import AppKit
import SwiftUI

/// 비활성화 스타일(.nonactivatingPanel)의 최상위 플로팅 윈도우 패널
/// - 클릭해도 작업 중인 앱의 포커스를 뺏지 않습니다.
/// - 모든 Space 및 전체 화면(Full-screen) 위에 안정적으로 표시됩니다.
public final class SurveyPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .nonactivatingPanel,
                .borderless
            ],
            backing: .buffered,
            defer: false
        )

        self.isMovable = true
        self.isMovableByWindowBackground = false
        self.isFloatingPanel = true
        // 상태바 레벨(statusWindow)로 설정하여 전체 화면 앱 위에도 항상 오버레이
        self.level = .statusBar
        // 모든 가상 데스크톱(Spaces) 및 전체 화면 보조 윈도우로 동작
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.hidesOnDeactivate = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.becomesKeyOnlyIfNeeded = true
    }

    /// becomesKeyOnlyIfNeeded = true 와 연동되어, 텍스트 필드를 클릭했을 때만 키 윈도우가 되어 타이핑/수정 가능
    public override var canBecomeKey: Bool {
        return true
    }

    public override var canBecomeMain: Bool {
        return false
    }

    /// Esc 키 입력 시 팝업 즉시 닫기
    public override func cancelOperation(_ sender: Any?) {
        SurveyWindowManager.shared.dismissPopup()
    }
}

/// 비활성 상태의 윈도우에서도 첫 마우스 클릭(버튼 누름)을 즉시 수신하는 전용 호스팅 뷰
public final class SurveyHostingView<Content: View>: NSHostingView<Content> {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    public override var mouseDownCanMoveWindow: Bool {
        // 호스팅 뷰 전체가 마우스 다운을 윈도우 드래그로 가로채지 않도록 하여 SwiftUI 버튼 클릭 보장
        return false
    }
}

/// 헤더 및 카드 배경을 마우스로 잡고 창을 자유롭게 이동할 수 있게 해주는 AppKit 네이티브 드래그 영역
public struct WindowDragArea: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    public func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

public final class WindowDragNSView: NSView {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    public override var mouseDownCanMoveWindow: Bool {
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        // AppKit 윈도우 서버 내장 드래그를 즉각 실행하여 120Hz 부드러운 드래그 및 다중 디스플레이 이동 지원
        window?.performDrag(with: event)
    }
}
