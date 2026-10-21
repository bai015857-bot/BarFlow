import Foundation

private final class MenuRunLoopTimerToken: MenuTimerToken {
    private var timer: Timer?
    init(_ timer: Timer) { self.timer = timer }
    func cancel() { timer?.invalidate(); timer = nil }
    deinit { cancel() }
}

struct MenuRunLoopScheduler: MenuTimerScheduling {
    func schedule(after delay: Double, repeating interval: Double?, _ action: @escaping () -> Void) -> MenuTimerToken {
        let timer = Timer(timeInterval: interval ?? delay, repeats: interval != nil) { _ in action() }
        timer.fireDate = Date().addingTimeInterval(delay)
        RunLoop.main.add(timer, forMode: .common)
        return MenuRunLoopTimerToken(timer)
    }
}
