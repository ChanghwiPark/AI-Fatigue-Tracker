import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// AI 대화(Chat / Thread / Context Window) 단위 세션 생명주기(open -> close)와
/// 활성(focus - 누적시간 계산) / 비활성(unfocus - 누적시간 일시중지) 및 사이 활동을 시각적으로 관찰하는 디버그 모니터
public struct DebugWindowView: View {
    @ObservedObject var debugStore: DebugLogStore = .shared
    @ObservedObject var sessionManager: SessionManager = .shared
    @ObservedObject var surveyScheduler: SurveyScheduler = .shared
    @ObservedObject var surveyLogStore: SurveyLogStore = .shared
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var config: ConfigManager = .shared
    @ObservedObject var syncManager: SupabaseSyncManager = .shared

    public enum ViewMode: String, CaseIterable, Identifiable {
        case timeline = "대화 세션 타임라인"
        case gantt = "비주얼 간트 차트"
        case rawLog = "전체 이벤트 로그"
        case survey = "설문 & 스케줄러"
        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .timeline: return "bubble.left.and.bubble.right.fill"
            case .gantt: return "chart.bar.xaxis"
            case .rawLog: return "list.bullet.rectangle"
            case .survey: return "slider.horizontal.3"
            }
        }
    }

    @State private var viewMode: ViewMode = {
        if CommandLine.arguments.contains("--survey-tab") { return .survey }
        if CommandLine.arguments.contains("--gantt-tab") { return .gantt }
        if CommandLine.arguments.contains("--log-tab") { return .rawLog }
        return .timeline
    }()
    @State private var selectedSessionId: UUID? = nil
    @State private var logFilterText: String = ""
    @State private var ganttTimeRange: GanttTimeRange = .all
    @State private var selectedEnvironment: ActivityEvent.EnvironmentCategory = .all
    @State private var selectedAIFilter: ActivityEvent.AIFilterOption = .all
    @State private var selectedEventTypes: Set<ActivityEvent.EventType> = Set(ActivityEvent.EventType.allCases)
    @State private var lastRuleCheckMessage: String = ""

    private let filterableEventTypes: [ActivityEvent.EventType] = [
        .open, .close,        // [1] 생애주기
        .focusIn, .focusOut,  // [2] 집중
        .navigate,            // [3] 전환
        .idleStart, .idleEnd, .suspend, .resume // [4] 입력·시스템
    ]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm:ss"
        return f
    }()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 1. 상단 종합 상태 대시보드
            topDashboardHeader
                .padding(14)
                .background(Config.Colors.paper)

            Divider()

            // 2. 뷰 모드 스위처 바
            viewModeSwitcherBar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Config.Colors.panelBackground)

            Divider()

            // 3. 메인 콘텐츠 영역
            Group {
                switch viewMode {
                case .timeline:
                    sessionMasterDetailView
                case .gantt:
                    visualGanttView
                case .rawLog:
                    rawLogTableView
                case .survey:
                    surveySchedulerView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Config.Colors.paper)

            Divider()

            // 4. 하단 상태 바
            bottomStatusBar
                .background(Config.Colors.panelBackground)
        }
        .frame(minWidth: 940, minHeight: 620)
        .background(Config.Colors.paper)
        .onAppear {
            if selectedSessionId == nil {
                selectedSessionId = sessionManager.focusedSession?.sessionId ?? sessionManager.activeSessions.first?.sessionId
            }
        }
    }

    // MARK: - 1. 상단 종합 상태 대시보드
    private var topDashboardHeader: some View {
        VStack(spacing: 12) {
            // 상단 상태 및 툴바
            HStack(alignment: .center, spacing: 14) {
                // 현재 실시간 세션 감지 상태 카드
                HStack(spacing: 12) {
                    // 상태 표시등 (Pulsing Halo)
                    ZStack {
                        Circle()
                            .fill(statusIndicatorColor.opacity(0.18))
                            .frame(width: 24, height: 24)
                        Circle()
                            .fill(statusIndicatorColor)
                            .frame(width: 11, height: 11)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        if let focused = sessionManager.focusedSession {
                            HStack(spacing: 6) {
                                Text("FOCUS")
                                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .cornerRadius(4)

                                Text(focused.toolName)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Config.Colors.ink)

                                Text("· 순수 누적: \(focused.formattedFocusedDuration) 측정 중")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            Text(focused.title)
                                .font(.system(size: 11.5))
                                .foregroundColor(Config.Colors.mute)
                                .lineLimit(1)
                        } else if !sessionManager.activeSessions.isEmpty {
                            HStack(spacing: 6) {
                                Text("UNFOCUS")
                                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .cornerRadius(4)

                                Text("일시중지 (\(sessionManager.activeSessions.count)개 대화 열림)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Config.Colors.ink)

                                Text("· 다른 창/앱 작업 중")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(Config.Colors.mute)
                            }
                            Text("대화 창으로 복귀 시 기존 누적 시간에 이어서 자동으로 측정됩니다.")
                                .font(.system(size: 11.5))
                                .foregroundColor(Config.Colors.mute)
                                .lineLimit(1)
                        } else if !sessionManager.closedSessions.isEmpty {
                            HStack(spacing: 6) {
                                Text("STANDBY")
                                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary)
                                    .cornerRadius(4)

                                Text("보존 대기 중 (\(sessionManager.closedSessions.count)개 대화)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Config.Colors.ink)
                            }
                            Text("창/앱이 닫혀 보존되었습니다. AI 창을 다시 열면 기존 누적 시간에 연결됩니다.")
                                .font(.system(size: 11.5))
                                .foregroundColor(Config.Colors.mute)
                                .lineLimit(1)
                        } else {
                            HStack(spacing: 6) {
                                Text("READY")
                                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray)
                                    .cornerRadius(4)

                                Text("AI 대화 감지 대기 중")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Config.Colors.ink)
                            }
                            Text("Claude, ChatGPT, claude.ai 등을 열면 대화 세션이 자동 생성되어 추적됩니다.")
                                .font(.system(size: 11.5))
                                .foregroundColor(Config.Colors.mute)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // 우측 모니터링 상태 뱃지 및 빠른 액션
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("실시간 자동 감지")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Config.Colors.ink)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.3), lineWidth: 0.8))

                    // 설정 탭 퀵 점프 버튼
                    Button(action: {
                        withAnimation { viewMode = .survey }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11))
                            Text("스케줄러 설정")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(Config.Colors.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(Config.Colors.cardBackground)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button("화면 로그 비우기") {
                            debugStore.clear()
                        }
                        Button("세션 기록 초기화", role: .destructive) {
                            sessionManager.clearAllSessions()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15))
                            .foregroundColor(Config.Colors.mute)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                }
            }

            // 4개 KPI 요약 카드
            HStack(spacing: 10) {
                kpiCard(
                    title: "\(sessionManager.activeSessions.count)개 열림",
                    subtitle: "보존 \(sessionManager.closedSessions.count)개 / 총 \(sessionManager.sessions.count)개",
                    icon: "bubble.left.and.bubble.right.fill",
                    color: Color(hex: Config.Colors.accentHex),
                    badge: sessionManager.activeSessions.isEmpty ? nil : "추적 중"
                )
                kpiCard(
                    title: totalFocusedTimeString,
                    subtitle: "순수 활성 누적 (Focus)",
                    icon: "play.circle.fill",
                    color: .green
                )
                kpiCard(
                    title: totalUnfocusedTimeString,
                    subtitle: "일시중지 / 사이작업",
                    icon: "pause.circle.fill",
                    color: .orange
                )
                kpiCard(
                    title: "\(debugStore.events.count)건",
                    subtitle: "누적 활동 이벤트 로그",
                    icon: "list.bullet.rectangle",
                    color: .blue
                )
            }
        }
    }

    private var statusIndicatorColor: Color {
        if sessionManager.focusedSession != nil {
            return .green
        } else if !sessionManager.activeSessions.isEmpty {
            return .orange
        } else if !sessionManager.closedSessions.isEmpty {
            return .secondary
        } else {
            return .gray
        }
    }

    private func kpiCard(title: String, subtitle: String, icon: String, color: Color, badge: String? = nil) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(Config.Colors.ink)
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(color)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(color.opacity(0.12))
                            .cornerRadius(3)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(Config.Colors.mute)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Config.Colors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Config.Colors.line, lineWidth: 0.8))
        )
    }

    private var totalFocusedTimeString: String {
        let sec = sessionManager.sessions.reduce(0) { $0 + $1.accumulatedFocusedDuration }
        return AISession.formatDuration(sec)
    }

    private var totalUnfocusedTimeString: String {
        let sec = sessionManager.sessions.reduce(0) { $0 + $1.accumulatedUnfocusedDuration }
        return AISession.formatDuration(sec)
    }

    // MARK: - 2. 뷰 모드 스위처 바
    private var viewModeSwitcherBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 530)

            Spacer()

            if viewMode == .rawLog {
                HStack(spacing: 8) {
                    Picker("분류", selection: $selectedEnvironment) {
                        ForEach(ActivityEvent.EnvironmentCategory.allCases) { env in
                            Text(env.badgeLabel).tag(env)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 95)

                    Picker("AI 여부", selection: $selectedAIFilter) {
                        ForEach(ActivityEvent.AIFilterOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 115)

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("앱, URL, 도구, 동작…", text: $logFilterText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .frame(width: 130)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Config.Colors.cardBackground)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.8))
                }
            } else if viewMode == .timeline {
                HStack(spacing: 6) {
                    Circle()
                        .fill(sessionManager.focusedSession != nil ? Color.green : (sessionManager.activeSessions.isEmpty ? Color.gray : Color.orange))
                        .frame(width: 6, height: 6)
                    Text(sessionManager.focusedSession != nil ? "1개 대화 집중 작업 중" : (sessionManager.activeSessions.isEmpty ? "대화 대기 중" : "\(sessionManager.activeSessions.count)개 대화 일시중지"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Config.Colors.mute)
                }
            } else if viewMode == .survey {
                HStack(spacing: 8) {
                    if appState.isPopupMutedForOneHour {
                        Text("1시간 음소거 중")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                    if config.isTimeWarpActive {
                        Text("30배속 왜곡 활성")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow)
                            .cornerRadius(4)
                    }
                }
            }
        }
    }

    // MARK: - 3-A. [모드 1] 대화 세션별 마스터-디테일 타임라인
    private var sessionMasterDetailView: some View {
        Group {
            if sessionManager.sessions.isEmpty {
                emptyPlaceholderView
            } else {
                HSplitView {
                    // 좌측: 세션 카드 목록
                    sessionCardsSidebarView
                        .frame(minWidth: 310, maxWidth: 380)

                    // 우측: 선택된 세션의 생명주기 및 사이활동 상세 타임라인
                    if let sid = selectedSessionId, let session = sessionManager.sessions.first(where: { $0.sessionId == sid }) {
                        sessionDetailTimelineView(session: session)
                            .frame(minWidth: 520)
                    } else if let first = sessionManager.sessions.first {
                        sessionDetailTimelineView(session: first)
                            .frame(minWidth: 520)
                    } else {
                        VStack { Text("세션을 선택해주세요").foregroundColor(.secondary) }
                    }
                }
            }
        }
    }

    private var emptyPlaceholderView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("열린 AI 대화(Session)가 없습니다")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Config.Colors.ink)
            Text("Claude 앱을 켜거나, Chrome에서 claude.ai / chatgpt.com에 접속하거나,\nTerminal을 열면 대화 단위로 세션이 자동 생성되어 추적됩니다.")
                .font(.system(size: 12.5))
                .foregroundColor(Config.Colors.mute)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // 좌측: 세션 카드 목록 사이드바
    private var sessionCardsSidebarView: some View {
        ScrollView {
            VStack(spacing: 8) {
                let active = sessionManager.activeSessions
                if !active.isEmpty {
                    sidebarSectionHeader(title: "진행 중인 대화 (\(active.count)개)", color: Color(hex: Config.Colors.accentHex))
                    ForEach(active) { session in
                        sessionCardRow(session: session)
                            .id("\(session.sessionId)_\(session.state.rawValue)_\(Int(session.accumulatedFocusedDuration))_\(Int(session.accumulatedUnfocusedDuration))")
                    }
                }

                let closed = sessionManager.closedSessions
                if !closed.isEmpty {
                    sidebarSectionHeader(title: "보존된 대화 (창/앱 닫힘: \(closed.count)개)", color: .secondary)
                        .padding(.top, 10)
                    ForEach(closed) { session in
                        sessionCardRow(session: session)
                            .id("\(session.sessionId)_\(session.state.rawValue)_\(Int(session.accumulatedFocusedDuration))_\(Int(session.accumulatedUnfocusedDuration))")
                    }
                }
            }
            .padding(10)
        }
        .background(Config.Colors.panelBackground)
    }

    private func sidebarSectionHeader(title: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func sessionCardRow(session: AISession) -> some View {
        let isSelected = (selectedSessionId == session.sessionId) ||
                         (selectedSessionId == nil && sessionManager.sessions.first?.sessionId == session.sessionId)

        return Button(action: {
            selectedSessionId = session.sessionId
        }) {
            VStack(alignment: .leading, spacing: 6) {
                // 헤더: AI 도구 태그 + 환경(앱/웹) + 상태 뱃지
                HStack(spacing: 6) {
                    Text(session.toolName)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(toolBadgeColor(session.toolName))
                        .cornerRadius(4)

                    environmentBadgeString(session.url != nil && !(session.url?.isEmpty ?? true) ? "웹" : "앱")

                    Text(session.appName)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    stateBadge(session.state)
                }

                // 대화 제목
                Text(session.title)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .semibold))
                    .foregroundColor(Config.Colors.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // 듀얼 타임 진행 바 (누적 사용 vs 일시중지 비율 시각화)
                dualProgressBar(focused: session.accumulatedFocusedDuration, unfocused: session.accumulatedUnfocusedDuration)

                // 하단 누적 시간 수치
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("누적 사용 \(session.formattedFocusedDuration)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 3) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("일시중지 \(session.formattedUnfocusedDuration)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Config.Colors.accentSoft : Config.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color(hex: Config.Colors.accentHex) : Config.Colors.line, lineWidth: isSelected ? 1.5 : 0.8)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dualProgressBar(focused: TimeInterval, unfocused: TimeInterval) -> some View {
        let total = max(1.0, focused + unfocused)
        let focusRatio = CGFloat(focused / total)

        return GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green)
                    .frame(width: max(4, geo.size.width * focusRatio))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 4)
        .cornerRadius(2)
        .background(Color.gray.opacity(0.15))
    }

    // 우측: 세션 상세 타임라인
    private func sessionDetailTimelineView(session: AISession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 상단 상세 정보 배너
                sessionDetailBanner(session: session)

                Divider()

                // 생명주기 및 사이 활동 타임라인 헤더
                HStack {
                    Text("세션 생명주기 (open → close) & 사이 작업 내역")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Config.Colors.ink)
                    Spacer()
                    Text("활성 시 누적시간 가산 / 비활성 시 일시중지")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // 타임라인 수직 노드들
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(session.lifecycleHistory.enumerated()), id: \.element.id) { index, node in
                        lifecycleNodeRow(node: node, index: index, session: session, isLast: index == session.lifecycleHistory.count - 1)
                    }
                }
            }
            .padding(16)
        }
        .background(Config.Colors.paper)
    }

    private func sessionDetailBanner(session: AISession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(session.toolName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(toolBadgeColor(session.toolName))
                            .cornerRadius(4)

                        environmentBadgeString(session.url != nil && !(session.url?.isEmpty ?? true) ? "웹" : "앱")

                        stateBadge(session.state)

                        Spacer()

                        if session.state == .close {
                            Text("보존된 세션 (창/앱 닫힘)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            Text("진행 중 (자동 추적 중)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: Config.Colors.sageHex))
                        }
                    }

                    Text(session.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Config.Colors.ink)

                    if let url = session.url, !url.isEmpty {
                        Text(url)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
            }

            // 누적 시간 요약 그리드
            HStack(spacing: 8) {
                sessionMetaPill(
                    icon: "clock",
                    label: "대화 시작",
                    value: Self.timeFormatter.string(from: session.openedAt),
                    color: .secondary
                )
                if let closed = session.closedAt {
                    sessionMetaPill(
                        icon: "xmark.circle",
                        label: "보존 시각",
                        value: Self.timeFormatter.string(from: closed),
                        color: .secondary
                    )
                }
                sessionMetaPill(
                    icon: "hourglass",
                    label: "총 존속 기간",
                    value: session.formattedTotalLifespan,
                    color: Config.Colors.ink
                )
                sessionMetaPill(
                    icon: "play.circle.fill",
                    label: "순수 누적",
                    value: session.formattedFocusedDuration,
                    color: .green
                )
                sessionMetaPill(
                    icon: "pause.circle.fill",
                    label: "일시중지",
                    value: session.formattedUnfocusedDuration,
                    color: .orange
                )
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Config.Colors.cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Config.Colors.line, lineWidth: 0.8))
    }

    private func sessionMetaPill(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1.5) {
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundColor(Config.Colors.mute)
                Text(value)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Config.Colors.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Config.Colors.panelBackground)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.7))
    }

    private func lifecycleNodeRow(node: SessionLifecycleNode, index: Int, session: AISession, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 좌측 타임라인 인디케이터
            VStack(spacing: 0) {
                Circle()
                    .fill(eventStateColor(node.state))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Config.Colors.cardBackground, lineWidth: 2))

                if !isLast {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 2)
                        .frame(minHeight: 44)
                }
            }

            // 우측 내용
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(Self.timeFormatter.string(from: node.timestamp))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    stateBadge(node.state)

                    if let dur = node.duration, dur > 0 {
                        Text("(\(AISession.formatDuration(dur)) 지속)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(eventStateColor(node.state))
                    }

                    Spacer()
                }

                Text(node.detail)
                    .font(.system(size: 12))
                    .foregroundColor(Config.Colors.ink)

                // focus_out(비활성) 상태일 경우 '해당 비활성 구간 사이'에 일어난 비AI 활동들만 표시
                if node.state == .focusOut {
                    let activitiesInSpan = interleavingActivitiesForNode(node: node, index: index, session: session)
                    if !activitiesInSpan.isEmpty {
                        interleavingActivitiesCard(activitiesInSpan)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    /// 특정 focus_out 노드의 타임스탬프부터 다음 focus_in/close 상태 전이 시각 사이의 활동만 정밀 필터링
    private func interleavingActivitiesForNode(node: SessionLifecycleNode, index: Int, session: AISession) -> [InterleavingActivity] {
        guard node.state == .focusOut else { return [] }

        let history = session.lifecycleHistory
        let startTime = node.timestamp

        // 다음 focus_in 또는 close 노드 탐색하여 종료 시각 설정
        var endTime = Date.distantFuture
        for i in (index + 1)..<history.count {
            let next = history[i]
            if next.state == .focusIn || next.state == .close {
                endTime = next.timestamp
                break
            }
        }

        // 이전 노드가 존재하면 그 시각 이후부터, 기본적으로 startTime 기준으로 필터링
        var lowerBound = startTime.addingTimeInterval(-0.05)
        if index > 0 {
            let prevNode = history[index - 1]
            if prevNode.timestamp > lowerBound {
                lowerBound = prevNode.timestamp
            }
        }

        return session.interleavingActivities.filter { act in
            act.timestamp >= lowerBound && act.timestamp < endTime
        }
    }

    private func interleavingActivitiesCard(_ activities: [InterleavingActivity]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10.5))
                    .foregroundColor(.orange)
                Text("이 대화 사이 작업 (누적시간 일시중지 중 발생: 총 \(activities.count)건)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Config.Colors.ink)
                Spacer()
            }

            VStack(spacing: 4) {
                ForEach(activities.prefix(12)) { act in
                    HStack(spacing: 6) {
                        Text(Self.timeFormatter.string(from: act.timestamp))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)

                        if let env = act.environment, !env.isEmpty {
                            environmentBadgeString(env)
                        }

                        if let actName = act.action, !actName.isEmpty {
                            actionBadgeString(actName)
                        }

                        if !act.titleOrURL.contains("➔") {
                            Text(act.appName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Config.Colors.ink)
                                .frame(width: 80, alignment: .leading)
                                .lineLimit(1)
                        }

                        Text(act.titleOrURL)
                            .font(.system(size: 10.5))
                            .foregroundColor(act.titleOrURL.hasPrefix("http") ? .blue : Config.Colors.ink)
                            .lineLimit(1)

                        Spacer()

                        if act.duration > 0 {
                            Text(String(format: "%.1fs", act.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Config.Colors.cardBackground)
                    .cornerRadius(4)
                }

                if activities.count > 12 {
                    Text("+ \(activities.count - 12)건의 추가 사이 활동")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .background(Config.Colors.panelBackground)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.3), lineWidth: 0.8))
    }

    // MARK: - 3-B. [모드 2] 비주얼 간트 타임라인 (Visual Gantt with Fixed Shared Time Axis)
    public enum GanttTimeRange: String, CaseIterable, Identifiable {
        case all = "전체 기간"
        case last15m = "최근 15분"
        case last1h = "최근 1시간"
        case last3h = "최근 3시간"
        case today = "오늘"
        public var id: String { rawValue }
    }

    private var ganttTimeBounds: (start: Date, end: Date) {
        let now = Date()
        let allStart = sessionManager.sessions.map { $0.openedAt }.min() ?? now.addingTimeInterval(-600)

        let start: Date
        switch ganttTimeRange {
        case .all:
            start = allStart
        case .last15m:
            start = now.addingTimeInterval(-15 * 60)
        case .last1h:
            start = now.addingTimeInterval(-60 * 60)
        case .last3h:
            start = now.addingTimeInterval(-3 * 3600)
        case .today:
            start = Calendar.current.startOfDay(for: now)
        }

        let end = now
        // 최소 60초 간격 확보
        let actualStart = min(start, end.addingTimeInterval(-60))
        return (actualStart, end)
    }

    private var visualGanttView: some View {
        let bounds = ganttTimeBounds
        let ticks = generateTimeTicks(minDate: bounds.start, maxDate: bounds.end, count: 6)

        return VStack(spacing: 0) {
            // 1. 간트 컨트롤 및 범례 헤더
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("대화 세션별 활동 간트 차트 (Visual Swimlanes)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Config.Colors.ink)
                    Text("모든 대화가 고정된 동일 시간 축(X축) 위에서 실제 시작 시각과 활성(Focus)/일시중지(Unfocus) 구간으로 배치됩니다.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 시간 범위 선택
                Picker("범위", selection: $ganttTimeRange) {
                    ForEach(GanttTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                // 범례 (Legend)
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                        Text("활성 (Focus)")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange)
                            .frame(width: 10, height: 10)
                        Text("일시중지/사이작업 (Unfocus)")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 7, height: 7)
                        Text("시작 (open)")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.gray)
                            .frame(width: 3, height: 10)
                        Text("종료 (close)")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Config.Colors.cardBackground)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Config.Colors.panelBackground)

            Divider()

            // 2. 고정된 시간 축 눈금자 (Fixed Time Axis Ruler)
            ganttTimeRuler(ticks: ticks, bounds: bounds)
                .background(Config.Colors.panelBackground)

            Divider()

            // 3. 스윔레인 목록 (Swimlanes List)
            if sessionManager.sessions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 36))
                        .foregroundColor(Config.Colors.mute.opacity(0.5))
                    Text("표시할 대화 세션이 없습니다")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Config.Colors.mute)
                    Text("새 대화를 열면 공통 시간 축 위에 스윔레인이 자동으로 생성됩니다.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(sessionManager.sessions) { session in
                            ganttSwimlaneRow(session: session, bounds: bounds, ticks: ticks)
                        }
                    }
                    .padding(12)
                }
                .background(Config.Colors.paper)
            }
        }
    }

    private func ganttTimeRuler(ticks: [Date], bounds: (start: Date, end: Date)) -> some View {
        HStack(spacing: 0) {
            // 좌측 헤더 레이블
            HStack {
                Text("대화 스레드 (Thread)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(width: 220)
            .padding(.leading, 12)

            Divider()

            // 우측 시간 눈금자 트랙
            GeometryReader { geo in
                let w = geo.size.width
                let totalSec = max(1.0, bounds.end.timeIntervalSince(bounds.start))

                ZStack(alignment: .leading) {
                    // 기준선
                    Rectangle()
                        .fill(Config.Colors.line)
                        .frame(height: 1)
                        .position(x: w / 2, y: geo.size.height - 1)

                    ForEach(Array(ticks.enumerated()), id: \.offset) { _, tickDate in
                        let ratio = tickDate.timeIntervalSince(bounds.start) / totalSec
                        let x = max(0, min(w, CGFloat(ratio) * w))

                        // 눈금 선
                        Rectangle()
                            .fill(Config.Colors.line)
                            .frame(width: 1, height: 6)
                            .position(x: x, y: geo.size.height - 3)

                        // 시각 텍스트
                        Text(formatGanttTick(tickDate, isMultiDay: totalSec > 86400))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(Config.Colors.mute)
                            .position(x: x, y: 10)
                    }

                    // 현재 시각 인디케이터
                    let nowRatio = Date().timeIntervalSince(bounds.start) / totalSec
                    if nowRatio >= 0 && nowRatio <= 1 {
                        let nowX = CGFloat(nowRatio) * w
                        VStack(spacing: 0) {
                            Text("현재")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(.red)
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 1, height: 8)
                        }
                        .position(x: nowX, y: 10)
                    }
                }
            }
            .frame(height: 24)
            .padding(.trailing, 12)
        }
        .frame(height: 28)
    }

    private func ganttSwimlaneRow(session: AISession, bounds: (start: Date, end: Date), ticks: [Date]) -> some View {
        HStack(spacing: 0) {
            // 좌측 정보 컬럼 (220pt)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(session.toolName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(toolBadgeColor(session.toolName))
                        .cornerRadius(3)

                    environmentBadgeString(session.url != nil && !(session.url?.isEmpty ?? true) ? "웹" : "앱")

                    stateBadge(session.state)

                    Spacer()
                }

                Text(session.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Config.Colors.ink)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("순수 \(session.formattedFocusedDuration)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("존속 \(session.formattedTotalLifespan)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 220, alignment: .leading)
            .padding(.leading, 12)
            .padding(.vertical, 8)

            Divider()

            // 우측 간트 트랙 (고정된 시간 축 기반)
            GeometryReader { geo in
                let w = geo.size.width
                let now = Date()

                ZStack(alignment: .leading) {
                    // 배경 트랙
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Config.Colors.panelBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Config.Colors.line.opacity(0.6), lineWidth: 0.6)
                        )

                    // 세로 격자 그리드 라인 (눈금자와 일치)
                    ForEach(Array(ticks.enumerated()), id: \.offset) { _, tickDate in
                        let x = calculateGanttX(date: tickDate, bounds: bounds, width: w)
                        Rectangle()
                            .fill(Config.Colors.line.opacity(0.35))
                            .frame(width: 1)
                            .position(x: x, y: geo.size.height / 2)
                    }

                    // 세션의 실제 활성(Focus) 및 일시중지(Unfocus) 블록들
                    let segments = session.computeTimelineSegments(upTo: now)
                    ForEach(segments) { seg in
                        let segStart = max(bounds.start, seg.start)
                        let segEnd = min(bounds.end, seg.end)
                        if segEnd > segStart {
                            let x1 = calculateGanttX(date: segStart, bounds: bounds, width: w)
                            let x2 = calculateGanttX(date: segEnd, bounds: bounds, width: w)
                            let blockW = max(3, x2 - x1)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(seg.isFocus ? Color.green : Color.orange.opacity(0.85))
                                .frame(width: blockW, height: 16)
                                .position(x: x1 + blockW / 2, y: geo.size.height / 2)
                                .help("\(seg.isFocus ? "활성 (Focus)" : "일시중지 (Unfocus)"): \(AISession.formatDuration(seg.duration))\n구간: \(Self.timeFormatter.string(from: seg.start)) ~ \(Self.timeFormatter.string(from: seg.end))")
                        }
                    }

                    // 세션 시작(Open) 마커
                    let openX = calculateGanttX(date: session.openedAt, bounds: bounds, width: w)
                    if session.openedAt >= bounds.start && session.openedAt <= bounds.end {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Config.Colors.cardBackground, lineWidth: 1.5))
                            .position(x: openX, y: geo.size.height / 2)
                            .help("대화 시작 (Open): \(Self.timeFormatter.string(from: session.openedAt))")
                    }

                    // 세션 종료(Close) 마커
                    if let closedAt = session.closedAt, closedAt >= bounds.start && closedAt <= bounds.end {
                        let closeX = calculateGanttX(date: closedAt, bounds: bounds, width: w)
                        Rectangle()
                            .fill(Color.gray)
                            .frame(width: 3, height: 18)
                            .position(x: closeX, y: geo.size.height / 2)
                            .help("대화 종료 (Close): \(Self.timeFormatter.string(from: closedAt))")
                    }

                    // 현재 시각(Now) 수직 가이드 라인
                    let nowX = calculateGanttX(date: now, bounds: bounds, width: w)
                    if now >= bounds.start && now <= bounds.end {
                        Rectangle()
                            .fill(Color.red.opacity(0.8))
                            .frame(width: 1.5, height: geo.size.height)
                            .position(x: nowX, y: geo.size.height / 2)
                    }
                }
            }
            .frame(height: 38)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .background(Config.Colors.cardBackground)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.8))
    }

    private func calculateGanttX(date: Date, bounds: (start: Date, end: Date), width: CGFloat) -> CGFloat {
        let totalSec = max(1.0, bounds.end.timeIntervalSince(bounds.start))
        let ratio = date.timeIntervalSince(bounds.start) / totalSec
        return max(0, min(width, CGFloat(ratio) * width))
    }

    private func generateTimeTicks(minDate: Date, maxDate: Date, count: Int = 6) -> [Date] {
        guard count > 1 else { return [minDate] }
        let total = maxDate.timeIntervalSince(minDate)
        guard total > 0 else { return [minDate] }
        let step = total / Double(count - 1)
        return (0..<count).map { minDate.addingTimeInterval(Double($0) * step) }
    }

    private func formatGanttTick(_ date: Date, isMultiDay: Bool) -> String {
        let f = DateFormatter()
        f.dateFormat = isMultiDay ? "M/d HH:mm" : "HH:mm:ss"
        return f.string(from: date)
    }


    // MARK: - 3-C. [모드 3] 전체 실시간 로그 테이블
    private var isAllEventTypesSelected: Bool {
        selectedEventTypes.count == ActivityEvent.EventType.allCases.count
    }

    private func toggleEventTypeFilter(_ type: ActivityEvent.EventType) {
        if isAllEventTypesSelected {
            // 전체 보기 상태에서 특정 라벨 클릭 시 해당 라벨 단독 선택
            selectedEventTypes = [type]
        } else {
            if selectedEventTypes.contains(type) {
                selectedEventTypes.remove(type)
                if selectedEventTypes.isEmpty {
                    selectedEventTypes = Set(ActivityEvent.EventType.allCases)
                }
            } else {
                selectedEventTypes.insert(type)
            }
        }
    }

    private func eventTypeColor(_ type: ActivityEvent.EventType) -> Color {
        switch type {
        case .focusIn:
            return .green
        case .focusOut:
            return .orange
        case .navigate:
            return .purple
        case .open:
            return .blue
        case .close:
            return .red
        case .idleStart:
            return .orange
        case .idleEnd:
            return .teal
        case .suspend:
            return .gray
        case .resume:
            return .teal
        }
    }

    private var labelFilterBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("라벨 필터:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Config.Colors.ink)
            }
            .padding(.trailing, 2)

            // '전체' 토글 버튼
            Button(action: {
                selectedEventTypes = Set(ActivityEvent.EventType.allCases)
            }) {
                HStack(spacing: 4) {
                    if isAllEventTypesSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    Text("전체")
                        .font(.system(size: 11, weight: isAllEventTypesSelected ? .bold : .medium))
                    Text("(\(debugStore.events.count))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(isAllEventTypesSelected ? .white.opacity(0.9) : .secondary)
                }
                .foregroundColor(isAllEventTypesSelected ? .white : Config.Colors.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isAllEventTypesSelected ? Color.blue : Config.Colors.cardBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isAllEventTypesSelected ? Color.blue : Config.Colors.line, lineWidth: isAllEventTypesSelected ? 1.2 : 0.8)
                )
            }
            .buttonStyle(.plain)

            // 개별 라벨 토글 칩들 (중복 선택 가능)
            ForEach(filterableEventTypes, id: \.self) { type in
                let isSelected = selectedEventTypes.contains(type)
                let count = debugStore.events.filter { $0.eventType == type }.count
                let color = eventTypeColor(type)
                let active = isSelected && !isAllEventTypesSelected

                Button(action: {
                    toggleEventTypeFilter(type)
                }) {
                    HStack(spacing: 4) {
                        if active {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        Text(type.code)
                            .font(.system(size: 10.5, weight: active ? .bold : .medium, design: .monospaced))
                        Text("(\(count))")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(active ? .white.opacity(0.9) : .secondary)
                    }
                    .foregroundColor(active ? .white : Config.Colors.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(active ? color : Config.Colors.cardBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(active ? color : Config.Colors.line, lineWidth: active ? 1.2 : 0.8)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if !isAllEventTypesSelected {
                Button("모두 보기 (초기화)") {
                    selectedEventTypes = Set(ActivityEvent.EventType.allCases)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blue)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Config.Colors.paper)
    }

    private var rawLogTableView: some View {
        VStack(spacing: 0) {
            // 상단 라벨 다중 선택 필터 바
            labelFilterBar

            Divider()

            // 테이블 헤더 (사용자 피드백: '그룹' 컬럼 제외하여 간결하고 넓은 가독성 확보)
            HStack(spacing: 8) {
                Text("시각").frame(width: 58, alignment: .leading)
                Text("라벨").frame(width: 78, alignment: .center)
                Text("환경").frame(width: 44, alignment: .center)
                Text("AI 구분").frame(width: 90, alignment: .leading)
                Text("앱 / 소스").frame(width: 100, alignment: .leading)
                Text("상세 맥락").frame(maxWidth: .infinity, alignment: .leading)
                Text("머문 시간").frame(width: 55, alignment: .trailing)
                Text("세션 ID").frame(width: 60, alignment: .leading)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Config.Colors.panelBackground)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    let filtered = debugStore.events.filter { event in
                        // 1. 라벨 필터링 (중복 선택 지원: 선택된 집합에 포함되는지 확인)
                        if !selectedEventTypes.contains(event.eventType) {
                            return false
                        }
                        // 2. 환경 분류 필터링
                        if selectedEnvironment != .all && event.environmentCategory != selectedEnvironment {
                            return false
                        }
                        // 3. AI 여부 필터링
                        switch selectedAIFilter {
                        case .all:
                            break
                        case .aiOnly:
                            if !event.isAI { return false }
                        case .nonAIOnly:
                            if event.isAI { return false }
                        }
                        // 4. 검색 텍스트 필터링
                        if logFilterText.isEmpty { return true }
                        return event.appName.localizedCaseInsensitiveContains(logFilterText) ||
                            event.windowTitle.localizedCaseInsensitiveContains(logFilterText) ||
                            (event.url?.localizedCaseInsensitiveContains(logFilterText) ?? false) ||
                            (event.aiTool?.localizedCaseInsensitiveContains(logFilterText) ?? false) ||
                            event.eventType.code.localizedCaseInsensitiveContains(logFilterText) ||
                            event.environmentCategory.badgeLabel.localizedCaseInsensitiveContains(logFilterText)
                    }

                    if filtered.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("선택된 라벨 및 조건에 일치하는 로그가 없습니다.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Button("모든 라벨 로그 표시하기") {
                                selectedEventTypes = Set(ActivityEvent.EventType.allCases)
                                selectedEnvironment = .all
                                selectedAIFilter = .all
                                logFilterText = ""
                            }
                            .font(.system(size: 12))
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 60)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(filtered) { event in
                            rawLogRow(event)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func rawLogRow(_ event: ActivityEvent) -> some View {
        HStack(spacing: 8) {
            // 시각
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 58, alignment: .leading)

            // 라벨 (open, close, focus_in, focus_out, navigate, idle_start, idle_end, suspend, resume)
            actionBadge(event.eventType)
                .frame(width: 78, alignment: .center)

            // 환경 (앱, 웹, 시스템 - 대괄호 없이 깔끔하게)
            environmentBadge(event.environmentCategory)
                .frame(width: 44, alignment: .center)

            // AI 구분
            aiPropertyBadge(isAI: event.isAI, toolName: event.aiTool)
                .frame(width: 90, alignment: .leading)

            // 앱 / 소스
            Text(event.appName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Config.Colors.ink)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            // 상세 맥락
            eventDetailContextView(event)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 머문 시간 (오직 focus_in 에만 누적/머문 시간 표시, 그 외 시점성/전환 이벤트는 -)
            if event.eventType == .focusIn, let d = event.duration, d > 0 {
                Text(formatDuration(d))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Config.Colors.ink)
                    .frame(width: 55, alignment: .trailing)
            } else {
                Text("-")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 55, alignment: .trailing)
            }

            // 세션 ID
            if let sid = event.sessionId {
                Text(String(sid.uuidString.prefix(6)))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: Config.Colors.sageHex))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(hex: Config.Colors.sageHex).opacity(0.15))
                    .cornerRadius(4)
                    .frame(width: 60, alignment: .leading)
            } else {
                Text("-")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 60, alignment: .center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(event.isAI ? Config.Colors.accentSoft.opacity(0.35) : Color.clear)
    }

    // MARK: - 상세 맥락 렌더러
    @ViewBuilder
    private func eventDetailContextView(_ event: ActivityEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch event.eventType {
            case .focusIn:
                // 포커스 진입: focus된 부분에 대한 정보만 표시
                Text(event.threadTitle ?? (event.windowTitle.isEmpty ? event.appName : event.windowTitle))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Config.Colors.ink)
                    .lineLimit(1)

            case .focusOut:
                // 포커스 이탈: 이탈/to 표기 없이 focus 해제된 부분에 대한 정보만 표시
                Text(event.threadTitle ?? (event.windowTitle.isEmpty ? event.appName : event.windowTitle))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

            case .navigate:
                HStack(spacing: 4) {
                    if let fromApp = event.fromApp, let toApp = event.toApp, fromApp != toApp {
                        // 1. 앱 간 전환: [app] 앱A (창제목) ➔ 앱B (창제목)
                        Text("[app]")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                        let fromDesc = (event.fromTitle != nil && !event.fromTitle!.isEmpty && event.fromTitle != fromApp) ? "\(fromApp) (\(event.fromTitle!))" : fromApp
                        let toDesc = (event.toTitle != nil && !event.toTitle!.isEmpty && event.toTitle != toApp) ? "\(toApp) (\(event.toTitle!))" : toApp
                        Text("\(fromDesc) ➔ \(toDesc)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Config.Colors.ink)
                            .lineLimit(1)
                    } else if let fromTitle = event.fromTitle, let toTitle = event.toTitle, fromTitle != toTitle && !fromTitle.isEmpty && !toTitle.isEmpty {
                        // 2. 동일 앱 내 창/문서/탭 전환: [window] 창A ➔ 창B
                        let badge = (event.navType == "chat") ? "[chat]" : ((event.navType == "tab" || event.navType == "new_tab") ? "[tab]" : "[window]")
                        Text(badge)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                        Text("\(fromTitle) ➔ \(toTitle)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Config.Colors.ink)
                            .lineLimit(1)
                    } else if let fDom = event.fromDomain, let tDom = event.toDomain, fDom != tDom {
                        // 3. 웹 도메인 전환: [domain] 도메인A ➔ 도메인B
                        Text("[domain]")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                        Text("\(fDom) ➔ \(tDom)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.purple)
                            .lineLimit(1)
                    } else if let fChat = event.fromChatId, let tChat = event.toChatId, fChat != tChat {
                        // 4. 대화 스레드 전환: [chat] 스레드A ➔ 스레드B
                        Text("[chat]")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.indigo)
                        Text("\(fChat) ➔ \(tChat)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.indigo)
                            .lineLimit(1)
                    } else if let nav = event.navType, !nav.isEmpty {
                        // 5. 기타 전이
                        Text("[\(nav)]")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                        Text(event.url ?? event.windowTitle)
                            .font(.system(size: 10.5, design: event.url != nil ? .monospaced : .default))
                            .foregroundColor(event.url != nil ? .blue : Config.Colors.ink)
                            .lineLimit(1)
                    } else {
                        Text(event.url ?? event.windowTitle)
                            .font(.system(size: 10.5))
                            .foregroundColor(event.url != nil ? .blue : Config.Colors.ink)
                            .lineLimit(1)
                    }
                }

            case .suspend:
                HStack(spacing: 4) {
                    Text("[\(event.suspendType ?? "suspend")]")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(event.windowTitle)
                        .font(.system(size: 11))
                        .foregroundColor(Config.Colors.ink)
                }

            case .resume:
                HStack(spacing: 4) {
                    Text("[\(event.suspendType ?? "resume")]")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.teal)
                    Text(event.windowTitle)
                        .font(.system(size: 11))
                        .foregroundColor(Config.Colors.ink)
                    if let dur = event.suspendDuration, dur > 0 {
                        Text("(\(formatDuration(dur)) 중단 후 복귀)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

            case .idleStart:
                Text("입력 유휴 시작 (2분 동안 키보드/마우스 입력 없음)")
                    .font(.system(size: 10.5))
                    .foregroundColor(.orange)

            case .idleEnd:
                HStack(spacing: 4) {
                    Text("입력 재개 (작업 복귀)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.teal)
                    if let dur = event.idleDuration, dur > 0 {
                        Text("(\(formatDuration(dur)) 유휴 후 복귀)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

            case .open:
                HStack(spacing: 4) {
                    let badgeLabel = (event.navType == "new_window" || event.navType == "new_tab") ? "[new_window]" : "[new_session]"
                    Text(badgeLabel)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                    Text(event.threadTitle ?? (event.windowTitle.isEmpty ? event.appName : event.windowTitle))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Config.Colors.ink)
                        .lineLimit(1)
                }

            case .close:
                HStack(spacing: 4) {
                    Text("[대화/앱 종료]")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.red)
                    Text(event.threadTitle ?? (event.windowTitle.isEmpty ? event.appName : event.windowTitle))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 4. 하단 상태 바
    private var bottomStatusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 11))
                    Text("\(debugStore.events.count)건 기록")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(Config.Colors.ink)

                Text("·")
                    .foregroundColor(Config.Colors.mute)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("\(sessionManager.activeSessions.count)개 열림")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Color.green)

                Text("·")
                    .foregroundColor(Config.Colors.mute)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                    Text("\(sessionManager.closedSessions.count)개 보존")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Config.Colors.mute)
            }

            Spacer()

            HStack(spacing: 6) {
                Text("표준 라벨 체계:")
                    .font(.system(size: 10.5))
                    .foregroundColor(Config.Colors.mute)
                groupBadge(.lifecycle)
                groupBadge(.focus)
                groupBadge(.transition)
                groupBadge(.system)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Config.Colors.panelBackground)
    }

    // MARK: - 디자인 뱃지 및 색상 헬퍼
    private func groupBadge(_ group: ActivityEvent.EventGroup) -> some View {
        let (color, bgColor): (Color, Color) = {
            switch group {
            case .lifecycle:
                return (.blue, Color.blue.opacity(0.12))
            case .focus:
                return (.green, Color.green.opacity(0.12))
            case .transition:
                return (.purple, Color.purple.opacity(0.12))
            case .system:
                return (.secondary, Color.gray.opacity(0.12))
            }
        }()

        return Text(group.badgeLabel)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bgColor)
            .cornerRadius(3)
    }

    private func stateBadge(_ state: AISession.SessionState) -> some View {
        let (title, bg, fg) = stateVisuals(state)
        return Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(bg)
            .cornerRadius(4)
    }

    private func stateVisuals(_ state: AISession.SessionState) -> (String, Color, Color) {
        switch state {
        case .open:
            return ("open", Color.blue.opacity(0.15), Color.blue)
        case .focusIn:
            return ("focus", Color.green.opacity(0.18), Color.green)
        case .focusOut:
            return ("unfocus", Color.orange.opacity(0.18), Color.orange)
        case .close:
            return ("close (보존)", Color.gray.opacity(0.2), Color.secondary)
        }
    }

    private func eventStateColor(_ state: AISession.SessionState) -> Color {
        switch state {
        case .open: return .blue
        case .focusIn: return .green
        case .focusOut: return .orange
        case .close: return .secondary
        }
    }

    private func toolBadgeColor(_ tool: String) -> Color {
        switch tool.lowercased() {
        case let t where t.contains("claude"):
            return Color(hex: Config.Colors.accentHex)
        case let t where t.contains("chatgpt"):
            return Color(hex: Config.Colors.sageHex)
        case let t where t.contains("cursor"):
            return Color.purple
        case let t where t.contains("antigravity"):
            return Color(hex: "#3B82C4")
        case let t where t.contains("windsurf"):
            return Color.teal
        default:
            return Color.blue
        }
    }

    private func environmentBadge(_ env: ActivityEvent.EnvironmentCategory) -> some View {
        environmentBadgeString(env.badgeLabel)
    }

    private func environmentBadgeString(_ label: String) -> some View {
        let (color, bgColor): (Color, Color) = {
            switch label {
            case "앱":
                return (Color.blue.opacity(0.75), Color.blue.opacity(0.08))
            case "웹":
                return (Color.teal.opacity(0.75), Color.teal.opacity(0.08))
            case "시스템":
                return (Color.secondary.opacity(0.8), Color.secondary.opacity(0.08))
            default:
                return (Color.secondary, Color.secondary.opacity(0.06))
            }
        }()

        return Text(label)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bgColor)
            .cornerRadius(3)
    }

    private func actionBadge(_ type: ActivityEvent.EventType) -> some View {
        actionBadgeString(type.code)
    }

    private func actionBadgeString(_ action: String) -> some View {
        let (color, bgColor): (Color, Color) = {
            switch action {
            // [1] 생애주기
            case "open":
                return (.blue, Color.blue.opacity(0.14))
            case "close":
                return (.red, Color.red.opacity(0.14))
            // [2] 포커스 & 탐색·전이
            case "focus_in":
                return (.green, Color.green.opacity(0.16))
            case "focus_out":
                return (.orange, Color.orange.opacity(0.14))
            case "navigate":
                return (.purple, Color.purple.opacity(0.14))
            // [3] 입력·시스템
            case "idle_start":
                return (.orange, Color.orange.opacity(0.12))
            case "idle_end":
                return (.teal, Color.teal.opacity(0.14))
            case "suspend":
                return (.gray, Color.gray.opacity(0.14))
            case "resume":
                return (.teal, Color.teal.opacity(0.14))

            // 레거시 국문 라벨 호환
            case "대화 시작", "새 대화":
                return (.blue, Color.blue.opacity(0.14))
            case "대화 종료", "앱 종료":
                return (.red, Color.red.opacity(0.14))
            case "포커스 진입", "대화 활성":
                return (.green, Color.green.opacity(0.16))
            case "포커스 이탈", "일시중지":
                return (.orange, Color.orange.opacity(0.14))
            case "앱 활성", "앱 비활성", "창 전환", "페이지 이동", "탐색/전환":
                return (.purple, Color.purple.opacity(0.14))
            case "자리 비움", "유휴 시작":
                return (.orange, Color.orange.opacity(0.12))
            case "입력 복귀":
                return (.teal, Color.teal.opacity(0.14))
            case "화면 잠금", "절전 모드":
                return (.gray, Color.gray.opacity(0.14))
            case "잠금 해제", "절전 해제":
                return (.teal, Color.teal.opacity(0.14))
            default:
                return (.secondary, Color.gray.opacity(0.12))
            }
        }()

        return Text(action)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bgColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color.opacity(0.25), lineWidth: 0.6)
            )
    }

    private func aiPropertyBadge(isAI: Bool, toolName: String?) -> some View {
        Group {
            if isAI {
                HStack(spacing: 3) {
                    Text("🤖")
                        .font(.system(size: 9))
                    if let tool = toolName, !tool.isEmpty {
                        Text(tool)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                    } else {
                        Text("AI")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundColor(toolBadgeColor(toolName ?? "ai"))
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(toolBadgeColor(toolName ?? "ai").opacity(0.14))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(toolBadgeColor(toolName ?? "ai").opacity(0.3), lineWidth: 0.6)
                )
            } else {
                Text("-")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval?) -> String {
        guard let d = duration, d > 0 else { return "·" }
        if d < 60 {
            return String(format: "%.1fs", d)
        } else {
            let m = Int(d) / 60
            let s = Int(d) % 60
            return "\(m)m \(s)s"
        }
    }

    // MARK: - 설문 팝업 & 스케줄러 뷰 (ViewMode.survey)
    private var surveySchedulerView: some View {
        VSplitView {
            // 상단: 스케줄러 컨트롤 & 실시간 설정 패널
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // 스크롤 상단 앵커
                        Color.clear.frame(height: 0).id("surveyTopAnchor")

                        // 1. 🎮 설문 팝업 인터랙티브 제어 & 테스트 카드
                        surveyTriggerControlCard

                        // 2. ⚙️ 연구 파라미터 & 스케줄러 실시간 설정
                        ConfigSettingsSectionView()

                        // 3. 📡 오프라인 동기화 큐 & 연구 로그 CSV 내보내기 허브
                        syncAndExportHubCard
                    }
                    .padding(14)
                }
                .onAppear {
                    proxy.scrollTo("surveyTopAnchor", anchor: .top)
                }
            }
            .frame(minHeight: 440)
            .background(Config.Colors.paper)

            Divider()

            // 하단: 설문 이벤트 이력 로그 테이블
            surveyEventTableView
                .frame(minHeight: 190)
        }
    }

    // MARK: - 1. 🎮 설문 팝업 인터랙티브 제어 & 테스트 카드
    private var surveyTriggerControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A. 상단 라이브 상태 바 (현재 팝업 상태 / 음소거 / 쿨다운 / 시간배속)
            HStack(alignment: .center, spacing: 12) {
                // 현재 팝업 표시 여부
                HStack(spacing: 8) {
                    Circle()
                        .fill(surveyScheduler.isPopupPresented ? Color.green : Color.gray)
                        .frame(width: 9, height: 9)

                    if surveyScheduler.isPopupPresented {
                        HStack(spacing: 6) {
                            Text("팝업 표시 중: \(surveyScheduler.currentPopupType?.badgeLabel ?? "") \(surveyScheduler.currentPopupType?.koreanTitle ?? "")")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundColor(.green)

                            Button("창 닫기") {
                                surveyScheduler.dismissCurrentPopup()
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Text("팝업 대기 중 (닫힘)")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }
                }

                Spacer()

                // 1시간 동안 팝업 끄기(Mute)
                Button(action: {
                    appState.toggleMuteOneHour()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: appState.isPopupMutedForOneHour ? "bell.slash.fill" : "bell.fill")
                            .font(.system(size: 11))
                        Text(appState.isPopupMutedForOneHour ? "1시간 음소거 중" : "1시간 팝업 끄기")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(appState.isPopupMutedForOneHour ? .white : Config.Colors.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(appState.isPopupMutedForOneHour ? Color.red : Config.Colors.cardBackground)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(appState.isPopupMutedForOneHour ? Color.clear : Config.Colors.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)

                // 15분 동안 기록 멈추기
                Button(action: {
                    appState.togglePauseRecording15Min()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: appState.isRecordingPaused15Min ? "pause.circle.fill" : "pause.circle")
                            .font(.system(size: 11))
                        Text(appState.isRecordingPaused15Min ? "기록 정지 중 (15분)" : "15분 기록 멈추기")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(appState.isRecordingPaused15Min ? .white : Config.Colors.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(appState.isRecordingPaused15Min ? Color.orange : Config.Colors.cardBackground)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(appState.isRecordingPaused15Min ? Color.clear : Config.Colors.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)

                // 쿨다운 상태 표시
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(cooldownStatusString)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(cooldownRemainingSeconds > 0 ? .orange : .green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((cooldownRemainingSeconds > 0 ? Color.orange : Color.green).opacity(0.1))
                .cornerRadius(6)

                // 시간 배속 (30배속) 상태 & 퀵 토글
                Button(action: {
                    config.toggleTimeWarp()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                        Text(config.isTimeWarpActive ? "30배속 왜곡 중" : "표준 시간 (1x)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(config.isTimeWarpActive ? .black : Config.Colors.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(config.isTimeWarpActive ? Color.yellow : Config.Colors.cardBackground)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(config.isTimeWarpActive ? Color.clear : Config.Colors.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }

            Divider()

            // B. 강제 팝업 실행 (⚡ 즉시 노출)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 5) {
                        Text("⚡")
                        Text("강제 팝업 즉시 실행")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }
                    Text("· 쿨다운 및 음소거 규칙을 무시하고 화면 우상단에 즉시 슬라이드 인")
                        .font(.system(size: 11))
                        .foregroundColor(Config.Colors.mute)
                    Spacer()
                }

                HStack(spacing: 8) {
                    ForEach(SurveyType.allCases) { type in
                        Button(action: {
                            lastRuleCheckMessage = "⚡ 즉시 강제 실행됨: \(type.rawValue)"
                            surveyScheduler.forceTrigger(type: type)
                        }) {
                            HStack(spacing: 5) {
                                Text(type.badgeLabel)
                                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                Text(type.shortLabel)
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: type.badgeColorHex))
                            .cornerRadius(6)
                            .shadow(color: Color(hex: type.badgeColorHex).opacity(0.3), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // C. 규칙 검증 팝업 실행 (🛡️ 쿨다운 & 음소거 검사)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 5) {
                        Text("🛡️")
                        Text("규칙 적용 팝업 실행")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }
                    Text("· 세션 간 30분 쿨다운(종료 팝업 뒤 30분간 시작 팝업 억제) 및 1시간 음소거 검증")
                        .font(.system(size: 11))
                        .foregroundColor(Config.Colors.mute)
                    Spacer()
                }

                HStack(spacing: 8) {
                    ForEach(SurveyType.allCases) { type in
                        Button(action: {
                            testTriggerWithRules(type: type)
                        }) {
                            HStack(spacing: 4) {
                                Text(type.badgeLabel)
                                    .font(.system(size: 10, design: .monospaced))
                                Text(type.shortLabel)
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundColor(Config.Colors.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Config.Colors.cardBackground)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Config.Colors.line, lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !lastRuleCheckMessage.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: isRuleDenied ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(isRuleDenied ? .red : .green)
                        Text(lastRuleCheckMessage)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(isRuleDenied ? .red : .green)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isRuleDenied ? Color.red : Color.green).opacity(0.1))
                    .cornerRadius(6)
                }
            }

            // D. 보류(Pending) 및 스누즈(Snooze) 상태 배너
            if surveyScheduler.pendingSurvey != nil || !surveyScheduler.activeSnoozes.isEmpty {
                Divider()
                HStack(spacing: 16) {
                    if let pending = surveyScheduler.pendingSurvey {
                        HStack(spacing: 6) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text("보류 팝업: [\(pending.type.rawValue)] 사용자 복귀 시 자동 노출 대기")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }

                    if !surveyScheduler.activeSnoozes.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                            Text("예약된 스누즈: \(surveyScheduler.activeSnoozes.count)건")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.blue)

                            ForEach(surveyScheduler.activeSnoozes) { snooze in
                                Button("[\(snooze.type.rawValue)] 즉시 재알림") {
                                    surveyScheduler.triggerSnoozeImmediately(id: snooze.id)
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Config.Colors.cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Config.Colors.line, lineWidth: 0.8))
    }

    private var isRuleDenied: Bool {
        lastRuleCheckMessage.contains("거부") ||
        lastRuleCheckMessage.contains("쿨다운") ||
        lastRuleCheckMessage.contains("음소거") ||
        lastRuleCheckMessage.contains("차단")
    }

    // MARK: - 3. 📡 오프라인 동기화 큐 & CSV 내보내기 허브
    private var syncAndExportHubCard: some View {
        HStack(alignment: .top, spacing: 12) {
            // 좌측: ☁️ 로컬 동기화 큐 & 백엔드 상태
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "externaldrive.badge.icloud")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                        Text("로컬 동기화 큐 & Supabase")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }
                    Spacer()
                    Text(syncManager.isOnline ? "🟢 온라인" : "🟠 오프라인 (로컬 큐)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(syncManager.isOnline ? .green : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((syncManager.isOnline ? Color.green : Color.orange).opacity(0.12))
                        .cornerRadius(4)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("대기 큐")
                            .font(.system(size: 10))
                            .foregroundColor(Config.Colors.mute)
                        Text("\(syncManager.pendingQueueCount)건")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(syncManager.pendingQueueCount > 0 ? .orange : .green)
                    }

                    if let count = syncManager.activeParticipantsCount {
                        Divider().frame(height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("활성 참여자")
                                .font(.system(size: 10))
                                .foregroundColor(Config.Colors.mute)
                            Text("\(count)명")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    }

                    if let lastSync = syncManager.lastSyncTime {
                        Divider().frame(height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("최근 전송")
                                .font(.system(size: 10))
                                .foregroundColor(Config.Colors.mute)
                            Text(Self.timeFormatter.string(from: lastSync))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(Config.Colors.ink)
                        }
                    }
                }
                .padding(8)
                .background(Config.Colors.panelBackground)
                .cornerRadius(6)

                HStack(spacing: 8) {
                    Button("지금 동기화 시도") {
                        syncManager.triggerSync()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderedProminent)

                    Button("큐 새로고침") {
                        syncManager.refreshQueueCount()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)

                    Button("큐 비우기") {
                        syncManager.clearQueue()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Config.Colors.cardBackground)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Config.Colors.line, lineWidth: 0.8))

            // 우측: 📥 연구 데이터 CSV 내보내기 허브
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                            .foregroundColor(.purple)
                        Text("연구 로그 CSV 내보내기")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Config.Colors.ink)
                    }
                    Spacer()
                    Text("SQLite 원본 데이터")
                        .font(.system(size: 10.5))
                        .foregroundColor(Config.Colors.mute)
                }

                HStack(spacing: 8) {
                    Button(action: {
                        let content = LocalDatabase.shared.exportActivityEventsToCSV()
                        saveCSVFile(filename: "activity_events.csv", content: content)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                            Text("활동 로그")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        let content = LocalDatabase.shared.exportSessionsToCSV()
                        saveCSVFile(filename: "sessions.csv", content: content)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right")
                            Text("세션 로그")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        let content = LocalDatabase.shared.exportSurveyResponsesToCSV()
                        saveCSVFile(filename: "survey_responses.csv", content: content)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                            Text("설문 응답")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: {
                    exportAllCSVToDownloads()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("전체 CSV 일괄 내보내기 (다운로드)")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.purple)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Config.Colors.cardBackground)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Config.Colors.line, lineWidth: 0.8))
        }
    }

    // MARK: - 설문 이벤트 로그 히스토리 테이블
    private var surveyEventTableView: some View {
        VStack(spacing: 0) {
            // 테이블 상단 바
            HStack {
                Text("설문 이벤트 로그 히스토리 (\(surveyLogStore.events.count)건)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Config.Colors.ink)

                Text("표시 시각, 응답 시각, 조치(응답·건너뛰기·미루기·무응답), 세션 ID 영구 기록")
                    .font(.system(size: 11))
                    .foregroundColor(Config.Colors.mute)

                Spacer()

                Button("기록 초기화") {
                    surveyLogStore.clearAll()
                }
                .font(.system(size: 11))
                .foregroundColor(.red)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Config.Colors.panelBackground)

            Divider()

            // 테이블 컬럼 헤더
            HStack(spacing: 12) {
                Text("표시 시각")
                    .frame(width: 80, alignment: .leading)
                Text("처리 시각")
                    .frame(width: 80, alignment: .leading)
                Text("소요 시간")
                    .frame(width: 65, alignment: .trailing)
                Text("종류")
                    .frame(width: 75, alignment: .leading)
                Text("조치 (Action)")
                    .frame(width: 110, alignment: .leading)
                Text("연계 AI 세션 및 도구")
                    .frame(minWidth: 180, alignment: .leading)
                Text("세션 ID")
                    .frame(width: 110, alignment: .leading)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Config.Colors.mute)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Config.Colors.paper)

            Divider()

            // 이벤트 리스트
            if surveyLogStore.events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 28))
                        .foregroundColor(Config.Colors.mute.opacity(0.4))
                    Text("아직 기록된 설문 이벤트가 없습니다.")
                        .font(.system(size: 12))
                        .foregroundColor(Config.Colors.mute)
                    Text("상단의 강제 팝업 실행 버튼을 눌러 동작을 검증해 보세요.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(surveyLogStore.events) { event in
                            surveyEventRow(event: event)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func surveyEventRow(event: SurveyEvent) -> some View {
        HStack(spacing: 12) {
            Text(Self.timeFormatter.string(from: event.shownAt))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Config.Colors.ink)
                .frame(width: 80, alignment: .leading)

            Text(Self.timeFormatter.string(from: event.respondedAt))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Config.Colors.ink)
                .frame(width: 80, alignment: .leading)

            Text(String(format: "%.1fs", event.durationToRespond))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .trailing)

            // 종류 배지
            Text(event.surveyType.badgeLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(hex: event.surveyType.badgeColorHex))
                .cornerRadius(4)
                .frame(width: 75, alignment: .leading)

            // 조치 배지
            surveyActionBadge(event.action)
                .frame(width: 110, alignment: .leading)

            // 세션 및 도구
            VStack(alignment: .leading, spacing: 1) {
                if let tool = event.aiTool {
                    Text(tool)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Config.Colors.ink)
                }
                Text(event.sessionTitle ?? "(세션 없음)")
                    .font(.system(size: 10.5))
                    .foregroundColor(Config.Colors.mute)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, alignment: .leading)

            // 세션 UUID
            Text(event.sessionId?.uuidString.prefix(8) ?? "-")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func surveyActionBadge(_ action: SurveyAction) -> some View {
        let (color, bg): (Color, Color) = {
            switch action {
            case .response:
                return (.green, Color.green.opacity(0.12))
            case .skip:
                return (.secondary, Color.gray.opacity(0.12))
            case .snooze:
                return (.orange, Color.orange.opacity(0.12))
            case .noResponse:
                return (.red, Color.red.opacity(0.12))
            }
        }()

        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(action.koreanLabel)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(bg)
        .cornerRadius(4)
    }

    private var cooldownRemainingSeconds: TimeInterval {
        guard let lastEnd = surveyScheduler.lastEndPopupShownAt else { return 0 }
        let elapsed = Date().timeIntervalSince(lastEnd)
        return max(0, Config.Scheduler.minPopupCooldown - elapsed)
    }

    private var cooldownStatusString: String {
        let remaining = cooldownRemainingSeconds
        if remaining > 0 {
            let m = Int(remaining) / 60
            let s = Int(remaining) % 60
            return "세션 간 쿨다운: \(m)분 \(s)초 남음"
        } else {
            return "세션 간 쿨다운: 완료 (시작 팝업 가능)"
        }
    }

    private func testTriggerWithRules(type: SurveyType) {
        let result = surveyScheduler.canShowPopup(type: type, force: false)
        if result.allowed {
            lastRuleCheckMessage = "규칙 통과: 팝업 표시됨"
            _ = surveyScheduler.requestSurvey(type: type, force: false)
        } else {
            lastRuleCheckMessage = "규칙 차단: \(result.reason ?? "거부됨")"
        }
    }

    // MARK: - CSV 파일 저장 헬퍼
    private func saveCSVFile(filename: String, content: String) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private func exportAllCSVToDownloads() {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let folder = downloads.appendingPathComponent("AIFatigue_Logs_\(timestamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let actCSV = LocalDatabase.shared.exportActivityEventsToCSV()
        let sessCSV = LocalDatabase.shared.exportSessionsToCSV()
        let survCSV = LocalDatabase.shared.exportSurveyResponsesToCSV()

        let actURL = folder.appendingPathComponent("activity_events.csv")
        let sessURL = folder.appendingPathComponent("sessions.csv")
        let survURL = folder.appendingPathComponent("survey_responses.csv")

        try? actCSV.write(to: actURL, atomically: true, encoding: .utf8)
        try? sessCSV.write(to: sessURL, atomically: true, encoding: .utf8)
        try? survCSV.write(to: survURL, atomically: true, encoding: .utf8)

        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
