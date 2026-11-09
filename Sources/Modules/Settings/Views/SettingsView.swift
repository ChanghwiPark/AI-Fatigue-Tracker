import SwiftUI
import AppKit

/// 설정 및 프라이버시 관리 창
/// 1. 이름 확인 및 수정 (display_name만 갱신, participant_id 유지)
/// 2. 시스템 권한 설정 확인 및 재요청 (손쉬운 사용, 자동화-브라우저별, 화면 기록, 마이크)
/// 3. 기록 제외 설정 관리 (연구팀 기본 목록은 고정, 참여자가 앱 및 사이트 자유롭게 추가/삭제)
/// 4. 연구 종료일 표시 (종료 시 모든 기록 중단 및 감사 화면 노출)
public struct SettingsView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var permissions: PermissionsManager = .shared
    @ObservedObject var customAIManager: CustomAITargetManager = .shared
    @ObservedObject var exclusionManager: PersonalExclusionManager = .shared
    @ObservedObject var syncManager: SupabaseSyncManager = .shared

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case profile = "참여 정보"
        case permissions = "권한 설정"
        case aiTargets = "AI 도구 추가 등록"
        case exclusions = "기록 제외 설정"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .profile: return "person.text.rectangle"
            case .permissions: return "lock.shield"
            case .aiTargets: return "sparkles.rectangle.stack"
            case .exclusions: return "eye.slash"
            }
        }
    }

    @State private var selectedTab: SettingsTab = .profile

    // 1. 프로필 수정용 상태
    @State private var editedName: String = ""
    @State private var isNameSavedToast: Bool = false
    @State private var isIdCopiedToast: Bool = false

    // 2. AI 도구 추가 등록용 상태
    @State private var newAIDomain: String = ""
    @State private var newAIDomainName: String = ""
    @State private var activeTabNotice: String? = nil
    @State private var newAIAppBundleId: String = ""
    @State private var newAIAppName: String = ""

    // 3. 제외 목록 추가용 상태
    @State private var newAppBundleId: String = ""
    @State private var newAppName: String = ""
    @State private var newDomain: String = ""

    // 4. 앱 종료 확인 다이얼로그용 상태
    @State private var isQuitConfirmPresented: Bool = false

    public init(initialTab: SettingsTab? = nil) {
        if let tab = initialTab {
            self._selectedTab = State(initialValue: tab)
        } else if CommandLine.arguments.contains("--test-settings-ai-targets") {
            self._selectedTab = State(initialValue: .aiTargets)
        } else if let savedTab = UserDefaults.standard.string(forKey: "settings_selected_tab"),
                  let tab = SettingsTab(rawValue: savedTab) {
            self._selectedTab = State(initialValue: tab)
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Config.Colors.panelBackground)
        }
        .tint(Color(hex: Config.Colors.accentHex))
        .accentColor(Color(hex: Config.Colors.accentHex))
        .frame(minWidth: 700, minHeight: 520)
        .onAppear {
            self.editedName = appState.participantName
            self.permissions.refreshAll()
            self.permissions.checkAllBrowserAutomation()
        }
        .onChange(of: selectedTab) { _, newTab in
            UserDefaults.standard.set(newTab.rawValue, forKey: "settings_selected_tab")
        }
    }

    // MARK: - 상단 탭 선택 바
    private var tabSelectionBar: some View {
        HStack(spacing: 8) {
            ForEach(SettingsTab.allCases) { tab in
                Button(action: {
                    selectedTab = tab
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
                .focusable(false)
                .focusEffectDisabled()
            }
            Spacer()
        }
    }

    // MARK: - 탭 1: 참여 정보 (종료 시 감사 화면)
    private var profileAndStudySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 연구 종료 상태 안내 배너 (닫기/지우기 지원)
                if appState.isStudyCompleted && !appState.isStudyCompletedBannerDismissed {
                    HStack(alignment: .top, spacing: 12) {
                        Text("☺️")
                            .font(.system(size: 24))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("참여해주셔서 감사합니다 🧡")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(Config.Colors.ink)
                            Text("14일간의 공식 연구 일정을 모두 달성하셨습니다. 앞으로도 피로 기록 기능을 자유롭게 계속 사용하실 수 있습니다.")
                                .font(.system(size: 11.5))
                                .foregroundColor(Config.Colors.mute)
                                .lineSpacing(2)
                        }
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.dismissStudyCompletedBanner()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Config.Colors.mute.opacity(0.8))
                                .frame(width: 16, height: 16)
                                .background(Color.black.opacity(0.06))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 1)
                        .help("배너 닫기")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.25), lineWidth: 0.8))
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
                        let trimmedEditedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let isNameModified = !trimmedEditedName.isEmpty && trimmedEditedName != appState.participantName

                        // 표시 이름
                        HStack(spacing: 10) {
                            Text("표시 이름")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Config.Colors.mute)
                                .frame(width: 76, alignment: .leading)

                            HStack(spacing: 6) {
                                TextField("이름 입력", text: $editedName)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Config.Colors.ink)
                                    .onSubmit {
                                        saveParticipantName()
                                    }

                                if isNameModified {
                                    Button {
                                        editedName = appState.participantName
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                            .font(.system(size: 9.5, weight: .medium))
                                            .foregroundColor(Config.Colors.mute)
                                    }
                                    .buttonStyle(.plain)
                                    .help("원래 이름으로 되돌리기")
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(width: 320, height: 28)
                            .background(Config.Colors.paper)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        isNameModified
                                            ? Color(hex: Config.Colors.accentHex).opacity(0.8)
                                            : Config.Colors.line,
                                        lineWidth: 0.8
                                    )
                            )

                            Button(action: saveParticipantName) {
                                HStack(spacing: 4) {
                                    if isNameSavedToast {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("저장됨")
                                            .font(.system(size: 11, weight: .semibold))
                                    } else {
                                        Text("저장")
                                            .font(.system(size: 11.5, weight: isNameModified ? .bold : .medium))
                                    }
                                }
                                .foregroundColor(
                                    isNameSavedToast
                                        ? .green
                                        : (isNameModified ? .white : Config.Colors.mute)
                                )
                                .frame(width: 72, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            isNameSavedToast
                                                ? Color.green.opacity(0.14)
                                                : (isNameModified ? Color(hex: Config.Colors.accentHex) : Config.Colors.paper)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(
                                                    isNameSavedToast
                                                        ? Color.green.opacity(0.6)
                                                        : (isNameModified ? Color.clear : Config.Colors.line),
                                                    lineWidth: 0.8
                                                )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!isNameModified && !isNameSavedToast)
                        }

                        // 연구 식별자 (UUID)
                        HStack(spacing: 10) {
                            Text("연구 식별자")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Config.Colors.mute)
                                .frame(width: 76, alignment: .leading)

                            HStack {
                                Text(appState.participantId)
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

                            Button(action: copyParticipantId) {
                                HStack(spacing: 4) {
                                    Image(systemName: isIdCopiedToast ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10))
                                    Text(isIdCopiedToast ? "복사됨" : "복사")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(isIdCopiedToast ? .green : Config.Colors.ink)
                                .frame(width: 72, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isIdCopiedToast ? Color.green.opacity(0.14) : Config.Colors.paper)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isIdCopiedToast ? Color.green.opacity(0.6) : Config.Colors.line, lineWidth: 0.8)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
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

                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Config.Colors.cardBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Config.Colors.line, lineWidth: 0.8))

                // 하단 보조 액션 (앱 종료)
                HStack {
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

    // MARK: - 탭 2: 권한 설정 및 다시 요청 (손쉬운 사용, 브라우저별 자동화, 화면 기록, 마이크)
    private var permissionsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("시스템 권한 점검 및 허용")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                VStack(spacing: 8) {
                    permissionRow(
                        title: "손쉬운 사용 (AI 사용 시간 확인)",
                        desc: "어떤 AI 도구를 얼마나 썼는지 확인해요.",
                        granted: permissions.isAccessibilityGranted,
                        isMandatory: true
                    ) {
                        permissions.requestAccessibility(openSettingsAlways: true, from: "settings")
                    }

                    Divider().background(Config.Colors.line.opacity(0.5))

                    permissionRow(
                        title: "브라우저 연동 (AI 사이트 확인)",
                        desc: "브라우저에서 AI 도구를 쓰는지 확인해요.",
                        granted: permissions.isBrowserAutomationGranted,
                        isMandatory: true
                    ) {
                        permissions.requestAllBrowserAutomation(from: "settings")
                    }

                    Divider().background(Config.Colors.line.opacity(0.5))

                    permissionRow(
                        title: "화면 기록 (선택 화면 캡처)",
                        desc: "피로 기록 시 원하는 창이나 화면 영역을 직접 캡처하여 첨부할 수 있어요.",
                        granted: permissions.isScreenCaptureGranted,
                        isMandatory: false
                    ) {
                        permissions.requestScreenCapture(openSettingsAlways: true, from: "settings")
                    }

                    Divider().background(Config.Colors.line.opacity(0.5))

                    permissionRow(
                        title: "마이크 (음성 녹음)",
                        desc: "서술형 설문 답변을 말로 녹음하기 위한 오디오 권한입니다.",
                        granted: permissions.isMicrophoneGranted,
                        isMandatory: false
                    ) {
                        permissions.requestMicrophone(from: "settings")
                        permissions.openSystemSettings(pane: "Privacy_Microphone", from: "settings")
                    }

                    Divider().background(Config.Colors.line.opacity(0.5))

                    permissionRow(
                        title: "음성 인식 (텍스트 변환)",
                        desc: "녹음된 음성을 한국어 텍스트(STT)로 자동 변환하기 위한 권한입니다.",
                        granted: permissions.isSpeechRecognitionGranted,
                        isMandatory: false
                    ) {
                        permissions.requestSpeechRecognition(from: "settings")
                        permissions.openSystemSettings(pane: "Privacy_SpeechRecognition", from: "settings")
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
                                Text("브라우저 연동 (AI 사이트 확인)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Config.Colors.ink)
                                Text("필수")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(Color(hex: Config.Colors.accentHex))
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1)
                                    .background(Color(hex: Config.Colors.accentHex).opacity(0.1))
                                    .cornerRadius(3)
                            }

                            Text("브라우저에서 AI 도구를 쓰는지 확인해요.")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        if permissions.isAllBrowserAutomationGranted {
                            Button {
                                permissions.requestAllBrowserAutomation(from: "settings")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(Color(hex: "#2E7D32"))
                                    Text("모든 브라우저 연동 완료")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Config.Colors.ink)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Config.Colors.paper)
                                .cornerRadius(5)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Config.Colors.line, lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                permissions.requestAllBrowserAutomation(from: "settings")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "link.badge.plus")
                                        .font(.system(size: 10))
                                    Text("권한 허용하기")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .foregroundColor(.white)
                                .background(Color(hex: Config.Colors.accentHex))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(spacing: 6) {
                        ForEach(permissions.installedBrowsers) { browser in
                            let granted = permissions.browserAutomationStatuses[browser.bundleId] ?? false
                            HStack {
                                Circle()
                                    .fill(granted ? Color(hex: "#34C759") : Color.orange)
                                    .frame(width: 7, height: 7)

                                Text(browser.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Config.Colors.ink)

                                Spacer()

                                Text(granted ? "허용됨" : "권한 필요")
                                    .font(.system(size: 11, weight: granted ? .regular : .semibold))
                                    .foregroundColor(granted ? Color(hex: "#2E7D32") : Color(hex: Config.Colors.accentHex))

                                Button(granted ? "다시 확인" : "개별 연동") {
                                    permissions.requestBrowserAutomation(bundleId: browser.bundleId, from: "settings")
                                }
                                .font(.system(size: 11))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 3)
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
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(granted ? Color(hex: "#34C759") : (isMandatory ? Color(hex: Config.Colors.accentHex) : Color.orange))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Config.Colors.ink)

                    if isMandatory {
                        Text("필수")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(Color(hex: Config.Colors.accentHex).opacity(0.1))
                            .cornerRadius(3)
                    } else {
                        Text("선택")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(Config.Colors.mute)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(Config.Colors.line.opacity(0.7))
                            .cornerRadius(3)
                    }
                }

                Text(desc)
                    .font(.system(size: 10.5))
                    .foregroundColor(Config.Colors.mute)
            }

            Spacer()

            Text(granted ? "허용됨" : "미허용")
                .font(.system(size: 11, weight: granted ? .regular : .semibold))
                .foregroundColor(granted ? Color(hex: "#2E7D32") : (isMandatory ? Color(hex: Config.Colors.accentHex) : Color.orange))

            Button(granted ? "설정 확인" : "권한 허용") {
                action()
            }
            .font(.system(size: 11))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 탭 3: 맞춤형 AI 도구 추가 등록 (사내 AI 웹사이트, 특수 웹 AI, 데스크톱 앱)
    private var aiTargetsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. AI 웹사이트 등록 카드
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("AI 웹사이트")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Config.Colors.ink)
                                Text("(\(customAIManager.customDomains.count)개 등록됨)")
                                    .font(.system(size: 11))
                                    .foregroundColor(Config.Colors.mute)
                            }
                            Text("자주 쓰는 AI 웹사이트가 기본 목록에 없다면 추가해 주세요.")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                        }

                        Spacer(minLength: 12)

                        HStack(spacing: 8) {
                            if let notice = activeTabNotice {
                                Text(notice)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(notice.contains("✓") ? Color(hex: Config.Colors.accentHex) : Config.Colors.mute)
                                    .transition(.opacity)
                            }

                            Button {
                                fetchActiveBrowserTab()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "globe.americas.fill")
                                        .font(.system(size: 10))
                                    Text("열린 탭 가져오기")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(Config.Colors.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Config.Colors.cardBackground)
                                .cornerRadius(5)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Config.Colors.line, lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
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
                                HStack(spacing: 8) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 11))
                                        .foregroundColor(Config.Colors.mute)
                                        .frame(width: 14)

                                    Text(item.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Config.Colors.ink)

                                    if item.displayName != item.value {
                                        Text("(\(item.value))")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(Config.Colors.mute)
                                    }

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
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("AI 데스크톱 앱")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Config.Colors.ink)
                                Text("(\(customAIManager.customApps.count)개 등록됨)")
                                    .font(.system(size: 11))
                                    .foregroundColor(Config.Colors.mute)
                            }
                            Text("자주 쓰는 AI 앱이 기본 목록에 없다면 추가해 주세요.")
                                .font(.system(size: 11))
                                .foregroundColor(Config.Colors.mute)
                        }

                        Spacer(minLength: 12)

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
                                    .font(.system(size: 10))
                                Text("실행 중인 앱 선택…")
                                    .font(.system(size: 11, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Config.Colors.mute)
                            }
                            .foregroundColor(Config.Colors.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Config.Colors.cardBackground)
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Config.Colors.line, lineWidth: 0.8))
                        }
                        .menuStyle(.borderlessButton)
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
                                HStack(spacing: 8) {
                                    Image(systemName: "macwindow")
                                        .font(.system(size: 11))
                                        .foregroundColor(Config.Colors.mute)
                                        .frame(width: 14)

                                    Text(item.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Config.Colors.ink)

                                    if item.displayName != item.value {
                                        Text("(\(item.value))")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(Config.Colors.mute)
                                    }

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
                    self.activeTabNotice = "✓ \(browser.name) 탭 가져옴"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if self.activeTabNotice?.contains("✓") == true {
                            self.activeTabNotice = nil
                        }
                    }
                    return
                }
            }
        }
        self.activeTabNotice = "열린 탭을 찾지 못함"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.activeTabNotice = nil
        }
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
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: Config.Colors.accentHex))
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
                                    Text("(고정)")
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
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: Config.Colors.accentHex))
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
                                    Text("(고정)")
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

    private func saveParticipantName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != appState.participantName else { return }
        appState.updateParticipantName(trimmed)
        withAnimation(.easeInOut(duration: 0.15)) {
            isNameSavedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isNameSavedToast = false
            }
        }
    }

    private func copyParticipantId() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.participantId, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            isIdCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isIdCopiedToast = false
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy년 M월 d일"
        return f.string(from: date)
    }
}
