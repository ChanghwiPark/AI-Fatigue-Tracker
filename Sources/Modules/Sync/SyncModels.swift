import Foundation

// MARK: - Supabase 전송용 DTO (Data Transfer Objects)

/// participants 테이블 전송 모델
public struct SupabaseParticipantPayload: Codable {
    public let id: String
    public let display_name: String
    public let enrolled_at: String
    public let last_seen_at: String
    public let app_version: String?

    public init(id: String, displayName: String, enrolledAt: Date, lastSeenAt: Date = Date(), appVersion: String? = nil) {
        let iso = ISO8601DateFormatter()
        self.id = id
        self.display_name = displayName
        self.enrolled_at = iso.string(from: enrolledAt)
        self.last_seen_at = iso.string(from: lastSeenAt)
        self.app_version = appVersion ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

/// sessions 테이블 전송 모델
public struct SupabaseSessionPayload: Codable {
    public let id: String
    public let participant_id: String
    public let session_title: String?
    public let started_at: String
    public let ended_at: String?
    public let ai_duration_sec: Int
    public let non_ai_duration_sec: Int
    public let ai_tools: [String]

    public init(session: AISession, participantId: String) {
        let iso = ISO8601DateFormatter()
        self.id = session.sessionId.uuidString
        self.participant_id = participantId
        self.session_title = session.title.isEmpty ? nil : session.title
        self.started_at = iso.string(from: session.openedAt)
        if let closed = session.closedAt {
            self.ended_at = iso.string(from: closed)
        } else {
            self.ended_at = nil
        }
        self.ai_duration_sec = Int(session.accumulatedFocusedDuration)
        self.non_ai_duration_sec = Int(session.accumulatedUnfocusedDuration)
        self.ai_tools = session.aiToolsUsed
    }
}

/// activity_events 테이블 전송 모델
public struct SupabaseActivityEventPayload: Codable {
    public let id: String
    public let participant_id: String
    public let session_id: String?
    public let event_type: String
    public let occurred_at: String
    public let ended_at: String?
    public let duration_sec: Int?
    public let app_name: String?
    public let bundle_id: String?
    public let window_title: String?
    public let url: String?
    public let domain: String?
    public let page_title: String?
    public let is_ai: Bool
    public let ai_tool: String?
    public let browser: String?

    public init(event: ActivityEvent, participantId: String) {
        let iso = ISO8601DateFormatter()
        self.id = event.id.uuidString
        self.participant_id = participantId
        self.session_id = event.sessionId?.uuidString

        // 표준 event_type 매핑
        var typeStr = "window_changed"
        if let susp = event.suspendType {
            if susp == "lock" { typeStr = "screen_locked" }
            else if susp == "unlock" { typeStr = "screen_unlocked" }
            else if susp == "sleep" { typeStr = "system_sleep" }
            else if susp == "wake" { typeStr = "system_wake" }
            else if susp == "pause_15m" {
                typeStr = (event.eventType == .suspend ? "recording_paused" : "recording_resumed")
            }
            else if susp == "mute_1h" {
                typeStr = (event.eventType == .suspend ? "popup_muted_1h" : "popup_unmuted_1h")
            }
        } else {
            switch event.eventType {
            case .idleStart:
                typeStr = "idle_start"
            case .idleEnd:
                typeStr = "idle_end"
            case .close:
                typeStr = "app_terminated"
            case .open, .focusIn:
                typeStr = "app_activated"
            case .focusOut:
                typeStr = "app_deactivated"
            case .navigate:
                if event.navType == "url" || (event.url != nil && !event.url!.isEmpty) {
                    typeStr = "page_visit"
                } else {
                    typeStr = "window_changed"
                }
            case .suspend:
                typeStr = "system_sleep"
            case .resume:
                typeStr = "system_wake"
            }
        }
        self.event_type = typeStr
        self.occurred_at = iso.string(from: event.timestamp)

        let dur = event.duration ?? event.suspendDuration ?? event.idleDuration ?? 0
        if dur > 0 {
            self.duration_sec = Int(dur)
            self.ended_at = iso.string(from: event.timestamp.addingTimeInterval(dur))
        } else {
            self.duration_sec = nil
            self.ended_at = nil
        }

        self.app_name = event.appName.isEmpty ? nil : event.appName
        self.bundle_id = event.bundleId.isEmpty ? nil : event.bundleId
        self.window_title = event.windowTitle.isEmpty ? nil : event.windowTitle
        self.url = event.url

        if let u = event.url, let host = URL(string: u)?.host {
            self.domain = host
        } else if let toD = event.toDomain, !toD.isEmpty {
            self.domain = toD
        } else {
            self.domain = nil
        }

        self.page_title = event.windowTitle.isEmpty ? nil : event.windowTitle
        self.is_ai = event.isAI
        self.ai_tool = event.aiTool

        if Config.Detection.supportedBrowsers.keys.contains(event.bundleId) {
            self.browser = event.appName
        } else {
            self.browser = nil
        }
    }
}

/// survey_responses 테이블 전송 모델
public struct SupabaseSurveyResponsePayload: Codable {
    public let id: String
    public let participant_id: String
    public let session_id: String?
    public let session_title: String?
    public let kind: String
    public let status: String
    public let shown_at: String
    public let answered_at: String
    public let fatigue: Int?
    public let usefulness: Int?
    public let purpose_text: String?
    public let no_purpose: Bool
    public let tlx_jsonb: [String: Double]?
    public let fatigue_types_jsonb: [[String: AnyCodable]]?
    public let helpful_text: String?
    public let improve_text: String?
    public let capture_path: String?
    public let context_app: String?
    public let context_url: String?
    public let raw_payload_jsonb: [String: String]?

    public init(event: SurveyEvent, participantId: String) {
        let iso = ISO8601DateFormatter()
        self.id = event.id.uuidString
        self.participant_id = participantId
        self.session_id = event.sessionId?.uuidString
        self.kind = event.surveyType.rawValue

        switch event.action {
        case .response:
            self.status = "answered"
        case .skip:
            self.status = "skipped"
        case .snooze:
            self.status = "snoozed"
        case .noResponse:
            self.status = "timeout"
        }

        self.shown_at = iso.string(from: event.shownAt)
        self.answered_at = iso.string(from: event.respondedAt)

        let payload = event.responsePayload ?? [:]

        self.session_title = event.sessionTitle ?? payload["session_title"]
        self.raw_payload_jsonb = payload.isEmpty ? nil : payload

        if let fStr = payload["fatigue_score"], let fVal = Int(fStr) {
            self.fatigue = fVal
        } else {
            self.fatigue = nil
        }

        if let uStr = payload["usefulness_score"], let uVal = Int(uStr) {
            self.usefulness = uVal
        } else {
            self.usefulness = nil
        }

        self.purpose_text = payload["purpose_final"] ?? payload["purpose_custom_text"]
        self.no_purpose = (payload["purpose_is_none"] == "true")

        // TLX JSON
        if payload["tlx_mental"] != nil {
            var tlx: [String: Double] = [:]
            tlx["mental"] = Double(payload["tlx_mental"] ?? "") ?? 0
            tlx["physical"] = Double(payload["tlx_physical"] ?? "") ?? 0
            tlx["temporal"] = Double(payload["tlx_temporal"] ?? "") ?? 0
            tlx["performance"] = Double(payload["tlx_performance"] ?? "") ?? 0
            tlx["effort"] = Double(payload["tlx_effort"] ?? "") ?? 0
            tlx["frustration"] = Double(payload["tlx_frustration"] ?? "") ?? 0
            self.tlx_jsonb = tlx
        } else {
            self.tlx_jsonb = nil
        }

        // fatigue_types_jsonb 형식: [{"dimension":"cognitive","chips":["결과가 너무 길거나 많아요"],"free_text":"..."}]
        if let catsStr = payload["fatigue_categories"], !catsStr.isEmpty {
            let catList = catsStr.components(separatedBy: "|")
            var arr: [[String: AnyCodable]] = []
            for cat in catList {
                let chipsStr = payload["fatigue_\(cat)_chips"] ?? ""
                let chips = chipsStr.isEmpty ? [] : chipsStr.components(separatedBy: "|")
                let text = payload["fatigue_\(cat)_custom_text"] ?? ""

                var item: [String: AnyCodable] = [:]
                item["dimension"] = AnyCodable(cat)
                item["chips"] = AnyCodable(chips)
                item["free_text"] = AnyCodable(text)
                arr.append(item)
            }
            self.fatigue_types_jsonb = arr
        } else {
            self.fatigue_types_jsonb = nil
        }

        self.helpful_text = payload["help_final"] ?? payload["help_custom_text"]
        self.improve_text = payload["how_to_reduce_fatigue"]
        self.capture_path = payload["capture_local_path"]
        self.context_app = payload["capture_app_name"] ?? event.aiTool
        self.context_url = payload["capture_url"]
    }
}

// MARK: - 임의의 JSON 값을 Codable로 인코딩하기 위한 AnyCodable 래퍼
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let arrayVal = try? container.decode([String].self) {
            value = arrayVal
        } else {
            value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let arrayVal = value as? [String] {
            try container.encode(arrayVal)
        } else if let dictVal = value as? [String: AnyCodable] {
            try container.encode(dictVal)
        } else {
            try container.encode("\(value)")
        }
    }
}
