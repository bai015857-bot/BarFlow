import Foundation
import ApplicationServices

/// 真实CGEvent到纯策略的唯一入口；测试不安装监听、不发送全局事件。
final class SideButtonEventProcessor {
    private var policy = SideButtonPolicy()
    var configuration = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: nil)
    var preferences: SideButtonPreferences { policy.preferences }
    var hasConsumedPairs: Bool { policy.hasConsumedPairs }
    func apply(_ preferences: SideButtonPreferences) { policy.preferences = preferences }
    func reset() { policy.reset() }
    func process(type: CGEventType, event: CGEvent, now: TimeInterval,
                 builder: (SideButtonShortcut) -> [CGEvent]? = { SideButtonKeyboardBuilder.build($0) },
                 poster: ([CGEvent]) -> Bool) -> Bool {
        guard type == event.type else { return false }
        let kind: SideButtonInput.Kind
        switch type {
        case .otherMouseDown: kind = .down
        case .otherMouseUp: kind = .up
        case .otherMouseDragged: kind = .dragged
        default: return false
        }
        let input = SideButtonInput(kind: kind,
            button: event.getIntegerValueField(.mouseEventButtonNumber), modifiers: event.flags.rawValue,
            sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID),
            sourceState: event.getIntegerValueField(.eventSourceStateID),
            sourceTag: event.getIntegerValueField(.eventSourceUserData))
        let configuration = self.configuration
        return policy.process(input, now: now) { direction in
            guard configuration.isAvailable,
                  let shortcut = direction == .left ? configuration.left : configuration.right,
                  let sequence = builder(shortcut) else { return false }
            return poster(sequence)
        }
    }
}
