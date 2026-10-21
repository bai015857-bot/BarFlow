import ApplicationServices

enum ScrollTapAction: Equatable {
    case none
    case reenable
    case stop
}

final class ScrollEventProcessor {
    var preferences = ScrollPreferences()
    var lifecycle = ScrollTapLifecycle()

    func process(type: CGEventType, event: CGEvent) -> ScrollTapAction {
        // Disabled notifications are control messages, never NSEvents.
        if type == .tapDisabledByTimeout {
            return lifecycle.timeout() ? .reenable : .none
        }
        if type == .tapDisabledByUserInput {
            return lifecycle.stop() ? .stop : .none
        }
        guard lifecycle.isRunning, type == .scrollWheel else { return .none }
        ScrollEventTransformer.transform(event, preferences: preferences,
                                         device: ScrollSourceClassifier.device(for: event))
        return .none
    }
}
