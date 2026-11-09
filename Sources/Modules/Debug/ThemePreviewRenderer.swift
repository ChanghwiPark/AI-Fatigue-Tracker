import AppKit
import SwiftUI

/// 온보딩 (1단계 및 2단계), 설정, 설문 팝업의 라이트 모드 및 다크 모드 렌더링 검증 렌더러
public enum ThemePreviewRenderer {
    public static func renderAllThemePreviews() {
        let artifactDir = "/Users/changhwipark/.gemini/antigravity/brain/82ec1a28-761a-4ba5-90d2-51afaaddcf8f"

        print("🎨 [ThemePreviewRenderer] 라이트/다크 모드 실제 화면 스냅샷 렌더링 시작...")

        // 0. 온보딩 환영 화면 (첫 페이지)
        renderView(OnboardingView(initialStep: 0), width: 540, height: 600, appearance: .aqua, path: "\(artifactDir)/theme_onboarding_step0_light.png")
        renderView(OnboardingView(initialStep: 0), width: 540, height: 600, appearance: .darkAqua, path: "\(artifactDir)/theme_onboarding_step0_dark.png")

        // 1. 온보딩 1단계 화면 (참여자 등록)
        renderView(OnboardingView(initialStep: 1), width: 540, height: 600, appearance: .aqua, path: "\(artifactDir)/theme_onboarding_step1_light.png")
        renderView(OnboardingView(initialStep: 1), width: 540, height: 600, appearance: .darkAqua, path: "\(artifactDir)/theme_onboarding_step1_dark.png")

        // 2. 온보딩 2단계 화면 (권한 설정 - 모든 권한 허용 완료 상태 - 사용자 제보 화면과 1:1 비교 검증)
        PermissionsManager.shared.refreshAll()
        PermissionsManager.shared.isAccessibilityGranted = true
        for b in PermissionsManager.shared.installedBrowsers {
            PermissionsManager.shared.browserAutomationStatuses[b.bundleId] = true
        }
        PermissionsManager.shared.isScreenCaptureGranted = true
        PermissionsManager.shared.isMicrophoneGranted = true
        PermissionsManager.shared.isSpeechRecognitionGranted = true
        renderView(OnboardingView(initialStep: 2), width: 540, height: 600, appearance: .darkAqua, path: "\(artifactDir)/theme_onboarding_step2_all_granted_dark.png")
        PermissionsManager.shared.refreshAll()

        renderView(OnboardingView(initialStep: 2), width: 540, height: 600, appearance: .aqua, path: "\(artifactDir)/theme_onboarding_step2_light.png")
        renderView(OnboardingView(initialStep: 2), width: 540, height: 600, appearance: .darkAqua, path: "\(artifactDir)/theme_onboarding_step2_dark.png")

        // 3. 온보딩 3단계 화면 (설정 완료 및 시작 안내)
        renderView(OnboardingView(initialStep: 3), width: 540, height: 600, appearance: .aqua, path: "\(artifactDir)/theme_onboarding_step3_light.png")
        renderView(OnboardingView(initialStep: 3), width: 540, height: 600, appearance: .darkAqua, path: "\(artifactDir)/theme_onboarding_step3_dark.png")

        // 4. 설정 화면 (연구 완료 배너 표시 상태 & 닫기 후 상태)
        AppState.shared.resetStudyCompletedBanner()
        renderView(SettingsView(), width: 780, height: 580, appearance: .aqua, path: "\(artifactDir)/settings_with_banner.png")
        AppState.shared.dismissStudyCompletedBanner()
        renderView(SettingsView(), width: 780, height: 580, appearance: .aqua, path: "\(artifactDir)/settings_banner_dismissed.png")
        renderView(SettingsView(), width: 780, height: 580, appearance: .darkAqua, path: "\(artifactDir)/theme_settings_dark.png")
        renderView(SettingsView(initialTab: .permissions), width: 780, height: 620, appearance: .aqua, path: "\(artifactDir)/settings_permissions.png")

        // 4. 설문 팝업 화면 (시작, 중간, 종료 - 라이트 & 다크)
        let startSurvey = SurveyPopupView(
            surveyType: .start,
            sessionTitle: "Antigravity 연구 세션",
            aiTool: "Antigravity",
            snoozeCount: 0,
            initialFatigue: 4,
            maxContentHeight: 480,
            onHeightChanged: { _ in },
            onAction: { _, _ in }
        )
        renderView(startSurvey, width: 372, height: 290, appearance: .aqua, path: "\(artifactDir)/theme_survey_start.png")
        renderView(startSurvey, width: 372, height: 290, appearance: .darkAqua, path: "\(artifactDir)/theme_survey_start_dark.png")

        let midSurvey = SurveyPopupView(
            surveyType: .mid,
            sessionTitle: "Claude 연구 분석 세션",
            aiTool: "Claude",
            snoozeCount: 0,
            initialSituation: "코드 리팩토링 및 테스트 검증 진행 중",
            initialFatigue: 4,
            initialAIFatigueImpact: 3,
            initialUsefulness: 4,
            initialSelectedCategories: ["overload", "physicalTired"],
            maxContentHeight: 1200,
            onHeightChanged: { _ in },
            onAction: { _, _ in }
        )
        renderView(midSurvey, width: 372, height: 1000, appearance: .aqua, path: "\(artifactDir)/theme_survey_mid_light.png")

        // 3-1. 피로 유형 후속 질문 및 유용성 후속 질문 전용 프리뷰
        struct FollowUpQuestionsStandalonePreview: View {
            @StateObject private var formState: SurveyFormState = {
                let state = SurveyFormState(
                    fatigueScore: 4,
                    aiFatigueImpactScore: 4,
                    usefulnessScore: 4
                )
                state.selectedFatigueCategories = ["overload", "discomfort"]
                return state
            }()

            var body: some View {
                VStack(alignment: .leading, spacing: 14) {
                    Text("피로 유형 및 유용성 추가 질문 프리뷰")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    Divider()

                    // 피로 질문 + AI 영향 및 유형 통합 서브 카드 (방안 A: 인셋 카드 + 2열 칩 배치)
                    VStack(alignment: .leading, spacing: 10) {
                        FatigueScaleView(score: $formState.fatigueScore)

                        if formState.isAIFatigueImpactVisible {
                            AIFatigueFollowUpCardView(formState: formState)
                        }
                    }

                    Divider()

                    // AI가 얼마나 도움이 되고 있나요? (4점 '많이' 선택됨) 및 후속 질문 (서브 카드 구조 적용)
                    VStack(alignment: .leading, spacing: 10) {
                        UsefulnessScaleView(
                            score: $formState.usefulnessScore,
                            title: "AI가 얼마나 도움이 되고 있나요?"
                        )

                        // 유용성 4점 이상 후속 질문 (피로와 동일한 서브 카드 적용)
                        if formState.isHighUsefulness {
                            UsefulnessHelpSectionView(formState: formState)
                        }
                    }
                }
                .padding(16)
                .frame(width: 372)
                .background(Config.Colors.popupBg)
            }
        }
        renderView(FollowUpQuestionsStandalonePreview(), width: 372, height: 820, appearance: .aqua, path: "\(artifactDir)/survey_followup_preview.png")
        renderView(FollowUpQuestionsStandalonePreview(), width: 372, height: 820, appearance: .darkAqua, path: "\(artifactDir)/survey_followup_preview_dark.png")

        let sampleSurvey = SurveyPopupView(
            surveyType: .end,
            sessionTitle: "Claude 연구 분석 세션",
            aiTool: "Claude",
            snoozeCount: 0,
            initialSituation: "문헌 조사 및 분석 보고서 초안 작성",
            initialFatigue: 4,
            initialAIFatigueImpact: 3,
            initialUsefulness: 4,
            initialSelectedCategories: ["other"],
            initialCapturePath: "\(artifactDir)/theme_survey_start.png",
            maxContentHeight: 700,
            onHeightChanged: { _ in },
            onAction: { _, _ in }
        )
        renderView(sampleSurvey, width: 372, height: 680, appearance: .aqua, path: "\(artifactDir)/theme_survey_light.png")
        renderView(sampleSurvey, width: 372, height: 680, appearance: .darkAqua, path: "\(artifactDir)/theme_survey_dark.png")

        // 4-0. 종료 설문 (.end) - NASA-TLX 6개 슬라이더 평가 포함 스냅샷
        let endSurvey = SurveyPopupView(
            surveyType: .end,
            sessionTitle: "ChatGPT 연구 세션",
            aiTool: "ChatGPT",
            initialSituation: "통계 데이터 분석 및 결과표 작성",
            initialFatigue: 4,
            initialAIFatigueImpact: 3,
            initialUsefulness: 4,
            maxContentHeight: 1200,
            onHeightChanged: { _ in },
            onAction: { _, _ in }
        )
        renderView(endSurvey, width: 372, height: 1150, appearance: .darkAqua, path: "\(artifactDir)/theme_survey_end_dark.png")

        // 4-0-C. 30분 뒤 피로 영향 및 대처 점검 (.followUp) 스냅샷
        let followUpSurvey = SurveyPopupView(
            surveyType: .followUp,
            sessionTitle: "ChatGPT 연구 세션",
            aiTool: "ChatGPT",
            maxContentHeight: 1200,
            onHeightChanged: { _ in },
            onAction: { _, _ in }
        )
        renderView(followUpSurvey, width: 372, height: 480, appearance: .aqua, path: "\(artifactDir)/theme_survey_followup_light.png")
        renderView(followUpSurvey, width: 372, height: 480, appearance: .darkAqua, path: "\(artifactDir)/theme_survey_followup_dark.png")

        // 4-0-B. NASA-TLX 슬라이더 전용 프리뷰 (상단 문구 -> 6개 슬라이더 -> 하단 척도 앵커)
        struct TLXStandalonePreview: View {
            @State private var tlx = NASA_TLXScores(
                mentalDemand: 20,
                physicalDemand: 45,
                temporalDemand: 50,
                performance: 50,
                effort: 50,
                frustration: 50
            )
            var body: some View {
                TLXSliderSectionView(tlx: $tlx)
                    .padding(14)
            }
        }
        renderView(TLXStandalonePreview(), width: 372, height: 380, appearance: .darkAqua, path: "\(artifactDir)/tlx_section_dark.png")
        renderView(TLXStandalonePreview(), width: 372, height: 380, appearance: .aqua, path: "\(artifactDir)/tlx_section_light.png")

        // 4-1. 5점 척도 호버 말풍선 툴팁 미리보기 (전혀/약간/어느정도/많이/매우 버튼 호버 시)
        struct LikertTooltipPreviewWrapper: View {
            @State private var score: Int? = 3
            var body: some View {
                VStack(alignment: .leading, spacing: 14) {
                    LikertScaleView(
                        title: "지금 얼마나 피로한가요?",
                        options: SurveyScaleDefinitions.fatigueScale,
                        selectedValue: $score,
                        previewHoveredValue: 3
                    )
                    Spacer()
                }
                .padding(16)
                .frame(width: 340, height: 130)
                .background(Config.Colors.popupBg)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Config.Colors.line, lineWidth: 1))
                .padding(10)
            }
        }
        renderView(LikertTooltipPreviewWrapper(), width: 360, height: 150, appearance: .aqua, path: "\(artifactDir)/scale_tooltip_preview.png")
        renderView(LikertTooltipPreviewWrapper(), width: 360, height: 150, appearance: .darkAqua, path: "\(artifactDir)/scale_tooltip_preview_dark.png")

        // 4-1-C. 화면 캡처 호버 말풍선 툴팁 미리보기 (실제 설문 레이아웃: 아래 Divider 및 다음 문항과의 겹침 검증)
        struct ScreenCaptureTooltipPreviewWrapper: View {
            @State private var imagePath: String? = nil
            @State private var answer = SubjectiveAnswer()
            var body: some View {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("어떤 작업을 하려고 하나요?")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Config.Colors.ink)

                        SubjectiveInputFieldView(
                            label: nil,
                            placeholder: "작업 목표나 기대하는 결과물",
                            fieldKey: "start_purpose",
                            chipOptions: [],
                            isSingleLine: true,
                            isDisabled: false,
                            answer: $answer
                        )

                        ScreenCaptureCardView(
                            imagePath: $imagePath,
                            appName: "Claude",
                            previewHovered: true
                        )
                    }

                    Divider()
                        .background(Config.Colors.line)

                    FatigueScaleView(score: .constant(3))
                }
                .padding(16)
                .frame(width: 372, height: 260)
                .background(Config.Colors.popupBg)
            }
        }
        renderView(ScreenCaptureTooltipPreviewWrapper(), width: 372, height: 260, appearance: .darkAqua, path: "\(artifactDir)/capture_tooltip_preview_dark.png")
        renderView(ScreenCaptureTooltipPreviewWrapper(), width: 372, height: 260, appearance: .aqua, path: "\(artifactDir)/capture_tooltip_preview_light.png")

        // 4-1-D. 주관식-캡처 완전 대체 시스템 비교 프리뷰 (캡처 전 vs 캡처로 대체 완료)
        struct SituationCaptureReplacementPreviewWrapper: View {
            let artifactDir: String
            let isDark: Bool
            @State private var answer1 = SubjectiveAnswer()
            @State private var cap1: String? = nil

            @State private var answer2 = SubjectiveAnswer()
            @State private var cap2: String? = nil

            init(artifactDir: String, isDark: Bool) {
                self.artifactDir = artifactDir
                self.isDark = isDark
                self._cap2 = State(initialValue: "\(artifactDir)/menubar_label_recording_dark.png")
            }

            var body: some View {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("주관식 질문 ➔ 화면 캡처 완전 대체 시스템")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))
                        Text("화면 캡처 시 주관식 입력창이 캡처 완료 카드로 전환되어 텍스트 작성 없이 즉시 저장 가능합니다.")
                            .font(.system(size: 11))
                            .foregroundColor(isDark ? Color(white: 0.65) : Color(white: 0.45))
                    }

                    // 1. 캡처 전 상태
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 캡처 전 (글 또는 캡처 중 자유 선택)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isDark ? Color(white: 0.75) : Color(white: 0.35))

                        SituationInputOrCaptureSectionView(
                            situationAnswer: $answer1,
                            capturedImagePath: $cap1,
                            appName: "ChatGPT",
                            fieldKey: "preview1"
                        )
                    }
                    .padding(12)
                    .background(isDark ? Color(white: 0.10) : Color.white)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDark ? Color(white: 0.2) : Color(white: 0.85), lineWidth: 0.8))

                    // 2. 캡처 첨부 완료 상태 (주관식 필드 완전 대체)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("2. 캡처 첨부 완료 시 (주관식 필드가 캡처 카드로 완전 대체됨)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.green)

                        SituationInputOrCaptureSectionView(
                            situationAnswer: $answer2,
                            capturedImagePath: $cap2,
                            appName: "ChatGPT",
                            fieldKey: "preview2"
                        )
                    }
                    .padding(12)
                    .background(isDark ? Color(white: 0.10) : Color.white)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.4), lineWidth: 0.8))
                }
                .padding(16)
                .frame(width: 440)
                .background(isDark ? Color(hex: "#151518") : Color(hex: "#F5F5F7"))
            }
        }
        renderView(SituationCaptureReplacementPreviewWrapper(artifactDir: artifactDir, isDark: true), width: 440, height: 420, appearance: .darkAqua, path: "\(artifactDir)/situation_capture_replacement_dark.png")
        renderView(SituationCaptureReplacementPreviewWrapper(artifactDir: artifactDir, isDark: false), width: 440, height: 420, appearance: .aqua, path: "\(artifactDir)/situation_capture_replacement_light.png")

        // 4-1-B-2. 앱 전역 통일 툴팁 시스템 비교 프리뷰 (상향 화살표 ▲ 일체형 디자인)
        struct UnifiedTooltipSystemPreviewWrapper: View {
            var body: some View {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. 리커트 5점 척도 호버 툴팁 (상향 화살표 ▲ - 버튼 하단 플로팅으로 타이틀 미가림 및 잘림 방지)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Config.Colors.ink)

                        UnifiedTooltipView(
                            text: "AI 때문에 약간 더 피로하지만, 신경 쓰일 정도는 아니에요",
                            arrowDirection: .up,
                            arrowX: 80,
                            width: 210,
                            textAlignment: .center
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("2. 화면 캡처 버튼 호버 툴팁 (상향 화살표 ▲ - 버튼 아이콘 정렬)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Config.Colors.ink)

                        UnifiedTooltipView(
                            text: "작업 창이나 AI 답변이 있으면 상황이 더 잘 전해져요",
                            arrowDirection: .up,
                            arrowX: 24,
                            textAlignment: .leading
                        )
                    }
                }
                .padding(20)
                .frame(width: 372, height: 230)
                .background(Config.Colors.popupBg)
            }
        }
        renderView(UnifiedTooltipSystemPreviewWrapper(), width: 372, height: 230, appearance: .darkAqua, path: "\(artifactDir)/unified_tooltip_system_preview_dark.png")
        renderView(UnifiedTooltipSystemPreviewWrapper(), width: 372, height: 230, appearance: .aqua, path: "\(artifactDir)/unified_tooltip_system_preview_light.png")

        // 4-1-B-3. 사용자 제보 후속 질문 툴팁 잘림 해결 검증 프리뷰
        struct TooltipFollowUpNoClippingPreviewWrapper: View {
            @StateObject private var formState: SurveyFormState = {
                let s = SurveyFormState(fatigueScore: 4, aiFatigueImpactScore: nil)
                return s
            }()

            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    FatigueScaleView(score: $formState.fatigueScore)

                    AIFatigueFollowUpCardView(
                        formState: formState,
                        previewHoveredValue: 2
                    )
                }
                .padding(16)
                .frame(width: 372, height: 220)
                .background(Config.Colors.popupBg)
            }
        }
        renderView(TooltipFollowUpNoClippingPreviewWrapper(), width: 372, height: 220, appearance: .darkAqua, path: "\(artifactDir)/tooltip_followup_no_clipping_preview_dark.png")

        // 4-1-B-4. 전수 검증 1: 상단 피로도 문항 호버 시 아래 후속 질문 카드와의 겹침/가림 검증
        struct TooltipMainScaleHoverPreviewWrapper: View {
            @StateObject private var formState: SurveyFormState = {
                let s = SurveyFormState(fatigueScore: 4, aiFatigueImpactScore: nil)
                return s
            }()

            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    FatigueScaleView(score: $formState.fatigueScore, previewHoveredValue: 3)
                        .zIndex(10)

                    AIFatigueFollowUpCardView(
                        formState: formState
                    )
                    .zIndex(1)
                }
                .padding(16)
                .frame(width: 372, height: 220)
                .background(Config.Colors.popupBg)
            }
        }
        renderView(TooltipMainScaleHoverPreviewWrapper(), width: 372, height: 220, appearance: .darkAqua, path: "\(artifactDir)/tooltip_main_scale_hover_preview_dark.png")

        // 4-1-B-5. 전수 검증 2: 후속 질문 문항 호버 시 아래 카테고리 보기 목록과의 겹침/가림 검증
        struct TooltipFollowUpCategoriesBelowPreviewWrapper: View {
            @StateObject private var formState: SurveyFormState = {
                let s = SurveyFormState(fatigueScore: 4, aiFatigueImpactScore: 3)
                return s
            }()

            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    FatigueScaleView(score: $formState.fatigueScore)

                    AIFatigueFollowUpCardView(
                        formState: formState,
                        previewHoveredValue: 4
                    )
                }
                .padding(16)
                .frame(width: 372, height: 380)
                .background(Config.Colors.popupBg)
            }
        }
        renderView(TooltipFollowUpCategoriesBelowPreviewWrapper(), width: 372, height: 380, appearance: .darkAqua, path: "\(artifactDir)/tooltip_followup_categories_preview_dark.png")

        // 4-1-B-6. 전수 검증 3: 유용성 문항 호버 시 아래 후속 질문과의 겹침/가림 검증
        struct TooltipUsefulnessPreviewWrapper: View {
            @StateObject private var formState: SurveyFormState = {
                let s = SurveyFormState(fatigueScore: 2, usefulnessScore: 4)
                return s
            }()

            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    UsefulnessScaleView(
                        score: $formState.usefulnessScore,
                        title: "AI가 얼마나 도움이 되고 있나요?",
                        previewHoveredValue: 4
                    )

                    if formState.isHighUsefulness {
                        UsefulnessHelpSectionView(formState: formState)
                    }
                }
                .padding(16)
                .frame(width: 372, height: 220)
                .background(Config.Colors.popupBg)
            }
        }
        renderView(TooltipUsefulnessPreviewWrapper(), width: 372, height: 220, appearance: .darkAqua, path: "\(artifactDir)/tooltip_usefulness_preview_dark.png")

        // 4-1-B. 툴팁 Overlap 방식 전/후 버튼 위치 비교 프리뷰
        struct TooltipOverlapComparisonView: View {
            @State private var score1: Int? = nil
            @State private var score2: Int? = 3
            var body: some View {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. 평상시 (마우스 호버 전)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Config.Colors.mute)
                        LikertScaleView(
                            title: "지금 얼마나 피로한가요?",
                            options: SurveyScaleDefinitions.fatigueScale,
                            selectedValue: $score1,
                            previewHoveredValue: nil
                        )
                    }
                    .padding(12)
                    .background(Config.Colors.cardBackground)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("2. 호버 중 (제안: Overlap 플로팅 툴팁 - 버튼 위치 불변)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                        LikertScaleView(
                            title: "지금 얼마나 피로한가요?",
                            options: SurveyScaleDefinitions.fatigueScale,
                            selectedValue: $score2,
                            previewHoveredValue: 3
                        )
                    }
                    .padding(12)
                    .background(Config.Colors.cardBackground)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))
                }
                .padding(16)
                .frame(width: 360)
            }
        }
        renderView(TooltipOverlapComparisonView(), width: 360, height: 260, appearance: .darkAqua, path: "\(artifactDir)/tooltip_overlap_comparison.png")

        // 4-2. NASA-TLX 척도 앵커 레이블 미니멀 스타일 비교 렌더링
        struct TLXMinimalComparisonWrapper: View {
            var body: some View {
                VStack(spacing: 12) {
                    styleCard(
                        title: "스타일 A. [배경 박스/점 제거] 순수 텍스트 앵커 (추천 ⭐)",
                        header: AnyView(
                            HStack {
                                Text("매우 낮음")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Config.Colors.mute.opacity(0.75))
                                Spacer()
                                Text("보통")
                                    .font(.system(size: 9.5, weight: .regular))
                                    .foregroundColor(Config.Colors.mute.opacity(0.45))
                                Spacer()
                                Text("매우 높음")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Config.Colors.mute.opacity(0.75))
                            }
                            .padding(.horizontal, 2)
                        )
                    )

                    styleCard(
                        title: "스타일 B. [숫자 + 텍스트] 0 낮음 ── 100 높음",
                        header: AnyView(
                            HStack {
                                Text("0 (낮음)")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(Config.Colors.mute.opacity(0.65))
                                Spacer()
                                Text("50")
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundColor(Config.Colors.mute.opacity(0.4))
                                Spacer()
                                Text("100 (높음)")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(Config.Colors.mute.opacity(0.65))
                            }
                            .padding(.horizontal, 2)
                        )
                    )

                    styleCard(
                        title: "스타일 C. [방향 화살표형] ← 낮음 ── 높음 →",
                        header: AnyView(
                            HStack {
                                Text("← 매우 낮음")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(Config.Colors.mute.opacity(0.65))
                                Spacer()
                                Text("매우 높음 →")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(Config.Colors.mute.opacity(0.65))
                            }
                            .padding(.horizontal, 2)
                        )
                    )

                    styleCard(
                        title: "스타일 D. [카드 내부 라벨 완전 제거 + 상단 서브 가이드]",
                        subHeader: "0(매우 낮음) ~ 100(매우 높음) 사이로 평가해 주세요",
                        header: nil
                    )
                }
                .padding(14)
                .background(Color(hex: "#1A1816"))
            }

            private func styleCard(title: String, subHeader: String? = nil, header: AnyView?) -> some View {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))

                    if let sub = subHeader {
                        Text(sub)
                            .font(.system(size: 9.5))
                            .foregroundColor(Config.Colors.mute.opacity(0.75))
                            .padding(.bottom, 2)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if let h = header {
                            h
                        }

                        VStack(spacing: 3) {
                            HStack {
                                Text("정신적 요구")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(Config.Colors.ink)
                                Spacer()
                                Text("20")
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: Config.Colors.accentHex))
                            }
                            Slider(value: .constant(20), in: 0...100)
                                .controlSize(.mini)
                                .tint(Color(hex: Config.Colors.accentHex))
                        }
                    }
                    .padding(10)
                    .background(Config.Colors.cardBackground)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))
                }
            }
        }
        renderView(TLXMinimalComparisonWrapper(), width: 360, height: 490, appearance: .darkAqua, path: "\(artifactDir)/tlx_label_styles_comparison.png")

        // 5. 자발적 피로 기록 팝업 (캡처 미첨부 상태 - 캡처하기 버튼 표시)
        let voluntaryNoCapture = VoluntaryRecordPopupView(
            context: VoluntaryCaptureContext(
                appName: "Claude",
                bundleId: "com.anthropic.claude",
                windowTitle: "Claude 연구 분석 대화",
                url: nil,
                capturedAt: Date(),
                sessionId: UUID(),
                sessionTitle: "Claude 분석 세션",
                localImagePath: nil
            ),
            initialFatigue: 4,
            initialAIFatigueImpact: 3,
            maxContentHeight: 850,
            onHeightChanged: { _ in },
            onRetakeCapture: { _ in },
            onRetakeAreaCapture: { _ in },
            onCancel: {},
            onSave: { _, _ in }
        )
        renderView(voluntaryNoCapture, width: 372, height: 780, appearance: .aqua, path: "\(artifactDir)/voluntary_popup_no_capture.png")
        renderView(voluntaryNoCapture, width: 372, height: 780, appearance: .darkAqua, path: "\(artifactDir)/voluntary_popup_no_capture_dark.png")

        // 6. 자발적 피로 기록 팝업 (영역 캡처 첨부 완료 상태 - 썸네일, 재캡처, 삭제 버튼 표시)
        let voluntaryWithCapture = VoluntaryRecordPopupView(
            context: VoluntaryCaptureContext(
                appName: "Claude",
                bundleId: "com.anthropic.claude",
                windowTitle: "Claude 연구 분석 대화",
                url: nil,
                capturedAt: Date(),
                sessionId: UUID(),
                sessionTitle: "Claude 분석 세션",
                localImagePath: "\(artifactDir)/theme_survey_start.png"
            ),
            initialSituation: "긴 코드 디버깅 중 과부하 발생",
            initialFatigue: 4,
            initialAIFatigueImpact: 3,
            initialCapturePath: "\(artifactDir)/theme_survey_start.png",
            maxContentHeight: 850,
            onHeightChanged: { _ in },
            onRetakeCapture: { _ in },
            onRetakeAreaCapture: { _ in },
            onCancel: {},
            onSave: { _, _ in }
        )
        renderView(voluntaryWithCapture, width: 372, height: 780, appearance: .aqua, path: "\(artifactDir)/voluntary_popup_with_capture.png")
        renderView(voluntaryWithCapture, width: 372, height: 780, appearance: .darkAqua, path: "\(artifactDir)/voluntary_popup_with_capture_dark.png")

        // 7. 메뉴 막대 패널 (연구 완료 감사 배너 표시 상태 & 닫기 후 상태)
        let defaultBarW = Config.Survey.menuBarDefaultWidth
        AppState.shared.resetStudyCompletedBanner()
        renderView(MenuBarView(), width: defaultBarW, height: 560, appearance: .aqua, path: "\(artifactDir)/menubar_with_banner.png")
        renderView(MenuBarView(), width: defaultBarW, height: 560, appearance: .darkAqua, path: "\(artifactDir)/menubar_with_banner_dark.png")

        AppState.shared.dismissStudyCompletedBanner()
        renderView(MenuBarView(), width: defaultBarW, height: 510, appearance: .aqua, path: "\(artifactDir)/menubar_banner_dismissed.png")

        // 활성 세션 상태에서의 메뉴바 패널 스냅샷 (종료 버튼 활성화 상태)
        SessionManager.shared.startNewChat(toolName: "ChatGPT", title: "연구 데이터 분석")
        renderView(MenuBarView(), width: defaultBarW, height: 510, appearance: .aqua, path: "\(artifactDir)/menubar_active_session.png")
        if let focused = SessionManager.shared.focusedSession {
            SessionManager.shared.closeSession(withId: focused.sessionId, now: Date())
        }

        // 폭 비교 스냅샷 (다크 모드 기준 320px vs 360px vs 372px vs 412px)
        renderView(MenuBarView(panelWidth: 320), width: 320, height: 510, appearance: .darkAqua, path: "\(artifactDir)/menubar_width_320_dark.png")
        renderView(MenuBarView(panelWidth: 345), width: 345, height: 510, appearance: .darkAqua, path: "\(artifactDir)/menubar_width_345_dark.png")
        renderView(MenuBarView(panelWidth: 360), width: 360, height: 510, appearance: .darkAqua, path: "\(artifactDir)/menubar_width_360_dark.png")
        renderView(MenuBarView(panelWidth: 372), width: 372, height: 510, appearance: .darkAqua, path: "\(artifactDir)/menubar_width_372_dark.png")
        renderView(MenuBarView(panelWidth: defaultBarW), width: defaultBarW, height: 510, appearance: .darkAqua, path: "\(artifactDir)/menubar_width_412_dark.png")

        // 7-1. 메뉴 막대 상주 아이콘 및 상태 (세션 시간 / OFF) 프리뷰 (실제 macOS 메뉴 막대 배경 시뮬레이션)
        struct MenuBarLabelPreviewWrapper: View {
            let isRecording: Bool
            let duration: String?
            let fatigueScore: Int?
            let isDark: Bool

            init(isRecording: Bool, duration: String? = nil, fatigueScore: Int? = nil, isDark: Bool) {
                self.isRecording = isRecording
                self.duration = duration
                self.fatigueScore = fatigueScore
                self.isDark = isDark
            }

            var body: some View {
                HStack {
                    MenuBarLabelView(
                        previewDuration: duration,
                        previewIsRecording: isRecording,
                        previewFatigueScore: fatigueScore
                    )
                }
                .padding(.horizontal, isRecording ? 8 : 6)
                .frame(width: isRecording ? 80 : 38, height: 28)
                .background(isDark ? Color(hex: "#1E1E22") : Color(hex: "#E8E8ED"))
            }
        }
        // 기본 세션 기록 중 ("8:54") 및 대기 중 (단독 아이콘)
        renderView(MenuBarLabelPreviewWrapper(isRecording: true, duration: "8:54", isDark: true), width: 80, height: 28, appearance: .darkAqua, path: "\(artifactDir)/menubar_label_recording_dark.png")
        renderView(MenuBarLabelPreviewWrapper(isRecording: true, duration: "8:54", isDark: false), width: 80, height: 28, appearance: .aqua, path: "\(artifactDir)/menubar_label_recording_light.png")
        renderView(MenuBarLabelPreviewWrapper(isRecording: false, isDark: true), width: 38, height: 28, appearance: .darkAqua, path: "\(artifactDir)/menubar_label_off_dark.png")
        renderView(MenuBarLabelPreviewWrapper(isRecording: false, isDark: false), width: 38, height: 28, appearance: .aqua, path: "\(artifactDir)/menubar_label_off_light.png")

        // 피로도 1~5점 수준별 배터리 잔량 & 색상 동적 변화 프리뷰
        for score in 1...5 {
            renderView(MenuBarLabelPreviewWrapper(isRecording: true, duration: "8:54", fatigueScore: score, isDark: true), width: 80, height: 28, appearance: .darkAqua, path: "\(artifactDir)/menubar_fatigue_level\(score)_dark.png")
            renderView(MenuBarLabelPreviewWrapper(isRecording: true, duration: "8:54", fatigueScore: score, isDark: false), width: 80, height: 28, appearance: .aqua, path: "\(artifactDir)/menubar_fatigue_level\(score)_light.png")
        }

        // 피로도 1~5점 통합 갤러리 프리뷰 카드
        struct FatigueIconGalleryView: View {
            let isDark: Bool
            let scores = [
                (1, "1점 (전혀)", "에너지 90% 만충 (초록 배터리 & 초록 말풍선)"),
                (2, "2점 (약간)", "에너지 70% 충전 (연두/라임 배터리 & 연두 말풍선)"),
                (3, "3점 (어느 정도)", "에너지 50% 절반 (옐로우 배터리 & 옐로우 말풍선)"),
                (4, "4점 (많이)", "에너지 33% 경고 (테라코타 배터리 & 테라코타 말풍선)"),
                (5, "5점 (매우)", "에너지 15% 위험 (레드 배터리 & 레드 말풍선)")
            ]
            var body: some View {
                VStack(alignment: .leading, spacing: 12) {
                    Text("피로도별 배터리 & 말풍선 일체화 색상 연동")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))

                    VStack(spacing: 8) {
                        ForEach(scores, id: \.0) { item in
                            HStack(spacing: 14) {
                                HStack {
                                    MenuBarLabelView(
                                        previewDuration: "8:54",
                                        previewIsRecording: true,
                                        previewFatigueScore: item.0
                                    )
                                }
                                .padding(.horizontal, 8)
                                .frame(width: 78, height: 26)
                                .background(isDark ? Color(hex: "#1E1E22") : Color(hex: "#E8E8ED"))
                                .cornerRadius(6)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.1)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))
                                    Text(item.2)
                                        .font(.system(size: 10.5))
                                        .foregroundColor(isDark ? Color(white: 0.7) : Color(white: 0.4))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isDark ? Color(white: 0.12) : Color.white)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(16)
                .frame(width: 390)
                .background(isDark ? Color(hex: "#151518") : Color(hex: "#F5F5F7"))
            }
        }
        renderView(FatigueIconGalleryView(isDark: true), width: 390, height: 320, appearance: .darkAqua, path: "\(artifactDir)/fatigue_levels_comparison_dark.png")
        renderView(FatigueIconGalleryView(isDark: false), width: 390, height: 320, appearance: .aqua, path: "\(artifactDir)/fatigue_levels_comparison_light.png")

        // 피로도 색상 전/후 및 2점 후보 색상 비교 프리뷰
        struct FatigueColorComparisonCard: View {
            let isDark: Bool

            var body: some View {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("메뉴 막대 아이콘 색상 일체화 및 2점 색상 비교")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))
                        Text("배터리 게이지와 말풍선(Dialogue)이 동일한 피로도 색상으로 자연스럽게 일체화됩니다.")
                            .font(.system(size: 11))
                            .foregroundColor(isDark ? Color(white: 0.65) : Color(white: 0.45))
                    }

                    // 비교 1: 2점 변경 전(민트 + 주황 말풍선) vs 변경 후(연두 일체형)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 2점 (약간) 색상 개선 비교")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("기존 (Before): 민트 배터리 + 주황 고정 말풍선")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color.red.opacity(0.85))

                                HStack(spacing: 10) {
                                    Image(nsImage: makeCustomDualIcon(levelHeight: 9.8, batColor: CGColor(red: 0.19, green: 0.69, blue: 0.78, alpha: 1.0), bubColor: CGColor(red: 0.91, green: 0.33, blue: 0.16, alpha: 1.0), isDark: isDark))
                                    Text("민트 + 오렌지 (색상 충돌)")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(isDark ? Color(white: 0.7) : Color(white: 0.4))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isDark ? Color(white: 0.10) : Color(hex: "#F0F0F2"))
                                .cornerRadius(6)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("개선 (After): 싱그러운 연두/라임 일체형 (추천)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.green)

                                HStack(spacing: 10) {
                                    Image(nsImage: MenuBarIconHelper.makeStatusIcon(duration: "8:54", isRecording: true, fatigueScore: 2))
                                    Text("연두/라임 (#6BC747)")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isDark ? Color.green.opacity(0.12) : Color.green.opacity(0.08))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.4), lineWidth: 0.8))
                            }
                        }
                    }

                    // 비교 2: 1~5점 전체 배터리 & 말풍선 일체화 스펙트럼
                    VStack(alignment: .leading, spacing: 8) {
                        Text("2. 피로도 1~5점 일체화 컬러 스펙트럼 (Green → Lime → Yellow → Orange → Red)")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))

                        HStack(spacing: 8) {
                            spectrumBadge(score: 1, name: "1점 전혀", colorDesc: "초록 (#34C759)")
                            spectrumBadge(score: 2, name: "2점 약간", colorDesc: "연두 (#6BC747)")
                            spectrumBadge(score: 3, name: "3점 어느정도", colorDesc: "노랑 (#FF9F0A)")
                            spectrumBadge(score: 4, name: "4점 많이", colorDesc: "주황 (#E0522A)")
                            spectrumBadge(score: 5, name: "5점 매우", colorDesc: "빨강 (#FF453A)")
                        }
                    }
                }
                .padding(16)
                .frame(width: 530)
                .background(isDark ? Color(hex: "#151518") : Color.white)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isDark ? Color(white: 0.2) : Color(white: 0.85), lineWidth: 0.8))
            }

            private func spectrumBadge(score: Int, name: String, colorDesc: String) -> some View {
                VStack(spacing: 5) {
                    Image(nsImage: MenuBarIconHelper.makeStatusIcon(duration: "8:54", isRecording: true, fatigueScore: score))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(isDark ? Color(hex: "#1E1E22") : Color(hex: "#E8E8ED"))
                        .cornerRadius(5)

                    Text(name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))

                    Text(colorDesc)
                        .font(.system(size: 8.5))
                        .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.45))
                }
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(isDark ? Color(white: 0.08) : Color(hex: "#F8F8FA"))
                .cornerRadius(6)
            }

            private func makeCustomDualIcon(levelHeight: CGFloat, batColor: CGColor, bubColor: CGColor, isDark: Bool) -> NSImage {
                let size = NSSize(width: 78.0, height: 18.0)
                return NSImage(size: size, flipped: false) { _ in
                    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                    let strokeColor = isDark
                        ? CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.98)
                        : CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.98)
                    let chamberFill = isDark
                        ? CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.14)
                        : CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.09)

                    // Cap
                    let capRect = CGRect(x: 2.8, y: 15.6, width: 3.6, height: 1.5)
                    ctx.setFillColor(strokeColor)
                    ctx.addPath(CGPath(roundedRect: capRect, cornerWidth: 0.75, cornerHeight: 0.75, transform: nil))
                    ctx.fillPath()

                    // Body
                    let batRect = CGRect(x: 1.0, y: 1.6, width: 7.2, height: 14.0)
                    let batPath = CGPath(roundedRect: batRect, cornerWidth: 2.4, cornerHeight: 2.4, transform: nil)
                    ctx.setFillColor(chamberFill)
                    ctx.addPath(batPath)
                    ctx.fillPath()
                    ctx.setLineWidth(1.6)
                    ctx.setStrokeColor(strokeColor)
                    ctx.addPath(batPath)
                    ctx.strokePath()

                    // Gauge
                    ctx.saveGState()
                    ctx.addPath(batPath)
                    ctx.clip()
                    let fillRect = CGRect(x: batRect.minX, y: batRect.minY, width: batRect.width, height: levelHeight)
                    ctx.setFillColor(batColor)
                    ctx.fill(fillRect)
                    ctx.restoreGState()

                    // Bubble
                    let bubRect = CGRect(x: 10.0, y: 2.8, width: 12.6, height: 12.6)
                    let bubR: CGFloat = 3.6
                    let bubP = CGMutablePath()
                    let minX = bubRect.minX
                    let maxX = bubRect.maxX
                    let minY = bubRect.minY
                    let maxY = bubRect.maxY
                    bubP.move(to: CGPoint(x: minX + bubR, y: maxY))
                    bubP.addLine(to: CGPoint(x: maxX - bubR, y: maxY))
                    bubP.addArc(center: CGPoint(x: maxX - bubR, y: maxY - bubR), radius: bubR, startAngle: .pi/2, endAngle: 0, clockwise: true)
                    bubP.addLine(to: CGPoint(x: maxX, y: minY + bubR))
                    bubP.addArc(center: CGPoint(x: maxX - bubR, y: minY + bubR), radius: bubR, startAngle: 0, endAngle: -.pi/2, clockwise: true)
                    bubP.addLine(to: CGPoint(x: minX + bubR, y: minY))
                    bubP.addArc(center: CGPoint(x: minX + bubR, y: minY + bubR), radius: bubR, startAngle: -.pi/2, endAngle: .pi, clockwise: true)
                    let tailCenterY: CGFloat = 8.8
                    bubP.addLine(to: CGPoint(x: minX, y: tailCenterY - 2.0))
                    bubP.addLine(to: CGPoint(x: minX - 2.0, y: tailCenterY))
                    bubP.addLine(to: CGPoint(x: minX, y: tailCenterY + 2.0))
                    bubP.addLine(to: CGPoint(x: minX, y: maxY - bubR))
                    bubP.addArc(center: CGPoint(x: minX + bubR, y: maxY - bubR), radius: bubR, startAngle: .pi, endAngle: .pi/2, clockwise: true)
                    bubP.closeSubpath()
                    ctx.setFillColor(bubColor)
                    ctx.addPath(bubP)
                    ctx.fillPath()

                    // Chevron & cursor
                    let cPath = CGMutablePath()
                    cPath.move(to: CGPoint(x: bubRect.midX - 2.8, y: bubRect.midY + 2.9))
                    cPath.addLine(to: CGPoint(x: bubRect.midX + 0.9, y: bubRect.midY))
                    cPath.addLine(to: CGPoint(x: bubRect.midX - 2.8, y: bubRect.midY - 2.9))
                    ctx.setLineWidth(1.7)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.99))
                    ctx.addPath(cPath)
                    ctx.strokePath()

                    let curPath = CGMutablePath()
                    curPath.move(to: CGPoint(x: bubRect.midX + 2.0, y: bubRect.midY - 2.2))
                    curPath.addLine(to: CGPoint(x: bubRect.midX + 4.3, y: bubRect.midY - 2.2))
                    ctx.setLineWidth(1.4)
                    ctx.setLineCap(.round)
                    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
                    ctx.addPath(curPath)
                    ctx.strokePath()

                    // Text "8:54"
                    let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
                    let curTextColor = isDark ? NSColor(white: 0.96, alpha: 0.98) : NSColor(white: 0.11, alpha: 0.98)
                    let curAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: curTextColor]
                    let curStr = "8:54" as NSString
                    let curSize = curStr.size(withAttributes: curAttrs)
                    let textY = (18.0 - curSize.height) / 2.0
                    curStr.draw(in: CGRect(x: 25.5, y: textY, width: curSize.width + 1.0, height: curSize.height), withAttributes: curAttrs)
                    return true
                }
            }
        }
        renderView(FatigueColorComparisonCard(isDark: true), width: 530, height: 280, appearance: .darkAqua, path: "\(artifactDir)/fatigue_color_comparison_dark.png")
        renderView(FatigueColorComparisonCard(isDark: false), width: 530, height: 280, appearance: .aqua, path: "\(artifactDir)/fatigue_color_comparison_light.png")

        // 7-B. 배터리 게이지 테두리 넘침 해결 및 정밀 인셋 비교 카드
        struct BatteryBorderRefinementCard: View {
            let isDark: Bool

            var body: some View {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("배터리 게이지 테두리 넘침(Bleed) 해결 및 정밀 인셋 개편")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))
                        Text("게이지 액체가 외곽선(Border)을 침범하지 않도록 1.35pt 내부 인셋 캐비티를 적용하고 외곽선을 최상단에 렌더링합니다.")
                            .font(.system(size: 11))
                            .foregroundColor(isDark ? Color(white: 0.65) : Color(white: 0.45))
                    }

                    HStack(spacing: 12) {
                        // 개편 내용 요약 박스
                        VStack(alignment: .leading, spacing: 6) {
                            Text("개편 핵심 포인트")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: Config.Colors.accentHex))

                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundColor(.green)
                                Text("내부 캐비티 분리: batRect.insetBy(dx: 1.35, dy: 1.35)로 게이지 전용 패스 생성")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(isDark ? Color(white: 0.8) : Color(white: 0.3))
                            }
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundColor(.green)
                                Text("드로잉 순서 역전: 게이지 액체 채움 후 1.3pt 외곽선 스트로크를 최상단에 얹음")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(isDark ? Color(white: 0.8) : Color(white: 0.3))
                            }
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundColor(.green)
                                Text("테두리 침범 0%: 게이지와 외곽선 사이 0.7pt의 선명한 유리관 여백 확보")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(isDark ? Color(white: 0.8) : Color(white: 0.3))
                            }
                        }
                        .padding(10)
                        .background(isDark ? Color(white: 0.08) : Color(hex: "#F5F5F7"))
                        .cornerRadius(6)

                        // 1~5점 적용 결과 미니 뷰
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1~5점 수준별 실제 렌더링")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))

                            HStack(spacing: 6) {
                                ForEach(1...5, id: \.self) { score in
                                    VStack(spacing: 3) {
                                        Image(nsImage: MenuBarIconHelper.makeIcon(fatigueScore: score))
                                            .frame(width: 24, height: 18)
                                        Text("\(score)점")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 4)
                                    .background(isDark ? Color(hex: "#1E1E22") : Color(hex: "#E8E8ED"))
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .padding(10)
                        .background(isDark ? Color(white: 0.08) : Color(hex: "#F5F5F7"))
                        .cornerRadius(6)
                    }
                }
                .padding(14)
                .frame(width: 530)
                .background(isDark ? Color(hex: "#151518") : Color.white)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDark ? Color(white: 0.2) : Color(white: 0.85), lineWidth: 0.8))
            }
        }
        renderView(BatteryBorderRefinementCard(isDark: true), width: 530, height: 175, appearance: .darkAqua, path: "\(artifactDir)/menubar_battery_border_refinement_dark.png")
        renderView(BatteryBorderRefinementCard(isDark: false), width: 530, height: 175, appearance: .aqua, path: "\(artifactDir)/menubar_battery_border_refinement_light.png")

        // 8. 스마트 캡처 상단 안내 배너 미리보기 (상/하 패딩 완벽 대칭 검증용)
        let bannerImg = NSImage(size: NSSize(width: 360, height: 48), flipped: false) { _ in
            let bannerRect = CGRect(x: 10, y: 8, width: 340, height: 32)
            let bannerPath = NSBezierPath(roundedRect: bannerRect, xRadius: 16, yRadius: 16)
            NSColor(white: 0.10, alpha: 0.92).setFill()
            bannerPath.fill()
            NSColor(white: 1.0, alpha: 0.22).setStroke()
            bannerPath.lineWidth = 0.8
            bannerPath.stroke()

            let bannerText = "창 클릭: 창 전체 캡처  |  드래그: 영역 지정  (취소: Esc)"
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: style
            ]
            let textSize = (bannerText as NSString).size(withAttributes: attrs)
            let textY = bannerRect.minY + (bannerRect.height - textSize.height) / 2.0
            let textRect = CGRect(x: bannerRect.minX, y: textY, width: bannerRect.width, height: textSize.height)
            (bannerText as NSString).draw(in: textRect, withAttributes: attrs)
            return true
        }
        if let tiff = bannerImg.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "\(artifactDir)/capture_guide_banner_preview.png"))
        }

        // 8-2. 방안 A: 롤링 카운터 및 +1 상승 플로팅 피드백 전/후 비교 프리뷰
        struct KPIRollingFeedbackComparisonView: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. 평상시 상태 (정적 디스플레이)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Config.Colors.mute)

                        HStack(spacing: 6) {
                            KPIRollingCardView(valueText: "9.5h", rawValue: 9.5, label: "누적 사용")
                            KPIRollingCardView(valueText: "122", rawValue: 122, label: "세션")
                            KPIRollingCardView(valueText: "8", rawValue: 8, label: "기록")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("2. 방안 A: 수치 상승 시 롤링 + 플로팅 피드백 (+0.1h / +1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: Config.Colors.accentHex))
                            Spacer()
                            Text("오렌지 펄스 테두리 & +1 플로팅")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(Color(hex: Config.Colors.accentHex))
                        }

                        HStack(spacing: 6) {
                            KPIRollingCardView(
                                valueText: "9.6h",
                                rawValue: 9.6,
                                label: "누적 사용",
                                unit: "h",
                                precision: 1,
                                previewFloatingBadge: "+0.1h"
                            )
                            KPIRollingCardView(
                                valueText: "123",
                                rawValue: 123,
                                label: "세션",
                                unit: "",
                                precision: 0,
                                previewFloatingBadge: "+1"
                            )
                            KPIRollingCardView(
                                valueText: "9",
                                rawValue: 9,
                                label: "기록",
                                unit: "",
                                precision: 0,
                                previewFloatingBadge: "+1"
                            )
                        }
                    }
                }
                .padding(14)
                .frame(width: 412)
                .background(Config.Colors.popupBg)
            }
        }
        renderView(KPIRollingFeedbackComparisonView(), width: 412, height: 185, appearance: .aqua, path: "\(artifactDir)/kpi_rolling_feedback_comparison.png")
        renderView(KPIRollingFeedbackComparisonView(), width: 412, height: 185, appearance: .darkAqua, path: "\(artifactDir)/kpi_rolling_feedback_comparison_dark.png")

        // 13. 저장 피드백 (Before: 대형 토스트 박스 vs After: 초미니멀 캡슐 HUD + 버튼 피드백)
        struct SaveFeedbackComparisonView: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 18) {
                    Text("팝업 저장 피드백 미니멀 개편 비교")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    // 1. Before: 기존 대형 토스트 박스
                    VStack(alignment: .leading, spacing: 6) {
                        Text("기존: 290×68 대형 토스트 박스 (과도한 텍스트 및 큰 아이콘)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Config.Colors.mute)

                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "#10B981").opacity(0.15))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(hex: "#10B981"))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("저장됨")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(Config.Colors.ink)
                                Text("설문 응답이 안전하게 저장되었습니다.")
                                    .font(.system(size: 11))
                                    .foregroundColor(Config.Colors.mute)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(width: 290)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Config.Colors.popupBg)
                                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Config.Colors.line.opacity(0.7), lineWidth: 0.8)
                        )
                    }

                    Divider()
                        .background(Config.Colors.line)

                    // 2. After: 신규 초미니멀 캡슐 HUD + 버튼 즉각 피드백
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("개선: 초미니멀 캡슐 HUD + 버튼 인라인 즉각 반응 ⭐")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(Color(hex: Config.Colors.accentHex))
                            Spacer()
                            Text("1.1초 노출 후 부드러운 소멸")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Config.Colors.mute)
                        }

                        HStack(spacing: 16) {
                            // 1단계: 버튼 인라인 피드백
                            VStack(alignment: .leading, spacing: 4) {
                                Text("1단계: 클릭 즉시 버튼 전환 (0ms)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Config.Colors.mute)

                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("저장됨")
                                }
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6.5)
                                .background(Color(hex: Config.Colors.accentHex))
                                .cornerRadius(6)
                            }

                            // 2단계: 화면 우상단 미니멀 캡슐 HUD
                            VStack(alignment: .leading, spacing: 4) {
                                Text("2단계: 화면 우상단 슬림 캡슐 (116×32)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Config.Colors.mute)

                                MinimalToastCapsuleView(title: "저장 완료")
                            }
                        }
                    }
                }
                .padding(16)
                .frame(width: 440)
                .background(Config.Colors.popupBg)
            }
        }
        renderView(SaveFeedbackComparisonView(), width: 440, height: 260, appearance: .aqua, path: "\(artifactDir)/save_feedback_comparison.png")
        renderView(SaveFeedbackComparisonView(), width: 440, height: 260, appearance: .darkAqua, path: "\(artifactDir)/save_feedback_comparison_dark.png")

        // 3-9. 참여자 정보 카드 레이아웃 정밀 프리뷰 (기본 상태, 수정 중 상태, 완료 상태)
        struct ParticipantInfoCardPreviewView: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 18) {
                    Text("참여자 정보 카드 레이아웃 개선 비교")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    // 1. 기본 상태 (미수정)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 기본 상태 (이름 미수정 시: 오렌지 글래어 제거 & 복사 버튼과 조화)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(Config.Colors.mute)

                        participantCardRow(name: "박창휘", isModified: false, isSaved: false, isCopied: false)
                    }

                    // 2. 수정 중 상태 (텍스트 변경 감지)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("2. 수정 중 상태 (텍스트 변경 감지 시: 저장 유도 오렌지 강조 & Enter 지원)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))

                        participantCardRow(name: "박창휘 (연구원)", isModified: true, isSaved: false, isCopied: false)
                    }

                    // 3. 완료 피드백 상태 (저장됨 & 복사됨)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("3. 피드백 완료 상태 (체크마크 + 3글자 대칭 '저장됨' / '복사됨')")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.green)

                        participantCardRow(name: "박창휘", isModified: false, isSaved: true, isCopied: true)
                    }
                }
                .padding(16)
                .frame(width: 530)
                .background(Config.Colors.popupBg)
            }

            private func participantCardRow(name: String, isModified: Bool, isSaved: Bool, isCopied: Bool) -> some View {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 7) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                        Text("참여자 정보")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        // 표시 이름
                        HStack(spacing: 10) {
                            Text("표시 이름")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Config.Colors.mute)
                                .frame(width: 76, alignment: .leading)

                            HStack(spacing: 6) {
                                Text(name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(Config.Colors.ink)
                                Spacer()
                                if isModified {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(Config.Colors.mute)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(width: 320, height: 28)
                            .background(Config.Colors.paper)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        isModified
                                            ? Color(hex: Config.Colors.accentHex).opacity(0.8)
                                            : Config.Colors.line,
                                        lineWidth: 0.8
                                    )
                            )

                            HStack(spacing: 4) {
                                if isSaved {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("저장됨")
                                        .font(.system(size: 11, weight: .semibold))
                                } else {
                                    Text("저장")
                                        .font(.system(size: 11.5, weight: isModified ? .bold : .medium))
                                }
                            }
                            .foregroundColor(
                                isSaved
                                    ? .green
                                    : (isModified ? .white : Config.Colors.mute)
                            )
                            .frame(width: 72, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        isSaved
                                            ? Color.green.opacity(0.14)
                                            : (isModified ? Color(hex: Config.Colors.accentHex) : Config.Colors.paper)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                isSaved
                                                    ? Color.green.opacity(0.6)
                                                    : (isModified ? Color.clear : Config.Colors.line),
                                                lineWidth: 0.8
                                            )
                                    )
                            )
                        }

                        // 연구 식별자
                        HStack(spacing: 10) {
                            Text("연구 식별자")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Config.Colors.mute)
                                .frame(width: 76, alignment: .leading)

                            HStack {
                                Text("4C49D094-7568-481C-8375-C841767F3140")
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(Config.Colors.ink.opacity(0.85))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(width: 320, height: 28)
                            .background(Config.Colors.paper.opacity(0.65))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.8))

                            HStack(spacing: 4) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                Text(isCopied ? "복사됨" : "복사")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(isCopied ? .green : Config.Colors.ink)
                            .frame(width: 72, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isCopied ? Color.green.opacity(0.14) : Config.Colors.paper)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isCopied ? Color.green.opacity(0.6) : Config.Colors.line, lineWidth: 0.8)
                                    )
                            )
                        }
                    }
                }
                .padding(14)
                .background(Config.Colors.cardBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))
            }
        }
        renderView(ParticipantInfoCardPreviewView(), width: 530, height: 490, appearance: .aqua, path: "\(artifactDir)/participant_info_card_preview.png")
        renderView(ParticipantInfoCardPreviewView(), width: 530, height: 490, appearance: .darkAqua, path: "\(artifactDir)/participant_info_card_preview_dark.png")

        // 8. "지금 어떤 상황인가요?" (글 또는 캡처) 표현 개선 4가지 제안안 비교 뷰
        struct SituationInputProposalsCard: View {
            let isDark: Bool

            var body: some View {
                VStack(alignment: .leading, spacing: 18) {
                    // 상단 헤더
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("지금 어떤 상황인가요? (글 또는 캡처) UI 개선 4가지 제안안")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))
                            Text("Mockup Preview")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: Config.Colors.accentHex).opacity(0.18))
                                .foregroundColor(Color(hex: Config.Colors.accentHex))
                                .cornerRadius(4)
                        }
                        Text("기존의 3중 중복 안내('대체 가능', '대신 가능', '택 1')를 해소하고 세련된 네이티브 인터랙션으로 개선하는 4가지 방안입니다.")
                            .font(.system(size: 11))
                            .foregroundColor(isDark ? Color(white: 0.65) : Color(white: 0.45))
                    }

                    // 2x2 그리드 비교 (실제 팝업 컨텐츠 폭인 310pt로 각각 렌더링)
                    HStack(alignment: .top, spacing: 18) {
                        // 좌측 열: 안 1 & 안 2
                        VStack(alignment: .leading, spacing: 16) {
                            // 안 1: 인라인 원터치 캡처 통합형 (강력 추천 1순위)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text("안 1. 인라인 통합형 (Inline Unified Bar)")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                                    Text("⭐ 강력 추천 (모던 메신저/AI 스타일)")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(.green)
                                }

                                VStack(alignment: .leading, spacing: 7) {
                                    // 질문 헤더
                                    HStack {
                                        Text("지금 어떤 상황인가요?")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))
                                        Spacer()
                                        Text("(필수)")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(isDark ? Color(white: 0.5) : Color(white: 0.5))
                                    }

                                    // 1단 통합 입력 바 (높이 36pt, 공간 절약 극대화)
                                    HStack(spacing: 8) {
                                        Text("하던 일 입력 또는 화면 캡처...")
                                            .font(.system(size: 11.5))
                                            .foregroundColor(isDark ? Color(white: 0.45) : Color(white: 0.55))

                                        Spacer()

                                        // 캡처 원터치 버튼
                                        HStack(spacing: 4) {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 10))
                                            Text("캡처")
                                                .font(.system(size: 10.5, weight: .bold))
                                        }
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.green.opacity(0.35), lineWidth: 0.8))

                                        // 마이크 아이콘
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 11.5))
                                            .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(isDark ? Color(white: 0.08) : Color.white)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isDark ? Color(white: 0.2) : Color(white: 0.85), lineWidth: 0.8))

                                    Text("• 특징: 1단(36pt)으로 높이 52% 절약. 구차한 안내문 없이 가장 직관적")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.45))
                                }
                                .padding(12)
                                .frame(width: 310)
                                .background(isDark ? Color(white: 0.11) : Color(hex: "#F9F9FB"))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: Config.Colors.accentHex).opacity(0.35), lineWidth: 1))
                            }

                            // 안 2: 헤더 세그먼트 탭 전환형 (강력 추천 2순위)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text("안 2. 세그먼트 탭 전환형 (Segmented Tab)")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                                    Text("⭐ 명확한 택 1 구조")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                                }

                                VStack(alignment: .leading, spacing: 7) {
                                    // 질문 헤더 + 세그먼트 탭 스위처
                                    HStack {
                                        Text("지금 어떤 상황인가요?")
                                            .font(.system(size: 12.5, weight: .bold))
                                            .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))

                                        Spacer()

                                        // 애플 네이티브 스타일 미니 세그먼트
                                        HStack(spacing: 0) {
                                            Text("글·음성")
                                                .font(.system(size: 9.5, weight: .bold))
                                                .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2.5)
                                                .background(isDark ? Color(white: 0.22) : Color.white)
                                                .cornerRadius(3)

                                            HStack(spacing: 3) {
                                                Image(systemName: "camera")
                                                    .font(.system(size: 8.5))
                                                Text("캡처")
                                                    .font(.system(size: 9.5, weight: .medium))
                                            }
                                            .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2.5)
                                        }
                                        .padding(1.5)
                                        .background(isDark ? Color(white: 0.12) : Color(hex: "#E5E5EA"))
                                        .cornerRadius(4)
                                    }

                                    // 선택된 탭 컨텐츠 (글 입력칸)
                                    HStack {
                                        Text("하던 일이나 AI에게 맡긴 일...")
                                            .font(.system(size: 11.5))
                                            .foregroundColor(isDark ? Color(white: 0.45) : Color(white: 0.55))
                                        Spacer()
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 11.5))
                                            .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(isDark ? Color(white: 0.08) : Color.white)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isDark ? Color(white: 0.2) : Color(white: 0.85), lineWidth: 0.8))

                                    Text("• 특징: UI 자체로 '택 1'임을 전달. 탭 전환으로 화면이 항상 단정함")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.45))
                                }
                                .padding(12)
                                .frame(width: 310)
                                .background(isDark ? Color(white: 0.11) : Color(hex: "#F9F9FB"))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDark ? Color(white: 0.2) : Color(white: 0.85), lineWidth: 0.8))
                            }
                        }

                        // 우측 열: 안 3 & 안 4
                        VStack(alignment: .leading, spacing: 16) {
                            // 안 3: 미니멀 'OR' 디바이더형
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text("안 3. 미니멀 'OR' 디바이더형 (Clean Split)")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                                    Text("양자택일 명확성")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(isDark ? Color(white: 0.7) : Color(white: 0.4))
                                }

                                VStack(alignment: .leading, spacing: 7) {
                                    Text("지금 어떤 상황인가요?")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))

                                    // 글 입력창
                                    HStack {
                                        Text("하던 일이나 AI에게 맡긴 일...")
                                            .font(.system(size: 11))
                                            .foregroundColor(isDark ? Color(white: 0.45) : Color(white: 0.55))
                                        Spacer()
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 7)
                                    .background(isDark ? Color(white: 0.08) : Color.white)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isDark ? Color(white: 0.2) : Color(white: 0.85), lineWidth: 0.8))

                                    // 미니멀 OR 구분선
                                    HStack(spacing: 8) {
                                        Rectangle().fill(isDark ? Color(white: 0.2) : Color(white: 0.85)).frame(height: 0.8)
                                        Text("또는")
                                            .font(.system(size: 9.5, weight: .medium))
                                            .foregroundColor(isDark ? Color(white: 0.5) : Color(white: 0.5))
                                        Rectangle().fill(isDark ? Color(white: 0.2) : Color(white: 0.85)).frame(height: 0.8)
                                    }
                                    .padding(.vertical, 1)

                                    // 캡처 추천 버튼
                                    HStack {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 10.5))
                                        Text("화면 캡처로 1초 만에 답변")
                                            .font(.system(size: 11, weight: .bold))
                                        Spacer()
                                        Text("추천")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 4.5)
                                            .padding(.vertical, 1.5)
                                            .background(Color.green.opacity(0.2))
                                            .cornerRadius(3)
                                    }
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.08))
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.3), lineWidth: 0.8))

                                    Text("• 특징: 군더더기 사족을 걷어내고 '또는' 구분선과 '추천' 배지로 자연스러운 넛지")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.45))
                                }
                                .padding(12)
                                .frame(width: 310)
                                .background(isDark ? Color(white: 0.11) : Color(hex: "#F9F9FB"))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDark ? Color(white: 0.2) : Color(white: 0.85), lineWidth: 0.8))
                            }

                            // 안 4: 좌우 듀얼 카드형
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text("안 4. 좌우 듀얼 카드형 (Side-by-Side Cards)")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                                    Text("5:5 동등 선택")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(isDark ? Color(white: 0.7) : Color(white: 0.4))
                                }

                                VStack(alignment: .leading, spacing: 7) {
                                    Text("지금 어떤 상황인가요?")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))

                                    // 좌우 2분할 카드
                                    HStack(spacing: 8) {
                                        // 좌: 글/음성 카드
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Image(systemName: "pencil.and.outline")
                                                    .font(.system(size: 10))
                                                Text("글 / 음성")
                                                    .font(.system(size: 10.5, weight: .bold))
                                            }
                                            .foregroundColor(isDark ? .white : Color(hex: "#1A1A1C"))
                                            Text("직접 간단히 입력")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(isDark ? Color(white: 0.5) : Color(white: 0.5))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(isDark ? Color(white: 0.08) : Color.white)
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isDark ? Color(white: 0.2) : Color(white: 0.85), lineWidth: 0.8))

                                        // 우: 화면 캡처 카드
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Image(systemName: "camera.fill")
                                                    .font(.system(size: 10))
                                                Text("화면 캡처")
                                                    .font(.system(size: 10.5, weight: .bold))
                                            }
                                            .foregroundColor(.green)
                                            Text("작업화면 1초 캡처")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.green.opacity(0.85))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color.green.opacity(0.08))
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.3), lineWidth: 0.8))
                                    }

                                    Text("• 특징: 양쪽 선택지를 시각적으로 5:5 완벽히 동등하게 대비")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.45))
                                }
                                .padding(12)
                                .frame(width: 310)
                                .background(isDark ? Color(white: 0.11) : Color(hex: "#F9F9FB"))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDark ? Color(white: 0.2) : Color(white: 0.85), lineWidth: 0.8))
                            }
                        }
                    }
                }
                .padding(20)
                .background(isDark ? Color(hex: "#161619") : Color(hex: "#EEF0F3"))
            }
        }
        renderView(SituationInputProposalsCard(isDark: true), width: 700, height: 490, appearance: .darkAqua, path: "\(artifactDir)/situation_input_proposals_dark.png")
        renderView(SituationInputProposalsCard(isDark: false), width: 700, height: 490, appearance: .aqua, path: "\(artifactDir)/situation_input_proposals_light.png")

        // ==========================================================
        // 5. [신규] 전체 데스크탑(Desktop) 라이트 모드 실제 사용 장면 렌더링
        // ==========================================================
        print("🖥️ [ThemePreviewRenderer] 데스크탑 전체 화면(라이트 모드) 스냅샷 생성 시작...")

        // 5-1. 중간 설문(.mid) 팝업이 우상단에 뜬 전체 데스크탑 화면 (라이트 모드)
        renderView(
            DesktopFullMockupView(sceneType: .midSurvey),
            width: 1440,
            height: 900,
            appearance: .aqua,
            path: "\(artifactDir)/desktop_survey_mid_light.png"
        )

        // 5-1-b. "5분 뒤에" 스누즈 후 이전 상태를 이어서 작성 중인 데스크탑 화면 (라이트 모드)
        renderView(
            DesktopFullMockupView(sceneType: .snoozeResumedSurvey),
            width: 1440,
            height: 900,
            appearance: .aqua,
            path: "\(artifactDir)/desktop_survey_snooze_resume_light.png"
        )

        // 5-2. 시작 설문(.start) 팝업이 우상단에 뜬 전체 데스크탑 화면 (라이트 모드)
        renderView(
            DesktopFullMockupView(sceneType: .startSurvey),
            width: 1440,
            height: 900,
            appearance: .aqua,
            path: "\(artifactDir)/desktop_survey_start_light.png"
        )

        // 5-3. 상단 메뉴바 대시보드가 열려 있는 전체 데스크탑 화면 (라이트 모드)
        renderView(
            DesktopFullMockupView(sceneType: .menuBarDropdown),
            width: 1440,
            height: 900,
            appearance: .aqua,
            path: "\(artifactDir)/desktop_menubar_dropdown_light.png"
        )

        // 5-4. 세션 종료 설문(.end) 팝업(Step 1: 피로도 평가)이 우상단에 뜬 전체 데스크탑 화면 (라이트 모드)
        renderView(
            DesktopFullMockupView(sceneType: .endSurvey),
            width: 1440,
            height: 900,
            appearance: .aqua,
            path: "\(artifactDir)/desktop_survey_end_light.png"
        )

        // 5-4-b. 세션 종료 설문(.end) 팝업(Step 3: NASA-TLX 슬라이더)이 우상단에 뜬 전체 데스크탑 화면 (라이트 모드)
        renderView(
            DesktopFullMockupView(sceneType: .endSurveyTLX),
            width: 1440,
            height: 900,
            appearance: .aqua,
            path: "\(artifactDir)/desktop_survey_end_tlx_light.png"
        )

        // 5-5. 자발적 기록 설문(.diary) 팝업이 우상단에 뜬 전체 데스크탑 화면 (라이트 모드)
        renderView(
            DesktopFullMockupView(sceneType: .diarySurvey),
            width: 1440,
            height: 900,
            appearance: .aqua,
            path: "\(artifactDir)/desktop_survey_diary_light.png"
        )

        // 5-6. 피로 후속 점검 설문(.followUp) 팝업이 우상단에 뜬 전체 데스크탑 화면 (라이트 모드)
        renderView(
            DesktopFullMockupView(sceneType: .followUpSurvey),
            width: 1440,
            height: 900,
            appearance: .aqua,
            path: "\(artifactDir)/desktop_survey_followup_light.png"
        )

        print("✅ [ThemePreviewRenderer] 모든 라이트/다크 모드 스냅샷 생성 완료!")
    }

    private static func renderView<V: View>(_ view: V, width: CGFloat, height: CGFloat, appearance: NSAppearance.Name, path: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = (appearance == .darkAqua) ? NSColor(hex: "#1A1816") : NSColor(hex: Config.Colors.paperHex)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("❌ Failed to create rep for \(path)")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("📸 스냅샷 생성 완료: \(path)")
        }
    }
}

