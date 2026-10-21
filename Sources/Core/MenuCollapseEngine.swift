import Foundation

enum MenuShortcutResult: Equatable {
    case registered
    case unavailable(Int32)
}

protocol MenuBarDriving: AnyObject {
    var layout: MenuBarLayout? { get }
    var hasCompetingManager: Bool { get }
    func setSeparator(visible: Bool, length: Double)
    func registerShortcut(_ action: @escaping () -> Void) -> MenuShortcutResult
    func unregisterShortcut()
    func removeSeparator()
}

final class MenuCollapseEngine {
    private let driver: MenuBarDriving
    private let scheduler: MenuTimerScheduling
    private var automaticTimer: MenuTimerToken?
    private var safetyTimer: MenuTimerToken?
    private var layoutTimer: MenuTimerToken?
    private var automaticSuspended = false
    private var shortcutRegistered = false
    private var shortcutError: Int32?
    private var cleanedUp = false
    private var preferences = MenuPreferences()
    private(set) var isCollapsed = false {
        didSet { if isCollapsed != oldValue { onStateChange?(isCollapsed) } }
    }
    var onStateChange: ((Bool) -> Void)?
    var onStatusChange: ((String) -> Void)?
    private(set) var statusText = "菜单栏折叠未启用。启用前请注意，其他菜单栏管理软件可能冲突。" {
        didSet { if statusText != oldValue { onStatusChange?(statusText) } }
    }

    init(driver: MenuBarDriving, scheduler: MenuTimerScheduling) {
        self.driver = driver
        self.scheduler = scheduler
    }

    func apply(_ preferences: MenuPreferences) {
        guard !cleanedUp else { return }
        // Reapplying settings must not undo a safety pause; re-enabling is explicit intent.
        if (!self.preferences.enabled && preferences.enabled)
            || (!self.preferences.autoCollapse && preferences.autoCollapse) {
            automaticSuspended = false
        }
        self.preferences = preferences
        if !preferences.enabled {
            isCollapsed = false
            safetyTimer?.cancel()
            safetyTimer = nil
            layoutTimer?.cancel()
            layoutTimer = nil
        }
        updateSeparator()
        updateShortcut()
        scheduleAutomaticCollapse()
        setStatus(preferences.enabled ? "请按住 ⌘ 安排分隔符位置；轻栏图标须保持在分隔符右侧。" : "菜单栏折叠未启用。启用前请注意，其他菜单栏管理软件可能冲突。")
    }

    func toggle() {
        guard !cleanedUp, preferences.enabled else { return }
        if isCollapsed { expand(); return }
        if driver.layout?.allowsCollapse != true {
            reveal(status: "请按住 ⌘ 拖动分隔符到待隐藏图标右侧，并让轻栏图标保持在分隔符右侧且位于同一屏幕。自动折叠已暂停。", suspendAutomatic: true)
            return
        }
        isCollapsed = true
        automaticTimer?.cancel()
        updateSeparator()
        setStatus("菜单栏已折叠")
        safetyTimer = scheduler.schedule(after: 90, repeating: nil) { [weak self] in
            self?.reveal(status: "已达到 90 秒安全时限，已自动展开；自动折叠已暂停。", suspendAutomatic: true)
        }
        layoutTimer = scheduler.schedule(after: 1, repeating: 1) { [weak self] in
            guard let self = self, self.isCollapsed, self.driver.layout?.allowsCollapse != true else { return }
            self.reveal(status: "分隔符或恢复入口位置异常，已展开；请重新安排同屏左右位置。", suspendAutomatic: true)
        }
    }

    func expand() {
        reveal(status: "菜单栏已展开", suspendAutomatic: false)
    }

    private func reveal(status: String, suspendAutomatic: Bool) {
        guard !cleanedUp else { return }
        safetyTimer?.cancel()
        safetyTimer = nil
        layoutTimer?.cancel()
        layoutTimer = nil
        automaticSuspended = suspendAutomatic
        isCollapsed = false
        updateSeparator()
        setStatus(status)
        scheduleAutomaticCollapse()
    }

    private func scheduleAutomaticCollapse() {
        automaticTimer?.cancel()
        automaticTimer = nil
        guard preferences.enabled, preferences.autoCollapse, !isCollapsed, !automaticSuspended,
              !driver.hasCompetingManager else { return }
        let delay = preferences.autoCollapseDelay.isFinite
            ? min(3600, max(3, preferences.autoCollapseDelay)) : 15
        automaticTimer = scheduler.schedule(after: delay, repeating: nil) { [weak self] in
            guard let self = self, self.preferences.enabled, !self.isCollapsed else { return }
            if self.driver.hasCompetingManager {
                self.setStatus("自动折叠已停用。")
                return
            }
            self.toggle()
        }
    }

    private func updateSeparator() {
        driver.setSeparator(visible: preferences.enabled, length: isCollapsed ? 5000 : 20)
    }

    func cleanup() {
        guard !cleanedUp else { return }
        cleanedUp = true
        automaticTimer?.cancel()
        safetyTimer?.cancel()
        layoutTimer?.cancel()
        automaticTimer = nil
        safetyTimer = nil
        layoutTimer = nil
        preferences.enabled = false
        isCollapsed = false
        driver.setSeparator(visible: false, length: 20)
        driver.unregisterShortcut()
        driver.removeSeparator()
        shortcutRegistered = false
        shortcutError = nil
        setStatus("菜单栏已恢复")
    }

    private func setStatus(_ message: String) {
        statusText = message + (driver.hasCompetingManager ? " 检测到其他菜单栏管理软件，可能存在冲突，自动折叠已停用。" : "")
            + (shortcutError.map { " ⌥⌘B 快捷键注册失败（\($0)），请使用轻栏菜单操作。" } ?? "")
    }

    private func updateShortcut() {
        guard preferences.enabled && preferences.hotKeyEnabled else {
            driver.unregisterShortcut()
            shortcutRegistered = false
            shortcutError = nil
            return
        }
        guard !shortcutRegistered else { return }
        switch driver.registerShortcut({ [weak self] in self?.toggle() }) {
        case .registered:
            shortcutRegistered = true
            shortcutError = nil
        case .unavailable(let code):
            shortcutError = code
        }
    }
}
