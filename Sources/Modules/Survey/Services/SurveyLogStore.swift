import Foundation
import Combine

/// 설문 이벤트 영구 저장 및 실시간 조회 관리자
public final class SurveyLogStore: ObservableObject {
    public static let shared = SurveyLogStore()

    @Published public private(set) var events: [SurveyEvent] = []

    private let storageKey = "ai_fatigue_survey_events"
    private let queue = DispatchQueue(label: "com.aifatigue.surveylogstore", qos: .utility)

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private init() {
        loadEvents()
    }

    /// 설문 이벤트 기록 및 저장
    public func addEvent(_ event: SurveyEvent) {
        DispatchQueue.main.async {
            self.events.insert(event, at: 0)
            self.saveEvents()

            // 통합 디버그 로그 스토어(DebugLogStore)에도 기록하여 실시간 모니터에서 관찰 가능하게 함
            let notice = ActivityEvent(
                timestamp: event.respondedAt,
                eventType: .navigate,
                appName: "설문 팝업",
                bundleId: "com.aifatigue.survey",
                windowTitle: "[\(event.surveyType.rawValue)] \(event.action.koreanLabel) (표시: \(Self.timeFormatter.string(from: event.shownAt)), 처리: \(Self.timeFormatter.string(from: event.respondedAt)))",
                isAI: true,
                aiTool: event.aiTool,
                threadTitle: event.sessionTitle,
                sessionId: event.sessionId,
                navType: "survey_\(event.action.rawValue)"
            )
            DebugLogStore.shared.addEvent(notice)

            // 로컬 SQLite 영구 보관 및 Supabase 오프라인 동기화 큐 저장
            LocalDatabase.shared.recordSurveyEvent(event)
        }
    }

    /// 당일 자발적 기록(diary 응답 완료) 건수 조회
    public func voluntaryRecordCountToday() -> Int {
        let calendar = Calendar.current
        return events.filter { event in
            event.surveyType == .diary &&
            event.action == .response &&
            calendar.isDateInToday(event.respondedAt)
        }.count
    }

    /// 모든 설문 기록 초기화
    public func clearAll() {
        DispatchQueue.main.async {
            self.events.removeAll()
            UserDefaults.standard.removeObject(forKey: self.storageKey)
        }
    }

    private func saveEvents() {
        queue.async {
            if let data = try? JSONEncoder().encode(self.events) {
                UserDefaults.standard.set(data, forKey: self.storageKey)
            }
        }
    }

    private func loadEvents() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SurveyEvent].self, from: data) {
            self.events = decoded
        }
    }
}
