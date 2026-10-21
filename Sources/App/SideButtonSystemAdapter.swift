import Foundation
import ApplicationServices

enum SideButtonSystemAdapter {
    static var eventMask: CGEventMask {
        [CGEventType.otherMouseDown, .otherMouseUp, .otherMouseDragged].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
    }
    static func readShortcutConfiguration(reader: () -> Any? = {
        UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys")
    }) -> SideButtonShortcutConfiguration { .resolve(symbolicHotkeys: reader()) }
    static func post(_ events: [CGEvent], permissionCheck: () -> Bool = {
        AXIsProcessTrusted() && CGPreflightPostEventAccess()
    }, postEvent: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) -> Bool {
        guard (4...10).contains(events.count), events.count.isMultiple(of: 2) else { return false }
        let down = events[events.count / 2 - 1]
        let keyCode = down.getIntegerValueField(.keyboardEventKeycode)
        // 只剥离生成器针对左右箭头添加的平台导航标志，再重建完整序列逐项验证。
        let shortcutFlags = (keyCode == 123 || keyCode == 124) ? down.flags.subtracting(.maskSecondaryFn) : down.flags
        guard down.type == .keyDown, (0...126).contains(keyCode),
              let expected = SideButtonKeyboardBuilder.build(SideButtonShortcut(keyCode: CGKeyCode(keyCode), flags: shortcutFlags)),
              expected.count == events.count else { return false }
        for (event, reference) in zip(events, expected) {
            let state = event.getIntegerValueField(.eventSourceStateID)
            guard event.type == reference.type, event.flags == reference.flags,
                  event.getIntegerValueField(.keyboardEventKeycode) == reference.getIntegerValueField(.keyboardEventKeycode),
                  event.getIntegerValueField(.eventSourceUserData) == SideButtonKeyboardBuilder.sourceTag,
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                  state != 0, state != 1 else { return false }
        }
        guard permissionCheck() else { return false }
        // CGEvent.post 没有返回值：true仅代表通过预检并同步提交完整序列，
        // 不等于WindowServer或Mission Control确认切换成功。中途不重复权限检查，避免漏发释放。
        for event in events { postEvent(event) }
        return true
    }
}
