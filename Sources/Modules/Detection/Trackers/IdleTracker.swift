import Foundation
import CoreGraphics

/// 키보드 및 마우스 입력을 모니터링하여 5분 이상 미입력 시 자리 비움(idle_start / idle_end)을 판별합니다.
public final class IdleTracker {
    public static let shared = IdleTracker()

    public var onIdleStart: (() -> Void)?
    public var onIdleEnd: ((TimeInterval) -> Void)?

    private var isCurrentlyIdle: Bool = false
    private var idleStartTime: Date?
    private var timer: Timer?

    /// 현재 사용자가 자리 비움(유휴) 상태인지 여부
    public var isIdle: Bool {
        return isCurrentlyIdle || getIdleTime() >= Config.Detection.idleThreshold
    }

    private init() {}

    public func startMonitoring() {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkIdleState()
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// 현재 유휴 시간(초) 확인
    public func getIdleTime() -> Double {
        // CGEventType(rawValue: ~0)!은 모든 입력(키보드, 마우스 이동/클릭 등)의 마지막 발생 시각을 반환
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func checkIdleState() {
        let idleSeconds = getIdleTime()

        if idleSeconds >= Config.Detection.idleThreshold {
            if !isCurrentlyIdle {
                isCurrentlyIdle = true
                idleStartTime = Date().addingTimeInterval(-idleSeconds)
                onIdleStart?()
            }
        } else if idleSeconds < 5.0 {
            if isCurrentlyIdle {
                isCurrentlyIdle = false
                let duration = idleStartTime.map { max(0, Date().timeIntervalSince($0)) } ?? idleSeconds
                idleStartTime = nil
                onIdleEnd?(duration)
            }
        }
    }
}
