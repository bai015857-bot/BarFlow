import AppKit
import ApplicationServices

/// Main-thread owner. Initialization and diagnostics never install an event tap.
final class ScrollEngine {
    var onStatusChange: ((String) -> Void)?
    private(set) var statusText = "已关闭"

    var isRunning: Bool {
        guard processor.lifecycle.isRunning, let resources = resources else { return false }
        return CFMachPortIsValid(resources.port) && CFRunLoopSourceIsValid(resources.source)
            && CGEvent.tapIsEnabled(tap: resources.port)
    }

    private let processor = ScrollEventProcessor()
    private var resources: ScrollTapResources?
    private var generation: UInt64 = 0
    private let accessibilityCheck: () -> Bool
    private let conflictCheck: () -> Bool
    private let tapCreator: (CGEventTapCallBack, UnsafeMutableRawPointer) -> CFMachPort?

    // Injectable preflight inputs and a creation-failure seam allow offline tests.
    // Production defaults below create the real public CGEventTap.
    init(accessibilityCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
         conflictCheck: @escaping () -> Bool = {
             !NSRunningApplication.runningApplications(withBundleIdentifier: "com.pilotmoon.scroll-reverser").isEmpty
         },
         tapCreator: @escaping (CGEventTapCallBack, UnsafeMutableRawPointer) -> CFMachPort? = { callback, context in
             CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                               options: .defaultTap,
                               eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue,
                               callback: callback, userInfo: context)
         }) {
        precondition(Thread.isMainThread, "ScrollEngine must be used on the main thread")
        self.accessibilityCheck = accessibilityCheck
        self.conflictCheck = conflictCheck
        self.tapCreator = tapCreator
    }

    func apply(_ preferences: ScrollPreferences) {
        precondition(Thread.isMainThread, "ScrollEngine must be used on the main thread")
        processor.preferences = preferences
        let decision = ScrollStartPolicy.evaluate(preferences,
                         accessibilityTrusted: preferences.enabled ? accessibilityCheck() : false,
                         scrollReverserRunning: preferences.enabled ? conflictCheck() : false)
        switch decision {
        case .disabled:
            stop()
        case .needsAccessibility:
            tearDown()
            setStatus("未启用：请在系统设置中手动允许辅助功能权限")
        case .conflict:
            tearDown()
            setStatus("未启用：原滚动反转软件正在运行，请手动退出后重试")
        case .allowed:
            guard !isRunning else { return }
            start()
        }
    }

    func stop() {
        precondition(Thread.isMainThread, "ScrollEngine must be used on the main thread")
        processor.preferences.enabled = false
        tearDown()
        setStatus("已关闭")
    }

    private func start() {
        tearDown()
        // Unretained context is safe because resources belong to this main-thread
        // owner and are invalidated before deinit can release the callback target.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<ScrollEngine>.fromOpaque(context).takeUnretainedValue()
            owner.receive(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let port = tapCreator(callback, context) else {
            setStatus("未启用：无法创建滚动监听，请检查系统辅助功能权限后重试")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0),
              let runLoop = CFRunLoopGetMain() else {
            CFMachPortInvalidate(port)
            setStatus("未启用：无法创建滚动监听的运行循环")
            return
        }
        resources = ScrollTapResources(port: port, source: source, runLoop: runLoop)
        processor.lifecycle.started()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        guard CGEvent.tapIsEnabled(tap: port) else {
            tearDown()
            setStatus("未启用：系统未允许滚动监听，请检查权限后重试")
            return
        }
        setStatus("已启用：离散鼠标滚轮；连续来源未知，保持原方向")
    }

    private func receive(type: CGEventType, event: CGEvent) {
        switch processor.process(type: type, event: event) {
        case .none:
            break
        case .reenable:
            guard let resources = resources, CFMachPortIsValid(resources.port) else { return }
            CGEvent.tapEnable(tap: resources.port, enable: true)
            if CGEvent.tapIsEnabled(tap: resources.port) {
                reportControlStatus("滚动监听已从超时恢复；连续来源保持原方向", stopping: false)
            } else {
                processor.lifecycle.stop()
                reportControlStatus("滚动监听恢复失败，请重新启用", stopping: true)
            }
        case .stop:
            // The processor stops immediately; physical teardown and UI callbacks
            // are deferred out of the event tap callback.
            reportControlStatus("滚动监听被系统停用，请手动重新启用", stopping: true)
        }
    }

    private func reportControlStatus(_ text: String, stopping: Bool) {
        let expectedGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.generation == expectedGeneration else { return }
            if stopping { self.tearDown() }
            self.setStatus(text)
        }
    }

    private func tearDown() {
        generation &+= 1
        processor.lifecycle.stop()
        resources?.invalidate()
        resources = nil
    }

    private func setStatus(_ text: String) {
        guard statusText != text else { return }
        statusText = text
        onStatusChange?(text)
    }

    static func diagnosticSnapshot() -> [String: Any] {
        return [
            "defaultEnabled": false,
            "accessibilityTrusted": AXIsProcessTrusted(),
            "scrollReverserRunning": !NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.pilotmoon.scroll-reverser").isEmpty,
            "eventTapAPI": "CGEvent.tapCreate (public)",
            "continuousSourcePolicy": "preserveUnknown",
            "trackpadReversalAvailable": false,
            "syntheticPolicy": "skip nonzero source PID, source tag, or private source state",
            "permissionPrompted": false
        ]
    }

    deinit { tearDown() }
}
