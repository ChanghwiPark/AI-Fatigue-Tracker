import Foundation
import ServiceManagement

/// macOS 13+ ServiceManagement API를 사용하여 로그인 시 자동 실행을 제어합니다.
public final class LaunchAtLoginService {
    public static let shared = LaunchAtLoginService()

    private init() {}

    /// 현재 로그인 시 자동 실행 활성화 여부
    public var isEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }

    /// 자동 실행 등록 또는 해제
    @discardableResult
    public func setEnabled(_ enable: Bool) -> Bool {
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            print("[LaunchAtLoginService] Failed to set launch at login: \(error.localizedDescription)")
            return false
        }
    }
}
