import AppKit
import CoreGraphics
import Foundation

// MARK: - 감지된 화면 윈도우 모델
public struct DetectedWindow {
    public let windowId: CGWindowID
    public let ownerName: String
    public let title: String
    public let boundsQuartz: CGRect      // Quartz 좌표계 (좌상단 원점, Y 아래로 증가)
    public let boundsCocoa: CGRect       // Cocoa 전역 스크린 좌표계 (주 모니터 좌하단 원점, Y 위로 증가)
}

// MARK: - 키보드(Esc) 이벤트를 수신하기 위한 전용 Borderless 윈도우
final class SmartCaptureOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.isReleasedWhenClosed = false
    }
}

// MARK: - 스마트 하이브리드 화면 캡처 서비스 (클릭 시 창 캡처, 드래그 시 영역 캡처)
/// CleanShot X / 카카오톡 캡처 방식:
/// - 마우스 호버 시 현재 작업 공간(Space)의 창을 실시간 감지하여 오렌지 테두리로 하이라이트
/// - 윈도우를 단순 클릭하면 해당 창 전체 캡처
/// - 마우스를 누른 채 드래그하면 원하는 사각 영역 캡처
/// - 빈 바탕화면 클릭 시 해당 화면 전체 캡처
/// - Esc 키 입력 시 즉시 취소 및 원래 설문 팝업 복귀
public final class SmartScreenCaptureService {
    public static let shared = SmartScreenCaptureService()

    private var overlayWindows: [NSWindow] = []
    private var completionHandler: ((String?) -> Void)?
    private var localEscMonitor: Any?
    private var globalEscMonitor: Any?
    private var isCapturing = false
    private var isCleaningUp = false
    private var hasPushedCursor = false
    private var spaceChangeObserver: NSObjectProtocol?

    // 실시간 창 캐시 (Space 이동 및 창 변화 대응용, 150ms 유효)
    private var cachedWindows: [DetectedWindow] = []
    private var lastWindowsFetchTime: TimeInterval = 0

    private init() {}

