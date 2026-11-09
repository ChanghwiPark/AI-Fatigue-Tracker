import Foundation
import SwiftUI
import Combine

/// 실시간 디버그 모니터 윈도우에 표시될 최근 이벤트 및 세션 로그를 저장하는 링 버퍼 스토어
public final class DebugLogStore: ObservableObject {
    public static let shared = DebugLogStore()

    @Published public private(set) var events: [ActivityEvent] = []
    private let maxEvents: Int = 500

    private init() {}

    public func addEvent(_ event: ActivityEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 동일 시각(1초 이내), 동일 앱/소스, 동일 이벤트 유형 및 동일 상세 맥락의 중복 유입 차단
            if let first = self.events.first,
               first.appName == event.appName,
               first.eventType == event.eventType,
               first.windowTitle == event.windowTitle,
               first.navType == event.navType,
               abs(first.timestamp.timeIntervalSince(event.timestamp)) < 1.0 {
                print("[DebugLogStore] 동일 이벤트 중복 수신 감지 -> 무시 (\(event.windowTitle))")
                return
            }

            self.events.insert(event, at: 0)
            if self.events.count > self.maxEvents {
                self.events.removeLast()
            }
        }
    }

    /// 특정 이벤트(특히 focus_in)의 머문 시간(지속 시간) 업데이트
    public func updateEventDuration(id: UUID, duration: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let idx = self.events.firstIndex(where: { $0.id == id }) {
                self.events[idx].duration = duration
            }
        }
    }

    /// 직전 이벤트의 머문 시간(지속 시간) 업데이트 (하위 호환)
    public func updatePreviousEventDuration(_ duration: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.events.isEmpty else { return }
            self.events[0].duration = duration
        }
    }

    /// 30분 이내 세션 재개 시 그 사이 발생한 비AI 활동들에 동일 sessionId 소급 부여
    public func tagInterleavingEvents(since startDate: Date, sessionId: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for i in 0..<self.events.count {
                if self.events[i].timestamp >= startDate && self.events[i].sessionId == nil {
                    self.events[i].sessionId = sessionId
                }
            }
        }
    }

    /// 세션 제목 변경 시 해당 세션의 이전 open 이벤트의 제목도 함께 갱신
    public func updateSessionOpenEventTitle(sessionId: UUID, newTitle: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for i in 0..<self.events.count {
                if self.events[i].sessionId == sessionId && self.events[i].eventType == .open {
                    self.events[i].threadTitle = newTitle
                    self.events[i].windowTitle = "새 대화 시작: \(newTitle)"
                }
            }
        }
    }

    public func removeEvents(withIds ids: Set<UUID>) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.events.removeAll(where: { ids.contains($0.id) })
        }
    }

    public func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.events.removeAll()
        }
    }
}
