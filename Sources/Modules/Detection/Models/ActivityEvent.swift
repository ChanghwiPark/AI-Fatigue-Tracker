import Foundation

/// 기록되는 모든 사용자 컴퓨터 활동 및 AI 세션 이벤트 모델
public struct ActivityEvent: Identifiable, Codable {
    /// 이벤트 그룹 체계 (생애주기, 집중, 전환, 입력·시스템)
    public enum EventGroup: String, Codable, CaseIterable, Identifiable {
        case lifecycle = "생애주기"
        case focus = "집중"
        case transition = "전환"
        case system = "입력·시스템"
        public var id: String { rawValue }
        public var badgeLabel: String { rawValue }
    }

    /// 환경/매체 분류 체계 ([앱인지/웹인지]만 구분)
    public enum EnvironmentCategory: String, Codable, CaseIterable, Identifiable {
        case all = "전체"
        case app = "앱"
        case web = "웹"
        case system = "시스템"
        public var id: String { rawValue }

        public var badgeLabel: String {
            switch self {
            case .all: return "전체"
            case .app: return "앱"
            case .web: return "웹"
            case .system: return "시스템"
            }
        }
    }

    /// AI 여부 필터 옵션
    public enum AIFilterOption: String, CaseIterable, Identifiable {
        case all = "전체"
        case aiOnly = "AI 활동만"
        case nonAIOnly = "일반 활동만"
        public var id: String { rawValue }
    }

    /// 4개 그룹 표준 이벤트 라벨
    public enum EventType: String, Codable, CaseIterable {
        // [1] 생애주기 (Lifecycle)
        case open = "open"                 // 앱 최초 실행, 새 창/탭 생성, 새 AI 대화 생성
        case close = "close"               // 창 닫기, 탭 닫기, 앱 종료 (AI 대화 최종 삭제 X)

        // [2] 집중 (Focus)
        case focusIn = "focus_in"          // 포커스 진입 및 순수 집중 시간 누적
        case focusOut = "focus_out"        // 포커스 이탈 및 집중 일시정지

        // [3] 전환 (Transition)
        case navigate = "navigate"         // 앱 전환, 창 전환, 탭 전환, URL 이동, 대화 전환

        // [4] 입력·시스템 (Input & System)
        case idleStart = "idle_start"      // 입력 없음 2분
        case idleEnd = "idle_end"          // 입력 복귀
        case suspend = "suspend"           // 화면 잠금, 절전
        case resume = "resume"             // 잠금 해제, 절전 해제

        /// 이벤트 그룹
        public var group: EventGroup {
            switch self {
            case .open, .close:
                return .lifecycle
            case .focusIn, .focusOut:
                return .focus
            case .navigate:
                return .transition
            case .idleStart, .idleEnd, .suspend, .resume:
                return .system
            }
        }

        /// 표준 영문 코드 (open, navigate, close 등)
        public var code: String { rawValue }

        /// 영문 라벨 (UI 표시용)
        public var label: String { rawValue }

        /// 직관적 국문 표시 라벨
        public var koreanLabel: String {
            switch self {
            case .open: return "열림"
            case .close: return "닫힘"
            case .navigate: return "탐색/전환"
            case .idleStart: return "유휴 시작"
            case .idleEnd: return "입력 복귀"
            case .suspend: return "절전/대기"
            case .resume: return "기상/복귀"
            case .focusIn: return "포커스 진입"
            case .focusOut: return "포커스 이탈"
            }
        }

        public var actionLabel: String { rawValue }

        // 하위 호환 편의 매핑 프로퍼티
        public static var focus: EventType { .focusIn }
        public static var unfocus: EventType { .focusOut }
        public static var appActivated: EventType { .focusIn }
        public static var appDeactivated: EventType { .focusOut }
        public static var appTerminated: EventType { .close }
        public static var windowChanged: EventType { .navigate }
        public static var pageVisit: EventType { .navigate }
        public static var screenLocked: EventType { .suspend }
        public static var screenUnlocked: EventType { .resume }
        public static var systemSleep: EventType { .suspend }
        public static var systemWake: EventType { .resume }
    }

    public let id: UUID
    public let timestamp: Date
    public var eventType: EventType
    public let appName: String
    public let bundleId: String
    public var windowTitle: String
    public var url: String?
    public var duration: TimeInterval?

    /// AI 활동 여부 및 도구명
    public var isAI: Bool
    public var aiTool: String?

    /// 개별 대화(Thread) 식별자 및 제목
    public var threadKey: String?
    public var threadTitle: String?

    /// 소속된 AI 세션 ID
    public var sessionId: UUID?

    // MARK: - 컨텍스트 전이 및 상세 메타데이터 필드 (새 체계 핵심 추가 필드)
    /// 포커스 이동 전 출발지 앱/창 정보
    public var fromApp: String?
    public var fromTitle: String?

    /// 포커스 이동 대상 목적지 앱/창 정보
    public var toApp: String?
    public var toTitle: String?

    /// 탐색 유형 (chat, url, tab, window)
    public var navType: String?
    public var fromDomain: String?
    public var toDomain: String?
    public var fromChatId: String?
    public var toChatId: String?

    /// 시스템 대기/복귀 유형 (lock, sleep)
    public var suspendType: String?
    public var idleDuration: TimeInterval?
    public var suspendDuration: TimeInterval?

    /// OS 윈도우 식별 번호 (CGWindowID)
    public var windowId: Int?

    /// 이벤트가 발생한 환경 분류: [앱] vs [웹] vs [시스템]
    public var environmentCategory: EnvironmentCategory {
        switch eventType {
        case .idleStart, .idleEnd, .suspend, .resume:
            return .system
        default:
            break
        }

        if eventType == .navigate && (navType == "url" || url != nil && !url!.isEmpty) {
            return .web
        }
        if url != nil && !url!.isEmpty {
            return .web
        }
        if Config.Detection.supportedBrowsers.keys.contains(bundleId) {
            return .web
        }

        return .app
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        eventType: EventType,
        appName: String,
        bundleId: String,
        windowTitle: String,
        url: String? = nil,
        duration: TimeInterval? = nil,
        isAI: Bool = false,
        aiTool: String? = nil,
        threadKey: String? = nil,
        threadTitle: String? = nil,
        sessionId: UUID? = nil,
        fromApp: String? = nil,
        fromTitle: String? = nil,
        toApp: String? = nil,
        toTitle: String? = nil,
        navType: String? = nil,
        fromDomain: String? = nil,
        toDomain: String? = nil,
        fromChatId: String? = nil,
        toChatId: String? = nil,
        suspendType: String? = nil,
        idleDuration: TimeInterval? = nil,
        suspendDuration: TimeInterval? = nil,
        windowId: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.url = url
        self.duration = duration
        self.isAI = isAI
        self.aiTool = aiTool
        self.threadKey = threadKey
        self.threadTitle = threadTitle
        self.sessionId = sessionId
        self.fromApp = fromApp
        self.fromTitle = fromTitle
        self.toApp = toApp
        self.toTitle = toTitle
        self.navType = navType
        self.fromDomain = fromDomain
        self.toDomain = toDomain
        self.fromChatId = fromChatId
        self.toChatId = toChatId
        self.suspendType = suspendType
        self.idleDuration = idleDuration
        self.suspendDuration = suspendDuration
        self.windowId = windowId
    }
}
