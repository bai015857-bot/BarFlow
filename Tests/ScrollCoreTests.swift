import AppKit
import ApplicationServices
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw TestFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

private func wheel(vertical: Int32 = 3, horizontal: Int32 = 2) -> CGEvent {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                        wheel1: vertical, wheel2: horizontal, wheel3: 0)!
    event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
    return event
}

@main
struct ScrollCoreTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("interleaved gesture and continuous input never changes source", testInterleavedUnknownSources),
            ("disabled by default", testDefaultDisabled),
            ("mouse and trackpad preferences are separate", testDevicePreferences),
            ("vertical and horizontal axes are independent", testIndependentAxes),
            ("synthetic source filtering is optional", testSyntheticFiltering),
            ("line fixed and point deltas retain their own magnitude", testAllDeltaRepresentations),
            ("integer extrema saturate instead of wrapping", testIntegerExtrema),
            ("fixed point extrema saturate safely", testFixedPointExtrema),
            ("continuous sources stay unknown and momentum preserves classification", testClassification),
            ("tap timeout recovers but stop never resurrects a tap", testLifecycleRecovery),
            ("start policy blocks conflicts and permission failures", testStartPolicy),
            ("engine stays stopped and status updates are deduplicated", testEngineDefault),
            ("resource teardown removes and invalidates a real run loop source", testResourceTeardown),
            ("callback handles control messages before scroll transformation", testCallbackPipeline),
            ("engine reports denied permission without starting", testEnginePermissionDenied),
            ("engine refuses a running Scroll Reverser", testEngineConflict),
            ("failed tap creation stays stopped and reports a failure", testTapCreationFailure),
            ("tagged and private synthetic events are ignored", testTaggedSynthetic),
            ("diagnostics are JSON serializable and explain continuous input limits", testDiagnostics),
            ("disabled apply performs no permission or process lookup", testDisabledNoPreflight),
            ("momentum phase and inactive axis representations are preserved", testMetadataAndInactiveAxis),
            ("mouse vertical reversal", testMouseVerticalReversal)
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }
        print("\(tests.count - failures)/\(tests.count) scroll tests passed")
        if failures > 0 { exit(1) }
    }

    static func testInterleavedUnknownSources() throws {
        let processor = ScrollEventProcessor()
        processor.lifecycle.started()
        processor.preferences.enabled = true
        processor.preferences.reverseMouse = false
        processor.preferences.reverseTrackpad = true
        let gestureType = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!
        let gesture = CGEvent(source: nil)!
        for phase: Int64 in [0, 1, 2, 3, 0] {
            _ = processor.process(type: gestureType, event: gesture)
            let ambiguous = wheel()
            ambiguous.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            ambiguous.setIntegerValueField(.scrollWheelEventMomentumPhase, value: phase)
            _ = processor.process(type: .scrollWheel, event: ambiguous)
            try expect(ambiguous.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3,
                       "gesture timing must not identify another device or propagate momentum identity")
        }
    }

    static func testDefaultDisabled() throws {
        let preferences = ScrollPreferences()
        try expect(preferences.enabled, false, "default activation")
        try expect(preferences.reverseMouse, true, "default mouse preference")
        try expect(preferences.reverseTrackpad, false, "default trackpad preference")
        try expect(preferences.reverseVertical, true, "default vertical preference")
        try expect(preferences.reverseHorizontal, false, "default horizontal preference")
        try expect(preferences.ignoreSynthetic, true, "default synthetic preference")
        let restored = try JSONDecoder().decode(ScrollPreferences.self, from: JSONEncoder().encode(preferences))
        try expect(restored, preferences, "preferences Codable round trip")
        let event = wheel()
        ScrollEventTransformer.transform(event, preferences: preferences, device: .mouse)
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "disabled keeps input")
    }

    static func testDevicePreferences() throws {
        var preferences = ScrollPreferences()
        preferences.enabled = true
        preferences.reverseMouse = false
        preferences.reverseTrackpad = true
        let mouse = wheel()
        ScrollEventTransformer.transform(mouse, preferences: preferences, device: .mouse)
        try expect(mouse.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "mouse opt-out")
        let trackpad = wheel()
        ScrollEventTransformer.transform(trackpad, preferences: preferences, device: .trackpad)
        try expect(trackpad.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3, "trackpad opt-in")
        let unknown = wheel()
        ScrollEventTransformer.transform(unknown, preferences: preferences, device: .unknown)
        try expect(unknown.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "unknown stays untouched")
    }

    static func testIndependentAxes() throws {
        var preferences = ScrollPreferences()
        preferences.enabled = true
        preferences.reverseVertical = false
        preferences.reverseHorizontal = true
        let event = wheel()
        ScrollEventTransformer.transform(event, preferences: preferences, device: .mouse)
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "vertical opt-out")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), -2, "horizontal opt-in")
    }

    static func testSyntheticFiltering() throws {
        var preferences = ScrollPreferences()
        preferences.enabled = true
        let event = wheel()
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 12345)
        ScrollEventTransformer.transform(event, preferences: preferences, device: .mouse)
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "synthetic input ignored")
        preferences.ignoreSynthetic = false
        ScrollEventTransformer.transform(event, preferences: preferences, device: .mouse)
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3, "synthetic opt-in")
    }

    static func testAllDeltaRepresentations() throws {
        var preferences = ScrollPreferences()
        preferences.enabled = true
        preferences.reverseHorizontal = true
        let event = wheel()
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 1.25)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 17)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -2.5)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -23)
        ScrollEventTransformer.transform(event, preferences: preferences, device: .mouse)
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3, "vertical line")
        try expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -1.25, "vertical fixed")
        try expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -17, "vertical point")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), -2, "horizontal line")
        try expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), 2.5, "horizontal fixed")
        try expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 23, "horizontal point")
    }

    static func testIntegerExtrema() throws {
        var preferences = ScrollPreferences()
        preferences.enabled = true
        preferences.reverseHorizontal = true
        let event = wheel(vertical: Int32(Int16.min), horizontal: Int32(Int16.max))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(Int32.min))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(Int32.max))
        ScrollEventTransformer.transform(event, preferences: preferences, device: .mouse)
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), Int64(Int16.max), "minimum line saturation")
        try expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), Int64(Int32.max), "minimum point saturation")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), -Int64(Int16.max), "maximum line reversal")
        try expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -Int64(Int32.max), "maximum point reversal")
    }

    static func testFixedPointExtrema() throws {
        var preferences = ScrollPreferences()
        preferences.enabled = true
        let event = wheel()
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -32768)
        ScrollEventTransformer.transform(event, preferences: preferences, device: .mouse)
        try expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                   Double(Int32.max) / 65536.0, "fixed 16.16 minimum saturation")
        try expect(ScrollEventTransformer.reversedCGInteger(Int64.min), Int64(Int32.max), "malformed Int64 minimum")
    }

    static func testClassification() throws {
        let mouse = wheel()
        try expect(ScrollSourceClassifier.device(for: mouse), .mouse, "discrete wheel")
        mouse.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
        try expect(ScrollSourceClassifier.device(for: mouse), .mouse, "momentum does not imply trackpad")
        let continuous = wheel()
        continuous.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        try expect(ScrollSourceClassifier.device(for: continuous), .unknown, "Magic Mouse and trackpad ambiguous")
        for momentum: Int64 in [0, 1, 2, 3, 4] {
            continuous.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            try expect(ScrollSourceClassifier.device(for: continuous), .unknown, "momentum preserves unknown")
        }
        var preferences = ScrollPreferences()
        preferences.enabled = true
        preferences.reverseMouse = true
        preferences.reverseTrackpad = true
        ScrollEventTransformer.transform(continuous, preferences: preferences,
                                         device: ScrollSourceClassifier.device(for: continuous))
        try expect(continuous.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "ambiguous continuous event preserved")
    }

    static func testLifecycleRecovery() throws {
        var lifecycle = ScrollTapLifecycle()
        try expect(lifecycle.isRunning, false, "initial stopped")
        try expect(lifecycle.timeout(), false, "no recovery before start")
        lifecycle.started()
        try expect(lifecycle.isRunning, true, "started")
        try expect(lifecycle.timeout(), true, "running timeout requests recovery")
        try expect(lifecycle.timeout(), true, "repeated timeout still recovers")
        try expect(lifecycle.stop(), true, "first stop requests cleanup")
        try expect(lifecycle.isRunning, false, "stopped")
        try expect(lifecycle.timeout(), false, "late timeout cannot restart")
        try expect(lifecycle.stop(), false, "second stop is idempotent")
    }

    static func testStartPolicy() throws {
        var preferences = ScrollPreferences()
        try expect(ScrollStartPolicy.evaluate(preferences, accessibilityTrusted: true,
                                              scrollReverserRunning: false), .disabled, "default blocks tap creation")
        preferences.enabled = true
        try expect(ScrollStartPolicy.evaluate(preferences, accessibilityTrusted: false,
                                              scrollReverserRunning: false), .needsAccessibility, "permission denied")
        try expect(ScrollStartPolicy.evaluate(preferences, accessibilityTrusted: true,
                                              scrollReverserRunning: true), .conflict, "Scroll Reverser conflict")
        try expect(ScrollStartPolicy.evaluate(preferences, accessibilityTrusted: false,
                                              scrollReverserRunning: true), .conflict, "conflict shown before permission")
        try expect(ScrollStartPolicy.evaluate(preferences, accessibilityTrusted: true,
                                              scrollReverserRunning: false), .allowed, "preflight allowed")
    }

    static func testEngineDefault() throws {
        let engine = ScrollEngine()
        var changes: [String] = []
        engine.onStatusChange = { changes.append($0) }
        try expect(engine.isRunning, false, "engine initially stopped")
        try expect(engine.statusText, "已关闭", "initial status")
        engine.apply(ScrollPreferences())
        engine.stop()
        engine.stop()
        try expect(engine.isRunning, false, "disabled apply does not create a tap")
        try expect(changes.count, 0, "identical status should not emit callbacks")
    }

    static func testResourceTeardown() throws {
        var context = CFMachPortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        let port = CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, &context, nil)!
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)!
        let loop = CFRunLoopGetMain()!
        CFRunLoopAddSource(loop, source, .commonModes)
        try expect(CFRunLoopContainsSource(loop, source, .commonModes), true, "real source registered")
        var resources: ScrollTapResources? = ScrollTapResources(port: port, source: source, runLoop: loop)
        resources?.invalidate()
        resources?.invalidate()
        try expect(CFRunLoopContainsSource(loop, source, .commonModes), false, "source removed")
        try expect(CFRunLoopSourceIsValid(source), false, "source invalidated")
        try expect(CFMachPortIsValid(port), false, "mach port invalidated")
        resources = nil
        var secondContext = CFMachPortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        let secondPort = CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, &secondContext, nil)!
        let secondSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, secondPort, 0)!
        var second: ScrollTapResources? = ScrollTapResources(port: secondPort, source: secondSource, runLoop: loop)
        CFRunLoopAddSource(loop, secondSource, .commonModes)
        try expect(second != nil, true, "second resource exists")
        second = nil
        try expect(CFMachPortIsValid(secondPort), false, "deinit invalidates port")
        try expect(CFRunLoopSourceIsValid(secondSource), false, "deinit invalidates source")
    }

    static func testCallbackPipeline() throws {
        let processor = ScrollEventProcessor()
        var preferences = ScrollPreferences()
        preferences.enabled = true
        processor.preferences = preferences
        let event = wheel()
        try expect(processor.process(type: .scrollWheel, event: event), .none, "stopped event passes")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "stopped input unchanged")
        processor.lifecycle.started()
        try expect(processor.process(type: .tapDisabledByTimeout, event: event), .reenable, "timeout recovery action")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "control event unchanged")
        try expect(processor.process(type: .scrollWheel, event: event), .none, "scroll has no UI side effect")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3, "actual CGEvent transformed")
        try expect(processor.process(type: .tapDisabledByUserInput, event: event), .stop, "user disable stops")
        try expect(processor.lifecycle.isRunning, false, "user disable closes lifecycle")
        try expect(processor.process(type: .tapDisabledByTimeout, event: event), .none, "late timeout ignored")
        try expect(processor.process(type: .scrollWheel, event: event), .none, "late input ignored")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3, "late event unchanged")
    }

    static func testEnginePermissionDenied() throws {
        let engine = ScrollEngine(accessibilityCheck: { false }, conflictCheck: { false })
        var changes: [String] = []
        engine.onStatusChange = { changes.append($0) }
        var preferences = ScrollPreferences()
        preferences.enabled = true
        engine.apply(preferences)
        try expect(engine.isRunning, false, "denied permission stays stopped")
        try expect(engine.statusText.contains("辅助功能"), true, "actionable permission status")
        engine.apply(preferences)
        try expect(changes.count, 1, "permission status deduplicated")
        engine.stop()
        try expect(engine.statusText, "已关闭", "stop status")
        try expect(changes.count, 2, "one stop notification")
    }

    static func testEngineConflict() throws {
        let engine = ScrollEngine(accessibilityCheck: { true }, conflictCheck: { true })
        var preferences = ScrollPreferences()
        preferences.enabled = true
        engine.apply(preferences)
        try expect(engine.isRunning, false, "conflict remains stopped")
        try expect(engine.statusText.contains("原滚动反转软件正在运行"), true, "localized conflict")
        try expect(engine.statusText.contains("手动"), true, "manual action required")
    }

    static func testTapCreationFailure() throws {
        var attempts = 0
        let engine = ScrollEngine(accessibilityCheck: { true }, conflictCheck: { false },
                                  tapCreator: { _, _ in attempts += 1; return nil })
        var preferences = ScrollPreferences()
        preferences.enabled = true
        engine.apply(preferences)
        try expect(attempts, 1, "start attempts tap creation once")
        try expect(engine.isRunning, false, "failed creation stays stopped")
        try expect(engine.statusText.contains("监听"), true, "tap creation failure is visible")
        engine.stop()
        try expect(engine.statusText, "已关闭", "failed start can be stopped")
    }

    static func testTaggedSynthetic() throws {
        var preferences = ScrollPreferences()
        preferences.enabled = true
        let tagged = wheel()
        tagged.setIntegerValueField(.eventSourceUserData, value: 0x424152)
        ScrollEventTransformer.transform(tagged, preferences: preferences, device: .mouse)
        try expect(tagged.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "tagged synthetic ignored")
        let source = CGEventSource(stateID: .privateState)!
        let privateEvent = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2,
                                   wheel1: 3, wheel2: 2, wheel3: 0)!
        privateEvent.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        ScrollEventTransformer.transform(privateEvent, preferences: preferences, device: .mouse)
        try expect(privateEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "private source ignored")
    }

    static func testDiagnostics() throws {
        let snapshot = ScrollEngine.diagnosticSnapshot()
        try expect(snapshot["defaultEnabled"] as? Bool, false, "diagnostic safe default")
        try expect(snapshot["continuousSourcePolicy"] as? String, "preserveUnknown", "explicit continuous-source limit")
        try expect(snapshot["trackpadReversalAvailable"] as? Bool, false, "no claimed trackpad identity")
        try expect(snapshot["accessibilityTrusted"] as? Bool, AXIsProcessTrusted(), "read-only actual permission check")
        let conflict = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.pilotmoon.scroll-reverser").isEmpty
        try expect(snapshot["scrollReverserRunning"] as? Bool, conflict, "read-only actual conflict check")
        try expect(JSONSerialization.isValidJSONObject(snapshot), true, "JSON-compatible diagnostics")
    }

    static func testDisabledNoPreflight() throws {
        var permissionReads = 0
        var processReads = 0
        let engine = ScrollEngine(accessibilityCheck: { permissionReads += 1; return false },
                                  conflictCheck: { processReads += 1; return false })
        engine.apply(ScrollPreferences())
        try expect(permissionReads, 0, "disabled avoids permission lookup")
        try expect(processReads, 0, "disabled avoids process lookup")
        try expect(engine.isRunning, false, "disabled remains idle")
    }

    static func testMetadataAndInactiveAxis() throws {
        let processor = ScrollEventProcessor()
        processor.lifecycle.started()
        processor.preferences.enabled = true
        let event = wheel()
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis3, value: 7)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 2.75)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 19)
        _ = processor.process(type: .scrollWheel, event: event)
        try expect(event.getIntegerValueField(.scrollWheelEventMomentumPhase), 2, "momentum metadata")
        try expect(event.getIntegerValueField(.scrollWheelEventScrollPhase), 4, "scroll phase metadata")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis3), 7, "third axis untouched")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), 2, "inactive horizontal line")
        try expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), 2.75, "inactive horizontal fixed")
        try expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 19, "inactive horizontal point")
    }

    static func testMouseVerticalReversal() throws {
        var preferences = ScrollPreferences()
        preferences.enabled = true
        let event = wheel()
        ScrollEventTransformer.transform(event, preferences: preferences, device: .mouse)
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3,
                   "mouse vertical line delta")
    }
}
