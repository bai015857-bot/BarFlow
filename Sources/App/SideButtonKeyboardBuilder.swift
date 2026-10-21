import ApplicationServices

/// 完整构造后才允许交给同步的批量发送器。
enum SideButtonKeyboardBuilder {
    static let sourceTag: Int64 = 0x424653494445
    typealias Factory = (CGEventSource, CGKeyCode, Bool) -> CGEvent?
    static func build(_ shortcut: SideButtonShortcut,
                      factory: Factory = { CGEvent(keyboardEventSource: $0, virtualKey: $1, keyDown: $2) }) -> [CGEvent]? {
        guard shortcut.isSupported, let source = CGEventSource(stateID: .privateState) else { return nil }
        let modifiers: [(CGEventFlags, CGKeyCode)] = [(.maskControl, 59), (.maskAlternate, 58),
                                                    (.maskShift, 56), (.maskCommand, 55)]
        let selected = modifiers.filter { shortcut.flags.contains($0.0) }
        var events: [CGEvent] = []
        var active: CGEventFlags = []
        func append(key: CGKeyCode, down: Bool, flags: CGEventFlags, modifier: Bool = false) -> Bool {
            guard let event = factory(source, key, down) else { return false }
            event.type = modifier ? .flagsChanged : (down ? .keyDown : .keyUp)
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            event.setIntegerValueField(.eventSourceUserData, value: sourceTag)
            // 即使注入工厂返回了错误对象，也不能把部分序列交给发送器。
            guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(key),
                  event.flags == flags,
                  event.getIntegerValueField(.eventSourceUserData) == sourceTag else { return false }
            events.append(event)
            return true
        }
        for (flag, key) in selected {
            active.insert(flag)
            guard append(key: key, down: true, flags: active, modifier: true) else { return nil }
        }
        // macOS桌面切换需将左右方向键标记为Fn导航事件；不改用户保存的逻辑快捷键。
        let keyFlags: CGEventFlags = [123, 124].contains(shortcut.keyCode)
            ? shortcut.flags.union(.maskSecondaryFn) : shortcut.flags
        guard append(key: shortcut.keyCode, down: true, flags: keyFlags),
              append(key: shortcut.keyCode, down: false, flags: keyFlags) else { return nil }
        for (flag, key) in selected.reversed() {
            active.remove(flag)
            guard append(key: key, down: false, flags: active, modifier: true) else { return nil }
        }
        return events
    }
}
