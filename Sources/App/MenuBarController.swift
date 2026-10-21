import AppKit

/// Own on the main thread. The anchor remains owned by the application.
final class MenuBarController {
    private let engine: MenuCollapseEngine
    private let notificationCenter: NotificationCenter
    private var terminationObserver: NSObjectProtocol?

    var onStateChange: ((Bool) -> Void)? {
        get { engine.onStateChange }
        set { engine.onStateChange = newValue }
    }
    var onStatusChange: ((String) -> Void)? {
        get { engine.onStatusChange }
        set { engine.onStatusChange = newValue }
    }
    var isCollapsed: Bool { engine.isCollapsed }
    var statusText: String { engine.statusText }

    convenience init(anchor: NSStatusItem) {
        precondition(Thread.isMainThread, "MenuBarController must be used on the main thread")
        let driver = MenuAppKitDriver(items: MenuAppKitStatusItems(anchor: anchor), shortcut: MenuCarbonShortcut())
        self.init(driver: driver, scheduler: MenuRunLoopScheduler())
    }

    /// Internal test seam: never creates a status item or registers a native key.
    init(driver: MenuBarDriving, scheduler: MenuTimerScheduling,
         notificationCenter: NotificationCenter = .default) {
        self.engine = MenuCollapseEngine(driver: driver, scheduler: scheduler)
        self.notificationCenter = notificationCenter
        terminationObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cleanup() }
    }

    func apply(_ preferences: MenuPreferences) { engine.apply(preferences) }
    func toggle() { engine.toggle() }
    func expand() { engine.expand() }

    func cleanup() {
        if let observer = terminationObserver {
            notificationCenter.removeObserver(observer)
            terminationObserver = nil
        }
        engine.cleanup()
    }

    deinit { cleanup() }
}
