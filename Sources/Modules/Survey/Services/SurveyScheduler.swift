import Foundation
import Combine
import AppKit

/// 설문 팝업 스케줄링 및 트리거 규칙 관리자
/// - 2단계 AI 세션 기준 팝업 시점 관리 (start, mid, end, diary, nudge)
/// - 공통 규칙: 30분 최소 간격(diary 예외), 1시간 팝업 끄기(Mute, diary 예외)
/// - 자리 비움(idle) 및 화면 잠금(lock) 시 보류(pending) 후 복귀 시 자동 표시
/// - "10분 뒤에" 스누즈(snooze) 재알림 및 무응답(timeout) 자동 닫힘 처리
public final class SurveyScheduler: ObservableObject {
    public static let shared = SurveyScheduler()

    // MARK: - 스케줄러 상태 모니터링 프로퍼티
    @Published public private(set) var isPopupPresented: Bool = false
    @Published public private(set) var currentPopupType: SurveyType? = nil
    @Published public private(set) var currentSessionId: UUID? = nil
    @Published public private(set) var lastPopupShownAt: Date? = nil
    @Published public private(set) var lastEndPopupShownAt: Date? = nil
    @Published public private(set) var pendingSurvey: PendingSurveyRequest? = nil
    @Published public private(set) var activeSnoozes: [SnoozedSurveyRequest] = []

    // 세션별 mid 타이머 (sessionId -> Timer)
    private var midSessionTimers: [UUID: Timer] = [:]
    // 데일리 18:30 넛지 타이머
    private var dailyNudgeTimer: Timer?
    private var lastNudgeFiredDateString: String? = nil

    private let nudgeDateKey = "ai_fatigue_last_nudge_date"
    private let lastEndPopupKey = "ai_fatigue_last_end_popup_at"

    private init() {
        self.lastNudgeFiredDateString = UserDefaults.standard.string(forKey: nudgeDateKey)
        if let savedEnd = UserDefaults.standard.object(forKey: lastEndPopupKey) as? Date {
            self.lastEndPopupShownAt = savedEnd
        }
        startDailyNudgeChecker()
    }

    /// 세션 간 쿨다운 초기화 (디버그/테스트용)
    public func resetCooldown() {
        lastEndPopupShownAt = nil
        UserDefaults.standard.removeObject(forKey: lastEndPopupKey)
    }

    // MARK: - 1. 세션 생명주기 연동 트리거 (start, mid, end)

    /// AI 세션 시작 직후 호출 (start 팝업 트리거 및 mid 타이머 등록)
    public func handleSessionStarted(_ session: AISession) {
        // 1) start 팝업 요청 (세션 간 30분 쿨다운 규칙 검사 적용)
        _ = requestSurvey(type: .start, session: session, force: false)

        // 2) mid 무작위 간격 (60~120분) 타이머 시작
        scheduleNextMidSurvey(for: session)
    }

    /// AI 세션 진행 중 60~120분 무작위 반복 타이머 등록 (mid 팝업)
    private func scheduleNextMidSurvey(for session: AISession) {
        // 기존 타이머 취소
        midSessionTimers[session.sessionId]?.invalidate()

        let randomDelay = TimeInterval.random(
            in: Config.Scheduler.midSurveyIntervalMin...Config.Scheduler.midSurveyIntervalMax
        )

        let timer = Timer.scheduledTimer(withTimeInterval: randomDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // 세션이 아직 활성 상태(close가 아님)인지 확인
            if let current = SessionManager.shared.sessions.first(where: { $0.sessionId == session.sessionId }),
               current.state != .close {
                _ = self.requestSurvey(type: .mid, session: current, force: false)
                // 다음 60~120분 뒤 타이머 재스케줄
                self.scheduleNextMidSurvey(for: current)
            } else {
                self.midSessionTimers.removeValue(forKey: session.sessionId)
            }
        }
        midSessionTimers[session.sessionId] = timer
    }

