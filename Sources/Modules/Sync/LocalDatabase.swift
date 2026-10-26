import Foundation
import SQLite3

/// 로컬 SQLite 데이터베이스 및 오프라인 전송 큐 관리자
/// - 모든 이벤트, 세션, 설문 응답은 먼저 로컬 SQLite에 원자적으로 저장됩니다.
/// - sync_queue 테이블에 보관되어 네트워크가 끊겨도 유지되며, 앱 강제 종료 시에도 복원됩니다.
/// - 메뉴 막대 패널의 KPI (누적 사용 시간, 세션 수, 설문 기록 수)는 이 로컬 SQLite 데이터로 실시간 계산됩니다.
public final class LocalDatabase {
    public static let shared = LocalDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.aifatigue.localdatabase", qos: .utility)

    private let dbPath: String

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("AIFatigueTracker", isDirectory: true)

        if !FileManager.default.fileExists(atPath: baseDir.path) {
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }

        self.dbPath = baseDir.appendingPathComponent("local_tracker.sqlite3").path
        openDatabase()
        createTables()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    // MARK: - DB 열기 및 테이블 생성
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[LocalDB] SQLite 열기 실패: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            // 동시 쓰기 잠금 방지를 위한 busy_timeout(5초) 설정
            sqlite3_busy_timeout(db, 5000)
            executeRaw("PRAGMA busy_timeout = 5000;")
            // WAL(Write-Ahead Logging) 모드 활성화로 동시성 및 내구성 강화
            executeRaw("PRAGMA journal_mode = WAL;")
            executeRaw("PRAGMA synchronous = NORMAL;")
        }
    }

    private func executeRaw(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let e = err {
                print("[LocalDB] SQL 에러 (\(sql)): \(String(cString: e))")
                sqlite3_free(e)
            }
        }
    }

    private func createTables() {
        // 1. 참여자 캐시 테이블
        let participantsSQL = """
        CREATE TABLE IF NOT EXISTS local_participants (
            id TEXT PRIMARY KEY,
            display_name TEXT,
            enrolled_at TEXT,
            last_seen_at TEXT,
            app_version TEXT
        );
        """
        executeRaw(participantsSQL)

        // 2. 세션 테이블
        let sessionsSQL = """
        CREATE TABLE IF NOT EXISTS local_sessions (
            id TEXT PRIMARY KEY,
            participant_id TEXT,
            session_title TEXT,
            started_at TEXT,
            ended_at TEXT,
            ai_duration_sec INTEGER DEFAULT 0,
            non_ai_duration_sec INTEGER DEFAULT 0,
            ai_tools_json TEXT
        );
        """
        executeRaw(sessionsSQL)
        executeRaw("ALTER TABLE local_sessions ADD COLUMN session_title TEXT;")

        // 3. 활동 이벤트 테이블
        let eventsSQL = """
        CREATE TABLE IF NOT EXISTS local_activity_events (
            id TEXT PRIMARY KEY,
            participant_id TEXT,
            session_id TEXT,
            event_type TEXT,
            occurred_at TEXT,
            ended_at TEXT,
            duration_sec INTEGER,
            app_name TEXT,
            bundle_id TEXT,
            window_title TEXT,
            url TEXT,
            domain TEXT,
            page_title TEXT,
            is_ai INTEGER DEFAULT 0,
            ai_tool TEXT,
            browser TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_local_events_time ON local_activity_events(occurred_at);
        """
        executeRaw(eventsSQL)

        // 4. 설문 및 다이어리 응답 테이블
        let surveySQL = """
        CREATE TABLE IF NOT EXISTS local_survey_responses (
            id TEXT PRIMARY KEY,
            participant_id TEXT,
            session_id TEXT,
            session_title TEXT,
            kind TEXT,
            status TEXT,
            shown_at TEXT,
            answered_at TEXT,
            fatigue INTEGER,
            usefulness INTEGER,
            purpose_text TEXT,
            no_purpose INTEGER DEFAULT 0,
            tlx_json TEXT,
            fatigue_types_json TEXT,
            helpful_text TEXT,
            improve_text TEXT,
            capture_path TEXT,
            context_app TEXT,
            context_url TEXT,
            raw_payload_json TEXT
        );
        """
        executeRaw(surveySQL)
        executeRaw("ALTER TABLE local_survey_responses ADD COLUMN session_title TEXT;")
        executeRaw("ALTER TABLE local_survey_responses ADD COLUMN raw_payload_json TEXT;")

        // 5. 오프라인 동기화 큐 테이블
        let queueSQL = """
        CREATE TABLE IF NOT EXISTS sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            record_id TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at REAL NOT NULL,
            retry_count INTEGER DEFAULT 0,
            UNIQUE(table_name, record_id)
        );
        CREATE INDEX IF NOT EXISTS idx_sync_queue_created ON sync_queue(created_at);
        """
        executeRaw(queueSQL)
    }

    // MARK: - 1. 참여자 정보 저장 및 큐 등록
    public func recordParticipant(id: String, displayName: String, enrolledAt: Date, appVersion: String? = nil) {
        queue.async {
            let payload = SupabaseParticipantPayload(
                id: id,
                displayName: displayName,
                enrolledAt: enrolledAt,
                lastSeenAt: Date(),
                appVersion: appVersion
            )

            guard let jsonData = try? JSONEncoder().encode(payload),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

            let sql = """
            INSERT OR REPLACE INTO local_participants (id, display_name, enrolled_at, last_seen_at, app_version)
            VALUES (?, ?, ?, ?, ?);
            """
            self.bindAndStep(sql: sql, params: [payload.id, payload.display_name, payload.enrolled_at, payload.last_seen_at, payload.app_version ?? ""])

            self.enqueueSync(tableName: "participants", recordId: payload.id, payloadJson: jsonStr)
        }
    }

    // MARK: - 2. 세션 정보 저장 및 큐 등록
    public func recordSession(_ session: AISession) {
        queue.async {
            let participantId = AppState.shared.participantId
            let payload = SupabaseSessionPayload(session: session, participantId: participantId)

            guard let jsonData = try? JSONEncoder().encode(payload),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

            let toolsJson = (try? JSONEncoder().encode(session.aiToolsUsed)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

            let sql = """
            INSERT OR REPLACE INTO local_sessions (id, participant_id, session_title, started_at, ended_at, ai_duration_sec, non_ai_duration_sec, ai_tools_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            self.bindAndStep(sql: sql, params: [
                payload.id,
                payload.participant_id,
                payload.session_title ?? "",
                payload.started_at,
                payload.ended_at ?? "",
                payload.ai_duration_sec,
                payload.non_ai_duration_sec,
                toolsJson
            ])

            self.enqueueSync(tableName: "sessions", recordId: payload.id, payloadJson: jsonStr)
        }
    }

    // MARK: - 3. 활동 이벤트 저장 및 큐 등록
    public func recordActivityEvent(_ event: ActivityEvent) {
        queue.async {
            let participantId = AppState.shared.participantId
            let payload = SupabaseActivityEventPayload(event: event, participantId: participantId)

            guard let jsonData = try? JSONEncoder().encode(payload),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

            let sql = """
            INSERT OR REPLACE INTO local_activity_events (
                id, participant_id, session_id, event_type, occurred_at, ended_at, duration_sec,
                app_name, bundle_id, window_title, url, domain, page_title, is_ai, ai_tool, browser
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            self.bindAndStep(sql: sql, params: [
                payload.id,
                payload.participant_id,
                payload.session_id ?? "",
                payload.event_type,
                payload.occurred_at,
                payload.ended_at ?? "",
                payload.duration_sec ?? 0,
                payload.app_name ?? "",
                payload.bundle_id ?? "",
                payload.window_title ?? "",
                payload.url ?? "",
                payload.domain ?? "",
                payload.page_title ?? "",
                payload.is_ai ? 1 : 0,
                payload.ai_tool ?? "",
                payload.browser ?? ""
            ])

            self.enqueueSync(tableName: "activity_events", recordId: payload.id, payloadJson: jsonStr)
        }
    }

    // MARK: - 4. 설문/다이어리 응답 저장 및 큐 등록
    public func recordSurveyEvent(_ event: SurveyEvent) {
        queue.async {
            let participantId = AppState.shared.participantId
            let payload = SupabaseSurveyResponsePayload(event: event, participantId: participantId)

            guard let jsonData = try? JSONEncoder().encode(payload),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

            let tlxStr = (try? JSONEncoder().encode(payload.tlx_jsonb)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let fatTypesStr = (try? JSONEncoder().encode(payload.fatigue_types_jsonb)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let rawPayloadStr = (try? JSONEncoder().encode(payload.raw_payload_jsonb ?? [:])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

            let sql = """
            INSERT OR REPLACE INTO local_survey_responses (
                id, participant_id, session_id, session_title, kind, status, shown_at, answered_at,
                fatigue, usefulness, purpose_text, no_purpose, tlx_json, fatigue_types_json,
                helpful_text, improve_text, capture_path, context_app, context_url, raw_payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            self.bindAndStep(sql: sql, params: [
                payload.id,
                payload.participant_id,
                payload.session_id ?? "",
                payload.session_title ?? "",
                payload.kind,
                payload.status,
                payload.shown_at,
                payload.answered_at,
                payload.fatigue ?? -1,
                payload.usefulness ?? -1,
                payload.purpose_text ?? "",
                payload.no_purpose ? 1 : 0,
                tlxStr,
                fatTypesStr,
                payload.helpful_text ?? "",
                payload.improve_text ?? "",
                payload.capture_path ?? "",
                payload.context_app ?? "",
                payload.context_url ?? "",
                rawPayloadStr
            ])

            self.enqueueSync(tableName: "survey_responses", recordId: payload.id, payloadJson: jsonStr)
        }
    }

    // MARK: - 큐 관리
    private func enqueueSync(tableName: String, recordId: String, payloadJson: String) {
        let sql = """
        INSERT INTO sync_queue (table_name, record_id, payload_json, created_at, retry_count)
        VALUES (?, ?, ?, ?, 0)
        ON CONFLICT(table_name, record_id) DO UPDATE SET
            payload_json = excluded.payload_json,
            created_at = excluded.created_at;
        """
        bindAndStep(sql: sql, params: [tableName, recordId, payloadJson, Date().timeIntervalSince1970])
    }

    public struct QueueItem {
        public let id: Int64
        public let tableName: String
        public let recordId: String
        public let payloadJson: String
        public let retryCount: Int
    }

    public func fetchPendingQueue(limit: Int = 100) -> [QueueItem] {
        var items: [QueueItem] = []
        queue.sync {
            let sql = "SELECT id, table_name, record_id, payload_json, retry_count FROM sync_queue ORDER BY id ASC LIMIT ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let qId = sqlite3_column_int64(stmt, 0)
                    let table = String(cString: sqlite3_column_text(stmt, 1))
                    let recId = String(cString: sqlite3_column_text(stmt, 2))
                    let payload = String(cString: sqlite3_column_text(stmt, 3))
                    let retries = Int(sqlite3_column_int(stmt, 4))
                    items.append(QueueItem(id: qId, tableName: table, recordId: recId, payloadJson: payload, retryCount: retries))
                }
            }
            sqlite3_finalize(stmt)
        }
        return items
    }

    public func removeQueueItems(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        queue.async {
            let idList = ids.map { String($0) }.joined(separator: ",")
            let sql = "DELETE FROM sync_queue WHERE id IN (\(idList));"
            self.executeRaw(sql)
        }
    }

    public func clearPendingQueue() {
        queue.async {
            self.executeRaw("DELETE FROM sync_queue;")
        }
    }

    public func incrementRetryCount(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        queue.async {
            let idList = ids.map { String($0) }.joined(separator: ",")
            let sql = "UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id IN (\(idList));"
            self.executeRaw(sql)
        }
    }

    public func getPendingQueueCount() -> Int {
        var count = 0
        queue.sync {
            let sql = "SELECT COUNT(*) FROM sync_queue;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
        }
        return count
    }

    // MARK: - 메뉴 막대 패널 KPI 로컬 계산 메서드
    /// 1. 누적 AI 사용 시간 (초 단위)
    public func getCumulativeAISeconds() -> Int {
        var totalSec: Int = 0
        queue.sync {
            let sql = "SELECT COALESCE(SUM(ai_duration_sec), 0) FROM local_sessions;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    totalSec = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
        }
        return totalSec
    }

    /// 2. 누적 AI 세션 수
    public func getSessionCount() -> Int {
        var count: Int = 0
        queue.sync {
            let sql = "SELECT COUNT(*) FROM local_sessions;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
        }
        return count
    }

    /// 3. 누적 설문 및 자발적 피로 기록 응답 완료 건수
    public func getSurveyRecordCount() -> Int {
        var count: Int = 0
        queue.sync {
            let sql = "SELECT COUNT(*) FROM local_survey_responses WHERE status = 'answered';"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
        }
        return count
    }

    /// 4. 연구 진행 일수 (1일째 ~ 14일째)
    public func getStudyDay() -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: AppState.shared.studyStartDate)
        let now = calendar.startOfDay(for: Date())
        let diff = calendar.dateComponents([.day], from: start, to: now).day ?? 0
        return max(1, min(14, diff + 1))
    }

    // MARK: - 오늘 기록된 활동 조회 및 참여자 삭제 기능
    public struct LoggedActivityItem: Identifiable, Hashable {
        public let id: String
        public let appName: String
        public let bundleId: String
        public let windowTitle: String
        public let url: String?
        public let domain: String?
        public let occurredAt: Date
        public let durationSec: Int
        public let isAI: Bool
        public let aiTool: String?

        public var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: occurredAt)
        }
    }

    public func fetchTodayActivities() -> [LoggedActivityItem] {
        var items: [LoggedActivityItem] = []
        queue.sync {
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            let iso = ISO8601DateFormatter()
            let startStr = iso.string(from: startOfToday)

            let sql = """
            SELECT id, app_name, bundle_id, window_title, url, domain, occurred_at, duration_sec, is_ai, ai_tool
            FROM local_activity_events
            WHERE occurred_at >= ?
            ORDER BY occurred_at DESC;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (startStr as NSString).utf8String, -1, nil)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(stmt, 0))
                    let app = String(cString: sqlite3_column_text(stmt, 1))
                    let bundle = String(cString: sqlite3_column_text(stmt, 2))
                    let title = String(cString: sqlite3_column_text(stmt, 3))
                    let urlStr = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) }
                    let domainStr = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) }
                    let timeStr = String(cString: sqlite3_column_text(stmt, 6))
                    let dur = Int(sqlite3_column_int(stmt, 7))
                    let isAi = sqlite3_column_int(stmt, 8) != 0
                    let tool = sqlite3_column_text(stmt, 9).flatMap { String(cString: $0) }

                    let date = iso.date(from: timeStr) ?? Date()
                    items.append(LoggedActivityItem(
                        id: id,
                        appName: app,
                        bundleId: bundle,
                        windowTitle: title,
                        url: urlStr,
                        domain: domainStr,
                        occurredAt: date,
                        durationSec: dur,
                        isAI: isAi,
                        aiTool: tool
                    ))
                }
            }
            sqlite3_finalize(stmt)
        }
        return items
    }

    public func deleteActivityEvents(ids: [String]) {
        guard !ids.isEmpty else { return }
        queue.async {
            let quoted = ids.map { "'\($0)'" }.joined(separator: ",")

            // 1. 로컬 SQLite에서 삭제
            self.executeRaw("DELETE FROM local_activity_events WHERE id IN (\(quoted));")

            // 2. 미전송 큐에 아직 남아있다면 취소
            self.executeRaw("DELETE FROM sync_queue WHERE table_name = 'activity_events' AND record_id IN (\(quoted));")

            // 3. 이미 Supabase에 전송된 경우 서버에서도 삭제할 수 있도록 삭제 동기화 항목 큐에 등록
            let deletionPayload = "{\"deleted_ids\":[\(quoted)]}"
            let batchId = UUID().uuidString
            self.enqueueSync(tableName: "activity_events_delete", recordId: batchId, payloadJson: deletionPayload)

            // 4. 메모리 내 디버그 스토어에서도 즉시 제거
            DispatchQueue.main.async {
                let idSet = Set(ids.compactMap { UUID(uuidString: $0) })
                DebugLogStore.shared.removeEvents(withIds: idSet)
            }
        }
    }

    // MARK: - CSV 로그 내보내기 기능
    public func exportActivityEventsToCSV() -> String {
        var csv = "id,participant_id,session_id,event_type,occurred_at,ended_at,duration_sec,app_name,bundle_id,window_title,url,domain,page_title,is_ai,ai_tool,browser\n"
        queue.sync {
            let sql = "SELECT id, participant_id, session_id, event_type, occurred_at, ended_at, duration_sec, app_name, bundle_id, window_title, url, domain, page_title, is_ai, ai_tool, browser FROM local_activity_events ORDER BY occurred_at ASC;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String] = []
                    for col in 0..<16 {
                        if let text = sqlite3_column_text(stmt, Int32(col)) {
                            let raw = String(cString: text).replacingOccurrences(of: "\"", with: "\"\"")
                            row.append("\"\(raw)\"")
                        } else {
                            row.append("\"\"")
                        }
                    }
                    csv += row.joined(separator: ",") + "\n"
                }
            }
            sqlite3_finalize(stmt)
        }
        return csv
    }

    public func exportSessionsToCSV() -> String {
        var csv = "id,participant_id,session_title,started_at,ended_at,ai_duration_sec,non_ai_duration_sec,ai_tools\n"
        queue.sync {
            let sql = "SELECT id, participant_id, session_title, started_at, ended_at, ai_duration_sec, non_ai_duration_sec, ai_tools_json FROM local_sessions ORDER BY started_at ASC;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String] = []
                    for col in 0..<8 {
                        if let text = sqlite3_column_text(stmt, Int32(col)) {
                            let raw = String(cString: text).replacingOccurrences(of: "\"", with: "\"\"")
                            row.append("\"\(raw)\"")
                        } else {
                            row.append("\"\"")
                        }
                    }
                    csv += row.joined(separator: ",") + "\n"
                }
            }
            sqlite3_finalize(stmt)
        }
        return csv
    }

    public func exportSurveyResponsesToCSV() -> String {
        var csv = "id,participant_id,session_id,session_title,kind,status,shown_at,answered_at,fatigue,usefulness,purpose_text,no_purpose,tlx_json,fatigue_types_json,helpful_text,improve_text,capture_path,context_app,context_url,raw_payload_json\n"
        queue.sync {
            let sql = "SELECT id, participant_id, session_id, session_title, kind, status, shown_at, answered_at, fatigue, usefulness, purpose_text, no_purpose, tlx_json, fatigue_types_json, helpful_text, improve_text, capture_path, context_app, context_url, raw_payload_json FROM local_survey_responses ORDER BY answered_at ASC;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String] = []
                    for col in 0..<20 {
                        if let text = sqlite3_column_text(stmt, Int32(col)) {
                            let raw = String(cString: text).replacingOccurrences(of: "\"", with: "\"\"")
                            row.append("\"\(raw)\"")
                        } else {
                            row.append("\"\"")
                        }
                    }
                    csv += row.joined(separator: ",") + "\n"
                }
            }
            sqlite3_finalize(stmt)
        }
        return csv
    }

    // MARK: - SQLite 바인딩 헬퍼
    private func bindAndStep(sql: String, params: [Any]) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for (index, val) in params.enumerated() {
                let idx = Int32(index + 1)
                if let str = val as? String {
                    sqlite3_bind_text(stmt, idx, (str as NSString).utf8String, -1, nil)
                } else if let num = val as? Int {
                    sqlite3_bind_int(stmt, idx, Int32(num))
                } else if let dbl = val as? Double {
                    sqlite3_bind_double(stmt, idx, dbl)
                } else if let b = val as? Bool {
                    sqlite3_bind_int(stmt, idx, b ? 1 : 0)
                } else {
                    sqlite3_bind_text(stmt, idx, "", -1, nil)
                }
            }
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[LocalDB] 실행 실패 (\(sql)): \(String(cString: sqlite3_errmsg(db)))")
            }
        } else {
            print("[LocalDB] 쿼리 준비 실패 (\(sql)): \(String(cString: sqlite3_errmsg(db)))")
        }
        sqlite3_finalize(stmt)
    }
}
