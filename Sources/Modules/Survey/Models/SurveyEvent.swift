import Foundation

/// 설문 팝업의 종류 (AI 세션 기준 및 사용자 트리거)
public enum SurveyType: String, Codable, CaseIterable, Identifiable {
    case start = "start"   // AI 세션 시작 직후
    case mid = "mid"       // AI 세션이 이어지는 동안 60~120분 무작위 간격 반복
    case end = "end"       // AI 세션 종료 직후
    case diary = "diary"   // 사용자가 직접 열 때
    case nudge = "nudge"   // 그날 자발적 기록 0건 시 18:30에 1회

    public var id: String { rawValue }

    public var koreanTitle: String {
        switch self {
        case .start: return "AI 세션 시작 설문"
        case .mid: return "진행 중 피로도 점검"
        case .end: return "AI 세션 종료 설문"
        case .diary: return "다이어리 기록"
        case .nudge: return "데일리 회고 넛지"
        }
    }

    public var shortLabel: String {
        switch self {
        case .start: return "시작 설문"
        case .mid: return "중간 점검"
        case .end: return "종료 설문"
        case .diary: return "다이어리"
        case .nudge: return "미기록 넛지"
        }
    }

    public var badgeLabel: String {
        return "[\(rawValue)]"
    }

    public var badgeColorHex: String {
        switch self {
        case .start: return "#2E78D2"   // 파란색
        case .mid: return "#D97706"     // 앰버/주황
        case .end: return "#10B981"     // 에메랄드 그린
        case .diary: return "#8B5CF6"   // 보라색
        case .nudge: return "#5D7A63"   // 세이지 그린
        }
    }
}

/// 팝업에 대한 사용자 조치 또는 타임아웃 액션
public enum SurveyAction: String, Codable, CaseIterable, Identifiable {
    case response = "response"       // 설문 응답 완료
    case skip = "skip"               // 건너뛰기
    case snooze = "snooze"           // 10분 뒤에 (미루기)
    case noResponse = "no_response"  // 무응답 타임아웃 (자동 닫힘)

    public var id: String { rawValue }

    public var koreanLabel: String {
        switch self {
        case .response: return "응답"
        case .skip: return "건너뛰기"
        case .snooze: return "10분 뒤(미루기)"
        case .noResponse: return "무응답"
        }
    }
}

/// 설문 팝업 표시 및 사용자 반응 이력 모델
public struct SurveyEvent: Identifiable, Codable {
    public let id: UUID
    public let surveyType: SurveyType
    public let action: SurveyAction
    public let shownAt: Date
    public let respondedAt: Date
    public let sessionId: UUID?
    public let sessionTitle: String?
    public let aiTool: String?
    public let responsePayload: [String: String]?

    public var durationToRespond: TimeInterval {
        max(0, respondedAt.timeIntervalSince(shownAt))
    }

    public init(
        id: UUID = UUID(),
        surveyType: SurveyType,
        action: SurveyAction,
        shownAt: Date,
        respondedAt: Date = Date(),
        sessionId: UUID? = nil,
        sessionTitle: String? = nil,
        aiTool: String? = nil,
        responsePayload: [String: String]? = nil
    ) {
        self.id = id
        self.surveyType = surveyType
        self.action = action
        self.shownAt = shownAt
        self.respondedAt = respondedAt
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        self.aiTool = aiTool
        self.responsePayload = responsePayload
    }
}
