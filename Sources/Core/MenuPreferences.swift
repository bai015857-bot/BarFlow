import Foundation

struct MenuPreferences: Codable, Equatable {
    var enabled: Bool = false
    var autoCollapse: Bool = true
    var autoCollapseDelay: Double = 15
    var hotKeyEnabled: Bool = true
}