    // MARK: - 캡처 시작
    public func startCapture(completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isCapturing {
                completion(nil)
                return
            }
            self.isCapturing = true
            self.completionHandler = completion

            // Space 전환(가상 데스크톱 이동) 감지 리스너 등록 -> 이동 시 창 목록 즉시 갱신
            self.registerSpaceChangeObserver()

            // 1. 현재 화면에 떠 있는 창 목록 즉시 수집
            self.refreshVisibleWindows(force: true)

            // 2. 모든 연결된 모니터에 반투명 대화형 오버레이 윈도우 띄우기
            self.presentOverlays()

            // 3. Esc 키 취소 모니터 등록 (로컬 + 글로벌 2중 안전장치)
            self.registerEscKeyMonitors()
        }
    }

    // MARK: - 가상 데스크톱(Space) 전환 감지 리스너
    private func registerSpaceChangeObserver() {
        if let existing = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(existing)
            spaceChangeObserver = nil
        }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isCapturing else { return }
            print("[SmartScreenCapture] Space 전환 감지 -> 새 작업 공간 창 목록 즉시 재수집")
            self.cachedWindows.removeAll()
            self.lastWindowsFetchTime = 0
            self.refreshVisibleWindows(force: true)

            // 마우스 현재 위치로 호버 즉시 갱신
            let mouseLoc = NSEvent.mouseLocation
            for window in self.overlayWindows {
                guard let view = window.contentView as? SmartCaptureOverlayView else { continue }
                view.updateHoverForPoint(mouseLoc, using: self.cachedWindows)
                view.needsDisplay = true
            }

            // macOS Space 전환 애니메이션 완료 후 2차 안전 갱신 (0.2초 뒤)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, self.isCapturing else { return }
                self.refreshVisibleWindows(force: true)
                for window in self.overlayWindows {
                    guard let view = window.contentView as? SmartCaptureOverlayView else { continue }
                    view.updateHoverForPoint(NSEvent.mouseLocation, using: self.cachedWindows)
                    view.needsDisplay = true
                }
            }
        }
    }

    // MARK: - 캡처 취소
    public func cancelCapture() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCapturing else { return }
            print("[SmartScreenCapture] 사용자에 의해 캡처 취소됨 (Esc)")
            self.cleanUp()
            let handler = self.completionHandler
            self.completionHandler = nil
            handler?(nil)
        }
    }

    // MARK: - 창 캡처 완료 처리
    fileprivate func finishWithWindow(_ win: DetectedWindow) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCapturing else { return }
            print("[SmartScreenCapture] 창 선택 완료: \(win.ownerName) (\(win.windowId))")
            self.cleanUp()

            let handler = self.completionHandler
            self.completionHandler = nil

            // 오버레이가 화면에서 완전히 사라질 때까지 80ms 대기 후 실제 캡처 실행
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let targetPath = self.generateCaptureFilePath()
                self.executeWindowCapture(win: win, targetPath: targetPath) { path in
                    handler?(path)
                }
            }
        }
    }

    // MARK: - 영역 드래그 캡처 완료 처리
    fileprivate func finishWithRegion(globalCocoaRect: CGRect) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCapturing else { return }
            print("[SmartScreenCapture] 영역 드래그 완료: \(globalCocoaRect)")
            self.cleanUp()

            let handler = self.completionHandler
            self.completionHandler = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let targetPath = self.generateCaptureFilePath()
                self.executeRegionCapture(globalCocoaRect: globalCocoaRect, targetPath: targetPath) { path in
                    handler?(path)
                }
            }
        }
    }

    // MARK: - 전체 모니터 클릭 캡처 완료 처리 (빈 공간 클릭 시)
    fileprivate func finishWithScreen(_ screen: NSScreen) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCapturing else { return }
            print("[SmartScreenCapture] 모니터 빈 공간 클릭 -> 해당 모니터 전체 캡처: \(screen.frame)")
            self.cleanUp()

            let handler = self.completionHandler
            self.completionHandler = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let targetPath = self.generateCaptureFilePath()
                self.executeRegionCapture(globalCocoaRect: screen.frame, targetPath: targetPath) { path in
                    handler?(path)
                }
            }
        }
    }

    // MARK: - 화면에 열려 있는 유효 창 목록 조회 (CGWindowListCopyWindowInfo)
    /// 현재 활성 작업 공간(Space)에 실제로 존재하는 창만 추출하여 다른 Space의 창 오인식을 원천 방지
    @discardableResult
    func refreshVisibleWindows(force: Bool = false) -> [DetectedWindow] {
        let now = Date().timeIntervalSince1970
        if !force && (now - lastWindowsFetchTime) < 0.15 {
            return cachedWindows
        }

        return autoreleasepool {
            let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
            let primaryH = primaryScreen?.frame.height ?? 0
            let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
                return cachedWindows
            }
            let myPID = ProcessInfo.processInfo.processIdentifier

            var result: [DetectedWindow] = []
            for dict in infoList {
                // 1. 현재 화면에 실제로 표시 중인 창인지 확인 (다른 Space나 최소화/숨김 창 배제)
                if let onScreenObj = dict[kCGWindowIsOnscreen as String] {
                    let isOnscreen: Bool = {
                        if let b = onScreenObj as? Bool { return b }
                        if let n = onScreenObj as? NSNumber { return n.boolValue }
                        if let i = onScreenObj as? Int { return i != 0 }
                        return true
                    }()
                    if !isOnscreen { continue }
                }

                // 2. 표준 애플리케이션 창(layer == 0) 및 유틸리티 플로팅 창(layer <= 3) 추출
                let layer = dict[kCGWindowLayer as String] as? Int ?? -1
                guard layer >= 0 && layer <= 3 else { continue }

                // 3. 자체 앱 창 배제
                let pid = dict[kCGWindowOwnerPID as String] as? Int32 ?? 0
                guard pid != myPID else { continue }

                // 4. 투명 창 배제
                let alpha = dict[kCGWindowAlpha as String] as? Double ?? 1.0
                guard alpha > 0.1 else { continue }

                guard let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                      let boundsQuartz = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                    continue
                }
                // 5. 너무 작은 창(인디케이터 등) 배제
                guard boundsQuartz.width >= 100 && boundsQuartz.height >= 100 else { continue }

                let ownerName = dict[kCGWindowOwnerName as String] as? String ?? ""
                guard !ownerName.isEmpty else { continue }

                let ignoredOwners = ["Window Server", "Dock", "Spotlight", "SystemUIServer", "Control Center", "Notification Center", "Wallpaper", "screencapture", "Screenshot"]
                guard !ignoredOwners.contains(ownerName) else { continue }

                let title = dict[kCGWindowName as String] as? String ?? ""
                let winId = dict[kCGWindowNumber as String] as? CGWindowID ?? 0

                // Quartz -> Cocoa 글로벌 좌표 변환
                let cocoaX = boundsQuartz.origin.x
                let cocoaY = primaryH - (boundsQuartz.origin.y + boundsQuartz.height)
                let boundsCocoa = CGRect(x: cocoaX, y: cocoaY, width: boundsQuartz.width, height: boundsQuartz.height)

                result.append(DetectedWindow(
                    windowId: winId,
                    ownerName: ownerName,
                    title: title,
                    boundsQuartz: boundsQuartz,
                    boundsCocoa: boundsCocoa
                ))
            }

            self.cachedWindows = result
            self.lastWindowsFetchTime = now
            return result
        }
    }

    // MARK: - 오버레이 윈도우 생성 및 노출
    private func presentOverlays() {
        cleanUpOverlays()

        for screen in NSScreen.screens {
            let overlayWindow = SmartCaptureOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            overlayWindow.isReleasedWhenClosed = false
            overlayWindow.level = .screenSaver
            overlayWindow.isOpaque = false
            overlayWindow.backgroundColor = .clear
            overlayWindow.hasShadow = false
            overlayWindow.ignoresMouseEvents = false
            overlayWindow.acceptsMouseMovedEvents = true
            overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let overlayView = SmartCaptureOverlayView(
                screen: screen,
                service: self
            )
            overlayWindow.contentView = overlayView

            self.overlayWindows.append(overlayWindow)
            overlayWindow.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        if !hasPushedCursor {
            NSCursor.crosshair.push()
            hasPushedCursor = true
        }
    }

    // MARK: - 다른 오버레이 뷰들의 호버 상태 동기화
    fileprivate func syncMouseHover(currentScreen: NSScreen, mouseLocation: CGPoint) {
        // 마우스 이동 시 창 목록 실시간 업데이트 (Space 이동/창 닫힘 대응)
        let liveWindows = refreshVisibleWindows(force: false)

        for window in overlayWindows {
            guard let view = window.contentView as? SmartCaptureOverlayView else { continue }
            if view.screen == currentScreen {
                view.updateHoverForPoint(mouseLocation, using: liveWindows)
            } else {
                view.clearHover()
            }
        }
    }

    // MARK: - 자원 정리 (Double-free 및 ARC 충돌 원천 방지)
    private func cleanUp() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        defer { isCleaningUp = false }

        if hasPushedCursor {
            NSCursor.pop()
            hasPushedCursor = false
        }
        if let obs = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            spaceChangeObserver = nil
        }
        cleanUpOverlays()
        removeEscKeyMonitors()
        isCapturing = false
    }

    private func cleanUpOverlays() {
        for win in overlayWindows {
            win.contentView = nil
            win.orderOut(nil)
            win.close()
        }
        overlayWindows.removeAll()
    }

    private func registerEscKeyMonitors() {
        removeEscKeyMonitors()

        // 로컬 모니터 (앱이 활성 상태일 때)
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.cancelCapture()
                return nil
            }
            return event
        }

        // 글로벌 모니터 (포커스가 다른 곳으로 튀었을 때 안전망)
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.cancelCapture()
            }
        }
    }

    private func removeEscKeyMonitors() {
        if let m = localEscMonitor {
            NSEvent.removeMonitor(m)
            localEscMonitor = nil
        }
        if let m = globalEscMonitor {
            NSEvent.removeMonitor(m)
            globalEscMonitor = nil
        }
    }

    // MARK: - 저장 파일 경로 생성
    private func generateCaptureFilePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AIFatigueTracker/Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "capture_smart_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).png"
        return dir.appendingPathComponent(filename).path
    }

    // MARK: - 창 캡처 실행 (screencapture -l)
    private func executeWindowCapture(win: DetectedWindow, targetPath: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInteractive).async {
            // 1차 시도: screencapture -l <windowID> -o (그림자 제거) -x (무음)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-l\(win.windowId)", "-o", "-x", targetPath]

            do {
                try process.run()
                process.waitUntilExit()

                if FileManager.default.fileExists(atPath: targetPath),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: targetPath),
                   let size = attrs[.size] as? UInt64, size > 100 {
                    print("[SmartScreenCapture] 창 캡처 성공 (windowId: \(win.windowId)): \(targetPath) (\(size) bytes)")
                    DispatchQueue.main.async { completion(targetPath) }
                    return
                }
            } catch {
                print("[SmartScreenCapture] screencapture -l 오류: \(error)")
            }

            // 2차 시도 (Fallback): 창 Quartz bounds를 이용한 영역 캡처
            let q = win.boundsQuartz
            let rectArg = "-R\(Int(q.origin.x)),\(Int(q.origin.y)),\(Int(q.width)),\(Int(q.height))"
            let fallbackProcess = Process()
            fallbackProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            fallbackProcess.arguments = [rectArg, "-x", targetPath]

            do {
                try fallbackProcess.run()
                fallbackProcess.waitUntilExit()

                if FileManager.default.fileExists(atPath: targetPath),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: targetPath),
                   let size = attrs[.size] as? UInt64, size > 100 {
                    print("[SmartScreenCapture] 창 bounds Fallback 캡처 성공: \(targetPath) (\(size) bytes)")
                    DispatchQueue.main.async { completion(targetPath) }
                    return
                }
            } catch {
                print("[SmartScreenCapture] Fallback 오류: \(error)")
            }

            // 3차 시도 (최종 Fallback): CGWindowListCreateImage 네이티브 캡처
            if let cgImage = CGWindowListCreateImage(win.boundsQuartz, .optionIncludingWindow, win.windowId, [.boundsIgnoreFraming]) {
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                if let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: URL(fileURLWithPath: targetPath))
                    if FileManager.default.fileExists(atPath: targetPath) {
                        print("[SmartScreenCapture] CGWindowListCreateImage 네이티브 캡처 성공: \(targetPath)")
                        DispatchQueue.main.async { completion(targetPath) }
                        return
                    }
                }
            }

            DispatchQueue.main.async { completion(nil) }
        }
    }

    // MARK: - 사각 영역 캡처 실행 (screencapture -R)
    private func executeRegionCapture(globalCocoaRect: CGRect, targetPath: String, completion: @escaping (String?) -> Void) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let qx = Int(globalCocoaRect.origin.x)
        let qy = Int(primaryH - (globalCocoaRect.origin.y + globalCocoaRect.height))
        let qw = Int(globalCocoaRect.width)
        let qh = Int(globalCocoaRect.height)

        DispatchQueue.global(qos: .userInteractive).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-R\(qx),\(qy),\(qw),\(qh)", "-x", targetPath]

            do {
                try process.run()
                process.waitUntilExit()

                if FileManager.default.fileExists(atPath: targetPath),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: targetPath),
                   let size = attrs[.size] as? UInt64, size > 100 {
                    print("[SmartScreenCapture] 영역 캡처 성공 (-R\(qx),\(qy),\(qw),\(qh)): \(targetPath) (\(size) bytes)")
                    DispatchQueue.main.async { completion(targetPath) }
                    return
                }
            } catch {
                print("[SmartScreenCapture] screencapture -R 오류: \(error)")
            }

            DispatchQueue.main.async { completion(nil) }
        }
    }
}

