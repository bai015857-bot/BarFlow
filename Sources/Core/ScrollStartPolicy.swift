enum ScrollStartDecision: Equatable {
    case disabled
    case conflict
    case needsAccessibility
    case allowed
}

enum ScrollStartPolicy {
    static func evaluate(_ preferences: ScrollPreferences, accessibilityTrusted: Bool,
                         scrollReverserRunning: Bool) -> ScrollStartDecision {
        guard preferences.enabled else { return .disabled }
        guard !scrollReverserRunning else { return .conflict }
        guard accessibilityTrusted else { return .needsAccessibility }
        return .allowed
    }
}
