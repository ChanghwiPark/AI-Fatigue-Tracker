import Foundation
import Combine
import AppKit
import SwiftUI

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
    @Published public private(set) var currentSnoozeCount: Int = 0
    @Published public private(set) var nextFollowUpScheduledAt: Date? = nil
    private var fatigueFollowUpTimer: Timer? = nil
    private var isHandlingPopupAction: Bool = false
    private var isReplacingPopup: Bool = false
    private var pendingReplacement: (type: SurveyType, session: AISession?, snoozeCount: Int, draftState: SurveyDraftState?)? = nil

    // 세션별 순수 활성 누적 시간(초) 기준 다음 mid 목표치 (sessionId -> 목표 누적 시간)
    private var nextMidTargetDurationBySession: [UUID: TimeInterval] = [:]
    // 데일리 18:30 넛지 타이머
    private var dailyNudgeTimer: Timer?
    private var lastNudgeFiredDateString: String? = nil
    private var lastStartedSessionId: UUID? = nil
    private var lastStartedSessionTime: Date? = nil

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

    /// AI 세션 시작 직후 호출 (start 팝업 트리거 및 mid 순수 활성 누적 시간 목표치 등록)
    public func handleSessionStarted(_ session: AISession) {
        let now = Date()
        // 동일 세션에 대한 3초 이내 중복 시작 트리거 차단 (새 탭/새 창 감지 시 open+focusIn 연쇄 방지)
        if lastStartedSessionId == session.sessionId,
           let lastTime = lastStartedSessionTime,
           now.timeIntervalSince(lastTime) < 3.0 {
            print("[SurveyScheduler] 동일 세션(\(session.sessionId)) 3초 이내 중복 시작 트리거 무시")
            return
        }
        lastStartedSessionId = session.sessionId
        lastStartedSessionTime = now

        // 1) start 팝업 요청 (세션 간 쿨다운 규칙 검사 적용)
        _ = requestSurvey(type: .start, session: session, force: false)

        // 2) mid 순수 활성 누적 시간 (20~40분 무작위) 목표치 계산 및 등록
        let interval = TimeInterval.random(
            in: Config.Scheduler.midSurveyIntervalMin...Config.Scheduler.midSurveyIntervalMax
        )
        nextMidTargetDurationBySession[session.sessionId] = session.accumulatedFocusedDuration + interval
    }

    /// AI 세션의 순수 활성 누적 시간(accumulatedFocusedDuration)을 검사하여 mid 팝업 조건 충족 시 트리거
    public func checkMidSurveyEligibility(for session: AISession) {
        // 1. 이미 화면에 어떤 설문 팝업이든 떠 있거나, 액션 처리 중 또는 팝업 교체 중이라면 검사 유보 (중복 팝업 원천 방지)
        if isPopupPresented || isHandlingPopupAction || isReplacingPopup {
            return
        }

        // 2. 세션이 순수 활성 상태(.focusIn)인지 확인 (일시중지 상태에서는 절대 노출 금지)
        guard session.state == .focusIn else { return }

        // 3. 자리 비움(idle)이나 화면 잠금 상태이면 노출 금지
        guard !isUserIdleOrScreenLocked() else { return }

        // 4. 15분 기록 멈추기 또는 1시간 팝업 끄기 상태이면 노출 금지
        guard !AppState.shared.isRecordingPaused15Min && !AppState.shared.isPopupMutedForOneHour else { return }

        // 5. 해당 세션의 다음 mid 목표 누적 시간 확인
        let targetDuration: TimeInterval
        if let existing = nextMidTargetDurationBySession[session.sessionId] {
            targetDuration = existing
        } else {
            let interval = TimeInterval.random(
                in: Config.Scheduler.midSurveyIntervalMin...Config.Scheduler.midSurveyIntervalMax
            )
            targetDuration = session.accumulatedFocusedDuration + interval
            nextMidTargetDurationBySession[session.sessionId] = targetDuration
            return
        }

        // 6. 순수 활성 누적 시간(accumulatedFocusedDuration)이 목표치에 도달했는지 확인
        if session.accumulatedFocusedDuration >= targetDuration {
            let eligibility = canShowPopup(type: .mid, force: false, session: session)
            if eligibility.allowed {
                // 다음 20~40분 순수 활성 누적 시간 목표치 예약
                let nextInterval = TimeInterval.random(
                    in: Config.Scheduler.midSurveyIntervalMin...Config.Scheduler.midSurveyIntervalMax
                )
                nextMidTargetDurationBySession[session.sessionId] = session.accumulatedFocusedDuration + nextInterval

                // mid 팝업 트리거
                _ = requestSurvey(type: .mid, session: session, force: false)
            }
        }
    }

    /// AI 세션 종료 직후 호출 (end 팝업 트리거 및 mid 목표치 해제)
    public func handleSessionEnded(_ session: AISession) {
        // mid 목표 누적 시간 해제
        nextMidTargetDurationBySession.removeValue(forKey: session.sessionId)

        // 종료된 세션에 대한 기존 스누즈 타이머 정리
        for req in activeSnoozes where req.session?.sessionId == session.sessionId {
            req.timer?.invalidate()
        }
        activeSnoozes.removeAll(where: { $0.session?.sessionId == session.sessionId })

        // 만약 이전 팝업(start/mid 등)이 아직 화면에 남아 있다면 닫고 end 팝업으로 교체 노출
        // (requestSurvey 내부의 팝업 교체 대체 로직을 통해 처리)
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
                // 중간 점검(.mid)은 사용자가 활발히 AI 작업 중인 상태가 아니면 복귀 시 띄우지 않고 정리
                if pending.type == .mid {
                    let active = pending.session ?? SessionManager.shared.focusedSession
                    guard let target = active, target.state == .focusIn else {
                        self.pendingSurvey = nil
                        return
                    }
                }

                let check = self.canShowPopup(type: pending.type, force: false, session: pending.session)
                if check.allowed {
                    self.pendingSurvey = nil
                    _ = self.requestSurvey(
                        type: pending.type,
                        session: pending.session,
                        force: false,
                        snoozeCount: pending.snoozeCount,
                        draftState: pending.draftState
                    )
                }
            }
        }
    }

    // MARK: - 3. 핵심 팝업 요청 및 규칙 검사

    public struct EligibilityResult {
        public let allowed: Bool
        public let reason: String?
    }

    /// 팝업 노출 규칙(세션 간 30분 쿨다운, 15분 일시중지, 1시간 팝업 끄기, 활성 상태) 검사
    /// - 세션 간 쿨다운 30분: 종료 팝업(.end) 뒤 30분 동안은 새 세션이 감지돼도 시작 팝업(.start)을 띄우지 않음
    /// - 세션 안의 팝업(시작·중간·종료)은 세션 내에서 쿨다운과 상관없이 정해진 시점에 뜸
    public func canShowPopup(type: SurveyType, force: Bool, session: AISession? = nil) -> EligibilityResult {
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

        // 2) 15분 동안 활동 기록 멈추기 (Pause) 검사 - 자동 설문 전반 적용
        if AppState.shared.isRecordingPaused15Min {
            return EligibilityResult(allowed: false, reason: "15분간 기록 일시중지 활성화 중")
        }

        // 3) 중간 점검 설문(.mid)은 AI 세션이 활발히 사용 중인(focusIn) 상태에서만 허용 (일시중지 상태에서는 절대 노출 금지)
        if type == .mid {
            let targetSession = session ?? SessionManager.shared.focusedSession
            guard let target = targetSession, target.state == .focusIn else {
                return EligibilityResult(allowed: false, reason: "세션이 일시중지(unfocus) 또는 비활성 상태임")
            }
        }

        // 4) 세션 간 쿨다운 검사:
        //    - 종료 팝업(.end) 뒤 설정된 쿨다운 동안은 새 세션이 감지돼도 시작 팝업(.start)을 띄우지 않음
        //    - 쿨다운이 0분(해제)이면 직전 종료 시각과 무관하게 즉시 팝업 허용
        if type == .start {
            if Config.Scheduler.minPopupCooldown <= 0 {
                return EligibilityResult(allowed: true, reason: "쿨다운 해제됨 (0분)")
            }
            if let lastEnd = lastEndPopupShownAt {
                let elapsed = Date().timeIntervalSince(lastEnd)
                if elapsed < Config.Scheduler.minPopupCooldown {
                    let remaining = Int(ceil((Config.Scheduler.minPopupCooldown - elapsed) / 60))
                    let cdMin = Int(ceil(Config.Scheduler.minPopupCooldown / 60))
                    return EligibilityResult(
                        allowed: false,
                        reason: "세션 간 쿨다운(\(cdMin)분) 중 (\(remaining)분 남음: 직전 종료 팝업 후 \(cdMin)분 미경과)"
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
        force: Bool = false,
        snoozeCount: Int = 0,
        draftState: SurveyDraftState? = nil
    ) -> Bool {
        // diary는 자발적 피로 기록(화면 캡처 연동) 전용 플로우 실행
        if type == .diary {
            VoluntaryRecordService.shared.startFlow()
            return true
        }

        // 15분 동안 활동 기록 멈추기 중인 경우: 자동 설문 차단
        if AppState.shared.isRecordingPaused15Min && !force {
            return false
        }

        // 자리 비움 또는 화면 잠금 중인 경우: 보류(pending)로 저장하고 복귀 시 띄움 (force일 경우 제외)
        // 단, 중간 설문(.mid)은 자리 비움 중 보류하지 않고, 사용자가 AI에 복귀했을 때 활성 누적 시간으로 자연스럽게 트리거되도록 함
        if isUserIdleOrScreenLocked() && !force {
            if type != .mid {
                pendingSurvey = PendingSurveyRequest(
                    type: type,
                    session: session,
                    requestedAt: Date(),
                    snoozeCount: snoozeCount,
                    draftState: draftState
                )
            }
            return false
        }

        // 중간 점검 설문(.mid)은 현재 세션이 focusIn(활성) 상태일 때만 허용
        if type == .mid && !force {
            let active = session ?? SessionManager.shared.focusedSession
            guard let target = active, target.state == .focusIn else {
                return false
            }
        }

        // 쿨다운, 15분 일시중지 및 1시간 음소거 규칙 검사
        let eligibility = canShowPopup(type: type, force: force, session: session)
        guard eligibility.allowed else {
            if AppState.shared.isPopupMutedForOneHour {
                let linkedSession = session ?? SessionManager.shared.currentSession
                let notice = ActivityEvent(
                    timestamp: Date(),
                    eventType: .survey,
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

        // [동일 타입 팝업 중복 노출 차단]:
        // 이미 동일한 타입의 설문 팝업이 화면에 떠 있다면 중복 호출 무시
        if isPopupPresented && currentPopupType == type && !force {
            print("[SurveyScheduler] 동일한 타입(\(type))의 팝업이 이미 노출 중이므로 중복 요청 무시")
            return false
        }

        // [중복 노출 시 이후에 뜨는 최신 팝업으로 대체 / 교체 노출]:
        // 화면에 이미 다른 팝업이 떠 있거나 닫히는 중인 경우, 새 팝업을 차단하지 않고 기존 팝업을 닫은 뒤 최신 팝업으로 교체 노출
        if isPopupPresented || isHandlingPopupAction || isReplacingPopup {
            pendingReplacement = (type: type, session: session, snoozeCount: snoozeCount, draftState: draftState)
            if !isReplacingPopup && !isHandlingPopupAction {
                isReplacingPopup = true
                dismissCurrentPopup { [weak self] in
                    guard let self = self else { return }
                    self.isReplacingPopup = false
                    if let next = self.pendingReplacement {
                        self.pendingReplacement = nil
                        _ = self.showPopupInternal(
                            type: next.type,
                            session: next.session,
                            snoozeCount: next.snoozeCount,
                            draftState: next.draftState
                        )
                    }
                }
            }
            return true
        }

        return showPopupInternal(type: type, session: session, snoozeCount: snoozeCount, draftState: draftState)
    }

    /// 실제 윈도우 생성 및 팝업 화면 표시 내부 구현
    private func showPopupInternal(
        type: SurveyType,
        session: AISession?,
        snoozeCount: Int,
        draftState: SurveyDraftState? = nil
    ) -> Bool {
        let shownAt = Date()
        let linkedSession = session ?? SessionManager.shared.currentSession

        isPopupPresented = true
        isHandlingPopupAction = false
        currentPopupType = type
        currentSessionId = linkedSession?.sessionId
        currentSnoozeCount = snoozeCount
        lastPopupShownAt = shownAt

        // 종료 팝업(.end)일 경우 직전 종료 팝업 시각 갱신 -> 이 시점부터 세션 간 쿨다운 시작
        if type == .end {
            lastEndPopupShownAt = shownAt
            UserDefaults.standard.set(shownAt, forKey: lastEndPopupKey)
        }

        // 윈도우 매니저를 통해 화면 우상단에 팝업 띄움 (스누즈 임시 저장 draftState 전달)
        SurveyWindowManager.shared.showPopup(
            type: type,
            session: linkedSession,
            snoozeCount: snoozeCount,
            draftState: draftState
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
        // 이미 해당 팝업에 대한 액션이 처리 중이거나 완료되었으면 중복 호출 원천 차단
        guard isPopupPresented && !isHandlingPopupAction else {
            print("[SurveyScheduler] 이미 팝업 액션 처리 중이거나 완료됨 -> 중복 호출 무시 (action: \(action))")
            return
        }
        isHandlingPopupAction = true
        isPopupPresented = false

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
            self.isHandlingPopupAction = false
            self.currentPopupType = nil
            self.currentSessionId = nil

            // 미기록 넛지에서 "기록하기"를 누른 경우, 슬라이드 아웃 완료 후 회고 다이어리 안전하게 실행
            if type == .nudge, payload?["nudge_choice"] == "record" {
                VoluntaryRecordService.shared.startNudgeReflectionFlow()
                return
            }

            // 넛지(.nudge)의 "없었어요" 등은 토스트 알림 없이 조용히 닫힘
            if action == .response && type != .nudge {
                SaveConfirmationToast.shared.show(message: "저장 완료")
            }

            // 팝업 닫힘 중 대기 중인 후속 대체 팝업이 있다면 즉시 교체 노출
            if let next = self.pendingReplacement {
                self.pendingReplacement = nil
                _ = self.showPopupInternal(type: next.type, session: next.session, snoozeCount: next.snoozeCount)
            }
        }

        // 3) 피로도 2점(조금) 이상 응답 시 30분 뒤 후속 설문(.followUp) 예약
        if action == .response && type != .followUp {
            if let fStr = payload?["fatigue_score"], let score = Int(fStr), score >= 2 {
                scheduleFatigueFollowUp(session: session)
            }
        }

        // 4) "5분 뒤에" 스누즈 예약 처리 (최대 2회, 입력 데이터 및 작성 단계 임시 저장 보존)
        if action == .snooze {
            let nextCount = currentSnoozeCount + 1
            if nextCount <= Config.Scheduler.maxSnoozeCount {
                let currentDraft = SurveyDraftStore.shared.getDraft(for: type)
                scheduleSnooze(
                    type: type,
                    session: session,
                    delay: Config.Scheduler.snoozeDuration,
                    snoozeCount: nextCount,
                    draftState: currentDraft
                )
                // 우측 상단 슬림 알림 토스트 표시
                SaveConfirmationToast.shared.show(
                    message: "임시 저장됨 (5분 뒤 계속)",
                    icon: "clock.arrow.circlepath",
                    iconColor: Color.orange
                )
            }
        } else if action == .response || action == .skip {
            // 설문 응답 완료 또는 건너뛰기 시 임시 저장본 삭제
            SurveyDraftStore.shared.clearDraft(for: type)
        }
    }

    // MARK: - 5. 피로도 2점 이상 30분 뒤 후속 설문(.followUp) 스케줄링
    /// 피로도 2점(조금) 이상 응답 시 30분 뒤 후속 점검 설문(.followUp) 예약
    /// (최근 응답 기준으로 타이머 갱신하여 1회만 트리거)
    public func scheduleFatigueFollowUp(session: AISession?, delay: TimeInterval = 30 * 60) {
        fatigueFollowUpTimer?.invalidate()
        fatigueFollowUpTimer = nil

        let targetDate = Date().addingTimeInterval(delay)
        nextFollowUpScheduledAt = targetDate

        print("[SurveyScheduler] 피로 후속 점검 설문(30분 뒤) 예약 완료: \(targetDate) (delay: \(Int(delay))초)")

        fatigueFollowUpTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.fatigueFollowUpTimer = nil
            self.nextFollowUpScheduledAt = nil
            print("[SurveyScheduler] 피로 후속 점검 타이머 만료 -> .followUp 팝업 트리거")
            _ = self.requestSurvey(
                type: .followUp,
                session: session ?? SessionManager.shared.currentSession,
                force: true
            )
        }
    }

    /// 테스트용: 예약된 피로 후속 설문 즉시 트리거
    public func triggerFollowUpImmediately() {
        fatigueFollowUpTimer?.invalidate()
        fatigueFollowUpTimer = nil
        nextFollowUpScheduledAt = nil
        _ = requestSurvey(
            type: .followUp,
            session: SessionManager.shared.currentSession,
            force: true
        )
    }

    // MARK: - 6. "5분 뒤에" 스누즈 관리 (표준 5분, 최대 2회, 임시 저장 draftState 지원)
    public func scheduleSnooze(
        type: SurveyType,
        session: AISession?,
        delay: TimeInterval = Config.Scheduler.snoozeDuration,
        snoozeCount: Int = 1,
        draftState: SurveyDraftState? = nil
    ) {
        let targetDate = Date().addingTimeInterval(delay)
        var snoozeRequest = SnoozedSurveyRequest(
            type: type,
            session: session,
            scheduledAt: Date(),
            targetDate: targetDate,
            snoozeCount: snoozeCount,
            draftState: draftState
        )

        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.activeSnoozes.removeAll(where: { $0.id == snoozeRequest.id })
            // 스누즈 팝업 표시 (snoozeCount 및 draftState 보존 전달)
            _ = self.requestSurvey(
                type: type,
                session: session,
                force: false,
                snoozeCount: snoozeRequest.snoozeCount,
                draftState: snoozeRequest.draftState
            )
        }

        snoozeRequest.timer = timer
        activeSnoozes.append(snoozeRequest)
    }

    /// 테스트용: 예약된 스누즈 즉시 재알림 실행
    public func triggerSnoozeImmediately(id: UUID) {
        if let idx = activeSnoozes.firstIndex(where: { $0.id == id }) {
            let req = activeSnoozes.remove(at: idx)
            req.timer?.invalidate()
            _ = requestSurvey(
                type: req.type,
                session: req.session,
                force: true,
                snoozeCount: req.snoozeCount,
                draftState: req.draftState
            )
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
        guard Config.Scheduler.isDailyNudgeEnabled else {
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: now)

        if hour == Config.Scheduler.dailyNudgeHour && minute == Config.Scheduler.dailyNudgeMinute {
            // 오늘 이미 발송(또는 생략 판정)했는지 확인
            if lastNudgeFiredDateString != todayString {
                // 당일 이미 설문/다이어리 응답을 1건 이상 작성했는지 확인 (당일 전체 설문 start, mid, end, diary 완료 기준)
                let totalResponses = SurveyLogStore.shared.totalResponseCountToday()
                let dbResponses = LocalDatabase.shared.fetchTodaySurveyResponseCount()
                let todaySurveyCount = max(totalResponses, dbResponses)

                lastNudgeFiredDateString = todayString
                UserDefaults.standard.set(todayString, forKey: nudgeDateKey)

                if todaySurveyCount == 0 {
                    _ = requestSurvey(type: .nudge, session: SessionManager.shared.currentSession, force: false)
                }
            }
        }
    }

    // MARK: - 7. 수동 강제 팝업 (완료 기준 충족용 API)
    public func forceTrigger(type: SurveyType) {
        _ = requestSurvey(type: type, session: SessionManager.shared.currentSession, force: true)
    }

    /// 현재 열려 있는 팝업 닫기
    public func dismissCurrentPopup(completion: (() -> Void)? = nil) {
        if isPopupPresented {
            SurveyWindowManager.shared.dismissPopup { [weak self] in
                self?.isPopupPresented = false
                self?.isHandlingPopupAction = false
                self?.currentPopupType = nil
                self?.currentSessionId = nil
                completion?()
            }
        } else {
            completion?()
        }
    }
}

// MARK: - 보조 모델 (보류 및 스누즈 요청)
public struct PendingSurveyRequest: Identifiable {
    public let id = UUID()
    public let type: SurveyType
    public let session: AISession?
    public let requestedAt: Date
    public let snoozeCount: Int
    public let draftState: SurveyDraftState?

    public init(
        type: SurveyType,
        session: AISession?,
        requestedAt: Date,
        snoozeCount: Int = 0,
        draftState: SurveyDraftState? = nil
    ) {
        self.type = type
        self.session = session
        self.requestedAt = requestedAt
        self.snoozeCount = snoozeCount
        self.draftState = draftState
    }
}

public struct SnoozedSurveyRequest: Identifiable {
    public let id: UUID
    public let type: SurveyType
    public let session: AISession?
    public let scheduledAt: Date
    public let targetDate: Date
    public var timer: Timer?
    public let snoozeCount: Int
    public let draftState: SurveyDraftState?

    public init(
        id: UUID = UUID(),
        type: SurveyType,
        session: AISession?,
        scheduledAt: Date,
        targetDate: Date,
        timer: Timer? = nil,
        snoozeCount: Int = 1,
        draftState: SurveyDraftState? = nil
    ) {
        self.id = id
        self.type = type
        self.session = session
        self.scheduledAt = scheduledAt
        self.targetDate = targetDate
        self.timer = timer
        self.snoozeCount = snoozeCount
        self.draftState = draftState
    }
}
