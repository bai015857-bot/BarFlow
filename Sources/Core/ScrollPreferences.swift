import Foundation

struct ScrollPreferences: Codable, Equatable {
    var enabled: Bool = false
    var reverseMouse: Bool = true
    var reverseTrackpad: Bool = false
    var reverseVertical: Bool = true
    var reverseHorizontal: Bool = false
    var ignoreSynthetic: Bool = true
}

enum ScrollDevice: Equatable {
    case mouse
    case trackpad
    case unknown
}
