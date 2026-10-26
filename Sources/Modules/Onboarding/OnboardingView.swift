import SwiftUI
import AppKit

/// 첫 실행 시 표시되는 직관적 온보딩 뷰
/// 1단계: 참여자 실명 입력
/// 2단계: 3대 권한 실시간 감지 및 원클릭 단계별 안내 (손쉬운 사용, 화면 기록, 마이크)
public struct OnboardingView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var permissions: PermissionsManager = .shared

    public enum PermissionGuideType: String {
        case accessibility
        case screenCapture
        case microphone
        case browser
    }

    @State private var step: Int = 1
    @State private var inputName: String = ""
    @State private var showErrorText: Bool = false
    @State private var activeGuide: PermissionGuideType? = nil

    @FocusState private var isFieldFocused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 헤더 영역
            headerView
                .padding(.top, 24)
                .padding(.horizontal, 28)

            Divider()
                .padding(.vertical, 16)
                .padding(.horizontal, 20)

            // 본문 (단계별 전환)
            if step == 1 {
                nameInputStepView
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            } else {
                permissionsStepView
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }

            Spacer(minLength: 8)

            // 하단 버튼 바
            bottomButtonBar
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
        .frame(width: 550, height: 640)
        .background(Config.Colors.paper)
        .onAppear {
            permissions.startPolling()
            if !appState.participantName.isEmpty {
                inputName = appState.participantName
                step = 2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFieldFocused = true
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
        .onChange(of: permissions.isMicrophoneGranted) { _, granted in
            if granted && activeGuide == .microphone {
                withAnimation(.spring()) { activeGuide = nil }
            }
        }
    }

    // MARK: - 헤더
    private var headerView: some View {
        HStack(spacing: 14) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 42, height: 42)
                    .cornerRadius(9)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else {
                ZStack {
                    Circle()
                        .stroke(Config.Colors.line, lineWidth: 1.5)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Config.Colors.cardBackground))

                    Image(systemName: "waveform.path")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: Config.Colors.accentHex))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("AI 피로 기록 연구 참여 안내")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                Text("2주간의 AI 도구 사용 및 피로 경험표집 연구")
                    .font(.system(size: 12))
                    .foregroundColor(Config.Colors.mute)
            }

            Spacer()

            // 단계 인디케이터
            HStack(spacing: 6) {
                Circle()
                    .fill(step == 1 ? Color(hex: Config.Colors.accentHex) : Config.Colors.line)
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(step == 2 ? Color(hex: Config.Colors.accentHex) : Config.Colors.line)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - 1단계: 이름 입력
    private var nameInputStepView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("참여자 등록")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Config.Colors.ink)

                Text("연구팀이 참여자를 구분하는 데 쓰니 본명을 정확하게 입력해주세요.")
                    .font(.system(size: 13))
                    .foregroundColor(Config.Colors.mute)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("이름")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                TextField("예: 홍길동", text: $inputName)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Config.Colors.ink)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Config.Colors.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(showErrorText ? Color.red : Config.Colors.line, lineWidth: 1)
                            )
                    )
                    .onChange(of: inputName) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showErrorText = false
                        }
                    }

                if showErrorText {
                    Text("이름을 입력해야 다음으로 넘어갈 수 있습니다.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.red)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - 2단계: 직관적 권한 설정
    private var permissionsStepView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 상단 제목 및 원클릭 순서대로 가이드 헤더
            HStack(alignment: .center) {
                let essentialCount = (permissions.isAccessibilityGranted ? 1 : 0) + 
                                     (permissions.isScreenCaptureGranted ? 1 : 0) + 
                                     (permissions.isBrowserAutomationGranted ? 1 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("필수 권한 설정")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Config.Colors.ink)

                        // 진행률 배지
                        Text("\(essentialCount) / 3 필수 완료")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(permissions.isEssentialGranted ? .green : Color(hex: Config.Colors.accentHex))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                (permissions.isEssentialGranted ? Color.green : Color(hex: Config.Colors.accentHex)).opacity(0.12)
                            )
                            .cornerRadius(10)
                    }

                    Text("스위치를 켜면 이 화면에서 실시간으로 자동 감지됩니다.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Config.Colors.mute)
                }

                Spacer()

                // 원클릭 마법사 버튼
                if !permissions.isAllGranted {
                    Button(action: {
                        if !permissions.isAccessibilityGranted {
                            permissions.requestAccessibility()
                            withAnimation(.spring()) { activeGuide = .accessibility }
                        } else if !permissions.isScreenCaptureGranted {
                            permissions.requestScreenCapture()
                            withAnimation(.spring()) { activeGuide = .screenCapture }
                        } else if !permissions.isBrowserAutomationGranted {
                            permissions.requestAllBrowserAutomation()
                            withAnimation(.spring()) { activeGuide = .browser }
                        } else if !permissions.isMicrophoneGranted {
                            permissions.requestMicrophone()
                            withAnimation(.spring()) { activeGuide = .microphone }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11))
                            Text("순서대로 설정")
                                .font(.system(size: 11.5, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: Config.Colors.accentHex))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 게이지 진행 바
            let essentialCount = (permissions.isAccessibilityGranted ? 1 : 0) + 
                                 (permissions.isScreenCaptureGranted ? 1 : 0) + 
                                 (permissions.isBrowserAutomationGranted ? 1 : 0)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Config.Colors.line)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(permissions.isEssentialGranted ? Color.green : Color(hex: Config.Colors.accentHex))
                        .frame(width: max(6, geo.size.width * CGFloat(essentialCount) / 3.0), height: 5)
                        .animation(.spring(), value: essentialCount)
                }
            }
            .frame(height: 5)
            .padding(.bottom, 2)

            // 권한 카드 목록
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 9) {
                    // 1. 손쉬운 사용 (핵심 필수)
                    permissionCard(
                        type: .accessibility,
                        tag: "필수",
                        tagColor: Color(hex: Config.Colors.accentHex),
                        icon: "macwindow.on.rectangle",
                        title: "손쉬운 사용 (창 제목 및 활동 감지)",
                        desc: "현재 작업 중인 AI 도구 창과 체류 시간을 감지합니다.",
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

                    // 2. 화면 기록 (필수)
                    permissionCard(
                        type: .screenCapture,
                        tag: "필수",
                        tagColor: Color(hex: Config.Colors.accentHex),
                        icon: "camera.viewfinder",
                        title: "화면 기록 (피로 순간 ⌥⌘S 화면 캡처)",
                        desc: "피로한 순간 직접 기록(⌥⌘S) 시 문제 화면을 캡처하고 분석하는 필수 권한입니다.",
                        isGranted: permissions.isScreenCaptureGranted,
                        guideSteps: [
                            "1. 방금 열린 [시스템 설정]의 '화면 및 시스템 오디오 녹음'을 확인하세요.",
                            "2. 목록에서 'AIFatigueTracker' 옆의 스위치를 켜주세요.",
                            "3. '종료 및 다시 열기' 창이 뜨면 클릭하거나 [나중에]를 눌러도 자동 감지됩니다."
                        ],
                        systemPane: "Privacy_ScreenCapture"
                    ) {
                        permissions.requestScreenCapture()
                        withAnimation(.spring()) {
                            activeGuide = .screenCapture
                        }
                    }

                    // 3. 웹 브라우저 자동화 (AppleEvents - 필수)
                    browserAutomationPermissionCard

                    // 4. 마이크 & 음성 인식 (선택)
                    permissionCard(
                        type: .microphone,
                        tag: "선택",
                        tagColor: .purple,
                        icon: "mic.fill",
                        title: "마이크 및 음성 인식 (음성 메모)",
                        desc: "피로 설문의 주관식 문항을 타자 대신 말로 빠르게 입력할 수 있습니다.",
                        isGranted: permissions.isMicrophoneGranted && permissions.isSpeechRecognitionGranted,
                        guideSteps: [
                            "1. 화면에 뜨는 '마이크에 접근하려고 합니다' 창에서 [허용]을 눌러주세요.",
                            "💡 키보드 타자로만 입력하실 경우 건너뛰셔도 연구 참여에 문제없습니다."
                        ],
                        systemPane: "Privacy_Microphone"
                    ) {
                        permissions.requestMicrophone()
                        permissions.requestSpeechRecognition()
                        withAnimation(.spring()) {
                            activeGuide = .microphone
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            // 하단 안내 텍스트
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(Config.Colors.mute)
                Text("상단 메뉴 막대 아이콘의 [설정…]에서 언제든 권한을 다시 설정하실 수 있습니다.")
                    .font(.system(size: 11))
                    .foregroundColor(Config.Colors.mute.opacity(0.9))
            }
            .padding(.top, 2)
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
                    .font(.system(size: 18))
                    .foregroundColor(isGranted ? .green : tagColor)
                    .frame(width: 24, height: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(Config.Colors.ink)

                        Text(tag)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(tagColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(tagColor.opacity(0.12))
                            .cornerRadius(4)
                    }

                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(Config.Colors.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                        Text("허용 완료")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tag == "필수" ? Color(hex: Config.Colors.accentHex) : Config.Colors.ink)
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
                        Text("설정 방법 안내 (스위치를 켜면 즉시 자동 감지됩니다)")
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
                            permissions.openSystemSettings(pane: systemPane)
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
                .fill(isGranted ? Color.green.opacity(0.07) : Config.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isGranted ? Color.green.opacity(0.25) : (isExpanded ? Color.orange.opacity(0.4) : Config.Colors.line), lineWidth: isExpanded ? 1.2 : 0.8)
                )
        )
    }

    // MARK: - 3. 웹 브라우저 자동화 (AppleEvents - 필수)
    private var browserAutomationPermissionCard: some View {
        let isExpanded = (activeGuide == .browser && !permissions.isBrowserAutomationGranted)
        let isGranted = permissions.isBrowserAutomationGranted
        let tagColor = Color(hex: Config.Colors.accentHex)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundColor(isGranted ? .green : tagColor)
                    .frame(width: 24, height: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("웹 브라우저 자동화 (방문 탭 URL 감지)")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(Config.Colors.ink)

                        Text("필수")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(tagColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(tagColor.opacity(0.12))
                            .cornerRadius(4)
                    }

                    Text("설치된 브라우저(\(permissions.installedBrowsers.map(\.name).joined(separator: ", ")))에서 ChatGPT, Claude.ai 사용을 감지하기 위한 필수 권한입니다. 권한이 없으면 일반 웹서핑과 AI 사용을 구분하지 못합니다.")
                        .font(.system(size: 11))
                        .foregroundColor(Config.Colors.mute)
                        .fixedSize(horizontal: false, vertical: true)

                    // 설치된 브라우저별 허용 상태 배지 표시
                    if !permissions.installedBrowsers.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(permissions.installedBrowsers) { browser in
                                let bGranted = permissions.browserAutomationStatuses[browser.bundleId] ?? false
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(bGranted ? Color.green : Color.orange)
                                        .frame(width: 5.5, height: 5.5)
                                    Text(browser.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(Config.Colors.ink)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
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
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                        Text("연동 완료")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
                    .padding(.top, 2)
                } else {
                    Button(action: {
                        permissions.requestAllBrowserAutomation()
                        withAnimation(.spring()) {
                            activeGuide = .browser
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "설정 중…" : "모든 브라우저 한꺼번에 연동")
                            if isExpanded {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tagColor)
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
                        Text("웹 브라우저 연동 방법 안내")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }

                    Text("1. [모든 브라우저 한꺼번에 연동]을 누르면 macOS 자동화 권한 허용 및 시스템 설정 창이 열립니다.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Config.Colors.ink.opacity(0.85))
                    Text("2. 'AIFatigueTracker가 Chrome/Safari/Brave을(를) 제어하려고 합니다' 팝업에서 [확인]을 눌러주세요.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Config.Colors.ink.opacity(0.85))
                    Text("3. 시스템 설정 > 자동화 목록에서 AI 피로 기록 앱 하위의 브라우저를 모두 켜주시면 됩니다.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Config.Colors.ink.opacity(0.85))

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
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isGranted ? Color.green.opacity(0.07) : Config.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isGranted ? Color.green.opacity(0.25) : (isExpanded ? Color.orange.opacity(0.4) : Config.Colors.line), lineWidth: isExpanded ? 1.2 : 0.8)
                )
        )
    }

    // MARK: - 하단 버튼 바
    private var bottomButtonBar: some View {
        HStack {
            if step == 2 {
                Button("이전") {
                    withAnimation {
                        step = 1
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(Config.Colors.mute)
                .font(.system(size: 13))
            }

            Spacer()

            if step == 1 {
                Button("다음 단계") {
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
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: Config.Colors.accentHex))
                .font(.system(size: 13, weight: .semibold))
                .disabled(inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                HStack(spacing: 12) {
                    // 친절한 상태 안내 문구 (3대 필수 권한: 손쉬운 사용 + 화면 기록 + 브라우저 자동화)
                    if permissions.isEssentialGranted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("필수 권한 준비 완료")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.green)
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
                            } else if !permissions.isScreenCaptureGranted {
                                Text("화면 기록 권한을 켜주세요")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            } else {
                                Text("웹 브라우저 자동화 권한을 연동해주세요")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    Button("시작하기") {
                        if !permissions.isAccessibilityGranted {
                            permissions.requestAccessibility()
                            withAnimation(.spring()) {
                                activeGuide = .accessibility
                            }
                        } else if !permissions.isScreenCaptureGranted {
                            permissions.requestScreenCapture()
                            withAnimation(.spring()) {
                                activeGuide = .screenCapture
                            }
                        } else if !permissions.isBrowserAutomationGranted {
                            permissions.requestAllBrowserAutomation()
                            withAnimation(.spring()) {
                                activeGuide = .browser
                            }
                        } else {
                            appState.completeOnboarding(name: inputName)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(permissions.isEssentialGranted ? Color(hex: Config.Colors.accentHex) : Color.gray)
                    .font(.system(size: 13, weight: .bold))
                }
            }
        }
    }
}
