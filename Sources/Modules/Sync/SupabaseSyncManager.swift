import Foundation
import Network
import Combine

/// Supabase 배치 전송 및 오프라인 동기화 관리자
/// - 로컬 SQLite sync_queue에 쌓인 데이터를 1분마다 배치(묶음)로 Supabase REST 엔드포인트에 전송
/// - 오프라인 시 큐에 안전하게 누적되며, 네트워크 재연결 시 즉시 자동 동기화
/// - 활성 참여자 수(RPC: get_active_participants_count)를 주기적으로 가져와 메뉴 막대에 전달
public final class SupabaseSyncManager: ObservableObject {
    public static let shared = SupabaseSyncManager()

    /// Supabase에서 가져온 현재 활성 참여자 수 (가져오기 실패 또는 오프라인 시 nil)
    @Published public private(set) var activeParticipantsCount: Int? = nil
    /// 마지막 동기화 시각
    @Published public private(set) var lastSyncTime: Date? = nil
    /// 현재 미전송 대기 큐 항목 수
    @Published public private(set) var pendingQueueCount: Int = 0
    /// 네트워크 연결 상태
    @Published public private(set) var isOnline: Bool = true

    private var syncTimer: Timer?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.aifatigue.networkmonitor")
    private let syncQueue = DispatchQueue(label: "com.aifatigue.syncmanager", qos: .utility)

    private var isSyncInProgress = false

    private init() {
        startNetworkMonitoring()
        startSyncTimer()
    }

    // MARK: - 네트워크 모니터링
    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let connected = (path.status == .satisfied)
            DispatchQueue.main.async {
                let transitionedToOnline = (!self.isOnline && connected)
                self.isOnline = connected
                if transitionedToOnline {
                    print("[SupabaseSync] 네트워크 복구됨 -> 즉시 오프라인 큐 동기화 시작")
                    self.triggerSync()
                    self.fetchActiveParticipantsCount()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - 1분 주기 타이머 시작
    public func startSyncTimer() {
        DispatchQueue.main.async {
            self.syncTimer?.invalidate()
            self.syncTimer = Timer.scheduledTimer(withTimeInterval: Config.SupabaseConfig.syncInterval, repeats: true) { [weak self] _ in
                self?.triggerSync()
                self?.fetchActiveParticipantsCount()
            }
            // 최초 실행 시 2초 뒤 첫 시도
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.triggerSync()
                self.fetchActiveParticipantsCount()
            }
        }
    }

    public func triggerSync() {
        syncQueue.async { [weak self] in
            self?.syncPendingQueue()
        }
    }

    public func clearQueue() {
        LocalDatabase.shared.clearPendingQueue()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pendingQueueCount = LocalDatabase.shared.getPendingQueueCount()
        }
    }

    public func refreshQueueCount() {
        let count = LocalDatabase.shared.getPendingQueueCount()
        DispatchQueue.main.async {
            self.pendingQueueCount = count
        }
    }

    // MARK: - 큐 배치 동기화 실행
    private func syncPendingQueue() {
        guard !isSyncInProgress else { return }
        isSyncInProgress = true
        defer { isSyncInProgress = false }

        // 현재 대기 중인 큐 개수 업데이트
        let count = LocalDatabase.shared.getPendingQueueCount()
        DispatchQueue.main.async {
            self.pendingQueueCount = count
        }

        // Supabase 설정 점검 (기본 placeholder인 경우 안전하게 보류)
        let baseURL = Config.SupabaseConfig.projectURL
        let anonKey = Config.SupabaseConfig.anonKey
        guard !baseURL.contains("your-project-id") && !anonKey.contains("your-anon-key") else {
            // print("[SupabaseSync] Supabase 설정이 아직 기본 placeholder 상태입니다. 로컬 SQLite 큐에 안전히 보관 중 (\(count)건)")
            return
        }

        guard isOnline else {
            print("[SupabaseSync] 오프라인 상태: \(count)건의 데이터가 로컬 큐에 보존 중입니다.")
            return
        }

        let pendingItems = LocalDatabase.shared.fetchPendingQueue(limit: 100)
        guard !pendingItems.isEmpty else { return }

        print("[SupabaseSync] 큐 동기화 시도: \(pendingItems.count)건 전송 시작")

        // 테이블별로 그룹화
        var grouped: [String: [LocalDatabase.QueueItem]] = [:]
        for item in pendingItems {
            grouped[item.tableName, default: []].append(item)
        }

        for (table, items) in grouped {
            syncBatch(for: table, items: items, baseURL: baseURL, anonKey: anonKey)
        }
    }

