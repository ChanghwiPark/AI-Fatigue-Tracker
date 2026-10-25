import Foundation
import AppKit

/// 참여자 맞춤형 커스텀 AI 감지 대상 관리자
/// - 연구팀 기본 감지 목록(ChatGPT, Claude, Cursor 등)에 포함되지 않은 사내 AI 포털, 특수 웹 AI, 자체 개발 AI 앱 등을 사용자가 직접 등록 가능
/// - 등록된 도메인 및 앱은 실시간으로 AI 활동(is_ai = true) 및 AI 대화 세션 감지 대상에 즉시 반영됨
public final class CustomAITargetManager: ObservableObject {
    public static let shared = CustomAITargetManager()

    public struct CustomTargetItem: Identifiable, Codable, Hashable {
        public let id: UUID
        public let value: String       // 도메인 (예: "ai.mycompany.com") 또는 앱 번들 ID / 앱 이름 키워드
        public let displayName: String // 사람이 읽기 편한 도구 명칭 (예: "사내 AI 어시스턴트")
        public let targetType: TargetType
        public let addedAt: Date

        public enum TargetType: String, Codable {
            case webDomain = "웹 도메인"
            case desktopApp = "데스크톱 앱"
        }

        public init(
            id: UUID = UUID(),
            value: String,
            displayName: String,
            targetType: TargetType,
            addedAt: Date = Date()
        ) {
            self.id = id
            self.value = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            self.displayName = trimmedName.isEmpty ? value : trimmedName
            self.targetType = targetType
            self.addedAt = addedAt
        }
    }

    private let customDomainsKey = "ai_fatigue_custom_ai_domains_v2"
    private let customAppsKey = "ai_fatigue_custom_ai_apps_v2"
    private let legacyCustomDomainsKey = "custom_ai_domains"

    @Published public private(set) var customDomains: [CustomTargetItem] = []
    @Published public private(set) var customApps: [CustomTargetItem] = []

    private init() {
        loadCustomTargets()
        if CommandLine.arguments.contains("--test-sample-custom-targets") && customDomains.isEmpty && customApps.isEmpty {
            addCustomDomain("ai.company.internal", displayName: "사내 지식검색 AI 포털")
            addCustomApp(bundleIdOrName: "com.company.copilot", displayName: "사내 코딩 AI 어시스턴트")
        }
    }

    // MARK: - 1. 웹 도메인 추가 및 삭제
    public func addCustomDomain(_ domainOrUrl: String, displayName: String) {
        var trimmed = domainOrUrl.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("https://") { trimmed = String(trimmed.dropFirst(8)) }
        if trimmed.hasPrefix("http://") { trimmed = String(trimmed.dropFirst(7)) }
        if let slashIdx = trimmed.firstIndex(of: "/") {
            trimmed = String(trimmed[..<slashIdx])
        }
        guard !trimmed.isEmpty else { return }
        guard !customDomains.contains(where: { $0.value == trimmed }) else { return }

        let item = CustomTargetItem(
            value: trimmed,
            displayName: displayName.isEmpty ? trimmed : displayName,
            targetType: .webDomain
        )
        customDomains.append(item)
        saveCustomTargets()
        print("[CustomAITargetManager] 새 커스텀 AI 도메인 등록: \(trimmed) (\(item.displayName))")
    }

    public func removeCustomDomain(id: UUID) {
        customDomains.removeAll(where: { $0.id == id })
        saveCustomTargets()
    }

    // MARK: - 2. 데스크톱 앱 추가 및 삭제
    public func addCustomApp(bundleIdOrName: String, displayName: String) {
        let trimmedVal = bundleIdOrName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVal.isEmpty else { return }
        guard !customApps.contains(where: { $0.value == trimmedVal }) else { return }

        let item = CustomTargetItem(
            value: trimmedVal,
            displayName: displayName.isEmpty ? bundleIdOrName : displayName,
            targetType: .desktopApp
        )
        customApps.append(item)
        saveCustomTargets()
        print("[CustomAITargetManager] 새 커스텀 AI 앱 등록: \(trimmedVal) (\(item.displayName))")
    }

    public func removeCustomApp(id: UUID) {
        customApps.removeAll(where: { $0.id == id })
        saveCustomTargets()
    }

    // MARK: - 3. 판별 로직 (ActivityDetector 및 BrowserTracker에서 호출)
    /// 웹 도메인 또는 URL이 커스텀 등록된 AI 대상인지 검사
    public func isCustomAIDomain(urlOrHost: String) -> (isMatch: Bool, toolName: String?) {
        var host = urlOrHost.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("https://") { host = String(host.dropFirst(8)) }
        if host.hasPrefix("http://") { host = String(host.dropFirst(7)) }
        if let slashIdx = host.firstIndex(of: "/") {
            host = String(host[..<slashIdx])
        }

        for target in customDomains {
            let val = target.value
            if host == val || host.hasSuffix("." + val) || host.contains(val) {
                return (true, target.displayName)
            }
        }
        return (false, nil)
    }

    /// 데스크톱 앱 (Bundle ID, 앱 이름, 창 제목)이 커스텀 등록된 AI 대상인지 검사
    public func isCustomAITarget(bundleId: String, appName: String, windowTitle: String = "") -> (isMatch: Bool, toolName: String?) {
        let bLower = bundleId.lowercased()
        let aLower = appName.lowercased()
        let wLower = windowTitle.lowercased()

        for target in customApps {
            let val = target.value
            if bLower.contains(val) || val.contains(bLower) || aLower.contains(val) || val.contains(aLower) || (!wLower.isEmpty && wLower.contains(val)) {
                return (true, target.displayName)
            }
        }
        return (false, nil)
    }

    // MARK: - 4. 영구 저장 및 복원
    private func saveCustomTargets() {
        if let domData = try? JSONEncoder().encode(customDomains) {
            UserDefaults.standard.set(domData, forKey: customDomainsKey)
        }
        if let appData = try? JSONEncoder().encode(customApps) {
            UserDefaults.standard.set(appData, forKey: customAppsKey)
        }

        // 기존 legacy string array와도 동기화 유지
        let domainStrings = customDomains.map { $0.value }
        UserDefaults.standard.set(domainStrings, forKey: legacyCustomDomainsKey)
    }

    private func loadCustomTargets() {
        if let domData = UserDefaults.standard.data(forKey: customDomainsKey),
           let decoded = try? JSONDecoder().decode([CustomTargetItem].self, from: domData) {
            self.customDomains = decoded
        } else if let legacyDomains = UserDefaults.standard.stringArray(forKey: legacyCustomDomainsKey) {
            // legacy 마이그레이션
            self.customDomains = legacyDomains.map {
                CustomTargetItem(value: $0, displayName: $0, targetType: .webDomain)
            }
        }

        if let appData = UserDefaults.standard.data(forKey: customAppsKey),
           let decoded = try? JSONDecoder().decode([CustomTargetItem].self, from: appData) {
            self.customApps = decoded
        }
    }
}
