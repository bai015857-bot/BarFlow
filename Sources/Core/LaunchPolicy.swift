import Foundation

enum LaunchPolicy {
    static func shouldStart(arguments: [String], existingOtherInstance: Bool) -> Bool {
        if arguments.contains("--diagnose") { return false }
        return arguments.contains("--smoke-test") || !existingOtherInstance
    }

    static func startupPreferences(_ stored: AppPreferences, arguments: [String]) -> AppPreferences {
        if arguments.contains("--smoke-test") { return AppPreferences() }
        var result = stored.sanitized()
        if arguments.contains("--safe-mode") {
            result.menuEnabled = false
            result.scrollEnabled = false
            result.sideButtonsEnabled = false
        }
        return result
    }
}