    /// AI 세션 종료 직후 호출 (end 팝업 트리거 및 mid 타이머 해제)
    public func handleSessionEnded(_ session: AISession) {
        // mid 타이머 해제
        midSessionTimers[session.sessionId]?.invalidate()
        midSessionTimers.removeValue(forKey: session.sessionId)

        // 만약 이전 팝업(start/mid)이 아직 화면에 남아 있다면 닫고 end 팝업으로 전환
        if isPopupPresented && currentPopupType != .end {
            dismissCurrentPopup()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                _ = self?.requestSurvey(type: .end, session: session, force: false)
            }
            return
        }

        // end 팝업 요청 (세션 내 종료 팝업은 쿨다운과 무관하게 즉시 표시)
        _ = requestSurvey(type: .end, session: session, force: false)
    }

    // MARK: - 2. 사용자 복귀 감지 (화면 잠금 해제, 시스템 깨우기, 자리 비움 복귀)
    public func handleUserReturned() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 여전히 자리 비움이거나 잠금 상태라면 대기 유지
            guard !self.isUserIdleOrScreenLocked() else { return }

            // 보류된 팝업이 있는지 확인
            if let pending = self.pendingSurvey {
                let check = self.canShowPopup(type: pending.type, force: false)
                if check.allowed {
                    self.pendingSurvey = nil
                    _ = self.requestSurvey(type: pending.type, session: pending.session, force: false)
                }
            }
        }
    }

    // MARK: - 3. 핵심 팝업 요청 및 규칙 검사

    public struct EligibilityResult {
        public let allowed: Bool
        public let reason: String?
    }

    /// 팝업 노출 규칙(세션 간 30분 쿨다운, 1시간 팝업 끄기) 검사
    /// - 세션 간 쿨다운 30분: 종료 팝업(.end) 뒤 30분 동안은 새 세션이 감지돼도 시작 팝업(.start)을 띄우지 않음
    /// - 세션 안의 팝업(시작·중간·종료)은 세션 내에서 쿨다운과 상관없이 정해진 시점에 뜸
    public func canShowPopup(type: SurveyType, force: Bool) -> EligibilityResult {
        if force {
            return EligibilityResult(allowed: true, reason: "강제 표시 (규칙 우회)")
        }

        // diary는 자발적 기록이므로 쿨다운과 1시간 음소거의 예외 (언제든 허용)
        if type == .diary {
            return EligibilityResult(allowed: true, reason: "다이어리는 쿨다운/음소거 예외 허용")
        }

        // 1) 1시간 동안 팝업 끄기 (Mute) 검사 - 자동 설문 전반 적용
        if AppState.shared.isPopupMutedForOneHour {
            return EligibilityResult(allowed: false, reason: "1시간 동안 팝업 끄기 활성화 중")
        }

        // 2) 세션 간 30분 쿨다운 검사:
        //    - 종료 팝업(.end) 뒤 30분 동안은 새 세션이 감지돼도 시작 팝업(.start)을 띄우지 않음
        //    - 세션 안의 팝업(시작·중간·종료)은 쿨다운과 상관없이 정해진 시점에 뜸
        if type == .start {
            if let lastEnd = lastEndPopupShownAt {
                let elapsed = Date().timeIntervalSince(lastEnd)
                if elapsed < Config.Scheduler.minPopupCooldown {
                    let remaining = Int(ceil((Config.Scheduler.minPopupCooldown - elapsed) / 60))
                    return EligibilityResult(
                        allowed: false,
                        reason: "세션 간 쿨다운(30분) 중 (\(remaining)분 남음: 직전 종료 팝업 후 30분 미경과)"
                    )
                }
            }
        }

        return EligibilityResult(allowed: true, reason: "규칙 충족 (표시 가능)")
    }

    /// 현재 사용자가 자리 비움(idle)이거나 화면이 잠겨있는지 판별
    public func isUserIdleOrScreenLocked() -> Bool {
        return IdleTracker.shared.isIdle || SystemEventTracker.shared.isLockedOrSleeping
    }

    /// 팝업 띄우기 요청 (force = true 시 쿨다운 및 음소거 규칙 우회)
    @discardableResult
    public func requestSurvey(
        type: SurveyType,
        session: AISession? = nil,
        force: Bool = false
    ) -> Bool {
        // 이미 팝업이 화면에 떠 있다면 중복으로 띄우지 않음
        if isPopupPresented {
            return false
        }

        // diary는 자발적 피로 기록(화면 캡처 연동) 전용 플로우 실행
        if type == .diary {
            VoluntaryRecordService.shared.startFlow()
            return true
        }

        // 자리 비움 또는 화면 잠금 중인 경우: 보류(pending)로 저장하고 복귀 시 띄움 (force일 경우 제외)
        if isUserIdleOrScreenLocked() && !force {
            pendingSurvey = PendingSurveyRequest(type: type, session: session, requestedAt: Date())
            return false
        }

        // 쿨다운 및 1시간 음소거 규칙 검사
        let eligibility = canShowPopup(type: type, force: force)
        guard eligibility.allowed else {
            if AppState.shared.isPopupMutedForOneHour {
                let linkedSession = session ?? SessionManager.shared.currentSession
                let notice = ActivityEvent(
                    timestamp: Date(),
                    eventType: .navigate,
                    appName: "설문 팝업",
                    bundleId: "com.aifatigue.survey",
                    windowTitle: "[\(type.rawValue)] 설문 생략 (1시간 동안 팝업 끄기 적용 중)",
                    isAI: true,
                    aiTool: linkedSession?.toolName,
                    threadTitle: linkedSession?.title,
                    sessionId: linkedSession?.sessionId,
                    navType: "survey_muted_suppressed"
                )
                DebugLogStore.shared.addEvent(notice)
            }
            return false
        }

        // 팝업 표시 시각 기록
        let shownAt = Date()
        let linkedSession = session ?? SessionManager.shared.currentSession

        isPopupPresented = true
        currentPopupType = type
        currentSessionId = linkedSession?.sessionId
        lastPopupShownAt = shownAt

        // 종료 팝업(.end)일 경우 직전 종료 팝업 시각 갱신 -> 이 시점부터 30분간 세션 간 쿨다운 시작
        if type == .end {
            lastEndPopupShownAt = shownAt
            UserDefaults.standard.set(shownAt, forKey: lastEndPopupKey)
        }

        // 윈도우 매니저를 통해 화면 우상단에 팝업 띄움
        SurveyWindowManager.shared.showPopup(
            type: type,
            session: linkedSession
        ) { [weak self] action, payload in
            self?.handlePopupAction(
                action: action,
                payload: payload,
                type: type,
                session: linkedSession,
                shownAt: shownAt
            )
        }

        return true
    }

    // MARK: - 4. 팝업 사용자 액션 처리 (응답, 건너뛰기, 10분 뒤에, 무응답)
    private func handlePopupAction(
        action: SurveyAction,
        payload: [String: String]?,
        type: SurveyType,
        session: AISession?,
        shownAt: Date
    ) {
        let respondedAt = Date()

        // 1) 이벤트 저장 및 session_id 바인딩
        let event = SurveyEvent(
            surveyType: type,
            action: action,
            shownAt: shownAt,
            respondedAt: respondedAt,
            sessionId: session?.sessionId,
            sessionTitle: session?.title,
            aiTool: session?.toolName,
            responsePayload: payload
        )
        SurveyLogStore.shared.addEvent(event)

        // 2) 윈도우 슬라이드 아웃 닫기
        SurveyWindowManager.shared.dismissPopup { [weak self] in
            guard let self = self else { return }
            self.isPopupPresented = false
            self.currentPopupType = nil
            self.currentSessionId = nil

            // 미기록 넛지에서 "기록하기"를 누른 경우, 슬라이드 아웃 완료 후 회고 다이어리 안전하게 실행
            if type == .nudge, payload?["nudge_choice"] == "record" {
                VoluntaryRecordService.shared.startNudgeReflectionFlow()
                return
            }

            // 넛지(.nudge)의 "없었어요" 등은 토스트 알림 없이 조용히 닫힘
            if action == .response && type != .nudge {
                SaveConfirmationToast.shared.show(message: "저장됨", detail: "설문 응답이 안전하게 저장되었습니다.")
            }
        }

        // 3) "10분 뒤에" 스누즈 예약 처리
        if action == .snooze {
            scheduleSnooze(type: type, session: session, delay: Config.Scheduler.snoozeDuration)
        }
    }

    // MARK: - 5. "10분 뒤에" 스누즈 관리
    public func scheduleSnooze(
        type: SurveyType,
        session: AISession?,
        delay: TimeInterval = Config.Scheduler.snoozeDuration
    ) {
        let targetDate = Date().addingTimeInterval(delay)
        var snoozeRequest = SnoozedSurveyRequest(
            type: type,
            session: session,
            scheduledAt: Date(),
            targetDate: targetDate
        )

        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.activeSnoozes.removeAll(where: { $0.id == snoozeRequest.id })
            // 스누즈 팝업 표시 (자리비움이면 자동으로 pending으로 전환됨)
            _ = self.requestSurvey(type: type, session: session, force: false)
        }

        snoozeRequest.timer = timer
        activeSnoozes.append(snoozeRequest)
    }

    /// 테스트용: 예약된 스누즈 즉시 재알림 실행
    public func triggerSnoozeImmediately(id: UUID) {
        if let idx = activeSnoozes.firstIndex(where: { $0.id == id }) {
            let req = activeSnoozes.remove(at: idx)
            req.timer?.invalidate()
            _ = requestSurvey(type: req.type, session: req.session, force: true)
        }
    }

    // MARK: - 6. 데일리 18:30 넛지 타이머
    private func startDailyNudgeChecker() {
        dailyNudgeTimer?.invalidate()
        // 30초마다 시각을 체크하여 18:30에 정확히 진입했을 때 1회 발송
        dailyNudgeTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkDailyNudgeCondition()
        }
    }

    private func checkDailyNudgeCondition() {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: now)

        if hour == Config.Scheduler.dailyNudgeHour && minute == Config.Scheduler.dailyNudgeMinute {
            // 오늘 이미 발송했는지 확인
            if lastNudgeFiredDateString != todayString {
                // 당일 자발적 기록(diary 응답)이 0건인지 확인
                let voluntaryCount = SurveyLogStore.shared.voluntaryRecordCountToday()
                if voluntaryCount == 0 {
                    lastNudgeFiredDateString = todayString
                    UserDefaults.standard.set(todayString, forKey: nudgeDateKey)
                    _ = requestSurvey(type: .nudge, session: SessionManager.shared.currentSession, force: false)
                }
            }
        }
    }

    // MARK: - 7. 수동 강제 팝업 (완료 기준 충족용 API)
    public func forceTrigger(type: SurveyType) {
        if isPopupPresented {
            dismissCurrentPopup()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                _ = self.requestSurvey(type: type, session: SessionManager.shared.currentSession, force: true)
            }
        } else {
            _ = requestSurvey(type: type, session: SessionManager.shared.currentSession, force: true)
        }
    }

    /// 현재 열려 있는 팝업 닫기
    public func dismissCurrentPopup() {
        if isPopupPresented {
            SurveyWindowManager.shared.dismissPopup { [weak self] in
                self?.isPopupPresented = false
                self?.currentPopupType = nil
                self?.currentSessionId = nil
            }
        }
    }
}

// MARK: - 보조 모델 (보류 및 스누즈 요청)
public struct PendingSurveyRequest: Identifiable {
    public let id = UUID()
    public let type: SurveyType
    public let session: AISession?
    public let requestedAt: Date
}

public struct SnoozedSurveyRequest: Identifiable {
    public let id: UUID
    public let type: SurveyType
    public let session: AISession?
    public let scheduledAt: Date
    public let targetDate: Date
    public var timer: Timer?

    public init(
        id: UUID = UUID(),
        type: SurveyType,
        session: AISession?,
        scheduledAt: Date,
        targetDate: Date,
        timer: Timer? = nil
    ) {
        self.id = id
        self.type = type
        self.session = session
        self.scheduledAt = scheduledAt
        self.targetDate = targetDate
        self.timer = timer
    }
}
