import Foundation

@main
struct PreferencesTests {
    static func main() throws {
        let defaults = AppPreferences()
        precondition(!defaults.menuEnabled, "A new app must not collapse the user's menu bar")
        precondition(!defaults.scrollEnabled, "A new app must not intercept scrolling")
        precondition(defaults.reverseMouse && !defaults.reverseTrackpad)
        precondition(!defaults.sideButtonsEnabled && !defaults.swapSideButtons, "Side-button desktop switching must be opt-in")
        print("PASS: safe defaults and independent device preferences")
        let suite = "BarFlow-tests-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        defer { ud.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: ud)
        var edited = defaults
        edited.reverseHorizontal = true
        edited.autoCollapseDelay = -100
        store.save(edited)
        let loaded = store.load()
        precondition(loaded.reverseHorizontal)
        precondition(loaded.autoCollapseDelay == 3, "Negative delays must be clamped safely")
        for seconds in [3.0, 8.0, 8.5, 120.0] {
            edited.autoCollapseDelay = seconds
            store.save(edited)
            precondition(store.load().autoCollapseDelay == seconds, "Supported custom delays must survive sanitization and persistence exactly")
        }
        for (seconds, expected) in [(Double.infinity, 15.0), (Double.nan, 15.0), (121.0, 120.0), (2.0, 3.0)] {
            edited.autoCollapseDelay = seconds
            precondition(edited.sanitized().autoCollapseDelay == expected, "Delay sanitization must retain its existing 3...120 bounds")
        }
        edited.reverseTrackpad = true
        precondition(!edited.sanitized().reverseTrackpad, "Unsupported trackpad reversal must be cleared when sanitizing old preferences")
        ud.set(try JSONEncoder().encode(edited), forKey: PreferencesStore.storageKey)
        precondition(!store.load().reverseTrackpad, "Loading an old enabled trackpad preference must keep the system direction")
        store.save(edited)
        precondition(!store.load().reverseTrackpad, "Saving preferences must never retain unsupported trackpad reversal")
        edited.sideButtonsEnabled = true
        edited.autoCollapseDelay = 8.5
        edited.swapSideButtons = true
        store.save(edited)
        precondition(store.load().sideButtonsEnabled && store.load().swapSideButtons, "New side-button settings must round trip")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as! [String: Any]
        legacy.removeValue(forKey: "sideButtonsEnabled")
        legacy.removeValue(forKey: "swapSideButtons")
        ud.set(try JSONSerialization.data(withJSONObject: legacy), forKey: PreferencesStore.storageKey)
        let migrated = store.load()
        precondition(migrated.reverseHorizontal && migrated.autoCollapseDelay == 8.5, "Adding side buttons must preserve the old 0.1.1 preferences")
        precondition(!migrated.sideButtonsEnabled && !migrated.swapSideButtons, "Old settings must not silently enable new interception")
        ud.set(Data("broken-json".utf8), forKey: PreferencesStore.storageKey)
        precondition(store.load() == defaults, "Corrupt settings must return safe defaults")
        print("PASS: round-trip persistence, safe delay clamp, corrupt settings recovery")
    }
}