// MARK: - 대화형 오버레이 뷰 (AppKit 커스텀 드로잉)
final class SmartCaptureOverlayView: NSView {
    let screen: NSScreen
    unowned let service: SmartScreenCaptureService

    private var hoveredWindow: DetectedWindow?
    private var windowAtMouseDown: DetectedWindow?
    private var dragStartPoint: CGPoint?
    private var currentDragPoint: CGPoint?
    private var isDragging = false
    private var isFlashing = false
    private var flashRect: CGRect?
    private var trackingArea: NSTrackingArea?

    init(screen: NSScreen, service: SmartScreenCaptureService) {
        self.screen = screen
        self.service = service
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, let existing = trackingArea {
            removeTrackingArea(existing)
            trackingArea = nil
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    // MARK: - 화면 캡처 전용 카메라 커서 (macOS 네이티브 스크린샷 카메라 스타일)
    static let cameraCursor: NSCursor = {
        let cursorSize = NSSize(width: 32, height: 32)
        let cursorImg = NSImage(size: cursorSize, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.saveGState()
            // 부드러운 드롭 섀도우
            ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 3.0, color: NSColor.black.withAlphaComponent(0.60).cgColor)

            let bx: CGFloat = 5.0
            let by: CGFloat = 8.0
            let bw: CGFloat = 22.0
            let bh: CGFloat = 16.0

            // 1. 카메라 상단 뷰파인더 턱
            let bumpPath = NSBezierPath()
            bumpPath.move(to: NSPoint(x: 11, y: by + bh))
            bumpPath.line(to: NSPoint(x: 13, y: by + bh + 4))
            bumpPath.line(to: NSPoint(x: 19, y: by + bh + 4))
            bumpPath.line(to: NSPoint(x: 21, y: by + bh))
            bumpPath.close()

            // 2. 셔터 버튼 (좌측 상단)
            let shutterPath = NSBezierPath(roundedRect: NSRect(x: 7, y: by + bh + 1, width: 3.5, height: 2), xRadius: 0.8, yRadius: 0.8)

            // 3. 카메라 메인 바디
            let bodyPath = NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: bw, height: bh), xRadius: 4, yRadius: 4)

            // 흰색 채우기
            NSColor.white.setFill()
            bumpPath.fill()
            bodyPath.fill()

            // 외곽선
            let darkLine = NSColor(white: 0.16, alpha: 0.95)
            darkLine.setStroke()
            bodyPath.lineWidth = 1.4
            bodyPath.stroke()
            bumpPath.lineWidth = 1.4
            bumpPath.stroke()

            darkLine.setFill()
            shutterPath.fill()

            // 4. 중앙 렌즈 (중심: x=16, y=16)
            let lensCenter = NSPoint(x: 16, y: by + bh / 2.0)
            let outerLens = NSBezierPath(ovalIn: NSRect(x: lensCenter.x - 5.5, y: lensCenter.y - 5.5, width: 11, height: 11))
            outerLens.lineWidth = 1.4
            outerLens.stroke()

            let innerLens = NSBezierPath(ovalIn: NSRect(x: lensCenter.x - 3.0, y: lensCenter.y - 3.0, width: 6.0, height: 6.0))
            NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.35, alpha: 1.0).setFill()
            innerLens.fill()

