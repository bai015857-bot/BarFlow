import Foundation

struct SideButtonPreferences: Codable, Equatable {
    var enabled = false
    var swapDirections = false
}

enum SideButtonDirection: Equatable { case left, right }

struct SideButtonInput {
    enum Kind { case down, up, dragged, other }
    var kind: Kind
    var button: Int64
    var modifiers: UInt64
    var sourcePID: Int64
    var sourceState: Int64
    var sourceTag: Int64
}

struct SideButtonPolicy {
    var preferences = SideButtonPreferences()
    // 每个侧键只保留一项，避免重复按下和失败后的半对事件。
    private var pairs: [Int64: Bool] = [:]
    private var lastSent: TimeInterval?
    static let throttleInterval: TimeInterval = 0.250
    static let clickModifierMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)

    var hasConsumedPairs: Bool { pairs.values.contains(true) }
    mutating func reset() { pairs.removeAll(); lastSent = nil }

    /// true 表示消费事件；发送器必须同步完成，false 不可有已发送的半对键盘副作用。
    mutating func process(_ input: SideButtonInput, now: TimeInterval,
                          send: (SideButtonDirection) -> Bool) -> Bool {
        guard input.button == 3 || input.button == 4,
              input.sourcePID == 0, input.sourceTag == 0,
              input.sourceState == 0 || input.sourceState == 1 else { return false }
        switch input.kind {
        case .up:
            return pairs.removeValue(forKey: input.button) ?? false
        case .dragged:
            return pairs[input.button] ?? false
        case .other:
            return false
        case .down:
            if let consumed = pairs[input.button] { return consumed }
            guard preferences.enabled, input.modifiers & Self.clickModifierMask == 0, now.isFinite else {
                pairs[input.button] = false
                return false
            }
            // 已成功消费的点击在节流窗口内整对丢弃，绝不漏出孤立抬起。
            if let last = lastSent, now < last + Self.throttleInterval {
                pairs[input.button] = true
                return true
            }
            let left = (input.button == 3) != preferences.swapDirections
            let consumed = send(left ? .left : .right)
            pairs[input.button] = consumed
            if consumed { lastSent = now }
            return consumed
        }
    }
}
