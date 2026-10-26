import SwiftUI
import AppKit

/// 설정 및 프라이버시 관리 창
/// 1. 이름 확인 및 수정 (display_name만 갱신, participant_id 유지)
/// 2. 시스템 권한 상태 확인 및 재요청 (손쉬운 사용, 자동화-브라우저별, 화면 기록, 마이크)
/// 3. 개인 제외 목록 관리 (연구팀 기본 목록은 고정, 참여자가 앱 및 사이트 자유롭게 추가/삭제)
/// 4. 오늘 기록된 활동 보기 및 선택 삭제 (로컬 및 서버 영구 삭제)
/// 5. 연구 종료일 표시 (종료 시 모든 기록 중단 및 감사 화면 노출)
public struct SettingsView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var permissions: PermissionsManager = .shared
    @ObservedObject var customAIManager: CustomAITargetManager = .shared
    @ObservedObject var exclusionManager: PersonalExclusionManager = .shared
    @ObservedObject var syncManager: SupabaseSyncManager = .shared

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case profile = "내 정보 & 연구 기간"
        case permissions = "권한 상태"
        case aiTargets = "AI 감지 대상 추가"
        case exclusions = "개인 제외 목록"
        case todayActivities = "오늘 기록된 활동"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .profile: return "person.text.rectangle"
            case .permissions: return "lock.shield"
            case .aiTargets: return "sparkles.rectangle.stack"
            case .exclusions: return "eye.slash"
            case .todayActivities: return "list.bullet.rectangle"
            }
        }
    }

    @State private var selectedTab: SettingsTab = .profile

    // 1. 프로필 수정용 상태
    @State private var editedName: String = ""
    @State private var isNameSavedToast: Bool = false
    @State private var isIdCopiedToast: Bool = false

    // 2. AI 감지 대상 추가용 상태
    @State private var newAIDomain: String = ""
    @State private var newAIDomainName: String = ""
    @State private var activeTabNotice: String? = nil
    @State private var newAIAppBundleId: String = ""
    @State private var newAIAppName: String = ""

    // 3. 제외 목록 추가용 상태
    @State private var newAppBundleId: String = ""
    @State private var newAppName: String = ""
    @State private var newDomain: String = ""

    // 4. 오늘 활동 조회 및 삭제용 상태
    @State private var todayActivities: [LocalDatabase.LoggedActivityItem] = []
    @State private var selectedActivityIds: Set<String> = []

    // 5. 앱 종료 확인 다이얼로그용 상태
    @State private var isQuitConfirmPresented: Bool = false

    public init() {
        if CommandLine.arguments.contains("--test-settings-ai-targets") {
            self._selectedTab = State(initialValue: .aiTargets)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 상단 탭 선택 바
            tabSelectionBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .background(Config.Colors.paper)

            Divider()

            // 탭별 본문 영역
            Group {
                switch selectedTab {
                case .profile:
                    profileAndStudySection
                case .permissions:
                    permissionsSection
                case .aiTargets:
                    aiTargetsSection
                case .exclusions:
                    exclusionsSection
                case .todayActivities:
                    todayActivitiesSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Config.Colors.panelBackground)
        }
        .frame(minWidth: 700, minHeight: 520)
        .onAppear {
            self.editedName = appState.participantName
            self.permissions.refreshAll()
            self.permissions.checkAllBrowserAutomation()
            self.loadTodayActivities()
        }
    }

    // MARK: - 상단 탭 선택 바
    private var tabSelectionBar: some View {
        HStack(spacing: 8) {
            ForEach(SettingsTab.allCases) { tab in
                Button(action: {
                    selectedTab = tab
                    if tab == .todayActivities {
                        loadTodayActivities()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                        Text(tab.rawValue)
                            .font(.system(size: 12.5, weight: selectedTab == tab ? .bold : .medium))
                    }
                    .foregroundColor(selectedTab == tab ? .white : Config.Colors.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color(hex: Config.Colors.accentHex) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - 탭 1: 내 정보 & 연구 기간 (종료 시 감사 화면)
    private var profileAndStudySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 연구 종료 상태 안내 배너
                if appState.isStudyCompleted {
                    HStack(spacing: 12) {
                        Text("☺️")
                            .font(.system(size: 24))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("참여해 주셔서 감사합니다 ☺️")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(Config.Colors.ink)
                            Text("14일간의 공식 연구 일정을 모두 달성하셨습니다. 앞으로도 피로 기록 및 AI 활동 감지 기능을 자유롭게 계속 사용하실 수 있습니다.")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.25), lineWidth: 0.8))
                }

                // 앱 대표 로고 및 연구 개요 카드
                HStack(spacing: 14) {
                    if let icon = Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage ?? NSImage(named: "AppIcon") {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI Fatigue Tracker")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                        Text("인간-AI 상호작용 및 피로도 경험표집 연구 시스템")
                            .font(.system(size: 11.5))
                            .foregroundColor(Config.Colors.mute)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Config.Colors.cardBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 1))

                // 1. 참여자 이름 및 식별자 카드
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 7) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                        Text("참여자 정보")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        // 표시 이름
                        HStack(spacing: 12) {
                            Text("표시 이름")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Config.Colors.mute)
                                .frame(width: 85, alignment: .leading)

                            TextField("이름 입력", text: $editedName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 240)

                            Button(action: {
                                appState.updateParticipantName(editedName)
                                isNameSavedToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    isNameSavedToast = false
                                }
                            }) {
                                Text("수정 저장")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(hex: Config.Colors.accentHex))
                                    )
                            }
                            .buttonStyle(.plain)

                            if isNameSavedToast {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("저장됨")
                                }
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.green)
                                .transition(.opacity)
                            }
                        }

                        // 연구 식별자 (UUID)
                        HStack(spacing: 12) {
                            Text("연구 식별자")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Config.Colors.mute)
                                .frame(width: 85, alignment: .leading)

                            HStack(spacing: 8) {
                                Text(appState.participantId)
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(Config.Colors.ink)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Config.Colors.paper)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Config.Colors.line, lineWidth: 0.8))
                                    )

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(appState.participantId, forType: .string)
                                    isIdCopiedToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                        isIdCopiedToast = false
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: isIdCopiedToast ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10.5))
                                        Text(isIdCopiedToast ? "복사됨" : "복사")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(isIdCopiedToast ? .green : Config.Colors.mute)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Config.Colors.cardBackground)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Config.Colors.line, lineWidth: 0.8))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                                .padding(.top, 1)
                            Text("이름을 수정하더라도 고유 연구 식별자(UUID)는 영구 유지되며, 서버의 참여자 데이터에 안전하게 반영됩니다.")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Config.Colors.cardBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))

                // 2. 연구 일정 및 진행 현황 카드
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 7) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                        Text("연구 일정 및 진행 상태")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }

                    let startStr = formatDate(appState.studyStartDate)
                    let endStr = formatDate(appState.studyEndDate)
                    let studyDay = LocalDatabase.shared.getStudyDay()
                    let progress = min(max(Double(studyDay) / 14.0, 0.0), 1.0)

                    // 3-컬럼 메트릭 카드
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("연구 시작일")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                            Text(startStr)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Config.Colors.ink)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Config.Colors.paper)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.6))
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("연구 종료일 (14일간)")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                            Text(endStr)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Config.Colors.ink)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Config.Colors.paper)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.6))
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("현재 진행")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                            Text(appState.isStudyCompleted ? "\(studyDay)일째 (완료)" : "\(studyDay)일째 (D-\(appState.daysRemaining))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(appState.isStudyCompleted ? .green : Color(hex: Config.Colors.accentHex))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Config.Colors.paper)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.6))
                        )
                    }

                    // 진행률 바
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("14일 연구 일정 진행률")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Config.Colors.mute)
                            Spacer()
                            Text("\(Int(progress * 100))% (\(studyDay)/14일)")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: Config.Colors.accentHex))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Config.Colors.line.opacity(0.5))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: Config.Colors.accentHex))
                                    .frame(width: max(8, geo.size.width * progress), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.top, 2)

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                            .padding(.top, 1)
                        Text("14일 연구 기간 완료 후에도 모든 활동 추적 및 피로 기록 기능은 중단 없이 계속 자유롭게 이용하실 수 있습니다.")
                            .font(.system(size: 11))
                            .foregroundColor(Config.Colors.mute)
                    }
                    .padding(.top, 2)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Config.Colors.cardBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))

                // 하단 보조 액션 (온보딩 프로세스 다시 실행 / 앱 종료)
                HStack {
                    Button(action: {
                        SettingsWindowManager.shared.closeSettingsWindow()
                        OnboardingWindowManager.shared.showOnboardingWindow()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .bold))
                            Text("온보딩 프로세스 다시 실행 (테스트)")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundColor(Config.Colors.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Config.Colors.cardBackground)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.8))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(role: .destructive) {
                        isQuitConfirmPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "power")
                                .font(.system(size: 11, weight: .bold))
                            Text("앱 종료")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red.opacity(0.85))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(20)
        }
        .confirmationDialog(
            "앱을 완전히 종료하시겠습니까?",
            isPresented: $isQuitConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("앱 종료", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("종료 시 다시 앱을 실행하기 전까지 AI 활동 감지 및 설문 조사가 중단됩니다.")
        }
    }

    // MARK: - 탭 2: 권한 상태 및 다시 요청 (손쉬운 사용, 브라우저별 자동화, 화면 기록, 마이크)
    private var permissionsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("시스템 권한 점검 및 허용")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                VStack(spacing: 10) {
                    permissionRow(
                        title: "손쉬운 사용 (Accessibility)",
                        desc: "현재 사용 중인 AI 도구 및 활성 창 제목을 감지하는 필수 권한입니다.",
                        granted: permissions.isAccessibilityGranted,
                        isMandatory: true
                    ) {
                        permissions.requestAccessibility()
                    }

                    permissionRow(
                        title: "화면 기록 (Screen Recording)",
                        desc: "피로한 순간 직접 기록(⌥⌘S) 시 문제 화면을 캡처하고 분석하는 필수 권한입니다.",
                        granted: permissions.isScreenCaptureGranted,
                        isMandatory: true
                    ) {
                        permissions.requestScreenCapture()
                    }

                    permissionRow(
                        title: "웹 브라우저 자동화 (AppleEvents)",
                        desc: "설치된 브라우저(\(permissions.installedBrowsers.map(\.name).joined(separator: ", ")))에서 chatgpt.com, claude.ai 탭을 감지하기 위한 필수 권한입니다.",
                        granted: permissions.isBrowserAutomationGranted,
                        isMandatory: true
                    ) {
                        permissions.requestAllBrowserAutomation()
                    }

                    permissionRow(
                        title: "마이크 (Microphone)",
                        desc: "주관식 피로 설문에 음성으로 답변할 때 사용되는 선택 권한입니다.",
                        granted: permissions.isMicrophoneGranted,
                        isMandatory: false
                    ) {
                        permissions.requestMicrophone()
                        PermissionsManager.shared.openSystemSettings(pane: "Privacy_Microphone")
                    }

                    permissionRow(
                        title: "음성 인식 (Speech Recognition)",
                        desc: "마이크로 입력된 음성을 한국어 텍스트(STT)로 실시간 변환하기 위해 필요한 선택 권한입니다.",
                        granted: permissions.isSpeechRecognitionGranted,
                        isMandatory: false
                    ) {
                        permissions.requestSpeechRecognition()
                        PermissionsManager.shared.openSystemSettings(pane: "Privacy_SpeechRecognition")
                    }
                }
                .padding(12)
                .background(Config.Colors.cardBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))

                // 브라우저별 자동화 (AppleEvents) 권한
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("웹 브라우저별 자동화 권한 (방문 탭 URL 감지)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Config.Colors.ink)
                                Text("필수")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(Color(hex: Config.Colors.accentHex))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color(hex: Config.Colors.accentHex).opacity(0.12))
                                    .cornerRadius(4)
                            }

                            Text("현재 Mac에 실제로 설치된 브라우저만 자동 감지하여 표시합니다. 웹 기반 AI 도구(ChatGPT, Claude 등)의 활성 대화를 정확히 감지하려면 브라우저 자동화 권한이 필요합니다.")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Button {
                            permissions.requestAllBrowserAutomation()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: permissions.isAllBrowserAutomationGranted ? "checkmark.circle.fill" : "link.badge.plus")
                                    .font(.system(size: 11))
                                Text(permissions.isAllBrowserAutomationGranted ? "모든 브라우저 연동 완료" : "모든 브라우저 한꺼번에 연동")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(permissions.isAllBrowserAutomationGranted ? Color.green : Color(hex: Config.Colors.accentHex))
                    }

                    VStack(spacing: 8) {
                        ForEach(permissions.installedBrowsers) { browser in
                            let granted = permissions.browserAutomationStatuses[browser.bundleId] ?? false
                            HStack {
                                Circle()
                                    .fill(granted ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)

                                Text(browser.name)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(Config.Colors.ink)

                                Spacer()

                                Text(granted ? "허용됨" : "권한 필요")
                                    .font(.system(size: 11, weight: granted ? .regular : .semibold))
                                    .foregroundColor(granted ? .green : .orange)

                                Button(granted ? "다시 확인" : "개별 연동") {
                                    permissions.requestBrowserAutomation(bundleId: browser.bundleId)
                                }
                                .font(.system(size: 11))
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(12)
                .background(Config.Colors.cardBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))
            }
            .padding(16)
        }
    }

    private func permissionRow(title: String, desc: String, granted: Bool, isMandatory: Bool = false, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(granted ? Color.green : (isMandatory ? Color.red : Color.orange))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Config.Colors.ink)

                    Text(isMandatory ? "필수" : "선택")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(isMandatory ? Color(hex: Config.Colors.accentHex) : Color.purple)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background((isMandatory ? Color(hex: Config.Colors.accentHex) : Color.purple).opacity(0.12))
                        .cornerRadius(3)
                }

                Text(desc)
                    .font(.system(size: 10.5))
                    .foregroundColor(Config.Colors.mute)
            }

            Spacer()

            Text(granted ? "허용됨" : "미허용")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(granted ? .green : (isMandatory ? .red : .orange))

            Button(granted ? "설정 확인" : "권한 허용") {
                action()
            }
            .font(.system(size: 11))
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 탭 3: 맞춤형 AI 감지 대상 추가 (사내 AI 웹사이트, 특수 웹 AI, 데스크톱 앱)
    private var aiTargetsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 상단 안내 배너
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("사내 AI 포털 및 맞춤형 AI 도구 등록")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                        Text("ChatGPT, Claude, Cursor 등 연구팀 기본 감지 목록에 없는 사내 AI 웹사이트나 데스크톱 앱을 직접 등록하세요. 등록된 도구는 정식 AI 활동으로 감지되어 대화 세션 및 피로도 설문에 즉시 반영됩니다.")
                            .font(.system(size: 11))
                            .foregroundColor(Config.Colors.mute)
                            .lineSpacing(2)
                    }
                }
                .padding(14)
                .background(Color(hex: Config.Colors.accentHex).opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: Config.Colors.accentHex).opacity(0.2), lineWidth: 0.8)
                )

                // 1. AI 웹사이트 / 도메인 등록 카드
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI 웹사이트 / 도메인 등록")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Config.Colors.ink)
                            Text("브라우저에서 접속하는 사내 AI 포털 또는 웹 AI 도구의 주소를 등록합니다.")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                        }
                        Spacer()
                        Text("등록된 도메인 \(customAIManager.customDomains.count)개")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Config.Colors.mute)
                    }

                    // 현재 활성 탭 주소 자동 가져오기 버튼
                    HStack(spacing: 8) {
                        Button {
                            fetchActiveBrowserTab()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "globe.americas.fill")
                                    .font(.system(size: 11))
                                Text("현재 열린 브라우저 탭 주소 가져오기")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: Config.Colors.accentHex).opacity(0.1))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)

                        if let notice = activeTabNotice {
                            Text(notice)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: Config.Colors.accentHex))
                                .transition(.opacity)
                        }

                        Spacer()
                    }

                    // 도메인 및 이름 입력 바
                    HStack(spacing: 8) {
                        TextField("웹 도메인 또는 주소 (예: ai.mycompany.com)", text: $newAIDomain)
                            .textFieldStyle(.roundedBorder)

                        TextField("도구 명칭 (예: 사내 AI 챗봇)", text: $newAIDomainName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)

                        Button("도메인 등록") {
                            customAIManager.addCustomDomain(newAIDomain, displayName: newAIDomainName)
                            newAIDomain = ""
                            newAIDomainName = ""
                            activeTabNotice = nil
                        }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: Config.Colors.accentHex))
                        .disabled(newAIDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    // 등록된 도메인 리스트
                    if customAIManager.customDomains.isEmpty {
                        HStack {
                            Spacer()
                            Text("아직 직접 등록된 웹 AI 도메인이 없습니다.")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute.opacity(0.7))
                                .padding(.vertical, 10)
                            Spacer()
                        }
                    } else {
                        VStack(spacing: 4) {
                            ForEach(customAIManager.customDomains) { item in
                                HStack {
                                    Text("웹 도메인")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color(hex: Config.Colors.accentHex).opacity(0.12))
                                        .cornerRadius(3)

                                    Text(item.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Config.Colors.ink)

                                    Text("(\(item.value))")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(Config.Colors.mute)

                                    Spacer()

                                    Button(role: .destructive) {
                                        customAIManager.removeCustomDomain(id: item.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Config.Colors.cardBackground)
                                .cornerRadius(5)
                            }
                        }
                    }
                }
                .padding(14)
                .background(Config.Colors.paper)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))

                // 2. AI 데스크톱 앱 등록 카드
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI 데스크톱 앱 등록")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Config.Colors.ink)
                            Text("Mac에 설치되어 실행되는 AI 전용 앱 또는 사내 AI 클라이언트를 등록합니다.")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                        }
                        Spacer()
                        Text("등록된 앱 \(customAIManager.customApps.count)개")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Config.Colors.mute)
                    }

                    // 실행 중인 일반 앱 빠른 선택 메뉴
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(getRunningCandidateApps(), id: \.processIdentifier) { app in
                                Button {
                                    self.newAIAppBundleId = app.bundleIdentifier ?? (app.localizedName ?? "")
                                    self.newAIAppName = app.localizedName ?? ""
                                } label: {
                                    Text("\(app.localizedName ?? "알 수 없음") (\(app.bundleIdentifier ?? "ID 없음"))")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow.on.rectangle")
                                    .font(.system(size: 11))
                                Text("실행 중인 앱에서 선택하여 채우기…")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Config.Colors.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Config.Colors.cardBackground)
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Config.Colors.line, lineWidth: 0.8))
                        }
                        .menuStyle(.borderlessButton)

                        Spacer()
                    }

                    // 앱 번들 ID 및 이름 입력 바
                    HStack(spacing: 8) {
                        TextField("앱 번들 ID 또는 이름 (예: com.company.aiassistant)", text: $newAIAppBundleId)
                            .textFieldStyle(.roundedBorder)

                        TextField("도구 명칭 (예: 사내 AI 비서)", text: $newAIAppName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)

                        Button("앱 등록") {
                            customAIManager.addCustomApp(bundleIdOrName: newAIAppBundleId, displayName: newAIAppName)
                            newAIAppBundleId = ""
                            newAIAppName = ""
                        }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: Config.Colors.accentHex))
                        .disabled(newAIAppBundleId.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    // 등록된 앱 리스트
                    if customAIManager.customApps.isEmpty {
                        HStack {
                            Spacer()
                            Text("아직 직접 등록된 AI 데스크톱 앱이 없습니다.")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute.opacity(0.7))
                                .padding(.vertical, 10)
                            Spacer()
                        }
                    } else {
                        VStack(spacing: 4) {
                            ForEach(customAIManager.customApps) { item in
                                HStack {
                                    Text("데스크톱 앱")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(Color.purple)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.purple.opacity(0.12))
                                        .cornerRadius(3)

                                    Text(item.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Config.Colors.ink)

                                    Text("(\(item.value))")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(Config.Colors.mute)

                                    Spacer()

                                    Button(role: .destructive) {
                                        customAIManager.removeCustomApp(id: item.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Config.Colors.cardBackground)
                                .cornerRadius(5)
                            }
                        }
                    }
                }
                .padding(14)
                .background(Config.Colors.paper)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))
            }
            .padding(16)
        }
    }

    private func fetchActiveBrowserTab() {
        for browser in permissions.installedBrowsers {
            if let tab = BrowserTracker.shared.fetchActiveTab(for: browser.bundleId, pid: nil), !tab.url.isEmpty {
                if let host = URL(string: tab.url)?.host {
                    self.newAIDomain = host
                    self.newAIDomainName = tab.title.isEmpty ? host : tab.title
                    self.activeTabNotice = "✓ \(browser.name) 활성 탭(\(host)) 가져옴"
                    return
                }
            }
        }
        self.activeTabNotice = "열려있는 브라우저 탭을 찾지 못했습니다"
    }

    private func getRunningCandidateApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    // MARK: - 탭 4: 개인 제외 목록 (연구팀 기본 고정 + 참여자 추가/삭제)
    private var exclusionsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. 앱 제외 목록
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("기록 제외 앱 목록")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                        Spacer()
                        Text("총 \(exclusionManager.allApps.count)개")
                            .font(.system(size: 11))
                            .foregroundColor(Config.Colors.mute)
                    }

                    // 새 앱 추가 입력창
                    HStack(spacing: 8) {
                        TextField("앱 번들 ID (예: com.kakao.KakaoTalk)", text: $newAppBundleId)
                            .textFieldStyle(.roundedBorder)
                        TextField("이름 (선택)", text: $newAppName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)

                        Button("앱 추가") {
                            exclusionManager.addCustomApp(bundleId: newAppBundleId, displayName: newAppName)
                            newAppBundleId = ""
                            newAppName = ""
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderedProminent)
                        .disabled(newAppBundleId.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    // 앱 목록
                    VStack(spacing: 4) {
                        ForEach(exclusionManager.allApps) { item in
                            HStack {
                                if item.isBuiltIn {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Config.Colors.mute)
                                }
                                Text(item.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Config.Colors.ink)
                                Text("(\(item.value))")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(Config.Colors.mute)

                                Spacer()

                                if item.isBuiltIn {
                                    Text("연구팀 기본 (고정)")
                                        .font(.system(size: 10))
                                        .foregroundColor(Config.Colors.mute)
                                } else {
                                    Button(role: .destructive) {
                                        exclusionManager.removeCustomApp(id: item.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(Config.Colors.cardBackground)
                            .cornerRadius(4)
                        }
                    }
                }
                .padding(14)
                .background(Config.Colors.paper)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))

                // 2. 도메인/사이트 제외 목록
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("기록 제외 웹사이트/도메인 목록")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                        Spacer()
                        Text("총 \(exclusionManager.allDomains.count)개")
                            .font(.system(size: 11))
                            .foregroundColor(Config.Colors.mute)
                    }

                    // 새 도메인 추가 입력창
                    HStack(spacing: 8) {
                        TextField("제외할 도메인 (예: youtube.com, instagram.com)", text: $newDomain)
                            .textFieldStyle(.roundedBorder)

                        Button("도메인 추가") {
                            exclusionManager.addCustomDomain(newDomain)
                            newDomain = ""
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderedProminent)
                        .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    // 도메인 목록
                    VStack(spacing: 4) {
                        ForEach(exclusionManager.allDomains) { item in
                            HStack {
                                if item.isBuiltIn {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Config.Colors.mute)
                                }
                                Text(item.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Config.Colors.ink)
                                Text("(\(item.value))")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(Config.Colors.mute)

                                Spacer()

                                if item.isBuiltIn {
                                    Text("연구팀 기본 (고정)")
                                        .font(.system(size: 10))
                                        .foregroundColor(Config.Colors.mute)
                                } else {
                                    Button(role: .destructive) {
                                        exclusionManager.removeCustomDomain(id: item.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(Config.Colors.cardBackground)
                            .cornerRadius(4)
                        }
                    }
                }
                .padding(14)
                .background(Config.Colors.paper)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))
            }
            .padding(16)
        }
    }

    // MARK: - 탭 4: 오늘 기록된 활동 보기 및 선택 삭제 (서버 연동 삭제)
    private var todayActivitiesSection: some View {
        VStack(spacing: 0) {
            // 상단 컨트롤 바
            HStack {
                Text("오늘 수집된 활동 (\(todayActivities.count)건)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                Spacer()

                // 새로고침 아이콘 버튼 (텍스트 없는 로고 버튼)
                Button(action: {
                    loadTodayActivities()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 2)
                }
                .buttonStyle(.bordered)
                .help("새로고침")

                // 전체 선택 / 전체 해제 버튼
                Button(action: {
                    if selectedActivityIds.count == todayActivities.count {
                        selectedActivityIds.removeAll()
                    } else {
                        selectedActivityIds = Set(todayActivities.map { $0.id })
                    }
                }) {
                    Text(selectedActivityIds.count == todayActivities.count && !todayActivities.isEmpty ? "전체 해제" : "전체 선택")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)

                // 삭제 버튼 (로고 + "삭제")
                Button(action: {
                    confirmAndDeleteActivities()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                        Text("삭제")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(selectedActivityIds.isEmpty ? Config.Colors.mute.opacity(0.5) : .red)
                }
                .buttonStyle(.bordered)
                .disabled(selectedActivityIds.isEmpty)
                .help("선택한 항목 삭제")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Config.Colors.paper)

            Divider()

            // 목록 테이블
            if todayActivities.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 30))
                        .foregroundColor(Config.Colors.mute)
                    Text("오늘 기록된 컴퓨터 활동이 없습니다.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Config.Colors.mute)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(todayActivities) { item in
                        HStack(spacing: 10) {
                            Button(action: {
                                if selectedActivityIds.contains(item.id) {
                                    selectedActivityIds.remove(item.id)
                                } else {
                                    selectedActivityIds.insert(item.id)
                                }
                            }) {
                                Image(systemName: selectedActivityIds.contains(item.id) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 14))
                                    .foregroundColor(selectedActivityIds.contains(item.id) ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute)
                            }
                            .buttonStyle(.plain)

                            Text(item.timeString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Config.Colors.mute)
                                .frame(width: 60, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.appName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Config.Colors.ink)
                                Text(item.windowTitle)
                                    .font(.system(size: 11))
                                    .foregroundColor(Config.Colors.mute)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if item.durationSec > 0 {
                                Text("\(item.durationSec)초")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Config.Colors.mute)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    /// 삭제 시 시스템 warning 모달 알림창을 띄우고 사용자가 확인했을 때만 영구 삭제 실행
    private func confirmAndDeleteActivities() {
        let count = selectedActivityIds.count
        guard count > 0 else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "선택한 활동 기록 \(count)개를 삭제하시겠습니까?"
        alert.informativeText = "삭제된 활동 기록은 로컬 데이터베이스와 서버에서 영구적으로 제거되며, 다시 복구할 수 없습니다."
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")

        if #available(macOS 11.0, *) {
            alert.buttons.first?.hasDestructiveAction = true
        }

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let idsToDelete = Array(selectedActivityIds)
            LocalDatabase.shared.deleteActivityEvents(ids: idsToDelete)
            selectedActivityIds.removeAll()
            loadTodayActivities()
        }
    }

    private func loadTodayActivities() {
        self.todayActivities = LocalDatabase.shared.fetchTodayActivities()
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy년 M월 d일"
        return f.string(from: date)
    }
}
