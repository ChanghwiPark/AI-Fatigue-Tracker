import Foundation
import Combine

/// 연구 파라미터, 스케줄러 주기, 감지 임계값을 실시간으로 관리하고 영구 저장하는 매니저
public final class ConfigManager: ObservableObject {
    public static let shared = ConfigManager()

    private enum Keys {
        static let minPopupCooldown = "cfg_min_popup_cooldown"
        static let autoDismissDuration = "cfg_auto_dismiss_duration"
        static let snoozeDuration = "cfg_snooze_duration"
        static let midSurveyIntervalMin = "cfg_mid_survey_min"
        static let midSurveyIntervalMax = "cfg_mid_survey_max"
        static let muteDuration = "cfg_mute_duration"
        static let dailyNudgeHour = "cfg_daily_nudge_hour"
        static let dailyNudgeMinute = "cfg_daily_nudge_minute"
        static let idleThreshold = "cfg_idle_threshold"
        static let popupWidth = "cfg_popup_width"
        static let highFatigueThreshold = "cfg_high_fatigue_threshold"
        static let highUsefulnessThreshold = "cfg_high_usefulness_threshold"
    }

    // MARK: - 표준 연구 기본값 (Research Defaults)
    public struct Defaults {
        public static let minPopupCooldown: TimeInterval = 30 * 60       // 30분
        public static let autoDismissDuration: TimeInterval = 5 * 60     // 5분
        public static let snoozeDuration: TimeInterval = 10 * 60         // 10분
        public static let midSurveyIntervalMin: TimeInterval = 60 * 60   // 60분
        public static let midSurveyIntervalMax: TimeInterval = 120 * 60  // 120분 (표준: 60~120분 무작위 반복)
        public static let muteDuration: TimeInterval = 60 * 60           // 60분
        public static let dailyNudgeHour: Int = 18                       // 18시
        public static let dailyNudgeMinute: Int = 30                     // 30분
        public static let idleThreshold: TimeInterval = 2 * 60           // 2분
        public static let popupWidth: CGFloat = 372.0                    // 372pt
        public static let highFatigueThreshold: Int = 6                  // 피로 6점 이상 심층 전개
        public static let highUsefulnessThreshold: Int = 4               // 유용성 4점 이상 후속 전개
    }

    // MARK: - 빠른 테스트 모드 기본값 (Fast Debug Preset)
    public struct FastTestDefaults {
        public static let minPopupCooldown: TimeInterval = 0             // 0초 (즉시 반복 가능)
        public static let autoDismissDuration: TimeInterval = 30         // 30초
        public static let snoozeDuration: TimeInterval = 10              // 10초
        public static let midSurveyIntervalMin: TimeInterval = 60        // 1분
        public static let midSurveyIntervalMax: TimeInterval = 120       // 2분
        public static let muteDuration: TimeInterval = 5 * 60            // 5분
        public static let dailyNudgeHour: Int = 18
        public static let dailyNudgeMinute: Int = 30
        public static let idleThreshold: TimeInterval = 10               // 10초
        public static let popupWidth: CGFloat = 372.0
        public static let highFatigueThreshold: Int = 6
        public static let highUsefulnessThreshold: Int = 4
    }

    // MARK: - 동적 프로퍼티 (UserDefaults 영구 저장)
    @Published public var minPopupCooldown: TimeInterval {
        didSet { UserDefaults.standard.set(minPopupCooldown, forKey: Keys.minPopupCooldown) }
    }

    @Published public var autoDismissDuration: TimeInterval {
        didSet { UserDefaults.standard.set(autoDismissDuration, forKey: Keys.autoDismissDuration) }
    }

    @Published public var snoozeDuration: TimeInterval {
        didSet { UserDefaults.standard.set(snoozeDuration, forKey: Keys.snoozeDuration) }
    }

    @Published public var midSurveyIntervalMin: TimeInterval {
        didSet { UserDefaults.standard.set(midSurveyIntervalMin, forKey: Keys.midSurveyIntervalMin) }
    }

    @Published public var midSurveyIntervalMax: TimeInterval {
        didSet { UserDefaults.standard.set(midSurveyIntervalMax, forKey: Keys.midSurveyIntervalMax) }
    }

    @Published public var muteDuration: TimeInterval {
        didSet { UserDefaults.standard.set(muteDuration, forKey: Keys.muteDuration) }
    }

