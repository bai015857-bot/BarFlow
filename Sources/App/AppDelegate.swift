import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menuController: MenuBarController!
    private var scrollEngine: ScrollEngine!
    private var sideButtonEngine: SideButtonEngine!
    private var settingsWindow: SettingsWindowController!
    private let store = PreferencesStore()
    private var preferences = AppPreferences()
    private var statusTimer: Timer?
    private let smoke = CommandLine.arguments.contains("--smoke-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildApplicationMenu()
        preferences = LaunchPolicy.startupPreferences(store.load(), arguments: CommandLine.arguments)
        // Start expanded, even when the user previously enabled menu management.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "BarFlow.Anchor"
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: "轻栏")
            button.toolTip = "轻栏：左键展开／收起，右键打开快捷菜单与设置"
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menuController = MenuBarController(anchor: statusItem)
        scrollEngine = ScrollEngine()
        sideButtonEngine = SideButtonEngine()
        let loginItemState = Self.currentLoginItemState()
        preferences.launchAtLogin = loginItemState.isEnabled
        settingsWindow = SettingsWindowController(preferences: preferences, loginItemState: loginItemState) { [weak self] next in self?.settingsChanged(next) }
        settingsWindow.onLoginItemChange = { [weak self] enabled in self?.changeLoginItem(enabled) }
        settingsWindow.onRevealAll = { [weak self] in self?.menuController.expand() }
        settingsWindow.onToggleMenu = { [weak self] in self?.menuController.toggle() }
        settingsWindow.onRequestAccessibility = { [weak self] in self?.requestAccessibility() }
        settingsWindow.onOpenPrivacy = { [weak self] in self?.openPrivacy() }
        settingsWindow.onQuit = { NSApp.terminate(nil) }
        menuController.onStateChange = { [weak self] collapsed in self?.updateIcon(collapsed: collapsed) }
        menuController.onStatusChange = { [weak self] _ in self?.refreshStatus() }
        scrollEngine.onStatusChange = { [weak self] _ in self?.refreshStatus() }
        sideButtonEngine.onStatusChange = { [weak self] _ in self?.refreshStatus() }
        applyPreferences()
        refreshStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshStatus() }
        if smoke {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.finishSmoke() }
        } else if CommandLine.arguments.contains("--show-settings") || !UserDefaults.standard.bool(forKey: "barflow.welcomed") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "barflow.welcomed")
        }
    }

    private func buildApplicationMenu() {
        let menu = NSMenu()
        let root = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出轻栏", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu
        menu.addItem(root)
        NSApp.mainMenu = menu
    }

    private func applyPreferences() {
        var menu = MenuPreferences()
        menu.enabled = preferences.menuEnabled
        menu.autoCollapse = preferences.autoCollapse
        menu.autoCollapseDelay = preferences.autoCollapseDelay
        menu.hotKeyEnabled = preferences.hotKeyEnabled
        menuController.apply(menu)
        var scroll = ScrollPreferences()
        scroll.enabled = preferences.scrollEnabled
        scroll.reverseMouse = preferences.reverseMouse
        scroll.reverseTrackpad = preferences.reverseTrackpad
        scroll.reverseVertical = preferences.reverseVertical
        scroll.reverseHorizontal = preferences.reverseHorizontal
        scroll.ignoreSynthetic = preferences.ignoreSynthetic
        scrollEngine.apply(scroll)
        var sideButtons = SideButtonPreferences()
        sideButtons.enabled = preferences.sideButtonsEnabled
        sideButtons.swapDirections = preferences.swapSideButtons
        sideButtonEngine.apply(sideButtons)
    }

    private func settingsChanged(_ next: AppPreferences) {
        preferences = next.sanitized()
        synchronizeLoginItemState()
        store.save(preferences)
        settingsWindow.updatePreferences(preferences)
        applyPreferences()
        refreshStatus()
    }

    private static func currentLoginItemState() -> LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    // Observing system settings never registers a service or writes saved preferences.
    private func synchronizeLoginItemState() {
        let state = Self.currentLoginItemState()
        preferences.launchAtLogin = state.isEnabled
        settingsWindow?.updateLoginItemState(state)
    }

    private func changeLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改登录启动"
            alert.informativeText = "请将轻栏放在固定的应用目录后再试，并检查系统设置中的登录项是否已批准。\n系统错误代码：\((error as NSError).code)"
            alert.addButton(withTitle: "确定")
            if let window = settingsWindow.window { alert.beginSheetModal(for: window) }
        }
        synchronizeLoginItemState()
        store.save(preferences)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        synchronizeLoginItemState()
    }

    @objc private func statusClicked(_ sender: Any?) {
        switch MenuStatusClickAction.resolve(eventType: NSApp.currentEvent?.type,
                                             menuEnabled: preferences.menuEnabled) {
        case .quickMenu: openQuickMenu()
        case .toggle: toggleMenu()
        case .settings: showSettings()
        }
    }

    private func openQuickMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "轻栏", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: menuController.isCollapsed ? "展开菜单栏  ⌥⌘B" : "收起菜单栏  ⌥⌘B", action: #selector(toggleMenu), keyEquivalent: "")
        menu.addItem(withTitle: "安全展开全部图标", action: #selector(revealMenu), keyEquivalent: "")
        menu.addItem(withTitle: "暂停滚动控制", action: #selector(pauseScroll), keyEquivalent: "")
        menu.addItem(withTitle: "暂停侧键切桌面", action: #selector(pauseSideButtons), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "退出轻栏", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleMenu() { menuController.toggle(); refreshStatus() }
    @objc private func revealMenu() { menuController.expand(); refreshStatus() }
    @objc private func pauseScroll() {
        preferences.scrollEnabled = false
        settingsChanged(preferences)
    }
    @objc private func pauseSideButtons() {
        preferences.sideButtonsEnabled = false
        settingsChanged(preferences)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showSettings() {
        synchronizeLoginItemState()
        settingsWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshStatus() {
        guard settingsWindow != nil, menuController != nil, scrollEngine != nil, sideButtonEngine != nil else { return }
        synchronizeLoginItemState()
        settingsWindow.renderStatus(menu: menuController.statusText, scroll: scrollEngine.statusText,
                                    accessibility: AXIsProcessTrusted(), sideButtons: sideButtonEngine.statusText)
    }

    private func updateIcon(collapsed: Bool) {
        statusItem.button?.image = NSImage(systemSymbolName: collapsed ? "chevron.left.2" : "rectangle.compress.vertical", accessibilityDescription: "轻栏")
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshStatus()
    }

    private func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func finishSmoke() {
        let initialCollapsed = menuController.isCollapsed
        let initialScrollRunning = scrollEngine.isRunning
        let initialSideButtonsRunning = sideButtonEngine.isRunning
        let windowBuilt = settingsWindow.window?.contentView != nil
        var nativeTest = MenuPreferences()
        nativeTest.enabled = true
        nativeTest.autoCollapse = false
        nativeTest.hotKeyEnabled = false
        let storedBefore = store.load()
        menuController.apply(nativeTest)
        let nativeExpanded = !menuController.isCollapsed
        menuController.expand()
        menuController.apply(MenuPreferences())
        cleanup()
        let result: [String: Any] = ["settings_window_built": windowBuilt, "menu_collapsed": initialCollapsed,
                                    "scroll_running": initialScrollRunning, "side_buttons_running": initialSideButtonsRunning,
                                    "cleanup_complete": !scrollEngine.isRunning && !sideButtonEngine.isRunning && !menuController.isCollapsed,
                                    "native_menu_enabled_expanded": nativeExpanded, "preferences_unchanged": store.load() == storedBefore]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
        NSApp.terminate(nil)
    }

    private func cleanup() {
        statusTimer?.invalidate()
        statusTimer = nil
        scrollEngine?.stop()
        sideButtonEngine?.stop()
        menuController?.cleanup()
    }

    func applicationWillTerminate(_ notification: Notification) { cleanup() }
}

@main
struct BarFlowMain {
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            let defaults = AppPreferences()
            let result: [String: Any] = ["app": "BarFlow", "version": "0.2.3", "architecture": "arm64",
                "accessibility_trusted": AXIsProcessTrusted(), "scroll": ScrollEngine.diagnosticSnapshot(),
                "side_buttons": SideButtonEngine.diagnosticSnapshot(),
                "safe_defaults": ["menuEnabled": defaults.menuEnabled, "scrollEnabled": defaults.scrollEnabled,
                                  "sideButtonsEnabled": defaults.sideButtonsEnabled]]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        let app = NSApplication.shared
        let other = NSRunningApplication.runningApplications(withBundleIdentifier: "local.longkaixin.barflow")
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard LaunchPolicy.shouldStart(arguments: CommandLine.arguments, existingOtherInstance: other != nil) else {
            other?.activate(options: [.activateIgnoringOtherApps])
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
