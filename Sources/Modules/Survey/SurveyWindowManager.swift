import AppKit
import SwiftUI

/// 설문 팝업 패널 윈도우 생성, 위치 지정 및 슬라이드 애니메이션 관리자
public final class SurveyWindowManager: ObservableObject {
    public static let shared = SurveyWindowManager()

    @Published public private(set) var isShowing: Bool = false
    public private(set) var currentPanel: SurveyPanel?
    private var targetX: CGFloat = 0
    private var isSlideInComplete: Bool = false
    public private(set) var isDismissing: Bool = false

    private init() {}

    /// 설문 팝업 윈도우를 주 모니터 우상단에 슬라이드 인 애니메이션과 함께 표시
    public func showPopup(
        type: SurveyType,
        session: AISession? = nil,
        onAction: @escaping (SurveyAction, [String: String]?) -> Void
    ) {
        DispatchQueue.main.async {
            self.isDismissing = false
            // 이미 열려 있는 창이 있다면 모두 닫고 새로 엽니다.
            for w in NSApp.windows where w is SurveyPanel {
                w.orderOut(nil)
            }
            self.currentPanel = nil

            guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }

            let visibleFrame = screen.visibleFrame
            let screenFrame = screen.frame

            // mid 및 nudge(07장면) 팝업은 340px, 그 외는 372px
            let targetWidth: CGFloat = (type == .mid || type == .nudge ? Config.Survey.popupMidWidth : Config.Survey.popupDefaultWidth)
            let rightMargin: CGFloat = 14.0
            let topMarginBelowMenuBar: CGFloat = 12.0
            let bottomMargin: CGFloat = 14.0

            // X 좌표: 오른쪽 여백 14px 고려
            let targetX = visibleFrame.maxX - rightMargin - targetWidth

            // Y 상단 기준점: 메뉴 막대 아래 12px
            let topY = visibleFrame.maxY - topMarginBelowMenuBar

            // 화면을 넘지 않도록 최대 가용 높이 계산
            let maxAvailableHeight = max(200.0, topY - (visibleFrame.minY + bottomMargin))
            let chromeOverhead: CGFloat = 150.0
            let maxScrollHeight = max(100.0, maxAvailableHeight - chromeOverhead)

            let estimatedContentHeight: CGFloat = {
                switch type {
                case .mid: return 195.0
                case .start: return 310.0
                case .end: return 480.0
                case .diary: return 220.0
                case .nudge: return 110.0
                }
            }()
            let initialHeight = min(estimatedContentHeight + chromeOverhead, maxAvailableHeight)

            let popupView = SurveyPopupView(
                surveyType: type,
                sessionTitle: session?.title,
                aiTool: session?.toolName,
                maxContentHeight: maxScrollHeight,
                onHeightChanged: { [weak self] newTotalHeight in
                    self?.updateHeight(newTotalHeight)
                },
                onAction: { action, payload in
                    onAction(action, payload)
                }
            )

            let hostingView = SurveyHostingView(rootView: popupView)
            hostingView.autoresizingMask = [.width, .height]
            let targetY = topY - initialHeight
            let targetFrame = NSRect(x: targetX, y: targetY, width: targetWidth, height: initialHeight)
            // 시작 위치: 화면 오른쪽 바깥
            let startFrame = NSRect(x: screenFrame.maxX + 20, y: targetY, width: targetWidth, height: initialHeight)

            self.targetX = targetX
            self.isSlideInComplete = false

            let panel = SurveyPanel(contentRect: startFrame)
            panel.contentView = hostingView
            panel.alphaValue = 1.0

            // 비활성 상태로 화면에 띄움 (포커스 탈취 방지)
            panel.orderFrontRegardless()

            // 오른쪽에서 밀려 들어오는 애니메이션 (Slide In)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            } completionHandler: {
                self.isSlideInComplete = true
            }

