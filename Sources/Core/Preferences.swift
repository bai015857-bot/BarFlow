import Foundation

struct AppPreferences: Codable, Equatable {
    var menuEnabled = false
    var launchAtLogin = false
    var autoCollapse = true
    var autoCollapseDelay: Double = 15
    var hotKeyEnabled = true
    var scrollEnabled = false
    var reverseMouse = true
    var reverseTrackpad = false
    var reverseVertical = true
    var reverseHorizontal = false
    var ignoreSynthetic = true
    var sideButtonsEnabled = false
    var swapSideButtons = false

    private enum CodingKeys: String, CodingKey {
        case menuEnabled, launchAtLogin, autoCollapse, autoCollapseDelay, hotKeyEnabled, scrollEnabled
        case reverseMouse, reverseTrackpad, reverseVertical, reverseHorizontal, ignoreSynthetic
        case sideButtonsEnabled, swapSideButtons
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Keep the original required fields strict. Only newly introduced settings may be absent.
        menuEnabled = try values.decode(Bool.self, forKey: .menuEnabled)
        launchAtLogin = try values.decode(Bool.self, forKey: .launchAtLogin)
        autoCollapse = try values.decode(Bool.self, forKey: .autoCollapse)
        autoCollapseDelay = try values.decode(Double.self, forKey: .autoCollapseDelay)
        hotKeyEnabled = try values.decode(Bool.self, forKey: .hotKeyEnabled)
        scrollEnabled = try values.decode(Bool.self, forKey: .scrollEnabled)
        reverseMouse = try values.decode(Bool.self, forKey: .reverseMouse)
        reverseTrackpad = try values.decode(Bool.self, forKey: .reverseTrackpad)
        reverseVertical = try values.decode(Bool.self, forKey: .reverseVertical)
        reverseHorizontal = try values.decode(Bool.self, forKey: .reverseHorizontal)
        ignoreSynthetic = try values.decode(Bool.self, forKey: .ignoreSynthetic)
        sideButtonsEnabled = try values.decodeIfPresent(Bool.self, forKey: .sideButtonsEnabled) ?? false
        swapSideButtons = try values.decodeIfPresent(Bool.self, forKey: .swapSideButtons) ?? false
    }

    func sanitized() -> AppPreferences {
        var copy = self
        copy.reverseTrackpad = false
        copy.autoCollapseDelay = autoCollapseDelay.isFinite ? min(120, max(3, autoCollapseDelay)) : 15
        return copy
    }
}

final class PreferencesStore {
    static let storageKey = "barflow.preferences.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> AppPreferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              let value = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            return AppPreferences()
        }
        return value.sanitized()
    }

    func save(_ value: AppPreferences) {
        if let data = try? JSONEncoder().encode(value.sanitized()) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
