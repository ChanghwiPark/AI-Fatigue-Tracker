import Foundation
import SwiftUI
import AppKit

/// 앱 전역 상태, 참여자 식별 정보, 메뉴 막대 노출 데이터를 관리합니다.
public final class AppState: ObservableObject {
    public static let shared = AppState()

    private enum Keys {
        static let participantId = "ai_fatigue_participant_id"
        static let participantName = "ai_fatigue_participant_name"
        static let hasCompletedOnboarding = "ai_fatigue_has_completed_onboarding"
        static let studyStartDate = "ai_fatigue_study_start_date"
    }

    // MARK: - 참여자 식별 정보
    /// 기기 고유의 UUID (첫 실행 시 자동 생성되어 영구 저장)
    @Published public private(set) var participantId: String
    /// 연구 참여자 실명
    @Published public private(set) var participantName: String
    /// 온보딩 완료 여부
    @Published public private(set) var hasCompletedOnboarding: Bool
    /// 연구 시작 일자
    @Published public private(set) var studyStartDate: Date

    // MARK: - 현재 세션 및 메뉴 막대 상태 (임시 및 런타임)
    /// 현재 감지된 AI 세션 앱 명칭 (예: "Claude, 터미널")
    @Published public var activeSessionAppNames: String? = nil
    /// 메뉴 막대 아이콘 옆에 표시할 경과 시간 문자열 (예: "1:12"). 세션이 없으면 nil
    @Published public var activeSessionDurationString: String? = nil
    /// 1시간 동안 팝업 끄기 활성화 여부
    @Published public var isPopupMutedForOneHour: Bool = false
    @Published public var popupMuteEndTime: Date? = nil
    private var popupMuteTimer: Timer?
    /// 15분 동안 활동 기록 멈추기 활성화 여부
    @Published public var isRecordingPaused15Min: Bool = false
    @Published public var recordingPauseEndTime: Date? = nil
    private var recordingPauseTimer: Timer?

    // 온보딩 윈도우 관리 참조
    public var onboardingWindowController: NSWindowController?

    private init() {
        // 1. Participant UUID 확인 또는 새로 생성
        if let storedId = UserDefaults.standard.string(forKey: Keys.participantId), !storedId.isEmpty {
            self.participantId = storedId
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: Keys.participantId)
            self.participantId = newId
        }