            self.currentPanel = panel
            self.isShowing = true
        }
    }

    /// 내부 폼 높이 변경 시(피로 심층 전개, 카테고리 선택 등) 창 크기를 부드럽게 조정
    /// 사용자가 창을 드래그하여 이동했을 경우 현재 창의 X 위치와 상단 Y 위치를 그대로 유지
    public func updateHeight(_ totalCardHeight: CGFloat) {
        DispatchQueue.main.async {
            // 창 닫기(퇴장) 애니메이션이 진행 중일 때는 높이/위치 조정을 전면 차단하여 퇴장 애니메이션 중단 방지
            guard !self.isDismissing,
                  let panel = self.currentPanel,
                  let screen = panel.screen ?? NSScreen.screens.first ?? NSScreen.main else { return }

            let visibleFrame = screen.visibleFrame
            let bottomMargin: CGFloat = 14.0

            let currentFrame = panel.frame
            let targetWidth = currentFrame.width

            // 사용자가 드래그하여 이동했을 수 있으므로 슬라이드인 완료 후에는 현재 X 위치 유지,
            // 슬라이드인이 아직 진행 중이거나 화면 밖(maxX 이상)에 있다면 targetX를 사용하여 창이 화면 바깥에 고정되는 현상 방지
            let currentX: CGFloat = {
                if !self.isSlideInComplete || currentFrame.origin.x >= visibleFrame.maxX - 10 {
                    return self.targetX
                }
                return currentFrame.origin.x
            }()
            let currentTopY = currentFrame.maxY

            let maxAvailableHeight = max(200.0, currentTopY - (visibleFrame.minY + bottomMargin))
            // totalCardHeight는 카드 전체(헤더+본문+푸터+외곽 마진)의 실측 높이이므로 정확한 크기 반영
            let totalWindowHeight = min(ceil(totalCardHeight), maxAvailableHeight)

            let targetY = currentTopY - totalWindowHeight
            let newFrame = NSRect(x: currentX, y: targetY, width: targetWidth, height: totalWindowHeight)

            if abs(currentFrame.height - totalWindowHeight) > 1.0 || (!self.isSlideInComplete && abs(currentFrame.origin.x - currentX) > 1.0) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(newFrame, display: true)
                }
            }
        }
    }

    /// 오른쪽으로 밀려 나가며 팝업 닫기 (Slide Out 애니메이션)
    public func dismissPopup(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            // 이미 닫히는 중이면 중복 실행 방지
            guard !self.isDismissing else { return }

            // 현재 화면에 실제로 보이는 SurveyPanel 찾기
            let visiblePanels: [SurveyPanel] = NSApp.windows.compactMap { $0 as? SurveyPanel }.filter { $0.isVisible }
            let panelToClose: SurveyPanel? = (self.currentPanel?.isVisible == true ? self.currentPanel : nil) ?? visiblePanels.first

            guard let panel = panelToClose else {
                print("[SurveyWindowManager] 닫을 열려 있는 SurveyPanel 없음 -> 완료 처리")
                self.currentPanel = nil
                self.isShowing = false
                completion?()
                return
            }

            self.isDismissing = true
            print("[SurveyWindowManager] 팝업 닫기(Slide-out) 애니메이션 시작 (panel: \(panel))")
            SpeechInputManager.shared.stopRecording()

            // 안전 타이머: 애니메이션 콜백 누락 시에도 0.5초 뒤 자동 잠금 해제
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if self?.isDismissing == true {
                    self?.isDismissing = false
                }
            }

            let screen = panel.screen ?? NSScreen.screens.first ?? NSScreen.main
            let exitX = (screen?.frame.maxX ?? panel.frame.maxX) + 20
            let exitFrame = NSRect(x: exitX, y: panel.frame.origin.y, width: panel.frame.width, height: panel.frame.height)

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(exitFrame, display: true)
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                // 화면의 모든 SurveyPanel을 orderOut 및 close하여 확실히 정리
                for w in NSApp.windows where w is SurveyPanel {
                    w.orderOut(nil)
                    w.alphaValue = 1.0
                    w.close()
                }
                self.currentPanel = nil
                self.isShowing = false
                self.isDismissing = false
                print("[SurveyWindowManager] 팝업 닫기 완료 (모든 패널 정리됨)")
                completion?()
            })
        }
    }

    /// 자발적 피로 기록(Scene 06 - ⌥⌘S 또는 메뉴 막대 "지금 피로 기록하기") 팝업 띄우기
    public func showVoluntaryPopup(context: VoluntaryCaptureContext) {
        DispatchQueue.main.async {
            self.isDismissing = false
            for w in NSApp.windows where w is SurveyPanel {
                w.orderOut(nil)
                w.close()
            }
            self.currentPanel = nil

            guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }

            let visibleFrame = screen.visibleFrame
            let screenFrame = screen.frame

            let targetWidth: CGFloat = Config.Survey.popupDefaultWidth // 372px
            let rightMargin: CGFloat = 14.0
            let topMarginBelowMenuBar: CGFloat = 12.0
            let bottomMargin: CGFloat = 14.0

            let targetX = visibleFrame.maxX - rightMargin - targetWidth
            let topY = visibleFrame.maxY - topMarginBelowMenuBar

            let maxAvailableHeight = max(200.0, topY - (visibleFrame.minY + bottomMargin))
            let chromeOverhead: CGFloat = 150.0
            let maxScrollHeight = max(100.0, maxAvailableHeight - chromeOverhead)

            let estimatedHeight: CGFloat = context.localImagePath != nil ? 440.0 : 340.0
            let initialHeight = min(estimatedHeight + chromeOverhead, maxAvailableHeight)

            let popupView = VoluntaryRecordPopupView(
                context: context,
                maxContentHeight: maxScrollHeight,
                onHeightChanged: { [weak self] newTotalHeight in
                    self?.updateHeight(newTotalHeight)
                },
                onRetakeCapture: { [weak self] callback in
                    guard let self = self else { return }
                    let activePanel = (self.currentPanel?.isVisible == true ? self.currentPanel : nil) ?? NSApp.windows.compactMap({ $0 as? SurveyPanel }).first(where: { $0.isVisible })
                    print("[VoluntaryRecord] 전체 캡처 다시 시도 (패널 숨김)")
                    activePanel?.orderOut(nil)
                    VoluntaryRecordService.shared.retakeCapture { newImagePath in
                        activePanel?.alphaValue = 1.0
                        activePanel?.orderFrontRegardless()
                        if let newPath = newImagePath {
                            print("[VoluntaryRecord] 새 전체 캡처 적용: \(newPath)")
                        } else {
                            print("[VoluntaryRecord] 캡처 취소됨 -> 기존 패널 복원")
                        }
                        callback(newImagePath)
                    }
                },
                onRetakeAreaCapture: { [weak self] callback in
                    guard let self = self else { return }
                    let activePanel = (self.currentPanel?.isVisible == true ? self.currentPanel : nil) ?? NSApp.windows.compactMap({ $0 as? SurveyPanel }).first(where: { $0.isVisible })
                    print("[VoluntaryRecord] 영역 캡처 시작 (패널 숨김, activePanel: \(String(describing: activePanel)))")
                    activePanel?.orderOut(nil)
                    VoluntaryRecordService.shared.retakeAreaCapture { newImagePath in
                        activePanel?.alphaValue = 1.0
                        activePanel?.orderFrontRegardless()
                        if let newPath = newImagePath {
                            print("[VoluntaryRecord] 새 영역 캡처 적용: \(newPath)")
                        } else {
                            print("[VoluntaryRecord] 영역 캡처 취소됨 -> 기존 패널 복원")
                        }
                        callback(newImagePath)
                    }
                },
                onCancel: { [weak self] in
                    print("[VoluntaryRecord] onCancel 호출됨 -> dismissPopup 실행")
                    self?.dismissPopup()
                },
                onSave: { [weak self] finalContext, payload in
                    // 1. 설문 이벤트 영구 기록 (자발적 피로 기록 diary)
                    let event = SurveyEvent(
                        surveyType: .diary,
                        action: .response,
                        shownAt: finalContext.capturedAt,
                        respondedAt: Date(),
                        sessionId: finalContext.sessionId,
                        sessionTitle: finalContext.sessionTitle,
                        aiTool: finalContext.appName,
                        responsePayload: payload
                    )
                    SurveyLogStore.shared.addEvent(event)

                    // 2. 캡처 이미지 Supabase Storage 비동기 업로드 시도
                    if let imgPath = finalContext.localImagePath {
                        SupabaseStorageUploader.shared.uploadScreenshot(localPath: imgPath) { success, storagePath in
                            print("[VoluntaryRecord] Supabase 스토리지 결과: \(success ? "성공 (\(storagePath ?? ""))" : "실패(로컬유지)")")
                        }
                    }

                    // 3. 팝업 창 닫기 및 "저장됨" 토스트 알림 띄우기
                    self?.dismissPopup {
                        SaveConfirmationToast.shared.show(message: "저장됨", detail: "피로 순간 기록이 안전하게 저장되었습니다.")
                    }
                }
            )

            let hostingView = SurveyHostingView(rootView: popupView)
            hostingView.autoresizingMask = [.width, .height]
            let targetY = topY - initialHeight
            let targetFrame = NSRect(x: targetX, y: targetY, width: targetWidth, height: initialHeight)
            let startFrame = NSRect(x: screenFrame.maxX + 20, y: targetY, width: targetWidth, height: initialHeight)

            self.targetX = targetX
            self.isSlideInComplete = false

            let panel = SurveyPanel(contentRect: startFrame)
            panel.contentView = hostingView
            panel.alphaValue = 1.0

            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            } completionHandler: {
                self.isSlideInComplete = true
            }

            self.currentPanel = panel
            self.isShowing = true
        }
    }
}
