import ApplicationServices

enum ScrollEventTransformer {
    // Observed CGEvent storage: line Int16, point Int32; accessors use Int64.
    // Saturation keeps minimum values from wrapping back to the same direction.
    static func reversedCGInteger(_ value: Int64, minimum: Int64 = Int64(Int32.min),
                                  maximum: Int64 = Int64(Int32.max)) -> Int64 {
        let reversed = value == Int64.min ? Int64.max : -value
        return min(maximum, max(minimum, reversed))
    }

    private static func reverse(_ event: CGEvent, line: CGEventField,
                                fixed: CGEventField, point: CGEventField) {
        let lineValue = event.getIntegerValueField(line)
        let fixedValue = event.getDoubleValueField(fixed)
        let pointValue = event.getIntegerValueField(point)
        // Setting line delta rewrites the other representations internally.
        event.setIntegerValueField(line, value: reversedCGInteger(lineValue,
                                    minimum: Int64(Int16.min), maximum: Int64(Int16.max)))
        event.setDoubleValueField(fixed, value: -fixedValue)
        event.setIntegerValueField(point, value: reversedCGInteger(pointValue))
    }

    static func transform(_ event: CGEvent, preferences: ScrollPreferences, device: ScrollDevice) {
        guard preferences.enabled else { return }
        if preferences.ignoreSynthetic {
            let hasProcess = event.getIntegerValueField(.eventSourceUnixProcessID) != 0
            let hasTag = event.getIntegerValueField(.eventSourceUserData) != 0
            let sourceState = event.getIntegerValueField(.eventSourceStateID)
            // A private source receives a distinct positive state ID, rather
            // than returning the .privateState creation sentinel (-1).
            let privateSource = sourceState != Int64(CGEventSourceStateID.combinedSessionState.rawValue)
                && sourceState != Int64(CGEventSourceStateID.hidSystemState.rawValue)
            guard !hasProcess, !hasTag, !privateSource else { return }
        }
        switch device {
        case .mouse: guard preferences.reverseMouse else { return }
        case .trackpad: guard preferences.reverseTrackpad else { return }
        case .unknown: return
        }
        if preferences.reverseVertical {
            reverse(event, line: .scrollWheelEventDeltaAxis1,
                    fixed: .scrollWheelEventFixedPtDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1)
        }
        if preferences.reverseHorizontal {
            reverse(event, line: .scrollWheelEventDeltaAxis2,
                    fixed: .scrollWheelEventFixedPtDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2)
        }
    }
}
