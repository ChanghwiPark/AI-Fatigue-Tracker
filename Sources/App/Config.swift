import SwiftUI
import AppKit

// MARK: - Global Configuration & Research Parameters
/// 연구 파일럿 및 본 실험에 필요한 모든 수치, 타이머, 임계값, 색상, 감지 대상을 한 곳에서 관리합니다.
public enum Config {

    // MARK: - 연구 메타 정보
    public enum Study {
        /// 총 연구 기간 (일 단위)
        public static let totalDays: Int = 14
        /// 목표 참여자 수
        public static let targetParticipants: Int = 15
        /// 연구 프로젝트 명
        public static let projectName: String = "AI Fatigue Tracker"
    }

    // MARK: - 디자인 및 테마 토큰 (mockup.html 기준)
    public enum Colors {
        /// 강조색 (주황) - 버튼, 주요 알림, 트레이 점
        public static let accentHex: String = "#E0522A"
        /// 보조색 (세이지 그린) - 유용성 선택, 보조 바
        public static let sageHex: String = "#5D7A63"
        /// 종이 질감 기본 배경색
        public static let paperHex: String = "#F3EFE6"
        /// 어두운 텍스트/잉크색
        public static let inkHex: String = "#1F1C17"
        /// 음소거된 설명 텍스트색
        public static let muteHex: String = "#6F675A"
        /// 테두리 선 색상
        public static let lineHex: String = "#D8D0C0"
        /// 강조 연한 배경색 (피로 6점 이상 hot 영역)
        public static let accentSoftHex: String = "#FBE3D8"
        /// 팝업 카드 배경색
        public static let popupBgHex: String = "#FCFAF6"

