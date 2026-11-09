import Foundation
import SwiftUI

/// 주관식 응답 데이터 구조 (분석 시 칩 선택과 직접 작성 문장을 명확히 구분)
public struct SubjectiveAnswer: Codable, Equatable {
    /// 탭하여 선택한 칩 목록 (연구 지표 코드 및 프리셋과 직접 연동)
    public var selectedChips: [String] = []

    /// 사용자가 직접 타이핑하거나 음성으로 수정한 텍스트
    public var customText: String = ""

    /// [start] 전용 "특별한 목적 없음" 선택 여부
    public var isNoSpecificPurpose: Bool = false

    public init(
        selectedChips: [String] = [],
        customText: String = "",
        isNoSpecificPurpose: Bool = false
    ) {
        self.selectedChips = selectedChips
        self.customText = customText
        self.isNoSpecificPurpose = isNoSpecificPurpose
    }

    /// 화면 표시 및 최종 저장용 종합 텍스트
    public var displayText: String {
        if isNoSpecificPurpose {
            return "특별한 목적 없음"
        }
        if !customText.isEmpty {
            return customText
        }
        return selectedChips.joined(separator: ", ")
    }
}

/// NASA-TLX 6개 슬라이더 평가 척도 (0~100, 5단위)
public struct NASA_TLXScores: Codable, Equatable {
    public var mentalDemand: Int = 50     // 정신적 요구
    public var physicalDemand: Int = 50   // 신체적 요구
    public var temporalDemand: Int = 50   // 시간 압박
    public var performance: Int = 50      // 성과 만족
    public var effort: Int = 50           // 노력
    public var frustration: Int = 50      // 좌절감

    public init(
        mentalDemand: Int = 50,
        physicalDemand: Int = 50,
        temporalDemand: Int = 50,
        performance: Int = 50,
        effort: Int = 50,
        frustration: Int = 50
    ) {
        self.mentalDemand = mentalDemand
        self.physicalDemand = physicalDemand
        self.temporalDemand = temporalDemand
        self.performance = performance
        self.effort = effort
        self.frustration = frustration
    }
}

/// 피로 6점 이상일 때 펼쳐지는 심층 원인 카테고리 정의
public struct FatigueReasonCategory: Identifiable {
    public let id: String
    public let emoji: String
    public let title: String
    public let chipOptions: [String]

    public var displayTitle: String {
        if emoji.isEmpty {
            return title
        }
        return "\(emoji) \(title)"
    }

    public static let allCategories: [FatigueReasonCategory] = [
        FatigueReasonCategory(
            id: "overload",
            emoji: "",
            title: "머리가 과부하돼요",
            chipOptions: [
                "결과가 너무 길거나 많아요",
                "하나하나 확인하느라 지쳐요"
            ]
        ),
        FatigueReasonCategory(
            id: "motivationLoss",
            emoji: "",
            title: "의욕이 떨어져요",
            chipOptions: [
                "생각하기 전에 AI부터 찾게 돼요",
                "내 능력에 자신이 없어져요"
            ]
        ),
        FatigueReasonCategory(
            id: "discomfort",
            emoji: "",
            title: "마음이 불편해요",
            chipOptions: [
                "내 힘으로 한 게 아닌 것 같아요",
                "결과물만큼 이해하지 못해 불안해요"
            ]
        ),
        FatigueReasonCategory(
            id: "physicalTired",
            emoji: "",
            title: "몸이 지쳐요",
            chipOptions: [
                "화면을 많이 읽어 눈이 피로해요",
                "오래 붙잡고 있어 몸이 지쳤어요"
            ]
        ),
        FatigueReasonCategory(
            id: "distracted",
            emoji: "",
            title: "집중이 흐트러져요",
            chipOptions: [
                "여러 창과 대화를 오가느라 정신이 없어요",
                "AI에 익숙해져서 이제 AI 없이 일하면 답답하고 조급해져요"
            ]
        ),
        FatigueReasonCategory(
            id: "other",
            emoji: "",
            title: "기타",
            chipOptions: [
                "권한 승인을 기다리느라 자리를 뜰 수가 없어요",
                "AI가 돌아가는 동안 계속 신경이 쓰여요",
                "더 잘할 수 있을것 같아서 계속 AI를 시켜 다듬게 돼요",
                "안 쓰면 뒤처질 것 같아서 필요 없을 때도 쓰게 돼요"
            ]
        )
    ]
}

/// 리커트 5점 척도 선택 항목 정의 (값, 버튼 라벨, 호버 설명)
public struct LikertScaleOption: Identifiable, Equatable {
    public let value: Int
    public let label: String
    public let description: String
    public var id: Int { value }

