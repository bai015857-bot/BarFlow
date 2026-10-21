import Foundation

protocol MenuTimerToken: AnyObject {
    func cancel()
}

protocol MenuTimerScheduling {
    func schedule(after delay: Double, repeating interval: Double?, _ action: @escaping () -> Void) -> MenuTimerToken
}
