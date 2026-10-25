import Foundation
import Carbon
import AppKit

/// 전역 단축키(Global HotKey) 등록 및 처리 관리자 (Carbon EventHotKey 기반)
/// - 외부 의존성 없이 macOS 전역 단축키 ⌥⌘S (Option + Command + S) 감지
public final class HotKeyManager {
    public static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var triggerAction: (() -> Void)?

    private init() {}

    /// 전역 단축키 ⌥⌘S 등록
    public func register(onTrigger: @escaping () -> Void) {
        unregister()
        self.triggerAction = onTrigger

        // Carbon EventHotKeyID: 'AIFT', ID: 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x41494654), id: 1)
        // macOS 가상 키코드: S = 0x01 (kVK_ANSI_S), modifiers: cmdKey | optionKey
        let keyCode: UInt32 = 0x01
        let modifiers: UInt32 = UInt32(cmdKey | optionKey)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            print("[HotKeyManager] 전역 핫키 등록 실패: OSStatus \(status)")
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                DispatchQueue.main.async {
                    HotKeyManager.shared.triggerAction?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        print("[HotKeyManager] 전역 핫키 ⌥⌘S (Option + Command + S) 등록 완료")
    }

    /// 전역 단축키 등록 해제
    public func unregister() {
        if let hk = hotKeyRef {
            UnregisterEventHotKey(hk)
            hotKeyRef = nil
        }
        if let eh = eventHandler {
            RemoveEventHandler(eh)
            eventHandler = nil
        }
        triggerAction = nil
    }

    deinit {
        unregister()
    }
}