    public init(value: Int, label: String, description: String) {
        self.value = value
        self.label = label
        self.description = description
    }
}

/// 2026 설문 개편 표준 5점 척도 항목 정의 (라벨 및 호버 툴팁 설명)
public enum SurveyScaleDefinitions {
    /// 1. 피로도 5점 척도 ("지금 얼마나 피로한가요?")
    public static let fatigueScale: [LikertScaleOption] = [
        LikertScaleOption(value: 1, label: "전혀", description: "전혀 피로하지 않아요. 활기차고 개운해요."),
        LikertScaleOption(value: 2, label: "조금", description: "조금 피로해요. 처음보다 개운함이 살짝 줄었어요."),
        LikertScaleOption(value: 3, label: "다소", description: "다소 피로해요. 기운이 빠지는 게 느껴져요."),
        LikertScaleOption(value: 4, label: "많이", description: "많이 피로해요. 기운이 없고 지친 느낌이에요."),
        LikertScaleOption(value: 5, label: "매우", description: "매우 피로해요. 완전히 지쳐서 기운이 하나도 없어요.")
    ]

    /// 2. AI가 피로에 준 영향 5점 척도 ("지금 피로에 AI가 얼마나 영향을 주었나요?")
    public static let aiImpactScale: [LikertScaleOption] = [
        LikertScaleOption(value: 1, label: "전혀", description: "AI는 지금 피로와 상관없어요."),
        LikertScaleOption(value: 2, label: "조금", description: "AI 때문에 조금 더 피로하지만, 신경 쓰일 정도는 아니에요."),
        LikertScaleOption(value: 3, label: "다소", description: "AI를 쓰면서 피로해진 게 느껴져요."),
        LikertScaleOption(value: 4, label: "많이", description: "AI 때문에 확실히 더 피로해요."),
        LikertScaleOption(value: 5, label: "매우", description: "AI가 지금 피로의 주된 원인이에요.")
    ]

    /// 3. AI 유용성 5점 척도 ("AI가 얼마나 도움이 되고 있나요/되었나요?")
    public static let usefulnessScale: [LikertScaleOption] = [
        LikertScaleOption(value: 1, label: "전혀", description: "도움이 되지 않아요. 안 쓰는 게 나을 것 같아요."),
        LikertScaleOption(value: 2, label: "조금", description: "조금 도움이 되지만, 혼자 해도 큰 차이는 없어요."),
        LikertScaleOption(value: 3, label: "다소", description: "들인 노력만큼은 도움이 돼요."),
        LikertScaleOption(value: 4, label: "많이", description: "혼자 할 때보다 확실히 빠르거나 나아요."),
        LikertScaleOption(value: 5, label: "매우", description: "AI 없이는 이만큼 하기 어려워요.")
    ]
}

/// AI 피로 영향 2점(조금) 이상일 때 선택할 수 있는 추천 칩 목록 ("피로하다고 느낀 점")
public enum FatigueReasonChipOptions {
    public static let items: [String] = [
        "결과가 너무 길거나 많아요",
        "하나하나 확인하느라 지쳐요",
        "원하는 답이 안 나와 계속 수정해요",
        "AI가 돌아가는 동안 계속 신경이 쓰여요",
        "내 힘으로 한 게 아닌 것 같아 마음이 불편해요",
        "화면을 오래 읽어 눈이 피로해요"
    ]
}

/// 유용성 2점(조금) 이상일 때 선택할 수 있는 추천 칩 목록
public enum UsefulnessChipOptions {
    public static let items: [String] = [
        "시간이 줄었어요",
        "막힌 걸 풀어줬어요",
        "아이디어를 얻었어요",
        "초안을 빨리 만들었어요",
        "확인과 검토를 대신해줬어요"
    ]
}

/// 설문 화면의 모든 입력 상태를 안전하게 보존하는 폼 상태 관리자
/// - 점수를 바꾸어 화면이 다시 그려지거나 접히더라도 써 둔 내용이 절대로 지워지지 않음
public final class SurveyFormState: ObservableObject {
    // 1. 공통 5점 척도 점수 (라벨 선택: 전혀/조금/다소/많이/매우)
    @Published public var fatigueScore: Int? = nil            // 지금 얼마나 피로한가요? (1~5)
    @Published public var aiFatigueImpactScore: Int? = nil    // 지금 피로에 AI가 얼마나 영향을 주었나요? (1~5)
    @Published public var usefulnessScore: Int? = nil         // AI가 얼마나 도움이 되고 있나요/되었나요? (1~5)

