import Foundation
import ApplicationServices

/// 只在主线程使用；初始化及诊断不会安装事件监听。
final class SideButtonEngine {
    var onStatusChange: ((String) -> Void)?
    private(set) var statusText = "已关闭"
    var isRunning: Bool {
        guard !safetySuspended, processor.preferences.enabled, let resources = resources else { return false }
        return CFMachPortIsValid(resources.port) && CFRunLoopSourceIsValid(resources.source)
            && tapIsEnabled(resources.port)
    }
    private let processor = SideButtonEventProcessor()
    private var resources: SideButtonTapResources?
    private var generation: UInt64 = 0
    private var safetySuspended = false
    private var requestedEnabled = false
    private var lastTimeout: TimeInterval?
    private var draining = false
    private var drainStatus = "已关闭"
    private let accessibilityCheck: () -> Bool
    private let shortcutConfigurationProvider: () -> SideButtonShortcutConfiguration
    private let tapCreator: (CGEventTapCallBack, UnsafeMutableRawPointer) -> CFMachPort?
    private let eventPoster: ([CGEvent]) -> Bool
    private let tapEnable: (CFMachPort, Bool) -> Void
    private let tapIsEnabled: (CFMachPort) -> Bool
    private let clock: () -> TimeInterval

    init(accessibilityCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
         shortcutConfigurationProvider: @escaping () -> SideButtonShortcutConfiguration = {
            SideButtonSystemAdapter.readShortcutConfiguration()
         },
         tapCreator: @escaping (CGEventTapCallBack, UnsafeMutableRawPointer) -> CFMachPort? = { callback, context in
            CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: SideButtonSystemAdapter.eventMask, callback: callback, userInfo: context)
         },
         eventPoster: @escaping ([CGEvent]) -> Bool = { SideButtonSystemAdapter.post($0) },
         tapEnable: @escaping (CFMachPort, Bool) -> Void = { CGEvent.tapEnable(tap: $0, enable: $1) },
         tapIsEnabled: @escaping (CFMachPort) -> Bool = { CGEvent.tapIsEnabled(tap: $0) },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        precondition(Thread.isMainThread, "侧键引擎仅可在主线程使用")
        self.accessibilityCheck = accessibilityCheck
        self.shortcutConfigurationProvider = shortcutConfigurationProvider
        self.tapCreator = tapCreator
        self.eventPoster = eventPoster
        self.tapEnable = tapEnable
        self.tapIsEnabled = tapIsEnabled
        self.clock = clock
    }
    func apply(_ preferences: SideButtonPreferences) {
        precondition(Thread.isMainThread, "侧键引擎仅可在主线程使用")
        requestedEnabled = preferences.enabled
        processor.apply(preferences)
        guard preferences.enabled else {
            safetySuspended = false
            lastTimeout = nil
            deactivate("已关闭")
            return
        }
        guard !safetySuspended else { return }
        guard accessibilityCheck() else {
            deactivate("未启用：请在系统设置中手动允许辅助功能权限")
            return
        }
        let configuration = shortcutConfigurationProvider()
        processor.configuration = configuration
        guard configuration.isAvailable else {
            deactivate("未启用：\(configuration.unavailableReason ?? "桌面快捷键配置不受支持")")
            return
        }
        draining = false
        if isRunning {
            setStatus("已启用：鼠标侧键切换左右桌面；按住修饰键保留原操作")
            return
        }
        start()
    }

    private func start() {
        tearDown()
        let context = SideButtonTapContext(owner: self, generation: generation)
        let callback: CGEventTapCallBack = { _, type, event, rawContext in
            guard Thread.isMainThread, let rawContext = rawContext else { return Unmanaged.passUnretained(event) }
            let context = Unmanaged<SideButtonTapContext>.fromOpaque(rawContext).takeUnretainedValue()
            guard context.active, let owner = context.owner else { return Unmanaged.passUnretained(event) }
            return owner.receive(type: type, event: event, generation: context.generation)
                ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = tapCreator(callback, Unmanaged.passUnretained(context).toOpaque()) else {
            context.active = false
            setStatus("未启用：无法创建鼠标侧键监听，请检查辅助功能权限后重试")
            return
        }
        guard CFMachPortIsValid(port),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0),
              let runLoop = CFRunLoopGetMain() else {
            context.active = false
            CFMachPortInvalidate(port)
            setStatus("未启用：无法创建侧键监听的运行循环")
            return
        }
        resources = SideButtonTapResources(port: port, source: source, runLoop: runLoop, context: context)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        tapEnable(port, true)
        guard isRunning else {
            tearDown()
            setStatus("未启用：系统未允许侧键监听，请检查权限后重试")
            return
        }
        setStatus("已启用：鼠标侧键切换左右桌面；按住修饰键保留原操作")
    }

    private func receive(type: CGEventType, event: CGEvent, generation: UInt64) -> Bool {
        guard self.generation == generation, let resources = resources,
              CFMachPortIsValid(resources.port), CFRunLoopSourceIsValid(resources.source) else { return false }
        // 控制通知到来时tap通常已经停用，不能先用isRunning把它过滤掉。
        if type == .tapDisabledByUserInput {
            suspend("侧键监听被系统停用，请手动关闭后重新启用")
            return false
        }
        if type == .tapDisabledByTimeout {
            guard (requestedEnabled || draining), !safetySuspended else { return false }
            guard accessibilityCheck() else {
                suspend("侧键监听无法恢复：辅助功能权限已撤销，请检查后手动重新启用")
                return false
            }
            let now = clock()
            if let last = lastTimeout, now - last < 5 {
                suspend("侧键监听连续超时，已安全暂停，请手动关闭后重新启用")
                return false
            }
            lastTimeout = now
            tapEnable(resources.port, true)
            if tapIsEnabled(resources.port) {
                setStatus(draining ? "\(drainStatus)；侧键监听超时恢复，仅等待已按下侧键释放"
                                   : "侧键监听已从超时恢复；已按下侧键仍保持配对")
            } else {
                suspend("侧键监听超时恢复失败，请手动关闭后重新启用")
            }
            return false
        }
        if draining {
            let consumed = processor.process(type: type, event: event, now: clock(), poster: { _ in false })
            if !processor.hasConsumedPairs {
                let text = drainStatus
                tearDown()
                setStatus(text)
            }
            return consumed
        }
        guard isRunning else { return false }
        return processor.process(type: type, event: event, now: clock(), poster: eventPoster)
    }

    /// 设置变更允许当前已吞下的鼠标整对完成；stop/deinit仍立即释放全部资源。
    private func deactivate(_ text: String) {
        var preferences = processor.preferences
        preferences.enabled = false
        processor.apply(preferences)
        if processor.hasConsumedPairs, let resources = resources,
           CFMachPortIsValid(resources.port), tapIsEnabled(resources.port) {
            draining = true
            drainStatus = text
            setStatus("\(text)；正在等待已按下侧键释放")
        } else {
            tearDown()
            setStatus(text)
        }
    }

    private func suspend(_ text: String) {
        safetySuspended = true
        tearDown()
        setStatus(text)
    }

    func stop() {
        precondition(Thread.isMainThread, "侧键引擎仅可在主线程使用")
        requestedEnabled = false
        safetySuspended = false
        lastTimeout = nil
        processor.apply(SideButtonPreferences())
        tearDown()
        setStatus("已关闭")
    }

    private func tearDown() {
        generation &+= 1
        draining = false
        resources?.invalidate()
        resources = nil
        processor.reset()
    }

    deinit { tearDown() }
    private func setStatus(_ text: String) {
        guard statusText != text else { return }
        statusText = text
        onStatusChange?(text)
    }
    static func diagnosticSnapshot() -> [String: Any] {
        let configuration = SideButtonSystemAdapter.readShortcutConfiguration()
        return ["defaultEnabled": false, "permissionPrompted": false,
         "eventTapAPI": "CGEvent.tapCreate (public)", "shortcutAPI": "CGEvent.post (public)",
         "accessibilityTrusted": AXIsProcessTrusted(), "throttleMilliseconds": 250,
         "sourcePolicy": "physicalOnly", "shortcutPreferencePolicy": "readOnly",
         "shortcutConfigurationAvailable": configuration.isAvailable,
         "shortcutConfigurationStatus": configuration.unavailableReason ?? "使用系统左右桌面快捷键；实际切换效果需授权后验证",
         "deliveryConfirmationAvailable": false, "hardwareAcceptancePerformed": false,
         "subscribedEvents": ["otherMouseDown", "otherMouseUp", "otherMouseDragged"]]
    }
}