            // 렌즈 하이라이트 반사 도트
            let highlight = NSBezierPath(ovalIn: NSRect(x: lensCenter.x - 1.8, y: lensCenter.y + 0.5, width: 1.8, height: 1.8))
            NSColor.white.withAlphaComponent(0.9).setFill()
            highlight.fill()

            // 5. 플래시 센서 도트
            let flashDot = NSBezierPath(ovalIn: NSRect(x: 21.5, y: by + bh - 4.5, width: 2.0, height: 2.0))
            NSColor(calibratedRed: 0.32, green: 0.34, blue: 0.38, alpha: 1.0).setFill()
            flashDot.fill()

            ctx.restoreGState()
            return true
        }

        return NSCursor(image: cursorImg, hotSpot: NSPoint(x: 16, y: 16))
    }()

    override func resetCursorRects() {
        if hoveredWindow != nil {
            addCursorRect(bounds, cursor: SmartCaptureOverlayView.cameraCursor)
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    // MARK: - 마우스 이동 이벤트 (호버 감지 및 커서 동적 전환: 창 내부=카메라, 외부=십자)
    override func mouseMoved(with event: NSEvent) {
        guard !isDragging else { return }
        service.syncMouseHover(currentScreen: screen, mouseLocation: NSEvent.mouseLocation)
        if hoveredWindow != nil {
            SmartCaptureOverlayView.cameraCursor.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    func updateHoverForPoint(_ globalMouse: CGPoint, using windows: [DetectedWindow]) {
        // z-order 앞선 창부터 검사하여 가장 전면의 창 매칭
        let found = windows.first { $0.boundsCocoa.contains(globalMouse) }
        if hoveredWindow?.windowId != found?.windowId {
            hoveredWindow = found
            needsDisplay = true
        }
    }

    func clearHover() {
        if hoveredWindow != nil {
            hoveredWindow = nil
            needsDisplay = true
        }
    }

    // MARK: - 마우스 드래그 및 클릭 상호작용
    override func mouseDown(with event: NSEvent) {
        dragStartPoint = convert(event.locationInWindow, from: nil)
        currentDragPoint = dragStartPoint
        isDragging = false

        // 마우스 누름 시점의 윈도우 보존 (트랙패드 클릭 시 미세 떨림으로 창 선택이 풀리는 것 원천 방지)
        let globalMouse = NSEvent.mouseLocation
        let liveWindows = service.refreshVisibleWindows(force: false)
        windowAtMouseDown = hoveredWindow ?? liveWindows.first { $0.boundsCocoa.contains(globalMouse) }

        // 창 내부에서 마우스를 꾹 눌렀을 때 포인팅 핸드(pointingHand)로 전환
        if windowAtMouseDown != nil {
            NSCursor.pointingHand.set()
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentDragPoint = convert(event.locationInWindow, from: nil)
        if let start = dragStartPoint, let current = currentDragPoint {
            let dist = hypot(current.x - start.x, current.y - start.y)
            // 15pt 이상 명확히 드래그했을 때만 영역 지정 모드로 진입
            if dist > 15.0 {
                isDragging = true
                hoveredWindow = nil
                windowAtMouseDown = nil
                NSCursor.crosshair.set()
            } else if windowAtMouseDown != nil {
                // 15pt 미만 미세 이동 중에는 꾹 누른 pointingHand 유지
                NSCursor.pointingHand.set()
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartPoint = nil
            currentDragPoint = nil
            isDragging = false
            windowAtMouseDown = nil
            needsDisplay = true
        }

        // 1. 유의미한 드래그(15pt 이상)가 발생한 경우: 영역 지정 사각 캡처
        if isDragging, let start = dragStartPoint, let current = currentDragPoint {
            let dragRect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            if dragRect.width >= 15 && dragRect.height >= 15 {
                let globalCocoaRect = dragRect.offsetBy(dx: screen.frame.origin.x, dy: screen.frame.origin.y)
                service.finishWithRegion(globalCocoaRect: globalCocoaRect)
                return
            }
        }

        // 2. 클릭(Click) 판정: 창 내부 어디를 클릭하든 창 전체 캡처!
        let clickGlobal = NSEvent.mouseLocation
        let liveWindows = service.refreshVisibleWindows(force: false)
        let matchedWin = windowAtMouseDown ?? hoveredWindow ?? liveWindows.first { $0.boundsCocoa.contains(clickGlobal) }

        if let win = matchedWin {
            // 카메라 셔터 플래시 피드백 실행 후 캡처 완료
            flashShutter(for: win) { [weak self] in
                self?.service.finishWithWindow(win)
            }
            return
        }

        // 3. 빈 바탕화면 클릭 시 해당 모니터 전체 캡처
        service.finishWithScreen(screen)
    }

    // MARK: - 클릭 시 카메라 셔터 플래시 효과
    private func flashShutter(for win: DetectedWindow, completion: @escaping () -> Void) {
        let localWinRect = win.boundsCocoa.offsetBy(dx: -screen.frame.origin.x, dy: -screen.frame.origin.y)
        self.isFlashing = true
        self.flashRect = localWinRect
        self.needsDisplay = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.isFlashing = false
            self?.flashRect = nil
            self?.needsDisplay = true
            completion()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            service.cancelCapture()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - 오버레이 드로잉
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. 기본 반투명 암전 배경 (20% Dark Veil)
        NSColor(white: 0.0, alpha: 0.20).setFill()
        bounds.fill()

        let accentColor = NSColor(hex: Config.Colors.accentHex)

        // 2. 창 호버 상태 (드래그 중이 아닐 때)
        if !isDragging, let win = hoveredWindow {
            let localWinRect = win.boundsCocoa.offsetBy(dx: -screen.frame.origin.x, dy: -screen.frame.origin.y)

            // 호버된 창 내부를 투명하게 뚫어 실제 화면 본래 밝기로 노출
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            let clipPath = NSBezierPath(roundedRect: localWinRect, xRadius: 6, yRadius: 6)
            clipPath.fill()
            ctx.restoreGState()

            // 창 외곽 하이라이트 테두리
            accentColor.setStroke()
            let strokePath = NSBezierPath(roundedRect: localWinRect, xRadius: 6, yRadius: 6)
            strokePath.lineWidth = 3.0
            strokePath.stroke()

            // 창 내부 은은한 틴트
            accentColor.withAlphaComponent(0.06).setFill()
            strokePath.fill()
        }

        // 3. 클릭 시 셔터 플래시 효과
        if isFlashing, let r = flashRect {
            NSColor.white.withAlphaComponent(0.35).setFill()
            let flashPath = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            flashPath.fill()
            accentColor.setStroke()
            flashPath.lineWidth = 3.5
            flashPath.stroke()
        }

        // 4. 영역 드래그 선택 상태
        if isDragging, let start = dragStartPoint, let current = currentDragPoint {
            let dragRect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )

            // 드래그된 사각 영역 내부를 투명하게 뚫어 본래 화면 노출
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            NSBezierPath(rect: dragRect).fill()
            ctx.restoreGState()

            // 드래그 영역 외곽 테두리
            accentColor.setStroke()
            let dragStroke = NSBezierPath(rect: dragRect)
            dragStroke.lineWidth = 1.5
            dragStroke.stroke()

            // 커서 근처 크기(W × H) 뱃지 표시
            drawDimensionBadge(dragRect: dragRect, cursorPoint: current)
        }

        // 5. 화면 상단 중앙 안내 바 (주 모니터에만 표시)
        if screen == NSScreen.screens.first {
            drawTopGuideBanner()
        }
    }

    // MARK: - 드래그 크기 뱃지 드로잉
    private func drawDimensionBadge(dragRect: CGRect, cursorPoint: CGPoint) {
        let dimText = "\(Int(dragRect.width)) × \(Int(dragRect.height))"
        let dimWidth: CGFloat = 90
        let dimHeight: CGFloat = 22

        let dimX = min(max(cursorPoint.x + 12, 10), bounds.width - dimWidth - 10)
        let dimY = min(max(cursorPoint.y - dimHeight - 12, 10), bounds.height - dimHeight - 10)
        let dimRect = CGRect(x: dimX, y: dimY, width: dimWidth, height: dimHeight)

        let dimPath = NSBezierPath(roundedRect: dimRect, xRadius: 4, yRadius: 4)
        NSColor(white: 0.10, alpha: 0.90).setFill()
        dimPath.fill()
        NSColor(white: 1.0, alpha: 0.20).setStroke()
        dimPath.lineWidth = 0.8
        dimPath.stroke()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style
        ]
        let textRect = CGRect(x: dimRect.minX, y: dimRect.minY + 3.5, width: dimRect.width, height: 15)
        NSString(string: dimText).draw(in: textRect, withAttributes: attrs)
    }

    // MARK: - 상단 안내 배너 드로잉 (전구 아이콘 제거)
    private func drawTopGuideBanner() {
        let bannerWidth: CGFloat = 340
        let bannerHeight: CGFloat = 32
        let bannerRect = CGRect(
            x: (bounds.width - bannerWidth) / 2.0,
            y: bounds.height - bannerHeight - 48,
            width: bannerWidth,
            height: bannerHeight
        )

        let bannerPath = NSBezierPath(roundedRect: bannerRect, xRadius: 16, yRadius: 16)
        NSColor(white: 0.10, alpha: 0.92).setFill()
        bannerPath.fill()
        NSColor(white: 1.0, alpha: 0.22).setStroke()
        bannerPath.lineWidth = 0.8
        bannerPath.stroke()

        let bannerText = "창 클릭: 창 전체 캡처  |  드래그: 영역 지정  (취소: Esc)"
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style
        ]
        let textSize = (bannerText as NSString).size(withAttributes: attrs)
        // 위/아래 패딩이 시각적으로 완벽히 대칭되도록 수직 중앙 정렬
        let textY = bannerRect.minY + (bannerRect.height - textSize.height) / 2.0
        let textRect = CGRect(x: bannerRect.minX, y: textY, width: bannerRect.width, height: textSize.height)
        NSString(string: bannerText).draw(in: textRect, withAttributes: attrs)
    }
}