    // 2. 사용 목적 및 역할 분담 (시작, 중간, 자발적 기록 필수)
    @Published public var taskPurpose: SubjectiveAnswer = SubjectiveAnswer() // 어떤 작업을 하려고/하고 있나요?
    @Published public var aiRole: SubjectiveAnswer = SubjectiveAnswer()      // AI가 어떤 도움을 주길 기대/주고 있나요?
    @Published public var myRole: SubjectiveAnswer = SubjectiveAnswer()      // 나는 무엇을 할 예정/하고 있나요?

    // 3. 이유 문항 (조건부 및 선택)
    @Published public var fatigueReasonAI: SubjectiveAnswer = SubjectiveAnswer()    // AI로 인한 이유 (AI 영향도에 따른 조건부 질문)
    @Published public var fatigueReasonNonAI: SubjectiveAnswer = SubjectiveAnswer() // 그 외의 이유 (선택)
    @Published public var usefulnessReason: SubjectiveAnswer = SubjectiveAnswer()   // 유용성 이유 (유용성에 따른 조건부 질문)

    // 4. 후속 설문 (.followUp, 피로 2점 이상 30분 뒤)
    @Published public var fatigueImpactOnWork: String = ""       // 피로를 느낀 뒤, 작업하는 방식이 달라진 점이 있나요?
    @Published public var isNoImpactOnWork: Bool = false         // [ ] 없음
    @Published public var copingStrategy: String = ""            // 그 사이 피로를 줄이려고 해 본 것이 있나요?
    @Published public var isNoCopingStrategy: Bool = false       // [ ] 없음
    @Published public var improvementIdea: String = ""           // AI, 나, 또는 조직 차원에서 무엇이 달랐다면 덜 피로했을까요? (선택)

    // 5. 화면 캡처 경로 (중간, 자발적 기록 선택 및 사용 목적 대체 가능)
    @Published public var capturedImagePath: String? = nil

    // 6. NASA-TLX 6개 슬라이더 [end 전용]
    @Published public var endTLX: NASA_TLXScores = NASA_TLXScores()
    @Published public var isTLXModified: Bool = false

    // 7. 하위 호환 필드 (기존 뷰/프로퍼티 연동)
    @Published public var selectedFatigueCategories: Set<String> = []
    @Published public var fatigueCategoryDetails: [String: SubjectiveAnswer] = [:]
    @Published public var isTextFieldFocused: Bool = false

    // 하위 호환 브리지 프로퍼티
    public var startPurpose: SubjectiveAnswer {
        get { taskPurpose }
        set { taskPurpose = newValue }
    }
    public var situationAnswer: SubjectiveAnswer {
        get { taskPurpose }
        set { taskPurpose = newValue }
    }
    public var fatigueReasonAnswer: SubjectiveAnswer {
        get { fatigueReasonAI }
        set { fatigueReasonAI = newValue }
    }
    public var endUsefulnessHelp: SubjectiveAnswer {
        get { usefulnessReason }
        set { usefulnessReason = newValue }
    }

    public init(
        fatigueScore: Int? = nil,
        aiFatigueImpactScore: Int? = nil,
        usefulnessScore: Int? = nil,
        capturedImagePath: String? = nil
    ) {
        self.fatigueScore = fatigueScore
        self.aiFatigueImpactScore = aiFatigueImpactScore
        self.usefulnessScore = usefulnessScore
        self.capturedImagePath = capturedImagePath
    }

    /// AI 피로 영향 질문 노출 여부
    public var isAIFatigueImpactVisible: Bool {
        // [중간, 종료, 자발적]에서는 피로도와 무관하게 필수 문항으로 노출됨
        return true
    }

    /// 피로 이유 질문 노출 여부 (AI 피로도가 선택되었을 때 노출)
    public var isFatigueTypeVisible: Bool {
        return aiFatigueImpactScore != nil
    }

    public var isHighFatigue: Bool {
        guard let score = fatigueScore else { return false }
        return score >= 2
    }

    public var isLowFatigue: Bool {
        guard let score = fatigueScore else { return false }
        return score == 1
    }

    public var isHighUsefulness: Bool {
        guard let score = usefulnessScore else { return false }
        return score >= 2
    }

