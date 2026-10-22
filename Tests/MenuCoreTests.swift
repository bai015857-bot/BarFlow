import Foundation
import AppKit
import Carbon

private var menuAssertionCount = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    menuAssertionCount += 1
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

final class FakeMenuDriver: MenuBarDriving {
    var length = 20.0
    var visible = false
    var hasCompetingManager = false
    var shortcutResult: MenuShortcutResult = .registered
    var shortcutAction: (() -> Void)?
    var shortcutRegistrations = 0
    var shortcutRemovals = 0
    var separatorEvents: [String] = []
    func removeSeparator() { separatorEvents.append("remove") }
    func registerShortcut(_ action: @escaping () -> Void) -> MenuShortcutResult {
        shortcutRegistrations += 1
        shortcutAction = action
        return shortcutResult
    }
    func unregisterShortcut() { shortcutRemovals += 1; shortcutAction = nil }
    var layout: MenuBarLayout? = MenuBarLayout(
        separatorFrame: CGRect(x: 800, y: 876, width: 20, height: 24),
        anchorFrame: CGRect(x: 830, y: 876, width: 24, height: 24),
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        separatorScreenID: 1, anchorScreenID: 1)
    func setSeparator(visible: Bool, length: Double) {
        self.visible = visible
        self.length = length
        separatorEvents.append("width:\(Int(length))")
    }
}

final class FakeMenuTimer: MenuTimerToken {
    var cancelled = false
    var due: Double
    let interval: Double?
    let action: () -> Void
    init(due: Double, interval: Double?, action: @escaping () -> Void) {
        self.due = due
        self.interval = interval
        self.action = action
    }
    func cancel() { cancelled = true }
}

final class FakeMenuClock: MenuTimerScheduling {
    var now = 0.0
    var timers: [FakeMenuTimer] = []
    func schedule(after delay: Double, repeating interval: Double?, _ action: @escaping () -> Void) -> MenuTimerToken {
        let timer = FakeMenuTimer(due: now + delay, interval: interval, action: action)
        timers.append(timer)
        return timer
    }
    func advance(_ seconds: Double) {
        let target = now + seconds
        while let next = timers.filter({ !$0.cancelled && $0.due <= target }).min(by: { $0.due < $1.due }) {
            now = next.due
            if let interval = next.interval { next.due += interval } else { next.cancel() }
            next.action()
        }
        now = target
    }
}

final class FakeMenuStatusItems: MenuStatusItemAccess {
    var events: [String] = []
    var separatorLength: Double = 20 { didSet { events.append("length:\(Int(separatorLength))") } }
    var separatorVisible = false { didSet { events.append("visible:\(separatorVisible)") } }
    var layout: MenuBarLayout? = FakeMenuDriver().layout
    func removeSeparator() { events.append("remove") }
}

final class FakeMenuShortcut: MenuShortcutRegistering {
    var unregistered = false
    func register(_ action: @escaping () -> Void) -> MenuShortcutResult { .registered }
    func unregister() { unregistered = true }
}