        // MARK: - 다크모드 대응 동적 컬러 (Dynamic Adaptive Colors)
        public static var paper: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#1A1816")
                    : NSColor(hex: paperHex)
            }))
        }

        public static var cardBackground: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#252320")
                    : NSColor.white
            }))
        }

        public static var panelBackground: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#201E1B")
                    : NSColor(hex: "#ECE7DE")
            }))
        }

        public static var ink: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#EDE8DF")
                    : NSColor(hex: inkHex)
            }))
        }

        public static var mute: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#9E9689")
                    : NSColor(hex: muteHex)
            }))
        }

        public static var line: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#38342F")
                    : NSColor(hex: lineHex)
            }))
        }

        public static var accentSoft: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#382218")
                    : NSColor(hex: accentSoftHex)
            }))
        }

        public static var popupBg: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#24221F")
                    : NSColor(hex: popupBgHex)
            }))
        }

        // MARK: - 피로 6점 이상 고피로 영역 테마 토큰 (다크모드/라이트모드 완벽 대응)
        public static var highFatigueBackground: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#301B17")
                    : NSColor(hex: "#FBE6DD")
            }))
        }

        public static var highFatigueBorder: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#5C2B22")
                    : NSColor(hex: "#F2C4B2")
            }))
        }

        public static var highFatigueTitle: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#F59D88")
                    : NSColor(hex: "#7A2E1E")
            }))
        }

        public static var highFatigueCardBg: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#3D201A")
                    : NSColor.white
            }))
        }

        public static var highFatigueCardBgUnselected: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#341B16")
                    : NSColor(hex: "#FFFFFF").withAlphaComponent(0.6)
            }))
        }

        public static var highFatigueInk: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#EDE8DF")
                    : NSColor(hex: "#1F1C17")
            }))
        }

        // MARK: - 유용성 4점 이상 고유용성 영역 테마 토큰 (다크모드/라이트모드 완벽 대응)
        public static var highUsefulnessBackground: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#1A251E")
                    : NSColor(hex: "#EFF4F0")
            }))
        }

        public static var highUsefulnessBorder: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#2C4032")
                    : NSColor(hex: "#C8D9CD")
            }))
        }

        public static var highUsefulnessTitle: Color {
            Color(NSColor(name: nil, dynamicProvider: { app in
                app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "#8FC29B")
                    : NSColor(hex: "#2E5838")
            }))
        }
    }

    // MARK: - 세션 감지 파라미터 (Detection)
    public enum Detection {
        /// 직전 세션 종료 후 신규 세션으로 인정하기 위한 최소 쿨다운 간격 (초 단위: 30분)
        public static let sessionCooldown: TimeInterval = 30 * 60

        /// AI 창이 비활성화되거나 종료된 후 세션 종료로 판정하는 유휴 시간 (초 단위: 10분)
        public static let inactivityThresholdForSessionEnd: TimeInterval = 10 * 60

        /// 창 제목 변경 폴링 및 하트비트 간격 (초 단위: 1초로 신속 감지)
        public static let windowPollingInterval: TimeInterval = 1.0

        /// 사용자 자리 비움(키보드/마우스 미입력) 판정 기준 (초 단위: 2분 기본, 모니터에서 동적 변경 가능)
        public static var idleThreshold: TimeInterval {
            get { ConfigManager.shared.idleThreshold }
            set { ConfigManager.shared.idleThreshold = newValue }
        }

        /// 브라우저 URL 저장 범위: "domain" (도메인만), "full" (쿼리 문자열을 뺀 전체 URL). 기본값: "full"
        public static let urlMode: String = "full"

        /// 웹 AI(claude.ai 등) 사용을 정식 AI 세션으로 판정할지 여부 (기본 false. false여도 이벤트에는 is_ai = true 표시)
        public static let countWebAIAsSession: Bool = false

        /// 감지 대상 AI 전용 데스크톱 앱 (Bundle ID -> 도구명)
        public static let aiDesktopApps: [String: String] = [
            "com.anthropic.claudefordesktop": "Claude",
            "com.anthropic.claude": "Claude",
            "com.openai.chat": "ChatGPT",
            "com.openai.ChatGPT": "ChatGPT",
            "com.openai.chat-macos": "ChatGPT",
            "com.openai.codex": "ChatGPT",
            "com.anysphere.cursor": "Cursor",
            "com.todesktop.230313mzl4w4u92": "Cursor",
            "cursor.app": "Cursor",
            "com.exafunction.windsurf": "Windsurf",
            "com.codeium.windsurf": "Windsurf",
            "com.google.antigravity-ide": "Antigravity",
            "com.google.antigravity": "Antigravity",
            "ai.elementlabs.lmstudio": "LM Studio",
            "ai.lmstudio.lmstudio": "LM Studio",
            "xyz.janhq.jan": "Jan",
            "jan.ai": "Jan",
            "ai.jan.jan": "Jan",
            "com.electron.ollama": "Ollama",
            "ai.ollama.ollama": "Ollama",
            "com.trae.app": "Trae",
            "com.trae.Trae": "Trae",
            "com.voideditor.void": "Void",
            "dev.zed.Zed": "Zed",
            "com.electron.cherry-studio": "Cherry Studio",
            "xyz.chatboxapp.chatbox": "Chatbox",
            "ai.perplexity.mac": "Perplexity",
            "com.perplexity.Perplexity": "Perplexity",
            "com.poe.Poe": "Poe"
        ]

        /// AI CLI 도구를 실행할 수 있는 터미널 앱 Bundle ID 목록
        public static let terminalBundleIDs: Set<String> = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Terminal",
            "com.mitchellh.ghostty",
            "com.github.wez.wezterm",
            "net.kovidgoyal.kitty",
            "io.alacritty"
        ]

        /// 프로세스 모니터링 대상 AI CLI 프로세스 키워드 (터미널 내부 실행 판별)
        public static let aiProcessKeywords: [String] = [
            "claude", "codex", "aider", "ollama", "gemini", "copilot", "interpreter", "sgpt", "agy",
            "antigravity", "cline", "roo", "goose", "cursor-agent", "plandex", "fabric", "gptscript",
            "mentat", "cody", "llm", "vllm", "copilot-agent", "copilot-language-server"
        ]

        /// 브라우저에서 AI 도구로 판별할 도메인 목록
        public static let aiWebDomains: [String] = [
            "claude.ai",
            "chatgpt.com",
            "chat.openai.com",
            "gemini.google.com",
            "perplexity.ai",
            "notebooklm.google.com",
            "copilot.microsoft.com",
            "deepseek.com",
            "bolt.new",
            "lovable.dev",
            "grok.com",
            "x.ai",
            "phind.com",
            "clova-x.naver.com",
            "wrtn.ai",
            "chat.mistral.ai",
            "poe.com",
            "groq.com",
            "v0.dev",
            "genspark.ai",
            "cursor.com",
            "cursor.directory",
            "monica.im",
            "sider.ai",
            "harpa.ai",
            "liner.ai"
        ]

        /// AppleScript 연동 지원 브라우저 목록 (Bundle ID -> AppleScript 앱 이름)
        public static let supportedBrowsers: [String: String] = [
            "com.apple.Safari": "Safari",
            "com.apple.SafariTechnologyPreview": "Safari Technology Preview",
            "com.google.Chrome": "Google Chrome",
            "com.google.Chrome.canary": "Google Chrome Canary",
            "org.chromium.Chromium": "Chromium",
            "company.thebrowser.Browser": "Arc",
            "company.thebrowser.arc": "Arc",
            "com.microsoft.edgemac": "Microsoft Edge",
            "com.brave.Browser": "Brave Browser",
            "com.operasoftware.Opera": "Opera",
            "com.operasoftware.OperaGX": "Opera GX",
            "com.vivaldi.Vivaldi": "Vivaldi",
            "com.vivaldi.Vivaldi.snapshot": "Vivaldi",
            "company.thebrowser.dia": "Dia",
            "sh.cortex.dia": "Dia",
            "com.electron.dia": "Dia",
            "com.naver.whale": "Whale"
        ]

        /// 프라이버시 보호를 위해 활동 로깅에서 완전히 제외할 앱 번들 ID
        public static let privacyExcludedBundleIDs: Set<String> = [
            "com.agilebits.onepassword",
            "com.apple.keychainaccess",
            "com.apple.Preferences",
            "com.apple.systempreferences"
        ]
    }

    // MARK: - 경험표집법(ESM) 스케줄러 파라미터 (Scheduler - ConfigManager 연동 동적 파라미터)
    public enum Scheduler {
        /// 중간 팝업(02) 최소 발생 대기 시간
        public static var midSurveyIntervalMin: TimeInterval {
            get { ConfigManager.shared.midSurveyIntervalMin }
            set { ConfigManager.shared.midSurveyIntervalMin = newValue }
        }

        /// 중간 팝업(02) 최대 발생 대기 시간
        public static var midSurveyIntervalMax: TimeInterval {
            get { ConfigManager.shared.midSurveyIntervalMax }
            set { ConfigManager.shared.midSurveyIntervalMax = newValue }
        }

        /// 세션 간 최소 쿨다운 간격 (종료 팝업 뒤 30분 동안 새 세션 시작 팝업 억제)
        public static var minPopupCooldown: TimeInterval {
            get { ConfigManager.shared.minPopupCooldown }
            set { ConfigManager.shared.minPopupCooldown = newValue }
        }

        /// "10분 뒤에" 버튼 클릭 시 스누즈 대기 시간
        public static var snoozeDuration: TimeInterval {
            get { ConfigManager.shared.snoozeDuration }
            set { ConfigManager.shared.snoozeDuration = newValue }
        }

        /// 팝업 무응답 시 자동으로 닫히는 시간
        public static var autoDismissDuration: TimeInterval {
            get { ConfigManager.shared.autoDismissDuration }
            set { ConfigManager.shared.autoDismissDuration = newValue }
        }

        /// 메뉴 막대 "1시간 동안 팝업 끄기" 지속 시간
        public static var muteDuration: TimeInterval {
            get { ConfigManager.shared.muteDuration }
            set { ConfigManager.shared.muteDuration = newValue }
        }

        /// 메뉴 막대 "15분 동안 기록 멈추기" 지속 시간 (15분 = 900초)
        public static let recordingPauseDuration: TimeInterval = 15 * 60

        /// 당일 자발적 기록이 0건일 때 데일리 넛지(07) 발송 시각
        public static var dailyNudgeHour: Int {
            get { ConfigManager.shared.dailyNudgeHour }
            set { ConfigManager.shared.dailyNudgeHour = newValue }
        }
        public static var dailyNudgeMinute: Int {
            get { ConfigManager.shared.dailyNudgeMinute }
            set { ConfigManager.shared.dailyNudgeMinute = newValue }
        }
    }

    // MARK: - 설문 분기 및 척도 기준
    public enum Survey {
        /// "어떤 점이 피곤하게 느껴졌나요?" 심층 질문이 펼쳐지는 피로도 점수 임계값 (0~10 척도 중)
        public static var highFatigueThreshold: Int {
            get { ConfigManager.shared.highFatigueThreshold }
            set { ConfigManager.shared.highFatigueThreshold = newValue }
        }

        /// "어떤 도움이 된다고 느꼈나요?" 후속 질문이 펼쳐지는 유용성 점수 임계값 (1~5 척도 중)
        public static var highUsefulnessThreshold: Int {
            get { ConfigManager.shared.highUsefulnessThreshold }
            set { ConfigManager.shared.highUsefulnessThreshold = newValue }
        }

        /// 팝업 기본 가로 폭 (pt)
        public static var popupDefaultWidth: CGFloat {
            get { ConfigManager.shared.popupWidth }
            set { ConfigManager.shared.popupWidth = newValue }
        }
        /// 중간 팝업 가로 폭 (pt)
        public static let popupMidWidth: CGFloat = 340.0
        /// 넛지/토스트 가로 폭 (pt)
        public static let popupToastWidth: CGFloat = 340.0
    }

    // MARK: - 백엔드 (Supabase) 연동 설정
    public enum SupabaseConfig {
        /// Supabase 프로젝트 URL
        public static let projectURL: String = "https://frnggrpcqvtyeofckdel.supabase.co"
        /// Supabase Anon 공개 키
        public static let anonKey: String = "sb_publishable_FWlVyxKrrrsl76gAirdpjQ_h1F-Y-Cu"
        /// 스크린샷 저장용 Storage 버킷 명 (비공개, 업로드 전용)
        public static let screenshotBucket: String = "captures"
        /// 로컬 오프라인 큐 동기화 시도 주기 (초 단위: 60초)
        public static let syncInterval: TimeInterval = 60.0
    }

    // MARK: - 개발자 및 디버그 모드 설정
    public enum DebugConfig {
        #if RELEASE_BUILD
        /// 릴리즈 배포 빌드(./build.sh --release): 디버그 모니터 메뉴가 기본 제외됩니다.
        /// (Option(⌥) 키를 누른 채 메뉴를 열면 연구자 히든 메뉴로 열람 가능)
        public static var showDebugMonitor: Bool = false
        public static let isReleaseBuild: Bool = true
        #else
        /// 일반 파일럿/개발 빌드(./build.sh): 디버그 모니터가 메뉴바에 항상 기본 표시됩니다.
        public static var showDebugMonitor: Bool = true
        public static let isReleaseBuild: Bool = false
        #endif
    }
}
