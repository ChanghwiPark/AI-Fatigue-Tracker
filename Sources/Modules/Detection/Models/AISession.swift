import Foundation

/// AI 대화(Chat / Thread / Context Window) 단위의 세션 모델
/// - 규칙: open → close가 하나의 세션.
/// - 그 사이 비활성화(unfocus)되면 누적시간이 일시중지되고, 다시 활성화(focus)되면 누적시간을 이어서 계산합니다.
/// - 며칠이 지나도 닫을(close) 때까지 유지됩니다.
public struct AISession: Identifiable, Codable {
    public enum SessionState: String, Codable {
        case open = "open"         // 새로 열림
        case focusIn = "focus_in"   // 활성 (사용자가 화면을 보고 대화 중 - 누적시간 계산 중)
        case focusOut = "focus_out" // 비활성 (다른 작업 중 - 누적시간 일시중지)
        case close = "close"       // 종료 (창/탭 닫힘, 대화 종료)

        public static var focus: SessionState { .focusIn }
        public static var unfocus: SessionState { .focusOut }
    }

    public var id: UUID { sessionId }
    public let sessionId: UUID
    public var threadKey: String       // 고유 식별키 (웹 URL 경로, 창 번호/제목, 터미널 PID 등)
    public var title: String           // 대화 제목 (예: "SwiftUI 레이아웃 연구", "새 대화")
    public let toolName: String        // "Claude", "ChatGPT", "Cursor", "Claude Code" 등
    public let appName: String         // "Google Chrome", "Claude", "Terminal" 등
    public let url: String?            // 웹 대화인 경우 URL

    public var state: SessionState
    public let openedAt: Date
    public var closedAt: Date?

    /// 활성화(focus)되어 실제 사용한 누적 시간 (초) - 일시중지 시 보존되고 활성화 시 이어서 증가
    public var accumulatedFocusedDuration: TimeInterval
    /// 비활성화(unfocus)되어 대기하거나 다른 일을 한 누적 시간 (초)
    public var accumulatedUnfocusedDuration: TimeInterval
    public var lastStateChangedAt: Date

    /// 세션 생명주기 기록 (open -> focus -> unfocus -> focus -> close)
    public var lifecycleHistory: [SessionLifecycleNode]
    /// 비활성화(unfocus) 구간 동안 발생한 비AI 사이 활동 목록
    public var interleavingActivities: [InterleavingActivity]

    public init(
        sessionId: UUID = UUID(),
        threadKey: String,
        title: String,
        toolName: String,
        appName: String,
        url: String? = nil,
        state: SessionState = .open,
        openedAt: Date = Date(),
        closedAt: Date? = nil,
        accumulatedFocusedDuration: TimeInterval = 0,
        accumulatedUnfocusedDuration: TimeInterval = 0,
        lastStateChangedAt: Date = Date(),
        lifecycleHistory: [SessionLifecycleNode] = [],
        interleavingActivities: [InterleavingActivity] = []
    ) {
        self.sessionId = sessionId
        self.threadKey = threadKey
        self.title = title
        self.toolName = toolName
        self.appName = appName
        self.url = url
        self.state = state
        self.openedAt = openedAt
        self.closedAt = closedAt
        self.accumulatedFocusedDuration = accumulatedFocusedDuration
        self.accumulatedUnfocusedDuration = accumulatedUnfocusedDuration
        self.lastStateChangedAt = lastStateChangedAt
        self.lifecycleHistory = lifecycleHistory
        self.interleavingActivities = interleavingActivities
    }

    // MARK: - 하위 호환 편의 프로퍼티
    public var startTime: Date { openedAt }
    public var endTime: Date? { closedAt }
    public var aiToolsUsed: [String] { [toolName] }
    public var aiDuration: TimeInterval { accumulatedFocusedDuration }
    public var nonAiDuration: TimeInterval { accumulatedUnfocusedDuration }
    public var lastAiActivityTime: Date { lastStateChangedAt }
    public var isActive: Bool { state != .close }

    /// 총 세션 생명주기 시간 (open 시각부터 현재 또는 close 시각까지)
    public var totalLifespan: TimeInterval {
        let end = closedAt ?? Date()
        return max(0, end.timeIntervalSince(openedAt))
    }

    /// 순수 사용 집중 누적 시간 포맷 ("14:22" or "1:14:22")
    public var formattedFocusedDuration: String {
        Self.formatDuration(accumulatedFocusedDuration)
    }

    /// 비활성/사이작업 누적 시간 포맷
    public var formattedUnfocusedDuration: String {
        Self.formatDuration(accumulatedUnfocusedDuration)
    }

    /// 총 존속 기간 포맷
    public var formattedTotalLifespan: String {
        Self.formatDuration(totalLifespan)
    }

    public static func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if days > 0 {
            return "\(days)일 \(hours)시간 \(minutes)분"
        } else if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

/// 세션 상태 전이 노드
public struct SessionLifecycleNode: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let state: AISession.SessionState
    public var duration: TimeInterval?
    public let detail: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        state: AISession.SessionState,
        duration: TimeInterval? = nil,
        detail: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.state = state
        self.duration = duration
        self.detail = detail
    }
}

/// 비활성 상태 동안 발생한 비AI 작업
public struct InterleavingActivity: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let appName: String
    public let titleOrURL: String
    public var duration: TimeInterval
    public var action: String?
    public var environment: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        appName: String,
        titleOrURL: String,
        duration: TimeInterval = 0,
        action: String? = nil,
        environment: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.titleOrURL = titleOrURL
        self.duration = duration
        self.action = action
        self.environment = environment
    }
}

/// 간트 차트 표현을 위한 시간 구간 (Focus vs Unfocus)
public struct TimelineSegment: Identifiable {
    public var id = UUID()
    public let start: Date
    public let end: Date
    public let isFocus: Bool
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public init(id: UUID = UUID(), start: Date, end: Date, isFocus: Bool) {
        self.id = id
        self.start = start
        self.end = end
        self.isFocus = isFocus
    }
}

extension AISession {
    /// 세션의 생명주기 기록을 바탕으로 (start, end, isFocus) 구간들을 순차적으로 분해하여 반환
    public func computeTimelineSegments(upTo now: Date = Date()) -> [TimelineSegment] {
        var segments: [TimelineSegment] = []

        guard !lifecycleHistory.isEmpty else {
            let finish = closedAt ?? now
            if finish > openedAt {
                segments.append(TimelineSegment(start: openedAt, end: finish, isFocus: state == .focusIn))
            }
            return segments
        }

        let sortedNodes = lifecycleHistory.sorted { $0.timestamp < $1.timestamp }

        for i in 0..<sortedNodes.count {
            let node = sortedNodes[i]
            let nextDate: Date
            if i + 1 < sortedNodes.count {
                nextDate = sortedNodes[i + 1].timestamp
            } else {
                nextDate = closedAt ?? now
            }

            guard nextDate > node.timestamp else { continue }

            if node.state == .focusIn || node.state == .open {
                segments.append(TimelineSegment(start: node.timestamp, end: nextDate, isFocus: true))
            } else if node.state == .focusOut {
                segments.append(TimelineSegment(start: node.timestamp, end: nextDate, isFocus: false))
            }
            // node.state == .close (창/앱 닫힘 보존 대기) 구간은 Focus도 Unfocus도 아니므로 세그먼트를 추가하지 않음
        }

        return segments
    }
}
