import ApplicationServices

enum ScrollSourceClassifier {
    static func device(for event: CGEvent) -> ScrollDevice {
        // Public scroll fields do not identify the physical device. Continuous
        // scroll can come from either a Magic Mouse or a trackpad. Momentum is
        // a phase, never evidence of a different device.
        return event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 ? .mouse : .unknown
    }
}
