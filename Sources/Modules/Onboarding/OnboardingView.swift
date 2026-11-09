import SwiftUI
import AppKit

/// 첫 실행 시 표시되는 직관적 온보딩 뷰
/// 1단계: 참여자 실명 입력
/// 2단계: 3대 권한 실시간 감지 및 원클릭 단계별 안내 (손쉬운 사용, 화면 기록, 브라우저 자동화, 마이크)
/// 3단계: 연구 시작 및 메뉴 막대/단축키 안내
public struct OnboardingView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var permissions: PermissionsManager = .shared

    public enum PermissionGuideType: String {
        case accessibility
        case screenCapture
        case browser
        case microphone
        case speechRecognition
    }

    @State private var step: Int = 0
    @State private var inputName: String = ""
    @State private var showErrorText: Bool = false
    @State private var activeGuide: PermissionGuideType? = nil

    @FocusState private var isFieldFocused: Bool
    private let forcedStep: Int?

    public init(initialStep: Int? = nil) {
        self.forcedStep = initialStep
        if let s = initialStep {
            _step = State(initialValue: s)
        } else {
            _step = State(initialValue: 0)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if step == 0 {
                welcomeStepView
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
            } else {
                // 헤더 영역 (참여자 등록, 필수 권한 설정, 설정 완료)
                headerView
                    .padding(.top, 18)
                    .padding(.horizontal, 26)

                Divider()
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 22)

                // 본문 (단계별 전환)
                if step == 1 {
                    nameInputStepView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if step == 2 {
                    permissionsStepView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else {
                    completionStepView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }

            Spacer(minLength: 6)

            // 하단 버튼 바
            bottomButtonBar
                .padding(.horizontal, 26)
                .padding(.bottom, 18)
        }
        .tint(Color(hex: Config.Colors.accentHex))
        .accentColor(Color(hex: Config.Colors.accentHex))
        .frame(width: 540, height: 600)
        .background(Config.Colors.paper)
        .onAppear {
            permissions.startPolling()
            if let forced = forcedStep {
                step = forced
                if forced >= 1 && inputName.isEmpty {
                    inputName = "박창휘"
                }
                return
            }
            let savedStep = UserDefaults.standard.integer(forKey: "onboarding_current_step")
            if savedStep >= 1 {
                step = savedStep
            } else if !appState.participantName.isEmpty {
                inputName = appState.participantName
                step = 2
            }
            if !appState.participantName.isEmpty && inputName.isEmpty {
                inputName = appState.participantName
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if step == 1 {
                    isFieldFocused = true
                }
            }
        }
        .onChange(of: step) { _, newStep in
            UserDefaults.standard.set(newStep, forKey: "onboarding_current_step")
            UserDefaults.standard.synchronize()
            if newStep == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFieldFocused = true
                }
            }
        }
        .onDisappear {
            permissions.stopPolling()
        }
        .onChange(of: permissions.isAccessibilityGranted) { _, granted in
            if granted && activeGuide == .accessibility {
                withAnimation(.spring()) { activeGuide = nil }
            }
        }
        .onChange(of: permissions.isScreenCaptureGranted) { _, granted in
            if granted && activeGuide == .screenCapture {
                withAnimation(.spring()) { activeGuide = nil }
            }
        }
        .onChange(of: permissions.isBrowserAutomationGranted) { _, granted in
            if granted && activeGuide == .browser {
                withAnimation(.spring()) { activeGuide = nil }
            }
        }
        .onChange(of: permissions.isMicrophoneGranted) { _, granted in
            if granted && activeGuide == .microphone {
                withAnimation(.spring()) { activeGuide = nil }
            }
        }
        .onChange(of: permissions.isSpeechRecognitionGranted) { _, granted in
            if granted && activeGuide == .speechRecognition {
                withAnimation(.spring()) { activeGuide = nil }
            }
        }
    }

    private var displayName: String {
        let trimmed = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !appState.participantName.isEmpty { return appState.participantName }
        return "참여자"
    }

    // MARK: - 헤더 (참여자 등록, 필수 권한 설정, 설정 완료)
    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                if step == 1 {
                    Text("참여자 등록")
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    Text("연구팀이 참여자를 구분하는 데 쓰니 본명을 정확하게 입력해주세요.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Config.Colors.mute)
                } else if step == 2 {
                    Text("필수 권한 설정")
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    Text("처음 한 번만 설정하면 돼요")
                        .font(.system(size: 11.5))
                        .foregroundColor(Config.Colors.mute)
                } else if step == 3 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16.5, weight: .bold))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))

                        Text("설정이 끝났어요")
                            .font(.system(size: 16.5, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }

                    Text("\(displayName)님, 2주 동안 잘 부탁드려요")
                        .font(.system(size: 11.5))
                        .foregroundColor(Config.Colors.mute)
                }
            }

            Spacer()

            // 단계 인디케이터 (3단계 점 유지)
            HStack(spacing: 6) {
                Circle()
                    .fill(step == 1 ? Color(hex: Config.Colors.accentHex) : Config.Colors.line)
                    .frame(width: 7.5, height: 7.5)
                Circle()
                    .fill(step == 2 ? Color(hex: Config.Colors.accentHex) : Config.Colors.line)
                    .frame(width: 7.5, height: 7.5)
                Circle()
                    .fill(step == 3 ? Color(hex: Config.Colors.accentHex) : Config.Colors.line)
                    .frame(width: 7.5, height: 7.5)
            }
        }
    }

    // MARK: - 0단계: 환영 화면
    private var welcomeStepView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                // 앱 대표 로고 (크게, 화면 가운데 정렬)
                bigAppLogoView

                VStack(spacing: 8) {
                    Text("AI 피로 연구 참여 안내")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    Text("2주 동안 AI를 쓰며 느낀 피로를 기록해요")
                        .font(.system(size: 13.5))
                        .foregroundColor(Config.Colors.mute)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var bigAppLogoView: some View {
        if let icon = appLogoImage {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .cornerRadius(22)
                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(hex: Config.Colors.accentHex))
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
                Image(systemName: "battery.100.bolt")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
            }
        }
    }

    @ViewBuilder
    private var appLogoView: some View {
        if let icon = appLogoImage {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 38)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1.5)
        }
    }

    private var appLogoImage: NSImage? {
        if let icon = Bundle.main.image(forResource: "AppIcon") {
            return icon
        }
        if let appIcon = NSApp.applicationIconImage, appIcon.isValid {
            return appIcon
        }
        if let named = NSImage(named: "AppIcon") {
            return named
        }
        let fallbackPath = "/Users/changhwipark/Desktop/UX_Research/DxD_Lab/[Project]AI_Fatigue/LogSystem_Test2_Mac/Sources/Resources/AppIcon.icns"
        if FileManager.default.fileExists(atPath: fallbackPath) {
            return NSImage(contentsOfFile: fallbackPath)
        }
        return nil
    }

    // MARK: - 1단계: 이름 입력
    private var nameInputStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 이름 입력 카드
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("이름")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    Text("필수")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Color(hex: Config.Colors.accentHex).opacity(0.1))
                        .cornerRadius(3)
                }

                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Config.Colors.mute)

                    TextField("예: 홍길동", text: $inputName)
                        .textFieldStyle(.plain)
                        .focused($isFieldFocused)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Config.Colors.ink)

                    if !inputName.isEmpty {
                        Button(action: { inputName = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Config.Colors.mute)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Config.Colors.cardBackground)
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(showErrorText ? Color.red : Config.Colors.line, lineWidth: showErrorText ? 1.2 : 0.8)
                )

                if showErrorText {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                        Text("이름을 입력해야 다음으로 넘어갈 수 있습니다.")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Config.Colors.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Config.Colors.line, lineWidth: 0.8))
            )

            Spacer()
        }
        .padding(.horizontal, 26)
    }

    // MARK: - 2단계: 직관적 권한 설정
    private var permissionsStepView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 권한 카드 목록
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    // 1. 손쉬운 사용 (핵심 필수)
                    permissionCard(
                        type: .accessibility,
                        tag: "필수",
                        tagColor: Color(hex: Config.Colors.accentHex),
                        icon: "macwindow.on.rectangle",
                        title: "손쉬운 사용 (AI 사용 시간 확인)",
                        desc: "어떤 AI 도구를 얼마나 썼는지 확인해요.",
                        isGranted: permissions.isAccessibilityGranted,
                        guideSteps: [
                            "1. 방금 열린 [시스템 설정] 창을 확인하세요.",
                            "2. 목록에서 'AIFatigueTracker' 옆의 스위치를 켜주세요.",
                            "3. 스위치를 켜는 즉시 이 화면에서 자동으로 '허용 완료'로 바뀝니다."
                        ],
                        systemPane: "Privacy_Accessibility"
                    ) {
                        permissions.requestAccessibility()
                        withAnimation(.spring()) {
                            activeGuide = .accessibility
                        }
                    }

                    // 2. 웹 브라우저 자동화 (AppleEvents - 필수)
                    browserAutomationPermissionCard

                    // 3. 화면 기록 (선택)
                    permissionCard(
                        type: .screenCapture,
                        tag: "선택",
                        tagColor: Config.Colors.mute,
                        icon: "camera.viewfinder",
                        title: "화면 기록 (선택 화면 캡처)",
                        desc: "피로 기록 시 원하는 창이나 화면 영역을 직접 캡처하여 첨부할 수 있어요.",
                        isGranted: permissions.isScreenCaptureGranted,
                        guideSteps: [
                            "1. 방금 열린 [시스템 설정]의 '화면 및 시스템 오디오 녹음'을 확인하세요.",
                            "2. 목록에서 'AIFatigueTracker' 옆의 스위치를 켜주세요.",
                            "3. 💡 '종료 및 다시 열기' 창이 뜨면 클릭하셔도 이 권한 설정 화면으로 즉시 안전하게 복원됩니다."
                        ],
                        systemPane: "Privacy_ScreenCapture"
                    ) {
                        permissions.requestScreenCapture(from: "onboarding")
                        withAnimation(.spring()) {
                            activeGuide = .screenCapture
                        }
                    }

                    // 4. 마이크 (선택)
                    permissionCard(
                        type: .microphone,
                        tag: "선택",
                        tagColor: Config.Colors.mute,
                        icon: "mic.fill",
                        title: "마이크 (음성 녹음)",
                        desc: "서술형 설문 답변을 말로 녹음해요.",
                        isGranted: permissions.isMicrophoneGranted,
                        guideSteps: [
                            "1. 화면에 뜨는 '마이크에 접근하려고 합니다' 창에서 [허용]을 눌러주세요.",
                            "2. 시스템 설정의 '마이크' 목록에서 AIFatigueTracker 스위치를 켜주세요.",
                            "💡 '종료 및 다시 열기' 창이 뜨더라도 이 설정 화면으로 자동 복귀됩니다."
                        ],
                        systemPane: "Privacy_Microphone"
                    ) {
                        permissions.requestMicrophone(from: "onboarding")
                        withAnimation(.spring()) {
                            activeGuide = .microphone
                        }
                    }

                    // 5. 음성 인식 (선택)
                    permissionCard(
                        type: .speechRecognition,
                        tag: "선택",
                        tagColor: Config.Colors.mute,
                        icon: "waveform.and.magnifyingglass",
                        title: "음성 인식 (텍스트 변환)",
                        desc: "녹음된 음성을 한국어 텍스트(STT)로 자동 변환해요.",
                        isGranted: permissions.isSpeechRecognitionGranted,
                        guideSteps: [
                            "1. 화면에 뜨는 '음성 인식에 접근하려고 합니다' 창에서 [허용]을 눌러주세요.",
                            "2. 시스템 설정의 '음성 인식' 목록에서 AIFatigueTracker 스위치를 켜주세요.",
                            "💡 '종료 및 다시 열기' 창이 뜨더라도 이 설정 화면으로 자동 복귀됩니다."
                        ],
                        systemPane: "Privacy_SpeechRecognition"
                    ) {
                        permissions.requestSpeechRecognition(from: "onboarding")
                        withAnimation(.spring()) {
                            activeGuide = .speechRecognition
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.top, 2)

            Spacer(minLength: 8)

            // 하단 안내 텍스트 (카드가 끝난 후 하단 버튼 바 바로 위 중앙 배치)
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(Config.Colors.mute)
                Text("상단 메뉴 막대 아이콘의 [설정]에서 언제든 권한을 다시 설정하실 수 있습니다.")
                    .font(.system(size: 11))
                    .foregroundColor(Config.Colors.mute.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - 권한 카드 컴포넌트
    private func permissionCard(
        type: PermissionGuideType,
        tag: String,
        tagColor: Color,
        icon: String,
        title: String,
        desc: String,
        isGranted: Bool,
        guideSteps: [String],
        systemPane: String,
        onAction: @escaping () -> Void
    ) -> some View {
        let isExpanded = (activeGuide == type && !isGranted)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isGranted ? Config.Colors.ink.opacity(0.85) : tagColor)
                    .frame(width: 24, height: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(Config.Colors.ink)

                        if tag == "선택" {
                            Text("선택")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(Config.Colors.mute)
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1)
                                .background(Config.Colors.line.opacity(0.7))
                                .cornerRadius(3)
                        } else {
                            Text(tag)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(tagColor)
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1)
                                .background(tagColor.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }

                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(Config.Colors.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(Color(hex: "#2E7D32"))
                        Text("허용됨")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#2E7D32"))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color(hex: "#2E7D32").opacity(0.08))
                    .cornerRadius(5)
                    .padding(.top, 2)
                } else {
                    Button(action: onAction) {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "설정 중…" : "권한 허용하기")
                            if isExpanded {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5.5)
                        .background(tag == "필수" ? Color(hex: Config.Colors.accentHex) : Color(hex: "#5C564D"))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            // 인라인 안내 가이드 (클릭 시 확장)
            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("설정 방법 안내 (처음 한 번만 설정하면 돼요)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }

                    ForEach(guideSteps, id: \.self) { step in
                        Text(step)
                            .font(.system(size: 10.5))
                            .foregroundColor(Config.Colors.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Spacer()
                        Button("설정 창 다시 열기") {
                            permissions.openSystemSettings(pane: systemPane, from: "onboarding")
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .buttonStyle(.bordered)
                        .padding(.top, 2)
                    }
                }
                .padding(9)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.25), lineWidth: 0.8))
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Config.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isExpanded ? Color.orange.opacity(0.4) : Config.Colors.line, lineWidth: isExpanded ? 1.2 : 0.8)
                )
        )
    }

    // MARK: - 3. 웹 브라우저 자동화 (AppleEvents - 필수)
    private var browserAutomationPermissionCard: some View {
        let isExpanded = (activeGuide == .browser && !permissions.isBrowserAutomationGranted)
        let isGranted = permissions.isBrowserAutomationGranted
        let tagColor = Color(hex: Config.Colors.accentHex)

        return VStack(alignment: .leading, spacing: 8) {
            browserCardHeader(isGranted: isGranted, isExpanded: isExpanded, tagColor: tagColor)

            if isExpanded {
                browserCardExpandedGuide
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Config.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isExpanded ? Color.orange.opacity(0.4) : Config.Colors.line, lineWidth: isExpanded ? 1.2 : 0.8)
                )
        )
    }

    private func browserCardHeader(isGranted: Bool, isExpanded: Bool, tagColor: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 16))
                .foregroundColor(isGranted ? Config.Colors.ink.opacity(0.85) : tagColor)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("브라우저 연동 (AI 사이트 확인)")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    Text("필수")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(tagColor)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(tagColor.opacity(0.1))
                        .cornerRadius(3)
                }

                Text("브라우저에서 AI 도구를 쓰는지 확인해요.")
                    .font(.system(size: 11))
                    .foregroundColor(Config.Colors.mute)
                    .fixedSize(horizontal: false, vertical: true)

                // 설치된 브라우저 목록 및 실시간 허용 상태 뱃지 (실제 설치된 브라우저만 동적 표시)
                if !permissions.installedBrowsers.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(permissions.installedBrowsers) { browser in
                            let bGranted = permissions.browserAutomationStatuses[browser.bundleId] == true
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(bGranted ? Color(hex: "#2E7D32") : Color.orange)
                                    .frame(width: 5.5, height: 5.5)
                                Text(browser.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Config.Colors.ink)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Config.Colors.panelBackground)
                            .cornerRadius(4)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Color(hex: "#2E7D32"))
                    Text("허용 완료")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#2E7D32"))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color(hex: "#2E7D32").opacity(0.08))
                .cornerRadius(5)
                .padding(.top, 2)
            } else {
                Button(action: {
                    permissions.requestAllBrowserAutomation()
                    withAnimation(.spring()) {
                        activeGuide = .browser
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "설정 중…" : "권한 허용하기")
                        if isExpanded {
                            Image(systemName: "arrow.right.circle.fill")
                        }
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5.5)
                    .background(Color(hex: Config.Colors.accentHex))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private var browserCardExpandedGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text("웹 브라우저 연동 방법 안내")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Config.Colors.ink)
            }

            Text("1. [권한 허용하기]를 누르면 macOS 자동화 권한 허용 및 시스템 설정 창이 열립니다.")
                .font(.system(size: 10.5))
                .foregroundColor(Config.Colors.ink.opacity(0.85))
            
            let browserNames = permissions.installedBrowsers.map(\.name).joined(separator: ", ")
            Text("2. 'AIFatigueTracker가 \(browserNames)을(를) 제어하려고 합니다' 팝업에서 [확인]을 눌러주세요.")
                .font(.system(size: 10.5))
                .foregroundColor(Config.Colors.ink.opacity(0.85))
            Text("3. 시스템 설정 > 개인정보 보호 및 보안 > 자동화 목록에서 브라우저를 모두 켜주시면 됩니다.")
                .font(.system(size: 10.5))
                .foregroundColor(Config.Colors.ink.opacity(0.85))

            // 설치된 브라우저별 실시간 연동 상태 표시
            VStack(alignment: .leading, spacing: 4) {
                Text("설치된 브라우저별 연동 상태 (모두 켜야 진행 가능):")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Config.Colors.ink)
                    .padding(.bottom, 1)

                ForEach(permissions.installedBrowsers, id: \.bundleId) { b in
                    let isBGranted = permissions.browserAutomationStatuses[b.bundleId] == true
                    HStack(spacing: 6) {
                        Image(systemName: isBGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(isBGranted ? Color(hex: "#2E7D32") : Color.orange)
                            .font(.system(size: 10.5))
                        Text(b.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Config.Colors.ink)
                        Spacer()
                        Text(isBGranted ? "허용 완료" : "스위치 켜기 필요")
                            .font(.system(size: 10, weight: isBGranted ? .regular : .semibold))
                            .foregroundColor(isBGranted ? Color(hex: "#2E7D32") : Color.orange)
                    }
                }
            }
            .padding(6)
            .background(Config.Colors.cardBackground)
            .cornerRadius(5)

            HStack {
                Spacer()
                Button("설정 창 다시 열기") {
                    permissions.openSystemSettings(pane: "Privacy_Automation")
                }
                .font(.system(size: 10.5, weight: .medium))
                .buttonStyle(.bordered)
                .padding(.top, 2)
            }
        }
        .padding(9)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.25), lineWidth: 0.8))
    }

    // MARK: - 3단계: 완료 및 시작 안내
    private var completionStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 핵심 이용 방법 카드 3종
            VStack(spacing: 11) {
                // 1. 메뉴 막대 상시 확인 안내
                HStack(alignment: .top, spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: Config.Colors.accentHex).opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: "menubar.arrow.up.rectangle")
                            .font(.system(size: 19))
                            .foregroundColor(Color(hex: Config.Colors.accentHex))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. 메뉴 막대에서 사용 시간을 볼 수 있어요")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Config.Colors.ink)

                        Text("AI 사용 현황과 설정을 한곳에서 볼수 있어요.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Config.Colors.mute)
                            .lineSpacing(2)
                    }

                    Spacer()
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Config.Colors.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Config.Colors.line, lineWidth: 1))
                )

                // 2. 단축키 ⌥⌘S 안내
                HStack(alignment: .top, spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: "command.square.fill")
                            .font(.system(size: 19))
                            .foregroundColor(.orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("2. 피곤할 땐 ⌥⌘S")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Config.Colors.ink)

                        Text("AI 때문에 피곤해지면 언제든 눌러주세요. 30초면 기록할 수 있어요.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Config.Colors.mute)
                            .lineSpacing(2)
                    }

                    Spacer()
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Config.Colors.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Config.Colors.line, lineWidth: 1))
                )

                // 3. 백그라운드 동작 안내
                HStack(alignment: .top, spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 42, height: 42)
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 19))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("3. AI를 쓸 때 짧은 설문이 떠요")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Config.Colors.ink)

                        Text("AI 도구를 쓰는 동안 한 번씩 짧은 설문이 떠요. 뜰 때마다 답해주시면 돼요.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Config.Colors.mute)
                            .lineSpacing(2)
                    }

                    Spacer()
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Config.Colors.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Config.Colors.line, lineWidth: 1))
                )
            }

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - 하단 버튼 바
    private var bottomButtonBar: some View {
        HStack {
            if step > 0 {
                Button("이전") {
                    withAnimation {
                        step -= 1
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(Config.Colors.mute)
                .font(.system(size: 13))
            }

            Spacer()

            if step == 0 {
                Button(action: {
                    withAnimation {
                        step = 1
                    }
                }) {
                    Text("시작하기")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Color(hex: Config.Colors.accentHex))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
            } else if step == 1 {
                Button(action: {
                    let trimmed = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        showErrorText = true
                    } else {
                        showErrorText = false
                        appState.saveDraftName(trimmed)
                        withAnimation {
                            step = 2
                        }
                    }
                }) {
                    Text("다음 단계")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : Color(hex: Config.Colors.accentHex))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .disabled(inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if step == 2 {
                HStack(spacing: 12) {
                    // 친절한 상태 안내 문구 (2대 필수 권한: 손쉬운 사용 + 브라우저 자동화)
                    if permissions.isEssentialGranted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "#2E7D32"))
                                .font(.system(size: 12))
                            Text("필수 권한 준비 완료")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color(hex: "#2E7D32"))
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            if !permissions.isAccessibilityGranted {
                                Text("손쉬운 사용 권한을 켜주세요")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            } else {
                                Text("모든 브라우저 자동화 권한을 켜주세요")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    Button(action: {
                        if !permissions.isAccessibilityGranted {
                            permissions.requestAccessibility()
                            withAnimation(.spring()) {
                                activeGuide = .accessibility
                            }
                        } else if !permissions.isBrowserAutomationGranted {
                            permissions.requestAllBrowserAutomation()
                            withAnimation(.spring()) {
                                activeGuide = .browser
                            }
                        } else {
                            withAnimation {
                                step = 3
                            }
                        }
                    }) {
                        Text(permissions.isEssentialGranted ? "다음 단계" : "권한 설정 계속")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color(hex: Config.Colors.accentHex))
                            .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // 3단계: 연구 시작 및 메뉴 막대 열기
                Button(action: {
                    UserDefaults.standard.removeObject(forKey: "onboarding_current_step")
                    appState.completeOnboarding(name: inputName)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("시작하기")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color(hex: Config.Colors.accentHex))
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
