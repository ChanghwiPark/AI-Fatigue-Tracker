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
        "\(emoji) \(title)"
    }

    public static let allCategories: [FatigueReasonCategory] = [
        FatigueReasonCategory(
            id: "overload",
            emoji: "🧠",
            title: "머리가 과부하돼요",
            chipOptions: [
                "결과가 너무 길거나 많아요",
                "하나하나 확인하느라 지쳐요"
            ]
        ),
        FatigueReasonCategory(
            id: "motivationLoss",
            emoji: "🪫",
            title: "의욕이 떨어져요",
            chipOptions: [
                "생각하기 전에 AI부터 찾게 돼요",
                "내 능력에 자신이 없어져요"
            ]
        ),
        FatigueReasonCategory(
            id: "discomfort",
            emoji: "😣",
            title: "마음이 불편해요",
            chipOptions: [
                "내 힘으로 한 게 아닌 것 같아요",
                "결과물만큼 이해하지 못해 불안해요"
            ]
        ),
        FatigueReasonCategory(
            id: "physicalTired",
            emoji: "🧍",
            title: "몸이 지쳐요",
            chipOptions: [
                "화면을 많이 읽어 눈이 피로해요",
                "오래 붙잡고 있어 몸이 지쳤어요"
            ]
        ),
        FatigueReasonCategory(
            id: "distracted",
            emoji: "🌀",
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

/// 유용성 기준값 이상일 때 나타나는 유용성 칩 옵션
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
    // 1. 공통 척도 점수
    @Published public var fatigueScore: Int? = nil       // 0~10
    @Published public var usefulnessScore: Int? = nil    // 1~5

    // 2. [start] 전용 상태
    @Published public var startPurpose: SubjectiveAnswer = SubjectiveAnswer()

    // 3. [end] 전용 상태
    @Published public var endTLX: NASA_TLXScores = NASA_TLXScores()
    @Published public var endUsefulnessHelp: SubjectiveAnswer = SubjectiveAnswer()

    // 4. [피로 6점 이상] 심층 질문 상태 (공통)
    @Published public var selectedFatigueCategories: Set<String> = []
    @Published public var fatigueCategoryDetails: [String: SubjectiveAnswer] = [:]

    // 5. NASA-TLX 슬라이더 조작 여부
    @Published public var isTLXModified: Bool = false

    // 6. 텍스트 입력 필드 활성/포커스 여부
    @Published public var isTextFieldFocused: Bool = false

    public init(fatigueScore: Int? = nil, usefulnessScore: Int? = nil) {
        self.fatigueScore = fatigueScore
        self.usefulnessScore = usefulnessScore
    }

    /// 피로도가 기준값(Config.Survey.highFatigueThreshold, 기본 6점) 이상인지 여부
    public var isHighFatigue: Bool {
        guard let score = fatigueScore else { return false }
        return score >= Config.Survey.highFatigueThreshold
    }

    /// 유용성이 기준값(Config.Survey.highUsefulnessThreshold, 기본 4점) 이상인지 여부
    public var isHighUsefulness: Bool {
        guard let score = usefulnessScore else { return false }
        return score >= Config.Survey.highUsefulnessThreshold
    }

    /// 사용자가 설문 폼에 하나라도 입력을 시작했는지 여부 (무응답 상태 탈피 여부)
    public var hasAnyInput: Bool {
        // 1. 피로도나 유용성 점수를 하나라도 선택한 경우
        if fatigueScore != nil || usefulnessScore != nil {
            return true
        }

        // 2. [start] 목적 입력칸에 글을 쓰거나 칩을 선택한 경우
        let purposeText = startPurpose.customText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !purposeText.isEmpty || !startPurpose.selectedChips.isEmpty || startPurpose.isNoSpecificPurpose {
            return true
        }

        // 3. 심층 피로 카테고리를 하나라도 선택한 경우
        if !selectedFatigueCategories.isEmpty {
            return true
        }

        // 4. [end] 유용성 후속 답변을 작성한 경우
        let helpText = endUsefulnessHelp.customText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !helpText.isEmpty || !endUsefulnessHelp.selectedChips.isEmpty {
            return true
        }

        // 5. [end] TLX 슬라이더를 하나라도 조작한 경우
        if isTLXModified {
            return true
        }

        // 6. 텍스트 필드를 클릭하여 입력 대기/작성 중인 경우
        if isTextFieldFocused {
            return true
        }

        return false
    }

    /// 각 설문 유형별 필수 문항 충족 여부 (미충족 시 저장 버튼 비활성화)
    public func isFormValid(for type: SurveyType) -> Bool {
        switch type {
        case .start:
            // 문항 1. 목적 (주관식 텍스트 또는 '특별한 목적 없음' 칩)
            let hasPurpose = startPurpose.isNoSpecificPurpose ||
                !startPurpose.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // 문항 2. 피로도 (0~10)
            let hasFatigue = fatigueScore != nil
            return hasPurpose && hasFatigue

        case .mid, .diary:
            // 문항 1. 피로도 (0~10)
            return fatigueScore != nil

        case .end:
            // 문항 1. 피로도 (0~10)
            // 문항 2. 유용성 (1~5)
            // 문항 3. 이번 작업은 어땠나요? (NASA-TLX 슬라이더 조작 필수)
            return fatigueScore != nil && usefulnessScore != nil && isTLXModified

        case .nudge:
            return true
        }
    }

    // MARK: - 칩 및 카테고리 토글 액션

    /// 주관식 칸 아래 칩 탭 핸들러 (여러 개 선택 가능, 텍스트에 추가/반영 및 해제 시 제거)
    public func toggleChip(in answer: inout SubjectiveAnswer, chip: String) {
        if let idx = answer.selectedChips.firstIndex(of: chip) {
            answer.selectedChips.remove(at: idx)
            // 칩 해제 시 customText에서 해당 칩 문구를 깔끔하게 제거
            var items = answer.customText.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
            items.removeAll(where: { $0 == chip })
            answer.customText = items.joined(separator: ", ")
        } else {
            answer.selectedChips.append(chip)
            if answer.customText.isEmpty {
                answer.customText = chip
            } else if !answer.customText.contains(chip) {
                answer.customText += ", " + chip
            }
        }
    }

    /// [start] "특별한 목적 없음" 칩 토글
    public func toggleNoSpecificPurpose() {
        startPurpose.isNoSpecificPurpose.toggle()
        if startPurpose.isNoSpecificPurpose {
            startPurpose.customText = ""
            startPurpose.selectedChips = ["특별한 목적 없음"]
        } else {
            startPurpose.selectedChips.removeAll()
        }
    }

    /// 피로 카테고리 토글
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

        if let f = fatigueScore {
            payload["fatigue_score"] = "\(f)"
        }
        // AI 유용성 척도는 [end] AI 세션 종료 설문 전용
        if type == .end, let u = usefulnessScore {
            payload["usefulness_score"] = "\(u)"
        }

        switch type {
        case .start:
            payload["purpose_is_none"] = "\(startPurpose.isNoSpecificPurpose)"
            payload["purpose_chips"] = startPurpose.selectedChips.joined(separator: "|")
            payload["purpose_custom_text"] = startPurpose.customText
            payload["purpose_final"] = startPurpose.displayText

        case .mid:
            break

        case .end:
            payload["tlx_mental"] = "\(endTLX.mentalDemand)"
            payload["tlx_physical"] = "\(endTLX.physicalDemand)"
            payload["tlx_temporal"] = "\(endTLX.temporalDemand)"
            payload["tlx_performance"] = "\(endTLX.performance)"
            payload["tlx_effort"] = "\(endTLX.effort)"
            payload["tlx_frustration"] = "\(endTLX.frustration)"

        case .diary, .nudge:
            break
        }

        // 유용성 기준값 이상 시 후속 질문 결과 ([end] 설문 전용)
        if type == .end && isHighUsefulness {
            payload["help_chips"] = endUsefulnessHelp.selectedChips.joined(separator: "|")
            payload["help_custom_text"] = endUsefulnessHelp.customText
            payload["help_final"] = endUsefulnessHelp.displayText
        }

        // 심층 피로 질문 결과 (피로 6점 이상 공통)
        if isHighFatigue {
            payload["fatigue_categories"] = Array(selectedFatigueCategories).sorted().joined(separator: "|")

            for catId in selectedFatigueCategories {
                if let detail = fatigueCategoryDetails[catId] {
                    payload["fatigue_\(catId)_chips"] = detail.selectedChips.joined(separator: "|")
                    payload["fatigue_\(catId)_custom_text"] = detail.customText
                    payload["fatigue_\(catId)_final"] = detail.displayText
                }
            }
        }

        return payload
    }
}
