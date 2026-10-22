import AppKit

enum MenuStatusClickAction: Equatable {
    case toggle
    case quickMenu
    case settings

    static func resolve(eventType: NSEvent.EventType?, menuEnabled: Bool) -> MenuStatusClickAction {
        if eventType == .rightMouseUp { return .quickMenu }
        return menuEnabled ? .toggle : .settings
    }
}
