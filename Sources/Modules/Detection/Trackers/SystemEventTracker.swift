import Foundation
import AppKit

/// 화면 잠금/해제 및 시스템 잠자기/깨우기 이벤트를 감지합니다.
public final class SystemEventTracker {
    public static let shared = SystemEventTracker()

    public var onScreenLocked: (() -> Void)?
    public var onScreenUnlocked: ((TimeInterval) -> Void)?
    public var onSystemSleep: (() -> Void)?
    public var onSystemWake: ((TimeInterval) -> Void)?

    private var lockStartTime: Date?
    private var sleepStartTime: Date?

    /// 화면 잠금 상태 여부
    public var isLocked: Bool { lockStartTime != nil }
    /// 시스템 절전(Sleep) 상태 여부
    public var isSleeping: Bool { sleepStartTime != nil }
    /// 잠금 또는 절전 여부
    public var isLockedOrSleeping: Bool { isLocked || isSleeping }

    private init() {}

    public func startMonitoring() {
        let distCenter = DistributedNotificationCenter.default()
        let wsCenter = NSWorkspace.shared.notificationCenter

        // 1. 화면 잠금
        distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lockStartTime = Date()
            self?.onScreenLocked?()
        }

        // 2. 화면 잠금 해제
        distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let duration = self?.lockStartTime.map { max(0, Date().timeIntervalSince($0)) } ?? 0
            self?.lockStartTime = nil
            self?.onScreenUnlocked?(duration)
        }

        // 3. 시스템 잠자기
        wsCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sleepStartTime = Date()
            self?.onSystemSleep?()
        }

        // 4. 시스템 깨우기
        wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let duration = self?.sleepStartTime.map { max(0, Date().timeIntervalSince($0)) } ?? 0
            self?.sleepStartTime = nil
            self?.onSystemWake?(duration)
        }
    }
}
