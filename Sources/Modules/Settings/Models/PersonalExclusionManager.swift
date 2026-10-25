import Foundation

/// 참여자 개인 및 연구팀 기본 제외 목록 관리자
/// - 연구팀 기본 목록(비밀번호 관리자, 은행/금융, 시스템 환경설정 등)은 영구 보존(삭제 불가)
/// - 참여자가 업무/사생활 보호를 위해 기록을 원치 않는 앱 및 사이트(도메인)를 직접 추가/삭제 가능
public final class PersonalExclusionManager: ObservableObject {
    public static let shared = PersonalExclusionManager()

    public struct ExclusionItem: Identifiable, Codable, Hashable {
        public let id: UUID
        public let value: String       // 번들 ID 또는 도메인/키워드
        public let displayName: String // 사람이 읽을 수 있는 이름
        public let isBuiltIn: Bool     // 연구팀 기본 항목 여부 (true면 삭제 불가)
        public let addedAt: Date

        public init(id: UUID = UUID(), value: String, displayName: String, isBuiltIn: Bool = false, addedAt: Date = Date()) {
            self.id = id
            self.value = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            self.displayName = displayName
            self.isBuiltIn = isBuiltIn
            self.addedAt = addedAt
        }
    }

    private let userAppsKey = "ai_fatigue_personal_excluded_apps"
    private let userDomainsKey = "ai_fatigue_personal_excluded_domains"

    // MARK: - 연구팀 기본 제외 목록 (삭제 불가)
    public let builtInApps: [ExclusionItem] = [
        ExclusionItem(value: "com.apple.systempreferences", displayName: "시스템 설정", isBuiltIn: true),
        ExclusionItem(value: "com.apple.Preferences", displayName: "시스템 환경설정", isBuiltIn: true),
        ExclusionItem(value: "com.apple.keychainaccess", displayName: "키체인 접근", isBuiltIn: true),
        ExclusionItem(value: "com.agilebits.onepassword", displayName: "1Password", isBuiltIn: true),
        ExclusionItem(value: "com.agilebits.onepassword7", displayName: "1Password 7", isBuiltIn: true),
        ExclusionItem(value: "com.1password.1password", displayName: "1Password 8", isBuiltIn: true),
        ExclusionItem(value: "com.bitwarden.desktop", displayName: "Bitwarden", isBuiltIn: true)
    ]

    public let builtInDomains: [ExclusionItem] = [
        ExclusionItem(value: "kbstar.com", displayName: "국민은행 (금융)", isBuiltIn: true),
        ExclusionItem(value: "shinhan.com", displayName: "신한은행 (금융)", isBuiltIn: true),
        ExclusionItem(value: "wooribank.com", displayName: "우리은행 (금융)", isBuiltIn: true),
        ExclusionItem(value: "hanafn.com", displayName: "하나은행 (금융)", isBuiltIn: true),
        ExclusionItem(value: "kakaobank.com", displayName: "카카오뱅크 (금융)", isBuiltIn: true),
        ExclusionItem(value: "toss.im", displayName: "토스 (금융)", isBuiltIn: true),
        ExclusionItem(value: "accounts.google.com", displayName: "Google 계정 로그인", isBuiltIn: true),
        ExclusionItem(value: "appleid.apple.com", displayName: "Apple ID 로그인", isBuiltIn: true)
    ]

    // MARK: - 참여자 직접 추가 목록
    @Published public private(set) var customApps: [ExclusionItem] = []
    @Published public private(set) var customDomains: [ExclusionItem] = []

    private init() {
        loadCustomExclusions()
    }

    // MARK: - 전체 합산 목록 (표시용)
    public var allApps: [ExclusionItem] {
        builtInApps + customApps
    }

    public var allDomains: [ExclusionItem] {
        builtInDomains + customDomains
    }

    // MARK: - 앱 제외 추가 및 삭제
    public func addCustomApp(bundleId: String, displayName: String) {
        let trimmedVal = bundleId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVal.isEmpty else { return }
        guard !allApps.contains(where: { $0.value == trimmedVal }) else { return }

        let item = ExclusionItem(
            value: trimmedVal,
            displayName: displayName.isEmpty ? trimmedVal : displayName,
            isBuiltIn: false
        )
        customApps.append(item)
        saveCustomExclusions()
    }

    public func removeCustomApp(id: UUID) {
        customApps.removeAll(where: { $0.id == id && !$0.isBuiltIn })
        saveCustomExclusions()
    }

    // MARK: - 도메인/사이트 제외 추가 및 삭제
    public func addCustomDomain(_ domain: String, displayName: String? = nil) {
        var trimmed = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // http, https 등 접두어 제거
        if trimmed.hasPrefix("https://") { trimmed = String(trimmed.dropFirst(8)) }
        if trimmed.hasPrefix("http://") { trimmed = String(trimmed.dropFirst(7)) }
        if let slashIdx = trimmed.firstIndex(of: "/") {
            trimmed = String(trimmed[..<slashIdx])
        }
        guard !trimmed.isEmpty else { return }
        guard !allDomains.contains(where: { $0.value == trimmed }) else { return }

        let disp = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = ExclusionItem(
            value: trimmed,
            displayName: (disp != nil && !disp!.isEmpty) ? disp! : trimmed,
            isBuiltIn: false
        )
        customDomains.append(item)
        saveCustomExclusions()
    }

    public func removeCustomDomain(id: UUID) {
        customDomains.removeAll(where: { $0.id == id && !$0.isBuiltIn })
        saveCustomExclusions()
    }

    // MARK: - 검사 로직 (ActivityDetector에서 실시간 호출)
    public func isExcluded(bundleId: String, domain: String? = nil, url: String? = nil) -> Bool {
        let bLower = bundleId.lowercased()

        // 1. 앱 번들 ID 검사
        if builtInApps.contains(where: { bLower.contains($0.value) }) {
            return true
        }
        if customApps.contains(where: { bLower.contains($0.value) }) {
            return true
        }

        // 2. 도메인 및 URL 검사
        let targetHost = (domain ?? (url.flatMap { URL(string: $0)?.host }))?.lowercased()
        if let host = targetHost {
            for item in builtInDomains {
                if host.contains(item.value) { return true }
            }
            for item in customDomains {
                if host.contains(item.value) { return true }
            }
        }

        return false
    }

    // MARK: - 영구 저장 및 복원
    private func saveCustomExclusions() {
        if let appData = try? JSONEncoder().encode(customApps) {
            UserDefaults.standard.set(appData, forKey: userAppsKey)
        }
        if let domData = try? JSONEncoder().encode(customDomains) {
            UserDefaults.standard.set(domData, forKey: userDomainsKey)
        }
    }

    private func loadCustomExclusions() {
        if let appData = UserDefaults.standard.data(forKey: userAppsKey),
           let decoded = try? JSONDecoder().decode([ExclusionItem].self, from: appData) {
            self.customApps = decoded
        }
        if let domData = UserDefaults.standard.data(forKey: userDomainsKey),
           let decoded = try? JSONDecoder().decode([ExclusionItem].self, from: domData) {
            self.customDomains = decoded
        }
    }
}
