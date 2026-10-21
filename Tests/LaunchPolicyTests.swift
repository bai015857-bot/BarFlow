import Foundation

@main
struct LaunchPolicyTests {
    static func main() {
        precondition(LaunchPolicy.shouldStart(arguments: [], existingOtherInstance: false))
        precondition(!LaunchPolicy.shouldStart(arguments: [], existingOtherInstance: true), "Duplicate live instances must never install two taps")
        precondition(LaunchPolicy.shouldStart(arguments: ["--smoke-test"], existingOtherInstance: true), "Safe smoke tests don't install taps")
        precondition(!LaunchPolicy.shouldStart(arguments: ["--diagnose"], existingOtherInstance: false), "Diagnostics must not start the app")
        let safe = LaunchPolicy.startupPreferences(AppPreferences(), arguments: [])
        precondition(!safe.menuEnabled && !safe.scrollEnabled)
        var enabled = AppPreferences()
        enabled.menuEnabled = true
        enabled.scrollEnabled = true
        enabled.sideButtonsEnabled = true
        let recovery = LaunchPolicy.startupPreferences(enabled, arguments: ["--safe-mode"])
        precondition(!recovery.menuEnabled && !recovery.scrollEnabled)
        precondition(!recovery.sideButtonsEnabled, "Recovery mode must not install the side-button tap")
        precondition(!LaunchPolicy.startupPreferences(enabled, arguments: ["--smoke-test"]).sideButtonsEnabled)
        precondition(LaunchPolicy.startupPreferences(enabled, arguments: []).sideButtonsEnabled)
        precondition(LaunchPolicy.startupPreferences(enabled, arguments: []).scrollEnabled)
        print("PASS: duplicate instance prevention, diagnostic no-launch, smoke isolation and safe recovery")
    }
}
