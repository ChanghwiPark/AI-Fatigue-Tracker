import SwiftUI
import AppKit

/// 메뉴 막대 상주 아이콘 뷰
/// - 주황 점이 든 원형 아이콘 (NSImage 기반으로 100% 렌더링 보장)
/// - 활성 AI 세션이 있을 때: 경과 시간(예: "1:12") 노출
/// - 활성 AI 세션이 없을 때: 아이콘만 노출
public struct MenuBarLabelView: View {
    @ObservedObject var appState: AppState = .shared
    private static let iconImage = MenuBarIconHelper.makeIcon()

    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.iconImage)

            // 세션 경과 시간 (세션 중일 때만 표시)
            if let duration = appState.activeSessionDurationString {
                Text(duration)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }
}
