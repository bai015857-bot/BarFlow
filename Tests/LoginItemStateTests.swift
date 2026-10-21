import Foundation

@main
struct LoginItemStateTests {
    static func main() {
        precondition(LoginItemState.enabled.isEnabled, "An enabled OS login item must override a disabled saved preference")
        for state in [LoginItemState.notRegistered, .requiresApproval, .notFound, .unknown] {
            precondition(!state.isEnabled, "Only enabled OS status means login launch is active")
            precondition(!state.statusText.isEmpty, "Inactive login status must have an explanation")
        }
        precondition(LoginItemState.requiresApproval.statusText.contains("需要批准"))
        precondition(LoginItemState.requiresApproval.statusText.contains("系统设置"))
        print("PASS: pure login-state mapping distinguishes enabled, unregistered, approval, missing, and unknown")
    }
}