    @Published public var dailyNudgeHour: Int {
        didSet { UserDefaults.standard.set(dailyNudgeHour, forKey: Keys.dailyNudgeHour) }
    }

    @Published public var dailyNudgeMinute: Int {
        didSet { UserDefaults.standard.set(dailyNudgeMinute, forKey: Keys.dailyNudgeMinute) }
    }

    @Published public var idleThreshold: TimeInterval {
        didSet { UserDefaults.standard.set(idleThreshold, forKey: Keys.idleThreshold) }
    }

    @Published public var popupWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(popupWidth), forKey: Keys.popupWidth) }
    }

    @Published public var highFatigueThreshold: Int {
        didSet { UserDefaults.standard.set(highFatigueThreshold, forKey: Keys.highFatigueThreshold) }
    }

    @Published public var highUsefulnessThreshold: Int {
        didSet { UserDefaults.standard.set(highUsefulnessThreshold, forKey: Keys.highUsefulnessThreshold) }
    }

    private init() {
        // UserDefaults에서 로드하거나 표준 기본값 사용
        let ud = UserDefaults.standard

        self.minPopupCooldown = ud.object(forKey: Keys.minPopupCooldown) != nil
            ? ud.double(forKey: Keys.minPopupCooldown)
            : Defaults.minPopupCooldown

        self.autoDismissDuration = ud.object(forKey: Keys.autoDismissDuration) != nil
            ? ud.double(forKey: Keys.autoDismissDuration)
            : Defaults.autoDismissDuration

        self.snoozeDuration = ud.object(forKey: Keys.snoozeDuration) != nil
            ? ud.double(forKey: Keys.snoozeDuration)
            : Defaults.snoozeDuration

        self.midSurveyIntervalMin = ud.object(forKey: Keys.midSurveyIntervalMin) != nil
            ? ud.double(forKey: Keys.midSurveyIntervalMin)
            : Defaults.midSurveyIntervalMin

        let savedMidMax = ud.object(forKey: Keys.midSurveyIntervalMax) != nil
            ? ud.double(forKey: Keys.midSurveyIntervalMax)
            : Defaults.midSurveyIntervalMax
        // 기존 90분(5400초) 표준을 사용 중이었던 경우 새 표준 120분(7200초)으로 자동 상향
        let resolvedMidMax = (savedMidMax == 90 * 60) ? Defaults.midSurveyIntervalMax : savedMidMax
        self.midSurveyIntervalMax = resolvedMidMax
        if savedMidMax != resolvedMidMax {
            ud.set(resolvedMidMax, forKey: Keys.midSurveyIntervalMax)
        }

        self.muteDuration = ud.object(forKey: Keys.muteDuration) != nil
            ? ud.double(forKey: Keys.muteDuration)
            : Defaults.muteDuration

        self.dailyNudgeHour = ud.object(forKey: Keys.dailyNudgeHour) != nil
            ? ud.integer(forKey: Keys.dailyNudgeHour)
            : Defaults.dailyNudgeHour

        self.dailyNudgeMinute = ud.object(forKey: Keys.dailyNudgeMinute) != nil
            ? ud.integer(forKey: Keys.dailyNudgeMinute)
            : Defaults.dailyNudgeMinute

        self.idleThreshold = ud.object(forKey: Keys.idleThreshold) != nil
            ? ud.double(forKey: Keys.idleThreshold)
            : Defaults.idleThreshold

        self.popupWidth = ud.object(forKey: Keys.popupWidth) != nil
            ? CGFloat(ud.double(forKey: Keys.popupWidth))
            : Defaults.popupWidth

        self.highFatigueThreshold = ud.object(forKey: Keys.highFatigueThreshold) != nil
            ? ud.integer(forKey: Keys.highFatigueThreshold)
            : Defaults.highFatigueThreshold

        self.highUsefulnessThreshold = ud.object(forKey: Keys.highUsefulnessThreshold) != nil
            ? ud.integer(forKey: Keys.highUsefulnessThreshold)
            : Defaults.highUsefulnessThreshold
    }

    // MARK: - 편의 분/초 접근자 (UI 바인딩용)
    public var minCooldownMinutes: Double {
        get { minPopupCooldown / 60.0 }
        set { minPopupCooldown = max(0, newValue * 60.0) }
    }

    public var autoDismissMinutes: Double {
        get { autoDismissDuration / 60.0 }
        set { autoDismissDuration = max(5, newValue * 60.0) }
    }

    public var snoozeMinutes: Double {
        get { snoozeDuration / 60.0 }
        set { snoozeDuration = max(0.1, newValue * 60.0) }
    }

    public var midMinMinutes: Double {
        get { midSurveyIntervalMin / 60.0 }
        set { midSurveyIntervalMin = max(1, newValue * 60.0) }
    }

    public var midMaxMinutes: Double {
        get { midSurveyIntervalMax / 60.0 }
        set { midSurveyIntervalMax = max(midMinMinutes, newValue * 60.0) }
    }

    public var idleThresholdMinutes: Double {
        get { idleThreshold / 60.0 }
        set { idleThreshold = max(1, newValue * 60.0) }
    }

    // MARK: - 시간 배속 모드 (1분 = 30분, 30배속 파일럿 디버그)
    @Published public var isTimeWarpActive: Bool = false

    public func toggleTimeWarp() {
        if isTimeWarpActive {
            disableTimeWarp()
        } else {
            applyTimeWarp()
        }
    }

    public func applyTimeWarp() {
        isTimeWarpActive = true
        // 1분 = 30분 (30배속)
        minPopupCooldown = 60                 // 30분 쿨다운 -> 1분 (60초)
        midSurveyIntervalMin = 120            // 60분 간격 -> 2분 (120초)
        midSurveyIntervalMax = 240            // 120분 간격 -> 4분 (240초)
        snoozeDuration = 20                   // 10분 스누즈 -> 20초
        muteDuration = 120                    // 60분 팝업 끄기 -> 2분 (120초)
        autoDismissDuration = 10              // 5분 타임아웃 -> 10초
        idleThreshold = 10                    // 2분 유휴 판정 -> 10초
    }

    public func disableTimeWarp() {
        isTimeWarpActive = false
        resetToDefaults()
    }

    // MARK: - 프리셋 복원 함수
    public func resetToDefaults() {
        isTimeWarpActive = false
        minPopupCooldown = Defaults.minPopupCooldown
        autoDismissDuration = Defaults.autoDismissDuration
        snoozeDuration = Defaults.snoozeDuration
        midSurveyIntervalMin = Defaults.midSurveyIntervalMin
        midSurveyIntervalMax = Defaults.midSurveyIntervalMax
        muteDuration = Defaults.muteDuration
        dailyNudgeHour = Defaults.dailyNudgeHour
        dailyNudgeMinute = Defaults.dailyNudgeMinute
        idleThreshold = Defaults.idleThreshold
        popupWidth = Defaults.popupWidth
        highFatigueThreshold = Defaults.highFatigueThreshold
        highUsefulnessThreshold = Defaults.highUsefulnessThreshold
    }

    public func applyFastTestPreset() {
        minPopupCooldown = FastTestDefaults.minPopupCooldown
        autoDismissDuration = FastTestDefaults.autoDismissDuration
        snoozeDuration = FastTestDefaults.snoozeDuration
        midSurveyIntervalMin = FastTestDefaults.midSurveyIntervalMin
        midSurveyIntervalMax = FastTestDefaults.midSurveyIntervalMax
        muteDuration = FastTestDefaults.muteDuration
        dailyNudgeHour = FastTestDefaults.dailyNudgeHour
        dailyNudgeMinute = FastTestDefaults.dailyNudgeMinute
        idleThreshold = FastTestDefaults.idleThreshold
        popupWidth = FastTestDefaults.popupWidth
        highFatigueThreshold = FastTestDefaults.highFatigueThreshold
        highUsefulnessThreshold = FastTestDefaults.highUsefulnessThreshold
    }

    /// 현재 시각 + 1분 뒤로 데일리 넛지 시각을 설정 (테스트용)
    public func setNudgeToNextMinute() {
        let calendar = Calendar.current
        let nextMinute = Date().addingTimeInterval(60)
        dailyNudgeHour = calendar.component(.hour, from: nextMinute)
        dailyNudgeMinute = calendar.component(.minute, from: nextMinute)
    }

    /// 초 단위를 'N분' 또는 'N분 N초' 또는 'N초' 형태로 가독성 있게 변환
    public static func formatDuration(_ sec: TimeInterval) -> String {
        let s = Int(sec)
        if s <= 0 { return "0초" }
        if s < 60 { return "\(s)초" }
        let m = s / 60
        let remS = s % 60
        if remS == 0 {
            return "\(m)분"
        } else {
            return "\(m)분 \(remS)초"
        }
    }
}