@main
struct MenuCoreTests {
    static func main() throws {
        let clickDriver = FakeMenuDriver()
        let clickClock = FakeMenuClock()
        let clickController = MenuBarController(driver: clickDriver, scheduler: clickClock)
        var clickPrefs = MenuPreferences()
        clickPrefs.enabled = true
        clickPrefs.autoCollapse = true
        clickPrefs.autoCollapseDelay = 15
        clickController.apply(clickPrefs)
        expect(MenuStatusClickAction.resolve(eventType: .leftMouseUp, menuEnabled: true) == .toggle,
               "left click on the menu icon must toggle instead of opening settings")
        expect(MenuStatusClickAction.resolve(eventType: .rightMouseUp, menuEnabled: true) == .quickMenu,
               "right click keeps the settings and recovery menu available")
        expect(MenuStatusClickAction.resolve(eventType: .leftMouseUp, menuEnabled: false) == .settings,
               "disabled menu module still allows settings through left click")
        expect(MenuStatusClickAction.resolve(eventType: .rightMouseUp, menuEnabled: false) == .quickMenu,
               "disabled menu module still allows the quick menu")
        expect(MenuStatusClickAction.resolve(eventType: nil, menuEnabled: true) == .toggle,
               "programmatic status button press uses the primary toggle action")
        for expectedCollapsed in [true, false] {
            if MenuStatusClickAction.resolve(eventType: .leftMouseUp, menuEnabled: true) == .toggle {
                clickController.toggle()
            }
            expect(clickController.isCollapsed == expectedCollapsed,
                   "successive icon clicks collapse then expand the real menu controller")
            expect(clickDriver.length == (expectedCollapsed ? 5000 : 20),
                   "icon clicks update the real separator width")
        }
        clickClock.advance(14.9)
        expect(!clickController.isCollapsed, "icon expansion honors the user's 15-second delay")
        clickClock.advance(0.1)
        expect(clickController.isCollapsed, "icon expansion automatically recollapses at the configured delay")
        clickController.cleanup()
        print("PASS: status icon primary click expands/collapses, right click preserves menu, timed recollapse")

        let defaults = MenuPreferences()
        expect(!defaults.enabled, "menu hiding starts disabled")
        expect(defaults.autoCollapse, "automatic collapse preference defaults on")
        expect(defaults.autoCollapseDelay == 15, "default collapse delay is 15 seconds")
        expect(defaults.hotKeyEnabled, "shortcut preference defaults on")
        let data = try JSONEncoder().encode(defaults)
        let decoded = try JSONDecoder().decode(MenuPreferences.self, from: data)
        expect(decoded == defaults, "preferences round-trip")
        print("PASS: preferences defaults and Codable")

        let driver = FakeMenuDriver()
        let clock = FakeMenuClock()
        let engine = MenuCollapseEngine(driver: driver, scheduler: clock)
        expect(!engine.isCollapsed, "initial state is expanded")
        engine.toggle()
        expect(!engine.isCollapsed && !driver.visible, "disabled toggle passes through")
        var prefs = MenuPreferences()
        prefs.enabled = true
        prefs.autoCollapse = false
        engine.apply(prefs)
        engine.toggle()
        expect(engine.isCollapsed && driver.length == 5000, "collapse uses 5000-point separator")
        engine.expand()
        expect(!engine.isCollapsed && driver.length == 20, "expand restores separator width")
        engine.toggle()
        engine.apply(defaults)
        expect(!engine.isCollapsed && !driver.visible, "disabling reveals and hides separator")
        print("PASS: disabled pass-through and collapse/expand")

        let valid = driver.layout!
        var badLayouts: [MenuBarLayout?] = [nil]
        var bad = valid
        bad.separatorScreenID = 2
        badLayouts.append(bad)
        bad = valid
        bad.separatorFrame.origin.x = 900
        badLayouts.append(bad)
        bad = valid
        bad.anchorFrame.origin.x = 1500
        badLayouts.append(bad)
        bad = valid
        bad.anchorFrame.size.width = .nan
        badLayouts.append(bad)
        engine.apply(prefs)
        for layout in badLayouts {
            driver.layout = layout
            engine.toggle()
            expect(!engine.isCollapsed && driver.length == 20, "unsafe layout rejects collapse")
            expect(engine.statusText.contains("分隔符"), "unsafe layout explains required placement")
        }
        driver.layout = valid
        var stateChanges: [Bool] = []
        var statuses: [String] = []
        engine.onStateChange = { stateChanges.append($0) }
        engine.onStatusChange = { statuses.append($0) }
        engine.toggle()
        engine.expand()
        expect(stateChanges == [true, false], "state callbacks report real transitions")
        expect(!statuses.isEmpty, "status callback reports user guidance")
        print("PASS: layout validation and state/status callbacks")

        for (input, delay) in [(-1.0, 3.0), (5000.0, 3600.0), (Double.nan, 15.0), (Double.infinity, 15.0), (8.0, 8.0)] {
            let timedDriver = FakeMenuDriver()
            let timedClock = FakeMenuClock()
            let timed = MenuCollapseEngine(driver: timedDriver, scheduler: timedClock)
            var autoPrefs = prefs
            autoPrefs.autoCollapse = true
            autoPrefs.autoCollapseDelay = input
            timed.apply(autoPrefs)
            timedClock.advance(delay - 0.1)
            expect(!timed.isCollapsed, "automatic collapse waits for clamped delay")
            timedClock.advance(0.1)
            expect(timed.isCollapsed, "automatic collapse occurs at clamped delay")
            timed.apply(defaults)
            timedClock.advance(10000)
            expect(!timed.isCollapsed, "disabled engine cancels automatic collapse")
        }
        print("PASS: automatic collapse and delay clamp")

        // Regression: a healthy recovery anchor must not disable auto-collapse after 90 seconds.
        let longLivedDriver = FakeMenuDriver()
        let longLivedClock = FakeMenuClock()
        let longLived = MenuCollapseEngine(driver: longLivedDriver, scheduler: longLivedClock)
        var longLivedPrefs = prefs
        longLivedPrefs.autoCollapse = true
        longLivedPrefs.autoCollapseDelay = 5
        longLived.apply(longLivedPrefs)
        longLivedClock.advance(5)
        expect(longLived.isCollapsed, "configured five-second delay collapses the menu")
        longLivedClock.advance(300)
        expect(longLived.isCollapsed && longLivedDriver.length == 5000,
               "healthy layout stays collapsed beyond 90 seconds instead of silently pausing")
        longLived.expand()
        longLivedClock.advance(4.9)
        expect(!longLived.isCollapsed, "manual expansion still waits for the user's delay")
        longLivedClock.advance(0.1)
        expect(longLived.isCollapsed, "automatic collapse still works after long uptime and expansion")
        longLived.cleanup()
        print("PASS: healthy menu does not permanently pause after 90 seconds")

        let safeDriver = FakeMenuDriver()
        let safeClock = FakeMenuClock()
        let safe = MenuCollapseEngine(driver: safeDriver, scheduler: safeClock)
        var safePrefs = prefs
        safePrefs.autoCollapse = true
        safePrefs.autoCollapseDelay = 3
        safe.apply(safePrefs)
        safe.toggle()
        safeClock.advance(89)
        expect(safe.isCollapsed, "healthy layout remains collapsed before safety recheck")
        // Simulate a missed fast watchdog: the independent 90-second check must
        // still reveal an unsafe anchor, and apply must not postpone that check.
        safeClock.timers.filter { $0.interval == 1 }.forEach { $0.cancel() }
        safeDriver.layout = nil
        safe.apply(safePrefs)
        safeClock.advance(1)
        expect(!safe.isCollapsed && safeDriver.length == 20, "independent safety recheck reveals unsafe layout without being reset by apply")
        expect(safe.statusText.contains("安全复查"), "safety recheck explains the geometry failure")
        safeClock.advance(200)
        expect(!safe.isCollapsed, "unsafe safety recheck suspends automatic recollapse")
        print("PASS: independent geometry-based safety recheck")

        safeDriver.layout = valid
        safe.apply(safePrefs)
        safe.toggle()
        expect(safe.isCollapsed, "explicit request can collapse after safety recovery")
        safeDriver.layout = nil
        safeClock.advance(1)
        expect(!safe.isCollapsed && safeDriver.length == 20, "lost recovery geometry reveals within one second")
        safeClock.advance(200)
        expect(!safe.isCollapsed, "layout failure suspends automatic recollapse")
        expect(safe.statusText.contains("分隔符"), "layout recovery explains placement")
        print("PASS: collapsed layout watchdog")

        for layoutRecovery in [false, true] {
            for resumeByEnablingModule in [false, true] {
                let pausedDriver = FakeMenuDriver()
                let pausedClock = FakeMenuClock()
                let paused = MenuCollapseEngine(driver: pausedDriver, scheduler: pausedClock)
                paused.apply(safePrefs)
                paused.toggle()
                if layoutRecovery {
                    pausedDriver.layout = nil
                    pausedClock.advance(1)
                    pausedDriver.layout = valid
                } else {
                    pausedClock.timers.filter { $0.interval == 1 }.forEach { $0.cancel() }
                    pausedDriver.layout = nil
                    pausedClock.advance(90)
                    pausedDriver.layout = valid
                }
                let recovery = layoutRecovery ? "layout recovery" : "independent safety recheck"
                expect(!paused.isCollapsed, "\(recovery) expands before preference updates")

                paused.apply(safePrefs)
                pausedClock.advance(safePrefs.autoCollapseDelay)
                expect(!paused.isCollapsed && pausedDriver.length == 20, "\(recovery) stays paused when identical preferences are reapplied")

                var changedPrefs = safePrefs
                changedPrefs.hotKeyEnabled = false
                paused.apply(changedPrefs)
                pausedClock.advance(changedPrefs.autoCollapseDelay)
                expect(!paused.isCollapsed, "\(recovery) stays paused after an unrelated shortcut preference change")

                changedPrefs.autoCollapseDelay = 7
                paused.apply(changedPrefs)
                pausedClock.advance(changedPrefs.autoCollapseDelay)
                expect(!paused.isCollapsed, "\(recovery) stays paused after changing only the automatic delay")

                if resumeByEnablingModule {
                    changedPrefs.enabled = false
                } else {
                    changedPrefs.autoCollapse = false
                }
                paused.apply(changedPrefs)
                pausedClock.advance(changedPrefs.autoCollapseDelay)
                expect(!paused.isCollapsed, "turning off the paused option keeps the menu expanded")
                changedPrefs.enabled = true
                changedPrefs.autoCollapse = true
                paused.apply(changedPrefs)
                pausedClock.advance(changedPrefs.autoCollapseDelay - 0.1)
                expect(!paused.isCollapsed, "explicit re-enable waits for the configured delay")
                pausedClock.advance(0.1)
                let option = resumeByEnablingModule ? "menu module" : "automatic collapse"
                expect(paused.isCollapsed && pausedDriver.length == 5000, "explicitly re-enabling \(option) resumes after \(recovery)")
                paused.cleanup()
            }
        }
        print("PASS: safety suspension survives preference updates until explicit re-enable")

        let conflictDriver = FakeMenuDriver()
        conflictDriver.hasCompetingManager = true
        let conflictClock = FakeMenuClock()
        let conflict = MenuCollapseEngine(driver: conflictDriver, scheduler: conflictClock)
        conflict.apply(safePrefs)
        expect(conflict.statusText.contains("其他菜单栏管理软件"), "competing menu manager warning is visible when enabled")
        conflictClock.advance(60)
        expect(!conflict.isCollapsed, "iBar conflict disables automatic collapse")
        conflict.toggle()
        expect(conflict.isCollapsed, "explicit collapse is still available with safe layout")
        conflict.expand()
        expect(conflict.statusText.contains("其他菜单栏管理软件"), "competing menu manager warning survives state changes")
        print("PASS: competing menu manager handling")
        let keyDriver = FakeMenuDriver()
        let keyed = MenuCollapseEngine(driver: keyDriver, scheduler: FakeMenuClock())
        keyDriver.shortcutResult = .unavailable(-9878)
        keyed.apply(prefs)
        expect(keyed.statusText.contains("⌥⌘B") && keyed.statusText.contains("-9878"), "duplicate shortcut reports failure")
        keyed.toggle()
        expect(keyed.isCollapsed, "shortcut failure preserves manual control")
        keyed.expand()
        keyDriver.shortcutResult = .registered
        keyed.apply(prefs)
        let registrations = keyDriver.shortcutRegistrations
        keyed.apply(prefs)
        expect(keyDriver.shortcutRegistrations == registrations, "registered shortcut is not duplicated")
        let staleShortcut = keyDriver.shortcutAction
        keyDriver.shortcutAction?()
        expect(keyed.isCollapsed, "global shortcut toggles collapse")
        keyed.apply(defaults)
        staleShortcut?()
        expect(!keyed.isCollapsed && keyDriver.shortcutAction == nil, "disabled shortcut is removed and stale callback is safe")
        var noHotkey = prefs
        noHotkey.hotKeyEnabled = false
        keyed.apply(noHotkey)
        expect(keyDriver.shortcutAction == nil, "shortcut preference is respected")
        print("PASS: shortcut duplicate failure and lifecycle")
        let cleanupDriver = FakeMenuDriver()
        let cleanupClock = FakeMenuClock()
        let cleaned = MenuCollapseEngine(driver: cleanupDriver, scheduler: cleanupClock)
        cleaned.apply(safePrefs)
        cleaned.toggle()
        let pending = cleanupClock.timers
        let oldKey = cleanupDriver.shortcutAction
        cleaned.cleanup()
        expect(!cleaned.isCollapsed && cleanupDriver.length == 20, "cleanup restores all hidden items")
        expect(Array(cleanupDriver.separatorEvents.suffix(2)) == ["width:20", "remove"], "cleanup expands before removing separator")
        expect(cleanupDriver.shortcutAction == nil, "cleanup unregisters shortcut")
        let eventCount = cleanupDriver.separatorEvents.count
        cleaned.cleanup()
        cleaned.apply(safePrefs)
        cleaned.toggle()
        cleaned.expand()
        oldKey?()
        pending.forEach { $0.action() }
        cleanupClock.advance(10000)
        expect(cleanupDriver.separatorEvents.count == eventCount, "cleanup is terminal and stale callbacks are harmless")
        print("PASS: cleanup restoration and stale callback safety")

        let controllerDriver = FakeMenuDriver()
        let center = NotificationCenter()
        let controller = MenuBarController(driver: controllerDriver, scheduler: FakeMenuClock(), notificationCenter: center)
        expect(!controller.isCollapsed && controller.statusText.contains("其他菜单栏管理软件"), "controller starts expanded with pre-enable conflict notice")
        var controllerStates: [Bool] = []
        var controllerStatuses: [String] = []
        controller.onStateChange = { controllerStates.append($0) }
        controller.onStatusChange = { controllerStatuses.append($0) }
        controller.apply(prefs)
        controller.toggle()
        expect(controller.isCollapsed, "controller forwards collapse")
        controller.expand()
        expect(!controller.isCollapsed, "controller forwards expansion")
        controller.toggle()
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        expect(!controller.isCollapsed && controllerDriver.separatorEvents.last == "remove", "application termination restores and removes separator")
        expect(controllerStates == [true, false, true, false], "controller forwards state callbacks")
        expect(!controllerStatuses.isEmpty, "controller forwards status callbacks")
        controller.cleanup()
        let releasedDriver = FakeMenuDriver()
        var released: MenuBarController? = MenuBarController(driver: releasedDriver, scheduler: FakeMenuClock(), notificationCenter: center)
        released?.apply(prefs)
        released?.toggle()
        released = nil
        expect(releasedDriver.length == 20 && releasedDriver.separatorEvents.last == "remove", "controller deinit restores separator")
        print("PASS: controller integration and termination cleanup")

        let runLoopScheduler = MenuRunLoopScheduler()
        var ticks = 0
        let liveTimer = runLoopScheduler.schedule(after: 0.01, repeating: 0.01) { ticks += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        expect(ticks > 0, "native scheduler fires on main run loop")
        liveTimer.cancel()
        let stoppedAt = ticks
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        expect(ticks == stoppedAt, "native scheduler cancellation stops callbacks")
        print("PASS: native run-loop scheduler")

        var removedHandlers = 0
        var carbonCalls = 0
        var callbackCalls = 0
        let failingCarbon = MenuCarbonFunctions(
            install: { _, _, output in output.pointee = OpaquePointer(bitPattern: 1); return noErr },
            register: { key, modifiers, identifier, _ in
                carbonCalls += 1
                expect(key == UInt32(kVK_ANSI_B), "Carbon shortcut uses B")
                expect(modifiers == UInt32(optionKey | cmdKey), "Carbon shortcut uses Option+Command")
                expect(identifier.signature == MenuCarbonShortcut.signature && identifier.id == 1, "Carbon shortcut has BarFlow identity")
                return OSStatus(eventHotKeyExistsErr)
            },
            unregister: { _ in noErr },
            removeHandler: { _ in removedHandlers += 1; return noErr })
        let carbonFailure = MenuCarbonShortcut(functions: failingCarbon)
        expect(carbonFailure.register { callbackCalls += 1 } == .unavailable(Int32(eventHotKeyExistsErr)), "native Carbon duplicate is propagated")
        expect(removedHandlers == 1 && carbonCalls == 1 && callbackCalls == 0, "native failure releases installed event handler")
        carbonFailure.unregister()
        expect(removedHandlers == 1, "failure cleanup is idempotent")
        print("PASS: native Carbon duplicate registration failure")

        var installedCallback: EventHandlerUPP?
        var installedContext: UnsafeMutableRawPointer?
        var successfulRegistrations = 0
        var unregisteredKeys = 0
        let successfulCarbon = MenuCarbonFunctions(
            install: { callback, context, output in
                installedCallback = callback
                installedContext = context
                output.pointee = OpaquePointer(bitPattern: 2)
                return noErr
            },
            register: { _, _, _, output in successfulRegistrations += 1; output.pointee = OpaquePointer(bitPattern: 3); return noErr },
            unregister: { _ in unregisteredKeys += 1; return noErr },
            removeHandler: { _ in noErr })
        let carbonSuccess = MenuCarbonShortcut(functions: successfulCarbon)
        expect(carbonSuccess.register { callbackCalls += 1 } == .registered, "Carbon registration succeeds")
        expect(carbonSuccess.register { callbackCalls += 1 } == .registered && successfulRegistrations == 1, "Carbon registration is idempotent")
        var event: EventRef?
        expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr, "create local Carbon test event")
        defer { if let event = event { ReleaseEvent(event) } }
        var identifier = EventHotKeyID(signature: MenuCarbonShortcut.signature, id: 1)
        expect(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier) == noErr, "set local Carbon event identifier")
        expect(installedCallback?(nil, event, installedContext) == noErr && callbackCalls == 1, "registered Carbon callback dispatches matching identifier")
        identifier.id = 2
        _ = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier)
        expect(installedCallback?(nil, event, installedContext) == OSStatus(eventNotHandledErr) && callbackCalls == 1, "unrelated Carbon key is ignored")
        carbonSuccess.unregister()
        expect(unregisteredKeys == 1, "Carbon cleanup unregisters key")
        print("PASS: native Carbon callback dispatch and cleanup")

        let placementSuite = "BarFlowTests.MenuPlacement.\(UUID().uuidString)"
        let placementDefaults = UserDefaults(suiteName: placementSuite)!
        defer { placementDefaults.removePersistentDomain(forName: placementSuite) }
        let positionKey = "NSStatusItem Preferred Position \(MenuAppKitStatusItems.separatorIdentity)"
        let visibleKey = "NSStatusItem Visible \(MenuAppKitStatusItems.separatorIdentity)"
        placementDefaults.set(329.0, forKey: positionKey)
        placementDefaults.set(false, forKey: visibleKey)
        placementDefaults.set("keep", forKey: "unrelated")
        var operationRan = false
        var creationSawVisible = false
        MenuAppKitStatusItems.withPreservedPlacement(visible: true, defaults: placementDefaults) {
            operationRan = true
            creationSawVisible = placementDefaults.bool(forKey: visibleKey)
            // AppKit removes Preferred Position when recreating a previously hidden item.
            placementDefaults.removeObject(forKey: positionKey)
        }
        expect(operationRan, "placement wrapper performs exactly the intended native operation")
        expect(creationSawVisible, "explicitly showing separator clears saved hidden state before AppKit creation")
        expect(placementDefaults.double(forKey: positionKey) == 329,
               "native recreation cannot erase the user's saved separator slot")
        MenuAppKitStatusItems.withPreservedPlacement(visible: false, defaults: placementDefaults) {
            placementDefaults.set(false, forKey: visibleKey)
            placementDefaults.removeObject(forKey: positionKey)
        }
        expect(placementDefaults.double(forKey: positionKey) == 329,
               "native hide/removal preserves the saved separator slot for the next launch")
        expect(!placementDefaults.bool(forKey: visibleKey), "hide operation retains its visibility state")
        expect(placementDefaults.string(forKey: "unrelated") == "keep", "placement preservation does not rewrite unrelated preferences")
        placementDefaults.removeObject(forKey: positionKey)
        MenuAppKitStatusItems.withPreservedPlacement(visible: true, defaults: placementDefaults) {}
        expect(placementDefaults.object(forKey: positionKey) == nil, "no saved position means no invented positioning")
        for malformedPosition: Any in ["not-a-position", true, -10.0, Double.nan, Double.infinity] {
            placementDefaults.set(malformedPosition, forKey: positionKey)
            MenuAppKitStatusItems.withPreservedPlacement(visible: false, defaults: placementDefaults) {
                placementDefaults.removeObject(forKey: positionKey)
            }
            expect(placementDefaults.object(forKey: positionKey) == nil,
                   "position preservation never resurrects malformed/negative/nonfinite positions")
        }
        print("PASS: saved separator placement survives native hidden-state recreation and removal")

        let items = FakeMenuStatusItems()
        let nativeKey = FakeMenuShortcut()
        let nativeDriver = MenuAppKitDriver(items: items, shortcut: nativeKey, competingManager: { true })
        expect(nativeDriver.layout?.allowsCollapse == true && nativeDriver.hasCompetingManager, "native driver forwards live layout and environment")
        nativeDriver.setSeparator(visible: true, length: 5000)
        expect(items.separatorVisible && items.separatorLength == 5000, "native driver sets separator width")
        nativeDriver.setSeparator(visible: false, length: 20)
        expect(Array(items.events.suffix(2)) == ["length:20", "visible:false"], "native driver expands before hiding separator")
        expect(nativeDriver.registerShortcut({}) == .registered, "native driver forwards shortcut registration")
        nativeDriver.unregisterShortcut()
        expect(nativeKey.unregistered, "native driver forwards shortcut cleanup")
        nativeDriver.removeSeparator()
        expect(items.events.last == "remove", "native driver removes only its separator")
        expect(MenuAppKitStatusItems.separatorIdentity == "BarFlow.MenuSeparator.v1", "separator identity is unique to BarFlow")
        expect(MenuAppKitDriver.isIBar(bundleIdentifier: "com.example.iBar", name: nil), "iBar bundle is detected")
        expect(MenuAppKitDriver.isIBar(bundleIdentifier: nil, name: "iBar"), "iBar app name is detected")
        expect(!MenuAppKitDriver.isIBar(bundleIdentifier: "com.example.sidebar", name: "Sidebar"), "unrelated bundles are not flagged")
        let anchorInitializer: (NSStatusItem) -> MenuBarController = { MenuBarController(anchor: $0) }
        _ = anchorInitializer // Compile the real entry point without creating an NSStatusItem.
        print("PASS: native AppKit adapter and public initializer compile")

        let invalidDriver = FakeMenuDriver()
        invalidDriver.layout = nil
        let invalidClock = FakeMenuClock()
        let invalid = MenuCollapseEngine(driver: invalidDriver, scheduler: invalidClock)
        invalid.apply(safePrefs)
        invalidClock.advance(3)
        expect(!invalid.isCollapsed, "automatic collapse rejects unarranged separator")
        invalidDriver.layout = valid
        invalidClock.advance(30)
        expect(!invalid.isCollapsed, "invalid placement suspends automatic retries until explicit action")
        let lateDriver = FakeMenuDriver()
        let lateClock = FakeMenuClock()
        let lateConflict = MenuCollapseEngine(driver: lateDriver, scheduler: lateClock)
        lateConflict.apply(safePrefs)
        lateDriver.hasCompetingManager = true
        lateClock.advance(3)
        expect(!lateConflict.isCollapsed && lateConflict.statusText.contains("其他菜单栏管理软件"), "late iBar launch cancels pending automatic collapse")
        print("PASS: automatic collapse rechecks safety at deadline")
        print("PASS: \(menuAssertionCount) assertions; no live status items or global key registrations")
    }
}