    /// 사용자가 설문 폼에 하나라도 입력을 시작했는지 여부 (무응답 상태 탈피 여부)
    public var hasAnyInput: Bool {
        if fatigueScore != nil || aiFatigueImpactScore != nil || usefulnessScore != nil {
            return true
        }

        let purposeText = taskPurpose.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !purposeText.isEmpty || taskPurpose.isNoSpecificPurpose {
            return true
        }

        let aiRoleText = aiRole.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !aiRoleText.isEmpty {
            return true
        }

        let myRoleText = myRole.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !myRoleText.isEmpty {
            return true
        }

        let fatigueReasonText = fatigueReasonAI.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fatigueReasonText.isEmpty {
            return true
        }

        let nonAIText = fatigueReasonNonAI.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nonAIText.isEmpty {
            return true
        }

        let helpText = usefulnessReason.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !helpText.isEmpty {
            return true
        }

        if !fatigueImpactOnWork.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isNoImpactOnWork {
            return true
        }

        if !copingStrategy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isNoCopingStrategy {
            return true
        }

        if !improvementIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if capturedImagePath != nil {
            return true
        }

        if !selectedFatigueCategories.isEmpty {
            return true
        }

        if isTLXModified {
            return true
        }

        if isTextFieldFocused {
            return true
        }

        return false
    }

    /// 각 설문 유형별 필수 문항 충족 여부 (미충족 시 저장 버튼 비활성화)
    public func isFormValid(for type: SurveyType) -> Bool {
        switch type {
        case .start:
            // 1. 사용 목적 (주관식 필수 ●)
            let hasPurpose = !taskPurpose.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || taskPurpose.isNoSpecificPurpose
            guard hasPurpose else { return false }

            // 2. AI가 하는 일 (기대, 필수 ●)
            let hasAIRole = !aiRole.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasAIRole else { return false }

            // 3. 내가 하는 일 (예정, 필수 ●)
            let hasMyRole = !myRole.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasMyRole else { return false }

            // 4. 피로도 (5점 척도 필수 ●)
            guard fatigueScore != nil else { return false }

            return true

        case .mid:
            // 1. 사용 목적 (주관식 또는 화면 캡처 첨부 둘 중 하나 이상 충족 시 유효)
            let hasPurpose = !taskPurpose.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasCapture = (capturedImagePath != nil && !capturedImagePath!.isEmpty)
            guard hasPurpose || hasCapture else { return false }

            // 2. AI가 하는 일 (실제, 필수 ●)
            let hasAIRole = !aiRole.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasAIRole else { return false }

            // 3. 내가 하는 일 (실제, 필수 ●)
            let hasMyRole = !myRole.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasMyRole else { return false }

            // 4. 피로도 (5점 척도 필수 ●)
            guard fatigueScore != nil else { return false }

            // 5. AI 피로도 (5점 척도 필수 ●)
            guard aiFatigueImpactScore != nil else { return false }

            // 6. AI 유용성 (5점 척도 필수 ●)
            guard usefulnessScore != nil else { return false }

            return true

        case .end:
            // 1. 피로도 (5점 척도 필수 ●)
            guard fatigueScore != nil else { return false }

            // 2. AI 피로도 (5점 척도 필수 ●)
            guard aiFatigueImpactScore != nil else { return false }

            // 3. AI 유용성 (5점 척도 필수 ●)
            guard usefulnessScore != nil else { return false }

            // 4. NASA-TLX (슬라이더 조작 필수 ●)
            guard isTLXModified else { return false }

            return true

        case .diary:
            // 1. 사용 목적 (주관식 또는 화면 캡처 첨부 둘 중 하나 이상 충족 시 유효)
            let hasPurpose = !taskPurpose.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasCapture = (capturedImagePath != nil && !capturedImagePath!.isEmpty)
            guard hasPurpose || hasCapture else { return false }

            // 2. AI가 하는 일 (실제, 필수 ●)
            let hasAIRole = !aiRole.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasAIRole else { return false }

            // 3. 내가 하는 일 (실제, 필수 ●)
            let hasMyRole = !myRole.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasMyRole else { return false }

            // 4. 피로도 (5점 척도 필수 ●)
            guard fatigueScore != nil else { return false }

            // 5. AI 피로도 (5점 척도 필수 ●)
            guard aiFatigueImpactScore != nil else { return false }

            return true

        case .followUp:
            // 1. 피로의 영향 (텍스트 입력 또는 '없음' 체크 필수 ●)
            let hasImpact = !fatigueImpactOnWork.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isNoImpactOnWork
            guard hasImpact else { return false }

            // 2. 대처 방식 (텍스트 입력 또는 '없음' 체크 필수 ●)
            let hasCoping = !copingStrategy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isNoCopingStrategy
            guard hasCoping else { return false }

            return true

        case .nudge:
            return true
        }
    }

    // MARK: - 카테고리 토글 액션 (하위 호환)
    public func toggleFatigueCategory(id: String) {
        if selectedFatigueCategories.contains(id) {
            selectedFatigueCategories.remove(id)
        } else {
            selectedFatigueCategories.insert(id)
            if fatigueCategoryDetails[id] == nil {
                fatigueCategoryDetails[id] = SubjectiveAnswer()
            }
        }
    }