// MARK: - 데스크탑 전체 화면 렌더링용 타입 및 컴포넌트
public enum DesktopSceneType {
    case midSurvey
    case snoozeResumedSurvey
    case startSurvey
    case endSurvey
    case endSurveyTLX
    case diarySurvey
    case menuBarDropdown
    case followUpSurvey
}

public struct DesktopFullMockupView: View {
    public let sceneType: DesktopSceneType

    public init(sceneType: DesktopSceneType) {
        self.sceneType = sceneType
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            wallpaperBackground
            browserWindowView
            popupOverlayView
            menuBarView
        }
        .frame(width: 1440, height: 900)
        .clipped()
    }

    // 1. macOS 캘리포니아 라이트 월페이퍼 (부드러운 엠비언트 그라데이션)
    private var wallpaperBackground: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(hex: "#EDE7DF"),
                    Color(hex: "#F5ECE1"),
                    Color(hex: "#E5EDF0"),
                    Color(hex: "#DDE6EA")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(hex: "#E0522A").opacity(0.08))
                .frame(width: 650, height: 650)
                .blur(radius: 120)
                .offset(x: 750, y: 80)

            Circle()
                .fill(Color(hex: "#3B82F6").opacity(0.06))
                .frame(width: 500, height: 500)
                .blur(radius: 100)
                .offset(x: 100, y: 400)
        }
    }

    // 2. 메인 AI 작업 창 (Safari 브라우저에서 ChatGPT로 작업 중인 실물 창)
    private var browserWindowView: some View {
        VStack(spacing: 0) {
                // 브라우저 탭 및 툴바
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "#FF5F56")).frame(width: 11, height: 11)
                        Circle().fill(Color(hex: "#FFBD2E")).frame(width: 11, height: 11)
                        Circle().fill(Color(hex: "#27C93F")).frame(width: 11, height: 11)
                    }
                    .padding(.leading, 12)

                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.5))
                    }

                    Spacer()

                    // URL 스마트 검색 필드
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                        Text("chatgpt.com — UX Research AI Fatigue")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#2C2C2E"))
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.08), lineWidth: 0.8))

                    Spacer()

                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .padding(.trailing, 14)
                }
                .frame(height: 40)
                .background(Color(hex: "#F6F6F6"))
                .overlay(Divider().background(Color.black.opacity(0.08)), alignment: .bottom)

                // 브라우저 웹 콘텐츠 (ChatGPT 실제 대화 장면)
                HStack(spacing: 0) {
                    // 좌측 사이드바
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11))
                            Text("새로운 채팅")
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(6)
                        .padding(.top, 10)
                        .padding(.horizontal, 8)

                        Text("최근 대화")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.top, 10)
                            .padding(.horizontal, 12)

                        HStack {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: Config.Colors.accentHex))
                            Text("AI 피로도 연구 분석")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "#1F1C17"))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: Config.Colors.accentHex).opacity(0.1))
                        .cornerRadius(6)
                        .padding(.horizontal, 8)

                        HStack {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 10))
                            Text("설문 프로토콜 검토")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)

                        Spacer()
                    }
                    .frame(width: 175)
                    .background(Color(hex: "#F9F9FB"))
                    .overlay(Divider().background(Color.black.opacity(0.06)), alignment: .trailing)

                    // 메인 대화 영역
                    VStack(alignment: .leading, spacing: 14) {
                        // 유저 메시지 말풍선
                        HStack {
                            Spacer()
                            Text("지금 작성 중인 연구 설문 시스템에서 피로도 점수와 AI 영향 평가 문항을 어떻게 구성하면 좋을지 정리해줘.")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(Color(hex: "#0F8B6C"))
                                .cornerRadius(12)
                                .frame(maxWidth: 420, alignment: .trailing)
                        }

                        // AI 응답 말풍선
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color(hex: "#0F8B6C"))
                                .frame(width: 24, height: 24)
                                .overlay(Image(systemName: "sparkles").font(.system(size: 11, weight: .bold)).foregroundColor(.white))

                            VStack(alignment: .leading, spacing: 8) {
                                Text("다음 3단계 설문 체계를 권장합니다:")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color(hex: "#1F1C17"))

                                Text("1. 전반적 피로도 (1~5점 척도): SPS 기반 활성도 평가\n2. AI 영향도 (2점 이상 시 노출): 인지적 과부하 원인 칩 선택\n3. 작업 맥락: 번거로운 텍스트 입력 대신 원터치 화면 캡처 연동\n\n이렇게 구성하면 사용자의 응답 부담(Survey Burden)을 60% 이상 줄이면서 고품질 데이터를 수집할 수 있습니다.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(Color(hex: "#333333"))
                                    .lineSpacing(3)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.07), lineWidth: 0.8))
                            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
                            .frame(maxWidth: 460, alignment: .leading)

                            Spacer()
                        }

                        Spacer()
                    }
                    .padding(18)
                    .background(Color(hex: "#FAFAFA"))
                }
            }
            .frame(width: 840, height: 560)
            .background(Color.white)
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            .offset(x: 50, y: 70)
    }

    // 3. 우상단 실제 설문 팝업 또는 메뉴바 드롭다운 패널 (상단 고정 배치)
    @ViewBuilder
    private var popupOverlayView: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                switch sceneType {
                case .midSurvey:
                    // 초기 미입력 상태 (placeholder 노출)
                    SurveyPopupView(
                        surveyType: .mid,
                        sessionTitle: "AI 피로도 연구 분석",
                        aiTool: "ChatGPT",
                        snoozeCount: 0,
                        initialSituation: nil,
                        initialFatigue: nil,
                        initialAIFatigueImpact: nil,
                        initialUsefulness: nil,
                        initialCapturePath: nil,
                        maxContentHeight: 1200,
                        onHeightChanged: { _ in },
                        onAction: { _, _ in }
                    )
                    .frame(width: Config.Survey.popupDefaultWidth)

                case .snoozeResumedSurvey:
                    // 5분 뒤 스누즈 후 이어서 작성 중인 화면 (1단계 작성 완료된 Draft 상태에서 2단계 피로도 평가로 복원된 상태)
                    SurveyPopupView(
                        surveyType: .mid,
                        sessionTitle: "AI 피로도 연구 분석",
                        aiTool: "ChatGPT",
                        snoozeCount: 1,
                        initialStep: 2,
                        draftState: SurveyDraftState(
                            currentStep: 2,
                            fatigueScore: 3,
                            aiFatigueImpactScore: 3,
                            taskPurpose: SubjectiveAnswer(customText: "설문 체계 분석 및 초안 정리 중"),
                            aiRole: SubjectiveAnswer(customText: "핵심만 빠르게 요약, 초안 틀 잡아주기"),
                            myRole: SubjectiveAnswer(customText: "요약 맞는지 확인, 내 말투로 고치기")
                        ),
                        initialSituation: "설문 체계 분석 및 초안 정리 중",
                        initialFatigue: 3,
                        initialAIFatigueImpact: 3,
                        maxContentHeight: 1200,
                        onHeightChanged: { _ in },
                        onAction: { _, _ in }
                    )
                    .frame(width: Config.Survey.popupDefaultWidth)

                case .startSurvey:
                    SurveyPopupView(
                        surveyType: .start,
                        sessionTitle: "AI 피로도 연구 분석",
                        aiTool: "ChatGPT",
                        snoozeCount: 0,
                        initialFatigue: 2,
                        maxContentHeight: 480,
                        onHeightChanged: { _ in },
                        onAction: { _, _ in }
                    )
                    .frame(width: Config.Survey.popupDefaultWidth)

                case .endSurvey:
                    // 아무것도 선택하지 않은 깨끗한 초기 상태 (맨 위부터 온전히 노출)
                    SurveyPopupView(
                        surveyType: .end,
                        sessionTitle: "AI 피로도 연구 분석",
                        aiTool: "ChatGPT",
                        snoozeCount: 0,
                        initialSituation: nil,
                        initialFatigue: nil,
                        initialAIFatigueImpact: nil,
                        initialUsefulness: nil,
                        maxContentHeight: 1200,
                        onHeightChanged: { _ in },
                        onAction: { _, _ in }
                    )
                    .frame(width: Config.Survey.popupDefaultWidth)

                case .endSurveyTLX:
                    // 3단계: 작업 부하 및 수행 평가 (NASA-TLX)
                    SurveyPopupView(
                        surveyType: .end,
                        sessionTitle: "AI 피로도 연구 분석",
                        aiTool: "ChatGPT",
                        snoozeCount: 0,
                        initialStep: 3,
                        initialSituation: nil,
                        initialFatigue: 4,
                        initialAIFatigueImpact: 3,
                        initialUsefulness: 4,
                        maxContentHeight: 1200,
                        onHeightChanged: { _ in },
                        onAction: { _, _ in }
                    )
                    .frame(width: Config.Survey.popupDefaultWidth)

                case .diarySurvey:
                    VoluntaryRecordPopupView(
                        context: VoluntaryCaptureContext(appName: "ChatGPT"),
                        initialSituation: nil,
                        initialFatigue: nil,
                        initialAIFatigueImpact: nil,
                        maxContentHeight: 1200,
                        onHeightChanged: { _ in },
                        onCancel: {},
                        onSave: { _, _ in }
                    )
                    .frame(width: Config.Survey.popupDefaultWidth)

                case .menuBarDropdown:
                    MenuBarView(showDebugMenu: false)
                        .frame(width: 412)
                        .background(Config.Colors.popupBg)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Config.Colors.line, lineWidth: 1.0))
                        .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: 8)
                        .padding(.trailing, 30)

                case .followUpSurvey:
                    SurveyPopupView(
                        surveyType: .followUp,
                        sessionTitle: "AI 피로도 연구 분석",
                        aiTool: "ChatGPT",
                        snoozeCount: 0,
                        maxContentHeight: 1200,
                        onHeightChanged: { _ in },
                        onAction: { _, _ in }
                    )
                    .frame(width: Config.Survey.popupDefaultWidth)
                }
            }
            .padding(.top, 24 + 12)
            .padding(.trailing, sceneType == .menuBarDropdown ? 0 : 20)
        }
        .frame(width: 1440, height: 900, alignment: .topTrailing)
    }

    // 4. macOS 상단 메뉴바 (24pt, 라이트 반투명)
    private var menubarFatigueScore: Int {
        switch sceneType {
        case .endSurvey, .diarySurvey, .followUpSurvey: return 4
        case .startSurvey: return 2
        default: return 3
        }
    }

    private var menubarDurationString: String {
        switch sceneType {
        case .endSurvey, .endSurveyTLX: return "ChatGPT 48:30"
        case .startSurvey: return "ChatGPT 02:10"
        case .diarySurvey: return "ChatGPT 35:20"
        case .followUpSurvey: return "ChatGPT 58:40"
        case .snoozeResumedSurvey: return "ChatGPT 29:15"
        default: return "ChatGPT 24:15"
        }
    }

    private var menuBarLeftView: some View {
        HStack(spacing: 14) {
            Image(systemName: "applelogo")
                .font(.system(size: 13, weight: .semibold))
            Text("Finder")
                .font(.system(size: 12, weight: .bold))
            Text("File")
                .font(.system(size: 12))
            Text("Edit")
                .font(.system(size: 12))
            Text("View")
                .font(.system(size: 12))
            Text("Go")
                .font(.system(size: 12))
            Text("Window")
                .font(.system(size: 12))
            Text("Help")
                .font(.system(size: 12))
        }
        .foregroundColor(Color.black.opacity(0.85))
    }

    private var trackerStatusPill: some View {
        HStack(spacing: 5) {
            MiniDesktopBatteryIcon(fatigueScore: menubarFatigueScore)
            Text(menubarDurationString)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundColor(Color.black.opacity(0.88))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(sceneType == .menuBarDropdown ? Color(hex: Config.Colors.accentHex).opacity(0.18) : Color.black.opacity(0.06))
        .cornerRadius(4)
    }

    private var menuBarRightView: some View {
        HStack(spacing: 12) {
            trackerStatusPill
            Image(systemName: "wifi")
                .font(.system(size: 11))
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
            Image(systemName: "switch.2")
                .font(.system(size: 11))
            Text("11월 9일 (월) 오후 3:20")
                .font(.system(size: 11.5, weight: .regular))
        }
        .foregroundColor(Color.black.opacity(0.85))
    }

    private var menuBarView: some View {
        HStack(spacing: 16) {
            menuBarLeftView
            Spacer()
            menuBarRightView
        }
        .padding(.horizontal, 14)
        .frame(width: 1440, height: 24)
        .background(Color.white.opacity(0.82))
        .overlay(Divider().background(Color.black.opacity(0.1)), alignment: .bottom)
    }
}

// 미니 배터리 아이콘
public struct MiniDesktopBatteryIcon: View {
    public let fatigueScore: Int

    public init(fatigueScore: Int) {
        self.fatigueScore = fatigueScore
    }

    public var body: some View {
        let fillFraction: CGFloat = CGFloat(fatigueScore) / 5.0
        let fillColor: Color = {
            switch fatigueScore {
            case 1: return Color(hex: "#10B981") // 초록
            case 2: return Color(hex: "#84CC16") // 연두
            case 3: return Color(hex: "#F59E0B") // 주황
            case 4: return Color(hex: "#F97316") // 진한 주황
            case 5: return Color(hex: "#EF4444") // 빨강
            default: return Color(hex: "#10B981")
            }
        }()

        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.black.opacity(0.7), lineWidth: 0.9)
                    .frame(width: 17, height: 9.5)

                RoundedRectangle(cornerRadius: 1)
                    .fill(fillColor)
                    .frame(width: max(2, (17 - 3) * fillFraction), height: 5.5)
                    .padding(.leading, 1.5)
            }
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color.black.opacity(0.7))
                .frame(width: 1.2, height: 3.5)
        }
    }
}

