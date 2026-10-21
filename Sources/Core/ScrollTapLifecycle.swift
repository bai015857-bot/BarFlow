struct ScrollTapLifecycle {
    private(set) var isRunning = false
    mutating func started() { isRunning = true }
    func timeout() -> Bool { isRunning }
    @discardableResult
    mutating func stop() -> Bool {
        let shouldCleanUp = isRunning
        isRunning = false
        return shouldCleanUp
    }
}