    // MARK: - 데이터 저장용 페이로드 직렬화
    public func toResponsePayload(type: SurveyType) -> [String: String] {
        var payload: [String: String] = [:]

        // 1. 피로도 점수 (1~5)
        if let f = fatigueScore {
            payload["fatigue_score"] = "\(f)"
        }

        // 2. AI 피로 영향 점수 (1~5)
        if let impact = aiFatigueImpactScore {
            payload["ai_fatigue_impact_score"] = "\(impact)"
            payload["ai_impact_score"] = "\(impact)"
        }

        // 3. AI 유용성 점수 (1~5)
        if let u = usefulnessScore {
            payload["usefulness_score"] = "\(u)"
        }

        // 4. 화면 캡처 경로
        if let cap = capturedImagePath, !cap.isEmpty {
            payload["capture_path"] = cap
        }

        // 5. 작업 목적 및 역할 분담
        let purposeText = taskPurpose.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !purposeText.isEmpty || taskPurpose.isNoSpecificPurpose {
            payload["task_purpose"] = purposeText
            payload["purpose_final"] = purposeText
            payload["purpose_is_none"] = "\(taskPurpose.isNoSpecificPurpose)"
            payload["purpose_custom_text"] = taskPurpose.customText
            if !taskPurpose.selectedChips.isEmpty {
                payload["purpose_chips"] = taskPurpose.selectedChips.joined(separator: "|")
            }
        }

        let aiRoleText = aiRole.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !aiRoleText.isEmpty {
            payload["ai_role"] = aiRoleText
            payload["ai_role_custom_text"] = aiRole.customText
            if !aiRole.selectedChips.isEmpty {
                payload["ai_role_chips"] = aiRole.selectedChips.joined(separator: "|")
            }
        }

        let myRoleText = myRole.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !myRoleText.isEmpty {
            payload["my_role"] = myRoleText
            payload["my_role_custom_text"] = myRole.customText
            if !myRole.selectedChips.isEmpty {
                payload["my_role_chips"] = myRole.selectedChips.joined(separator: "|")
            }
        }

        // 6. AI로 인한 이유
        let aiReasonText = fatigueReasonAI.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !aiReasonText.isEmpty {
            payload["fatigue_reason_ai"] = aiReasonText
            payload["fatigue_reason_final"] = aiReasonText
            payload["fatigue_reason_custom_text"] = fatigueReasonAI.customText
            if !fatigueReasonAI.selectedChips.isEmpty {
                payload["fatigue_reason_chips"] = fatigueReasonAI.selectedChips.joined(separator: "|")
            }
        }

        // 7. 그 외의 이유
        let nonAIReasonText = fatigueReasonNonAI.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nonAIReasonText.isEmpty {
            payload["fatigue_reason_non_ai"] = nonAIReasonText
            payload["fatigue_reason_non_ai_custom_text"] = fatigueReasonNonAI.customText
        }

        // 8. 유용성 이유
        let usefulnessReasonText = usefulnessReason.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !usefulnessReasonText.isEmpty {
            payload["usefulness_reason"] = usefulnessReasonText
            payload["help_final"] = usefulnessReasonText
            payload["help_custom_text"] = usefulnessReason.customText
            if !usefulnessReason.selectedChips.isEmpty {
                payload["help_chips"] = usefulnessReason.selectedChips.joined(separator: "|")
            }
        }

        // 9. NASA-TLX 6개 점수 [end 전용]
        if type == .end {
            payload["tlx_mental"] = "\(endTLX.mentalDemand)"
            payload["tlx_physical"] = "\(endTLX.physicalDemand)"
            payload["tlx_temporal"] = "\(endTLX.temporalDemand)"
            payload["tlx_performance"] = "\(endTLX.performance)"
            payload["tlx_effort"] = "\(endTLX.effort)"
            payload["tlx_frustration"] = "\(endTLX.frustration)"
        }

        // 10. 후속 설문 [.followUp 전용]
        if type == .followUp {
            payload["fatigue_impact_on_work"] = isNoImpactOnWork ? "없음" : fatigueImpactOnWork
            payload["is_no_impact_on_work"] = "\(isNoImpactOnWork)"
            payload["coping_strategy"] = isNoCopingStrategy ? "없음" : copingStrategy
            payload["is_no_coping_strategy"] = "\(isNoCopingStrategy)"
            if !improvementIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["improvement_idea"] = improvementIdea
            }
        }

        return payload
    }
}
