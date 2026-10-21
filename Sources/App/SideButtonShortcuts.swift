import Foundation
import ApplicationServices

struct SideButtonShortcut: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    var isSupported: Bool {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let allowed = modifiers.union(.maskNumericPad)
        // 公开HIToolbox键表：普通键、国际布局键、功能键及导航键；
        // 排除修饰键本身、音量/静音和未定义孔位，避免无效或副作用输入。
        let unsupported: Set<CGKeyCode> = [52, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
                                          66, 68, 70, 72, 73, 74, 77, 108, 112]
        return keyCode <= 126 && !unsupported.contains(keyCode)
            && !flags.intersection(modifiers).isEmpty && flags.subtracting(allowed).isEmpty
    }
}

struct SideButtonShortcutConfiguration {
    let left: SideButtonShortcut?
    let right: SideButtonShortcut?
    let unavailableReason: String?
    var isAvailable: Bool {
        guard let left = left, let right = right else { return false }
        return left.isSupported && right.isSupported && left != right && unavailableReason == nil
    }

    static func resolve(symbolicHotkeys: Any?) -> Self {
        let defaults = Self(left: SideButtonShortcut(keyCode: 123, flags: .maskControl),
                            right: SideButtonShortcut(keyCode: 124, flags: .maskControl),
                            unavailableReason: nil)
        guard let symbolicHotkeys = symbolicHotkeys else { return defaults }
        guard let domain = symbolicHotkeys as? [String: Any] else {
            return unavailable("桌面快捷键配置格式不受支持")
        }
        guard let raw = domain["AppleSymbolicHotKeys"] else { return defaults }
        guard let entries = raw as? [String: Any] else {
            return unavailable("桌面快捷键配置格式不受支持")
        }
        func shortcut(_ id: String, fallback: SideButtonShortcut) -> SideButtonShortcut? {
            guard let rawEntry = entries[id] else { return fallback }
            guard let entry = rawEntry as? [String: Any], let enabled = entry["enabled"] as? NSNumber,
                  enabled.doubleValue == 1 else { return nil }
            // 系统域是稀疏覆盖：只启用而未提供value时继承对应ID默认；显式坏值仍拒绝。
            guard let rawValue = entry["value"] else { return fallback }
            guard let value = rawValue as? [String: Any],
                  value["type"] as? String == "standard", let parameters = value["parameters"] as? [Any],
                  parameters.count == 3,
                  let character = integer(parameters[0]), character <= 65535,
                  let keyCode = integer(parameters[1]), keyCode <= 126,
                  let flags = integer(parameters[2]) else { return nil }
            let shortcut = SideButtonShortcut(keyCode: CGKeyCode(keyCode), flags: CGEventFlags(rawValue: flags))
            return shortcut.isSupported ? shortcut : nil
        }
        guard let left = shortcut("79", fallback: defaults.left!),
              let right = shortcut("81", fallback: defaults.right!) else {
            return unavailable("左右桌面快捷键已停用或配置不受支持，请检查系统设置中的键盘快捷键")
        }
        guard left != right else { return unavailable("左右桌面快捷键相同，请检查系统设置中的键盘快捷键") }
        return Self(left: left, right: right, unavailableReason: nil)
    }

    /// 只接受 plist 的非负整数；不悄悄截断浮点或把布尔当键码。
    private static func integer(_ value: Any) -> UInt64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue <= Double(UInt32.max),
              number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
        return number.uint64Value
    }

    private static func unavailable(_ reason: String) -> Self {
        Self(left: nil, right: nil, unavailableReason: reason)
    }
}