        // 2. 참여자 이름 및 온보딩 상태 로드
        self.participantName = UserDefaults.standard.string(forKey: Keys.participantName) ?? ""
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)

        if let storedDate = UserDefaults.standard.object(forKey: Keys.studyStartDate) as? Date {
            self.studyStartDate = storedDate
        } else {
            let today = Date()
            UserDefaults.standard.set(today, forKey: Keys.studyStartDate)
            self.studyStartDate = today
        }

        // 이미 온보딩을 마친 참여자인 경우 로컬 DB 및 동기화 큐에 참여자 정보 기록
        if self.hasCompletedOnboarding && !self.participantName.isEmpty {
            LocalDatabase.shared.recordParticipant(
                id: self.participantId,
                displayName: self.participantName,
                enrolledAt: self.studyStartDate
            )
        }
    }

    // MARK: - 연구 기간 및 종료 상태
    /// 연구 종료 일자 (시작일로부터 14일 뒤)
    public var studyEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 14, to: studyStartDate) ?? studyStartDate.addingTimeInterval(14 * 86400)
    }

    /// 14일 공식 연구 기간 경과 여부 (경과 후에도 활동 감지 및 설문 팝업은 중단 없이 계속 이용 가능)
    public var isStudyCompleted: Bool {
        Date() >= studyEndDate
    }

    /// 남은 연구 일수 (0~14일)
    public var daysRemaining: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: studyEndDate)
        let diff = calendar.dateComponents([.day], from: today, to: end).day ?? 0
        return max(0, diff)
    }

    // MARK: - 이름 임시 저장 및 수정 (participant_id는 유지)
    public func updateParticipantName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.participantName = trimmed
        UserDefaults.standard.set(trimmed, forKey: Keys.participantName)

        // 로컬 SQLite 및 Supabase 동기화 큐에 display_name 업데이트 등록 (동일한 participant_id 유지)
        LocalDatabase.shared.recordParticipant(
            id: self.participantId,
            displayName: trimmed,
            enrolledAt: self.studyStartDate
        )
    }

    public func saveDraftName(_ name: String) {
        updateParticipantName(name)
    }

    // MARK: - 온보딩 완료 처리
    public func completeOnboarding(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        self.participantName = trimmedName
        self.hasCompletedOnboarding = true

        UserDefaults.standard.set(trimmedName, forKey: Keys.participantName)
        UserDefaults.standard.set(true, forKey: Keys.hasCompletedOnboarding)

        // 로컬 DB 및 Supabase 동기화 큐에 참여자 등록
        LocalDatabase.shared.recordParticipant(
            id: self.participantId,
            displayName: trimmedName,
            enrolledAt: self.studyStartDate
        )

        // 로그인 시 자동 실행 활성화
        LaunchAtLoginService.shared.setEnabled(true)

        // 온보딩 창 닫기
        onboardingWindowController?.close()
        onboardingWindowController = nil

        // 사용자가 앱 상주 위치(상단 메뉴 막대)를 즉시 인지할 수 있도록 패널 자동 열기
        MenuBarAccessHelper.openMenuBarExtra(delay: 0.3)
    }

    // MARK: - 팝업 1시간 음소거 토글 및 로깅
    public func toggleMuteOneHour() {
        if isPopupMutedForOneHour {
            unmuteOneHour(reason: "user_cancel")
        } else {
            muteOneHour()
        }
    }

    public func muteOneHour() {
        let duration = Config.Scheduler.muteDuration
        let endTime = Date().addingTimeInterval(duration)
        popupMuteEndTime = endTime
        isPopupMutedForOneHour = true

        // 1. 1시간 동안 팝업 끄기 시스템 이벤트 로그 저장
        ActivityDetector.shared.emitEvent(
            type: .suspend,
            appName: "AIFatigueTracker",
            bundleId: Bundle.main.bundleIdentifier ?? "com.dxd.AIFatigueTracker",
            windowTitle: "1시간 동안 팝업 끄기 (사용자 요청)",
            suspendType: "mute_1h"
        )

        // 2. 타이머 가동 (1시간 후 자동 해제)
        popupMuteTimer?.invalidate()
        popupMuteTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.unmuteOneHour(reason: "timeout")
            }
        }
    }

    public func unmuteOneHour(reason: String = "manual") {
        guard isPopupMutedForOneHour else { return }

        let actualDuration: TimeInterval = {
            if let end = popupMuteEndTime {
                let duration = Config.Scheduler.muteDuration
                let start = end.addingTimeInterval(-duration)
                return max(0, Date().timeIntervalSince(start))
            }
            return 0
        }()

        isPopupMutedForOneHour = false
        popupMuteEndTime = nil
        popupMuteTimer?.invalidate()
        popupMuteTimer = nil

        let reasonDesc = (reason == "timeout") ? "1시간 만료" : "사용자 해제"

        // 팝업 끄기 해제 시스템 이벤트 로그 저장
        ActivityDetector.shared.emitEvent(
            type: .resume,
            appName: "AIFatigueTracker",
            bundleId: Bundle.main.bundleIdentifier ?? "com.dxd.AIFatigueTracker",
            windowTitle: "팝업 끄기 해제 (\(reasonDesc))",
            suspendType: "mute_1h",
            suspendDuration: actualDuration
        )
    }

    // MARK: - 15분 동안 활동 기록 일시정지 토글
    public func togglePauseRecording15Min() {
        if isRecordingPaused15Min {
            resumeRecording()
        } else {
            pauseRecording15Min()
        }
    }

    public func pauseRecording15Min() {
        let duration = Config.Scheduler.recordingPauseDuration
        let endTime = Date().addingTimeInterval(duration)
        recordingPauseEndTime = endTime

        // 1. 15분 활동 기록 일시정지 시스템 이벤트 로그 저장
        ActivityDetector.shared.emitEvent(
            type: .suspend,
            appName: "AIFatigueTracker",
            bundleId: Bundle.main.bundleIdentifier ?? "com.dxd.AIFatigueTracker",
            windowTitle: "15분 활동 기록 일시정지 (사용자 요청)",
            suspendType: "pause_15m"
        )

        // 2. 일시정지 플래그 활성화 및 타이머 가동
        isRecordingPaused15Min = true
        recordingPauseTimer?.invalidate()
        recordingPauseTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.resumeRecording()
            }
        }
    }

    public func resumeRecording() {
        guard isRecordingPaused15Min else { return }

        let actualPauseDuration: TimeInterval = {
            if let end = recordingPauseEndTime {
                let duration = Config.Scheduler.recordingPauseDuration
                let start = end.addingTimeInterval(-duration)
                return max(0, Date().timeIntervalSince(start))
            }
            return 0
        }()

        // 1. 일시정지 플래그 해제
        isRecordingPaused15Min = false
        recordingPauseEndTime = nil
        recordingPauseTimer?.invalidate()
        recordingPauseTimer = nil

        // 2. 활동 기록 재개 시스템 이벤트 로그 저장
        ActivityDetector.shared.emitEvent(
            type: .resume,
            appName: "AIFatigueTracker",
            bundleId: Bundle.main.bundleIdentifier ?? "com.dxd.AIFatigueTracker",
            windowTitle: "활동 기록 재개",
            suspendType: "pause_15m",
            suspendDuration: actualPauseDuration
        )
    }

    // MARK: - 디버그/테스트용 세션 시뮬레이션
    public func simulateSession(active: Bool, appNames: String = "Claude, 터미널", duration: String = "1:12") {
        if active {
            self.activeSessionAppNames = appNames
            self.activeSessionDurationString = duration
        } else {
            self.activeSessionAppNames = nil
            self.activeSessionDurationString = nil
        }
    }
}
