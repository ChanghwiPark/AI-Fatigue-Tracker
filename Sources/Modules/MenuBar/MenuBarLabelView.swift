import SwiftUI
import AppKit

/// 메뉴 막대 상주 아이콘 뷰
/// - C-2 배터리 & 프롬프트 말풍선 아이콘 + 상태(세션 경과 시간 / 대기 시 아이콘 단독)를 NSImage로 결합 렌더링
/// - 간격을 2.9pt로 밀착하여 아이콘과 텍스트 간 시각적 일체감 완성
/// - 세션 기록 중: 경과 시간(예: "8:54")을 모노스페이스 볼드 폰트로 실시간 표시
/// - 대기 중: 텍스트 없이 단독 아이콘(24×18)만 미니멀하고 깔끔하게 표시
/// - 마지막 체크된 피로도(1~5점)에 따라 배터리 잔량(90%~15%) 및 색상 동적 반영
public struct MenuBarLabelView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var sessionManager: SessionManager = .shared

    public var previewDuration: String? = nil
    public var previewIsRecording: Bool? = nil
    public var previewFatigueScore: Int? = nil

    public init(
        previewDuration: String? = nil,
        previewIsRecording: Bool? = nil,
        previewFatigueScore: Int? = nil
    ) {
        self.previewDuration = previewDuration
        self.previewIsRecording = previewIsRecording
        self.previewFatigueScore = previewFatigueScore
    }

    private var isRecording: Bool {
        if let preview = previewIsRecording {
            return preview
        }
        guard !appState.isRecordingPaused15Min else { return false }
        return sessionManager.focusedSession != nil || appState.activeAIAppName != nil || appState.activeSessionDurationString != nil
    }

    private var durationString: String? {
        if let preview = previewDuration {
            return preview
        }
        return appState.activeSessionDurationString ?? (isRecording ? "0:00" : nil)
    }

    private var fatigueScore: Int? {
        if let preview = previewFatigueScore {
            return preview
        }
        return appState.lastFatigueScore
    }

    public var body: some View {
        Image(nsImage: MenuBarIconHelper.makeStatusIcon(
            duration: durationString,
            isRecording: isRecording,
            fatigueScore: fatigueScore
        ))
    }
}