    private func syncBatch(for table: String, items: [LocalDatabase.QueueItem], baseURL: String, anonKey: String) {
        if table == "activity_events_delete" {
            for item in items {
                guard let data = item.payloadJson.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]],
                      let deletedIds = json["deleted_ids"], !deletedIds.isEmpty else {
                    LocalDatabase.shared.removeQueueItems(ids: [item.id])
                    continue
                }
                let cleanIds = deletedIds.map { $0.replacingOccurrences(of: "'", with: "") }
                let inParam = "(" + cleanIds.joined(separator: ",") + ")"
                guard let deleteURL = URL(string: "\(baseURL)/rest/v1/activity_events?id=in.\(inParam)") else { continue }

                var delReq = URLRequest(url: deleteURL)
                delReq.httpMethod = "DELETE"
                delReq.setValue(anonKey, forHTTPHeaderField: "apikey")
                delReq.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

                let sem = DispatchSemaphore(value: 0)
                URLSession.shared.dataTask(with: delReq) { _, resp, err in
                    defer { sem.signal() }
                    if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        print("[SupabaseSync] ✅ 활동 기록 \(cleanIds.count)건 서버 삭제 동기화 성공 (HTTP \(http.statusCode))")
                        LocalDatabase.shared.removeQueueItems(ids: [item.id])
                    } else {
                        LocalDatabase.shared.incrementRetryCount(ids: [item.id])
                    }
                }.resume()
                sem.wait()
            }
            return
        }

        guard let url = URL(string: "\(baseURL)/rest/v1/\(table)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        // 클라이언트 UUID 기반 멱등성 보장 (중복 시 무시 또는 병합)
        if table == "activity_events" || table == "survey_responses" {
            request.setValue("resolution=ignore-duplicates, return=minimal", forHTTPHeaderField: "Prefer")
        } else {
            request.setValue("resolution=merge-duplicates, return=minimal", forHTTPHeaderField: "Prefer")
        }

        // JSON 배열로 묶음(Batch) 생성
        let jsonArrayString = "[" + items.map { $0.payloadJson }.joined(separator: ",") + "]"
        request.httpBody = jsonArrayString.data(using: .utf8)

        let ids = items.map { $0.id }

        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }

            if let error = error {
                print("[SupabaseSync] \(table) 묶음 전송 실패 (네트워크 에러): \(error.localizedDescription)")
                LocalDatabase.shared.incrementRetryCount(ids: ids)
                return
            }

            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    print("[SupabaseSync] ✅ \(table) \(items.count)건 배치 전송 성공 (HTTP \(http.statusCode))")
                    LocalDatabase.shared.removeQueueItems(ids: ids)
                    DispatchQueue.main.async {
                        self.lastSyncTime = Date()
                        self.pendingQueueCount = LocalDatabase.shared.getPendingQueueCount()
                    }
                } else {
                    print("[SupabaseSync] ⚠️ \(table) 전송 응답 코드: \(http.statusCode)")
                    LocalDatabase.shared.incrementRetryCount(ids: ids)
                }
            }
        }
        task.resume()
        semaphore.wait()
    }

    // MARK: - 활성 참여자 수 가져오기 (RPC)
    public func fetchActiveParticipantsCount() {
        let baseURL = Config.SupabaseConfig.projectURL
        let anonKey = Config.SupabaseConfig.anonKey

        // placeholder인 경우 실패로 간주하고 nil 처리 (메뉴 막대 해당 줄 숨김)
        guard !baseURL.contains("your-project-id") && !anonKey.contains("your-anon-key") else {
            DispatchQueue.main.async {
                self.activeParticipantsCount = nil
            }
            return
        }

        guard isOnline else {
            DispatchQueue.main.async {
                self.activeParticipantsCount = nil
            }
            return
        }

        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/get_active_participants_count") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                print("[SupabaseSync] 활성 참여자 수 조회 실패: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.activeParticipantsCount = nil
                }
                return
            }

            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let data = data {
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let count = Int(str) {
                    DispatchQueue.main.async {
                        self.activeParticipantsCount = count
                    }
                    return
                } else if let json = try? JSONSerialization.jsonObject(with: data) as? Int {
                    DispatchQueue.main.async {
                        self.activeParticipantsCount = json
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                self.activeParticipantsCount = nil
            }
        }.resume()
    }
}
