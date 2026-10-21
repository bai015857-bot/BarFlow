import AppKit

/// 仅渲染设置界面；不创建菜单栏项、不安装输入监听、不访问正式偏好或系统授权。
@main
struct SettingsPreview {
    static var controller: SettingsWindowController!
    static var preferences = AppPreferences()
    static var loginEnabled = false

    static func argument(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.count > index + 1 else { return nil }
        return CommandLine.arguments[index + 1]
    }

    static func render(_ note: String? = nil) {
        controller.window?.subtitle = note ?? "独立界面预览"
        controller.renderStatus(
            menu: note ?? "界面预览：未连接实际菜单栏管理。",
            scroll: note ?? "界面预览：未启动滚动监听。",
            accessibility: false,
            sideButtons: note ?? "界面预览：未启动侧键监听，正式应用不受影响。")
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if CommandLine.arguments.contains("--demo-enabled") { preferences.sideButtonsEnabled = true }
        controller = SettingsWindowController(preferences: preferences) { next in
            preferences = next
            controller.updatePreferences(next)
            render()
        }
        controller.onLoginItemChange = { enabled in
            loginEnabled = enabled
            controller.updateLoginItemState(enabled ? .enabled : .notRegistered)
            render("界面预览：登录开关仅演示外观，不注册系统登录项。")
        }
        controller.onRevealAll = { render("界面预览：安全展开按钮回调正常；未操作系统菜单栏。") }
        controller.onToggleMenu = { render("界面预览：切换按钮回调正常；未操作系统菜单栏。") }
        controller.onRequestAccessibility = { render("界面预览：不会申请或授予系统权限。") }
        controller.onOpenPrivacy = { render("界面预览：不会打开或修改系统设置。") }
        controller.onQuit = { app.terminate(nil) }
        guard let window = controller.window else { return }
        window.title = "轻栏 · 曜石精密预览（不修改正式设置）"
        for button in descendants(window.contentView!).compactMap({ $0 as? NSButton }) {
            if button.title == "安全展开全部图标" { button.title = "演示：安全展开" }
            if button.title == "退出" { button.title = "退出预览" }
        }
        if let mode = argument("--appearance"), ["light", "dark"].contains(mode) {
            window.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
        }
        if CommandLine.arguments.contains("--verify-follow-system") {
            precondition(window.appearance == nil, "独立预览必须默认继承系统外观，不能强制深色")
            print("PASS: 独立预览默认跟随系统外观")
            app.terminate(nil)
            return
        }
        controller.selectTab(argument("--page") ?? "sideButtons")
        render()
        if CommandLine.arguments.contains("--minimum-size") { window.setContentSize(NSSize(width: 880, height: 660)) }
        if CommandLine.arguments.contains("--scroll-bottom") {
            window.contentView!.layoutSubtreeIfNeeded()
            let tabs = descendants(window.contentView!).compactMap { $0 as? NSTabView }.first!
            let scroll = tabs.selectedTabViewItem!.view as! NSScrollView
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, scroll.documentView!.bounds.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        controller.showWindow(nil)
        if let output = argument("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(window.windowNumber), output]
                do {
                    try capture.run()
                    capture.waitUntilExit()
                    guard capture.terminationStatus == 0 else { app.terminate(nil); return }
                    print("已保存外观预览：\(output)")
                } catch { fputs("无法保存预览：\(error)\n", stderr) }
                app.terminate(nil)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) { app.terminate(nil) }
        }
        withExtendedLifetime(controller) { app.run() }
    }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
