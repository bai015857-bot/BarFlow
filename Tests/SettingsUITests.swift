import AppKit

@main
struct SettingsUITests {
    static func main() {
        _ = NSApplication.shared
        var saved: AppPreferences?
        let controller = SettingsWindowController(preferences: AppPreferences()) { saved = $0 }
        let ids = ["launchAtLogin", "menuEnabled", "autoCollapse", "hotKeyEnabled", "scrollEnabled", "reverseMouse", "reverseTrackpad", "reverseVertical", "reverseHorizontal", "ignoreSynthetic", "sideButtonsEnabled", "swapSideButtons"]
        for id in ids {
            precondition(controller.control(id: id) is NSButton, "Missing usable control: \(id)")
        }
        precondition((controller.control(id: "menuEnabled") as! NSButton).state == .off)
        precondition((controller.control(id: "scrollEnabled") as! NSButton).state == .off)
        let mouse = controller.control(id: "reverseMouse") as! NSButton
        mouse.performClick(nil)
        precondition(saved?.reverseMouse == false, "A real settings button must send a changed preference")
        controller.renderStatus(menu: "菜单栏测试状态", scroll: "滚动测试状态", accessibility: false)
        precondition(controller.statusSummary.contains("菜单栏测试状态"))
        precondition(controller.statusSummary.contains("滚动测试状态"))
        precondition(controller.window?.contentView != nil)
        testLiveSideButtonMapping()
        testObsidianVisualSystem()
        testInheritedAppearanceChangesPreserveState()
        testTogglePresentation()
        testExposedButtonAccessibility()
        testSidebarNavigationPreservesSettings()
        testAdaptiveCardLayout()
        testAllActionCallbacks()
        testEveryPreferenceCallbackIsIsolated()
        testSimplifiedChinesePresentation()
        testLoginItemPresentation()
        testCustomDelays()
        testTrackpadRemainsDisabled()
        testSideButtonControls()
        print("PASS: 12 native settings controls, safe initial state, button callback, status rendering")
        controller.updatePreferences(AppPreferences())
        controller.renderStatus(menu: "菜单栏管理未启用", scroll: "滚动控制未启用", accessibility: false)
        if let flag = CommandLine.arguments.firstIndex(of: "--appearance"), CommandLine.arguments.count > flag + 1 {
            let name: NSAppearance.Name = CommandLine.arguments[flag + 1] == "dark" ? .darkAqua : .aqua
            controller.window?.appearance = NSAppearance(named: name)
        }
        if CommandLine.arguments.contains("--minimum-size") {
            controller.window?.setContentSize(NSSize(width: 880, height: 660))
        }
        if let raw = CommandLine.arguments.firstIndex(of: "--tab"), CommandLine.arguments.count > raw + 1 {
            controller.selectTab(CommandLine.arguments[raw + 1])
        }
        if CommandLine.arguments.contains("--scroll-bottom"), let root = controller.window?.contentView {
            root.layoutSubtreeIfNeeded()
            let tabs = descendants(root).compactMap { $0 as? NSTabView }.first!
            let scroll = tabs.selectedTabViewItem!.view as! NSScrollView
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, scroll.documentView!.bounds.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1,
           let view = controller.window?.contentView {
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
            }
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--window-snapshot"), CommandLine.arguments.count > flag + 1 {
            controller.showWindow(nil)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", "\(controller.window!.windowNumber)", CommandLine.arguments[flag + 1]]
            try! capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0)
        }
        if CommandLine.arguments.contains("--live-preview") {
            controller.showWindow(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) { NSApp.terminate(nil) }
            NSApp.run()
        }
        controller.close()
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    static func testLiveSideButtonMapping() {
        var saved: [AppPreferences] = []
        let controller = SettingsWindowController(preferences: AppPreferences()) { saved.append($0) }
        defer { controller.close() }
        controller.selectTab("sideButtons")
        func mapping(_ id: String) -> String? {
            descendants(controller.window!.contentView!).compactMap { $0 as? NSTextField }
                .first { $0.identifier?.rawValue == id }?.stringValue
        }
        precondition(mapping("mapping.back") == "← 左侧桌面", "选定设计需要显示当前映射，而不是不随交换改变的默认说明")
        precondition(mapping("mapping.forward") == "右侧桌面 →")
        (controller.control(id: "swapSideButtons") as! NSButton).performClick(nil)
        precondition(saved.count == 1 && saved[0].swapSideButtons)
        precondition(mapping("mapping.back") == "右侧桌面 →" && mapping("mapping.forward") == "← 左侧桌面")
        controller.updatePreferences(AppPreferences())
        precondition(mapping("mapping.back") == "← 左侧桌面" && saved.count == 1)
        print("PASS: 侧键实际映射随交换点击与偏好刷新同步，无额外保存")
    }

    static func testObsidianVisualSystem() {
        let controller = SettingsWindowController(preferences: AppPreferences()) { _ in }
        defer { controller.close() }
        let window = controller.window!
        let root = window.contentView!
        precondition(descendants(root).contains { $0.identifier?.rawValue == "settings.obsidianBackdrop" }, "选定曜石设计需要独立的石墨灰视觉表面")
        for page in ["menu", "scroll", "sideButtons", "about"] {
            controller.selectTab(page)
            root.layoutSubtreeIfNeeded()
            let visible = descendants(root)
            precondition(visible.contains { $0.identifier?.rawValue == "header.\(page)" }, "每个功能页需要统一的视觉标题组件")
        }
        for mode in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: mode)
            controller.selectTab("menu")
            root.layoutSubtreeIfNeeded()
            let card = descendants(root).first { $0.identifier?.rawValue == "card.menu.primary" }!
            precondition(card.layer!.cornerRadius >= 10 && card.layer!.cornerRadius <= 14, "精密卡片使用克制的12点圆角")
            let nav = controller.control(id: "nav.menu") as! NSButton
            precondition(nav.state == .on && !nav.hasAmbiguousLayout)
        }
        controller.selectTab("sideButtons")
        root.layoutSubtreeIfNeeded()
        let main = descendants(root).first { $0.identifier?.rawValue == "sideButtons.main" }!
        let prep = descendants(root).first { $0.identifier?.rawValue == "sideButtons.preparation" }!
        let mainRect = main.convert(main.bounds, to: root)
        let prepRect = prep.convert(prep.bounds, to: root)
        precondition(mainRect.maxX < prepRect.minX, "主控映射与准备说明需要左右分区")
        print("PASS: 曜石材质、四页精密标题、克制圆角、侧键左右分区")
    }

    static func testInheritedAppearanceChangesPreserveState() {
        let previous = NSApp.appearance
        var saves = 0
        var initial = AppPreferences()
        initial.swapSideButtons = true
        let controller = SettingsWindowController(preferences: initial) { _ in saves += 1 }
        defer { NSApp.appearance = previous; controller.close() }
        controller.selectTab("sideButtons")
        let root = controller.window!.contentView!
        precondition(controller.window!.appearance == nil)
        var colors: [CGColor] = []
        for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            NSApp.appearance = NSAppearance(named: name)
            root.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            let card = descendants(root).first { $0.identifier?.rawValue == "card.sideButtons.primary" }!
            precondition(card.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
            colors.append(card.layer!.backgroundColor!)
            precondition(controller.window!.appearance == nil && saves == 0)
            precondition((controller.control(id: "swapSideButtons") as! NSButton).state == .on)
        }
        precondition(colors[0] != colors[1] && colors[0] == colors[2], "继承应用外观切换时，真实卡片图层必须更新并恢复")
        print("PASS: 窗口不锁定外观，继承浅→深→浅即时刷新，保留侧键设置且不保存")
    }

    static func testTogglePresentation() {
        var saved: [AppPreferences] = []
        let controller = SettingsWindowController(preferences: AppPreferences()) { saved.append($0) }
        defer { controller.close() }
        controller.selectTab("sideButtons")
        controller.window!.contentView!.layoutSubtreeIfNeeded()
        let toggle = controller.control(id: "sideButtonsEnabled") as! NSButton
        precondition(toggle.frame.width >= 46 && toggle.frame.height >= 30, "开关必须有明确的横向轨道及足够的点击区域")
        precondition(toggle.accessibilityLabel() == "启用鼠标侧键切换桌面")
        precondition(toggle.acceptsFirstResponder, "开关必须保留键盘操作")
        toggle.performClick(nil)
        precondition(toggle.state == .on && saved.last?.sideButtonsEnabled == true)
        toggle.performClick(nil)
        precondition(toggle.state == .off && saved.last?.sideButtonsEnabled == false)
        controller.selectTab("about")
        controller.updateLoginItemState(.requiresApproval)
        let login = controller.control(id: "launchAtLogin") as! NSButton
        precondition(login.state == .mixed, "新的开关外观必须保留待批准状态")
        controller.selectTab("scroll")
        let trackpad = controller.control(id: "reverseTrackpad") as! NSButton
        let count = saved.count
        trackpad.performClick(nil)
        precondition(!trackpad.isEnabled && trackpad.state == .off && saved.count == count)
        print("PASS: 横向开关尺寸、无障碍标签、真实开关动作、mixed及禁用状态")
    }

    static func testExposedButtonAccessibility() {
        var saved: [AppPreferences] = []
        var loginRequests: [Bool] = []
        let controller = SettingsWindowController(preferences: AppPreferences()) { saved.append($0) }
        defer { controller.close() }
        controller.onLoginItemChange = { loginRequests.append($0) }
        let native = NSButton(checkboxWithTitle: "原生对照", target: nil, action: nil)
        let nativeElement = NSAccessibility.unignoredDescendant(of: native) as! NSAccessibilityProtocol
        precondition(nativeElement.accessibilityRole() == .checkBox)
        precondition(nativeElement.accessibilityLabel() == "原生对照" || nativeElement.accessibilityTitle() == "原生对照")
        var failures: [String] = []
        func verify(_ button: NSButton, name: String, value: Int, enabled: Bool, context: String) {
            guard let element = NSAccessibility.unignoredDescendant(of: button) as? NSAccessibilityProtocol else {
                failures.append("\(context)：缺少实际暴露的无障碍元素")
                return
            }
            let label = element.accessibilityLabel() ?? ""
            let title = element.accessibilityTitle() ?? ""
            let role = element.accessibilityRole()
            let actualValue = (element.accessibilityValue() as? NSNumber)?.intValue
            if label != name && title != name { failures.append("\(context)：实际暴露元素缺少中文名称“\(name)”（label=\(label)，title=\(title)）") }
            if role != nativeElement.accessibilityRole() { failures.append("\(context)：必须保留原生 AXCheckBox 角色") }
            if actualValue != value { failures.append("\(context)：AX 值应为 \(value)，实际为 \(String(describing: actualValue))") }
            if element.isAccessibilityEnabled() != enabled { failures.append("\(context)：AX 启用状态错误") }
            print("AX \(context): type=\(type(of: element)) label=\(label) title=\(title) role=\(role?.rawValue ?? "nil") value=\(String(describing: actualValue)) enabled=\(element.isAccessibilityEnabled())")
        }
        controller.selectTab("sideButtons")
        let toggle = controller.control(id: "sideButtonsEnabled") as! NSButton
        verify(toggle, name: "启用鼠标侧键切换桌面", value: 0, enabled: true, context: "off")
        toggle.performClick(nil)
        precondition(toggle.state == .on && saved.count == 1 && saved.last?.sideButtonsEnabled == true)
        verify(toggle, name: "启用鼠标侧键切换桌面", value: 1, enabled: true, context: "on")
        precondition(controller.window!.makeFirstResponder(toggle))
        let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                    windowNumber: controller.window!.windowNumber, context: nil, characters: " ",
                                    charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        toggle.keyDown(with: space)
        precondition(toggle.state == .off && saved.count == 2 && saved.last?.sideButtonsEnabled == false, "本地空格按键必须保留原生切换与回调；不发送全局输入")
        verify(toggle, name: "启用鼠标侧键切换桌面", value: 0, enabled: true, context: "space-off")
        controller.selectTab("about")
        controller.updateLoginItemState(.requiresApproval)
        let login = controller.control(id: "launchAtLogin") as! NSButton
        precondition(login.state == .mixed)
        verify(login, name: "登录时启动轻栏", value: 2, enabled: true, context: "mixed")
        login.performClick(nil)
        precondition(loginRequests == [false] && saved.count == 2, "mixed 仅发送专用禁用回调，不注册登录项")
        controller.selectTab("scroll")
        let disabled = controller.control(id: "reverseTrackpad") as! NSButton
        verify(disabled, name: "触控板保持系统方向（本版）", value: 0, enabled: false, context: "disabled")
        disabled.performClick(nil)
        precondition(!disabled.isEnabled && disabled.state == .off && saved.count == 2 && loginRequests == [false])
        let navigation = [("menu", "菜单栏"), ("scroll", "滚动控制"), ("sideButtons", "侧键切桌面"), ("about", "关于与权限")]
        let tabs = descendants(controller.window!.contentView!).compactMap { $0 as? NSTabView }.first!
        for (id, _) in navigation {
            (controller.control(id: "nav.\(id)") as! NSButton).performClick(nil)
            precondition(tabs.selectedTabViewItem?.identifier as? String == id)
            for (other, name) in navigation {
                let button = controller.control(id: "nav.\(other)") as! NSButton
                precondition(button.state == (other == id ? .on : .off))
                verify(button, name: name, value: other == id ? 1 : 0, enabled: true, context: "nav.\(other) selected=\(id)")
            }
        }
        precondition(saved.count == 2 && loginRequests == [false], "无障碍检查和导航不得产生额外设置回调")
        fflush(stdout)
        precondition(failures.isEmpty, failures.joined(separator: "\n"))
        print("PASS: 实际 unignored 无障碍元素具有中文名称、原生角色、off/on/mixed 的 0/1/2 值和禁用语义；四导航选中/未选中、点击与本地空格回归通过")
    }

    static func testSidebarNavigationPreservesSettings() {
        var saved: [AppPreferences] = []
        let controller = SettingsWindowController(preferences: AppPreferences()) { saved.append($0) }
        defer { controller.close() }
        let root = controller.window!.contentView!
        let tabs = descendants(root).compactMap { $0 as? NSTabView }.first!
        precondition(tabs.tabViewType == .noTabsNoBorder, "侧栏必须驱动无边框内容，而不是原生顶部标签")
        let ids = ["menu", "scroll", "sideButtons", "about"]
        let mouse = controller.control(id: "reverseMouse") as! NSButton
        mouse.performClick(nil)
        controller.renderStatus(menu: "菜单待命", scroll: "滚动已暂停", accessibility: false, sideButtons: "侧键未启用")
        let status = controller.statusSummary
        for id in ids {
            guard let nav = controller.control(id: "nav.\(id)") as? NSButton else {
                preconditionFailure("缺少真正可点击的侧栏按钮：\(id)")
            }
            nav.performClick(nil)
            precondition(tabs.selectedTabViewItem?.identifier as? String == id, "侧栏点击必须切换实际内容：\(id)")
            for other in ids {
                let button = controller.control(id: "nav.\(other)") as! NSButton
                precondition(button.state == (other == id ? .on : .off), "侧栏选中状态必须与内容一致")
                precondition(button.focusRingType != .none, "侧栏必须保留键盘焦点反馈")
                precondition(controller.window!.makeFirstResponder(button) && controller.window!.firstResponder === button, "侧栏按钮应能获得真实键盘焦点")
            }
            precondition(mouse.state == .off && saved.count == 1 && saved.last?.reverseMouse == false)
            precondition(controller.statusSummary == status, "导航不能重置运行状态")
        }
        controller.selectTab("scroll")
        precondition(tabs.selectedTabViewItem?.identifier as? String == "scroll")
        precondition((controller.control(id: "nav.scroll") as! NSButton).state == .on)
        controller.selectTab("missing")
        precondition(tabs.selectedTabViewItem?.identifier as? String == "scroll")
        print("PASS: 四个真实侧栏按钮切换实际内容，程序选择同步高亮，导航保留设置与状态")
    }

    static func testAdaptiveCardLayout() {
        let controller = SettingsWindowController(preferences: AppPreferences()) { _ in }
        defer { controller.close() }
        let window = controller.window!
        precondition(window.styleMask.contains(.resizable), "设置窗口需要可调整尺寸")
        precondition(window.contentMinSize.width == 880 && window.contentMinSize.height == 660)
        precondition(window.contentView!.bounds.size == NSSize(width: 940, height: 720))
        precondition(window.appearance == nil, "默认外观必须跟随系统，不能强制浅色")
        let long = String(repeating: "辅助功能尚未授权，请前往系统设置检查；", count: 24)
        controller.renderStatus(menu: long, scroll: long, accessibility: false, sideButtons: long)
        precondition(controller.statusSummary == [long, long, long, "辅助功能权限：未授权（滚动控制和侧键切桌面需要）"].joined(separator: "\n"))
        var backgrounds: [CGColor] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for size in [NSSize(width: 880, height: 660), NSSize(width: 1060, height: 800)] {
                window.setContentSize(size)
                for tab in ["menu", "scroll", "sideButtons", "about"] {
                    controller.selectTab(tab)
                    window.contentView!.layoutSubtreeIfNeeded()
                    let views = descendants(window.contentView!)
                    let tabs = views.compactMap { $0 as? NSTabView }.first!
                    precondition(tabs.selectedTabViewItem?.identifier as? String == tab)
                    guard let scroll = tabs.selectedTabViewItem?.view as? NSScrollView,
                          let document = scroll.documentView else { preconditionFailure("每页都应可以纵向滚动") }
                    precondition(!scroll.hasHorizontalScroller)
                    precondition(abs(document.frame.width - scroll.contentView.bounds.width) < 2, "正文应随窗口横向收缩")
                    precondition(document.frame.height > 0 && !document.hasAmbiguousLayout)
                    for control in descendants(document).compactMap({ $0 as? NSControl }) {
                        precondition(!control.hasAmbiguousLayout, "内容控件不能有歧义布局：\((control as? NSTextField)?.stringValue ?? control.identifier?.rawValue ?? control.description)，\(control.frame)")
                        let rect = control.convert(control.bounds, to: document)
                        precondition(rect.minX >= -1 && rect.maxX <= document.bounds.width + 1, "控件不能横向溢出")
                        precondition(rect.minY >= -1 && rect.maxY <= document.bounds.height + 1, "控件不能纵向裁切")
                        if let field = control as? NSTextField, field.stringValue == long {
                            let required = field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10000)).height
                            precondition(field.bounds.height + 2 >= required, "长状态必须完整换行，不压成单行")
                        }
                    }
                    precondition(document.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
                    if document.bounds.height > scroll.contentView.bounds.height {
                        let bottom = document.bounds.height - scroll.contentView.bounds.height
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        window.contentView!.layoutSubtreeIfNeeded()
                        precondition(abs(scroll.contentView.bounds.minY - bottom) < 2, "滚动必须能到达长内容底部")
                        scroll.contentView.scroll(to: .zero)
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                    if tab == "menu", size.width == 880 {
                        let card = descendants(document).first { $0.identifier?.rawValue == "card.menu.primary" }!
                        precondition(card.layer!.cornerRadius >= 10 && card.layer!.borderWidth > 0)
                        backgrounds.append(card.layer!.backgroundColor!)
                        let sidebar = views.first { $0.identifier?.rawValue == "settings.sidebar" }!
                        precondition(abs(sidebar.frame.width - 200) < 1)
                    }
                }
            }
        }
        precondition(backgrounds.count == 2 && backgrounds[0] != backgrounds[1], "卡片图层必须响应深浅外观变化")
        print("PASS: 浅色/深色 × 最小/扩展尺寸 × 四页，长状态完整换行、无歧义与裁切、卡片动态配色")
    }

    static func testAllActionCallbacks() {
        let controller = SettingsWindowController(preferences: AppPreferences()) { _ in }
        defer { controller.close() }
        var calls: [String] = []
        controller.onRevealAll = { calls.append("reveal") }
        controller.onToggleMenu = { calls.append("toggle") }
        controller.onRequestAccessibility = { calls.append("request") }
        controller.onOpenPrivacy = { calls.append("privacy") }
        controller.onQuit = { calls.append("quit") }
        for (tab, title, event) in [("menu", "立即展开／收起", "toggle"), ("about", "申请辅助功能权限…", "request"), ("about", "打开隐私设置…", "privacy"), ("about", "安全展开全部图标", "reveal"), ("scroll", "退出", "quit")] {
            controller.selectTab(tab)
            let before = calls.count
            let button = descendants(controller.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == title }!
            button.performClick(nil)
            precondition(calls.count == before + 1 && calls.last == event, "操作按钮必须仅触发对应回调：\(title)")
        }
        print("PASS: 展开、权限、隐私、安全恢复和退出均由真实按钮调用专用回调，无系统副作用")
    }

    static func testEveryPreferenceCallbackIsIsolated() {
        let keys: [(String, WritableKeyPath<AppPreferences, Bool>)] = [
            ("menuEnabled", \.menuEnabled), ("autoCollapse", \.autoCollapse), ("hotKeyEnabled", \.hotKeyEnabled),
            ("scrollEnabled", \.scrollEnabled), ("reverseMouse", \.reverseMouse), ("reverseVertical", \.reverseVertical),
            ("reverseHorizontal", \.reverseHorizontal), ("ignoreSynthetic", \.ignoreSynthetic),
            ("sideButtonsEnabled", \.sideButtonsEnabled), ("swapSideButtons", \.swapSideButtons)
        ]
        for (id, key) in keys {
            var values: [AppPreferences] = []
            let initial = AppPreferences()
            let controller = SettingsWindowController(preferences: initial) { values.append($0) }
            let button = controller.control(id: id) as! NSButton
            button.performClick(nil)
            var expected = initial
            expected[keyPath: key].toggle()
            precondition(values == [expected], "每个设置只修改自身，不得触发额外偏好：\(id)")
            controller.selectTab("about")
            controller.selectTab("scroll")
            controller.selectTab("menu")
            precondition(button.state == (expected[keyPath: key] ? .on : .off))
            controller.updatePreferences(initial)
            precondition(button.state == (initial[keyPath: key] ? .on : .off) && values.count == 1)
            controller.close()
        }
        print("PASS: 十个可用偏好按钮逐一点击，只发送对应字段；刷新与切页不额外保存")
    }

    static func testSimplifiedChinesePresentation() {
        let controller = SettingsWindowController(preferences: AppPreferences()) { _ in }
        defer { controller.close() }
        precondition(controller.window?.title == "轻栏", "窗口标题应只显示中文应用名")
        func visibleTexts(_ view: NSView) -> [String] {
            var values: [String] = []
            if let field = view as? NSTextField { values.append(field.stringValue) }
            if let button = view as? NSButton { values.append(button.title) }
            if let tabs = view as? NSTabView { values += tabs.tabViewItems.map(\.label) }
            values += view.subviews.flatMap(visibleTexts)
            return values
        }
        for tab in ["menu", "scroll", "sideButtons", "about"] {
            controller.selectTab(tab)
            let texts = visibleTexts(controller.window!.contentView!)
            let joined = texts.joined(separator: "\n")
            precondition(!joined.contains("BarFlow"), "设置内容不得残留英文应用名")
            precondition(!joined.contains("Apple Silicon") && !joined.contains("Magic Mouse"), "硬件说明应中文化")
            for value in texts where value.range(of: "[A-Za-z]{3,}", options: .regularExpression) != nil {
                precondition(value.contains("原项目名称") && value.contains("Scroll Reverser"), "仅开源归属中的原始项目名可保留英文：\(value)")
            }
        }
        print("PASS: 全部设置页为简体中文，仅开源归属保留原项目名称")
    }

    static func testSideButtonControls() {
        var saved: [AppPreferences] = []
        let controller = SettingsWindowController(preferences: AppPreferences()) { saved.append($0) }
        defer { controller.close() }
        controller.selectTab("sideButtons")
        let enabled = controller.control(id: "sideButtonsEnabled") as! NSButton
        let swap = controller.control(id: "swapSideButtons") as! NSButton
        precondition(enabled.state == .off && swap.state == .off)
        enabled.performClick(nil)
        precondition(saved.last?.sideButtonsEnabled == true && saved.last?.scrollEnabled == false)
        swap.performClick(nil)
        precondition(saved.last?.swapSideButtons == true && saved.last?.sideButtonsEnabled == true)
        controller.updatePreferences(AppPreferences())
        precondition(enabled.state == .off && swap.state == .off)
        controller.renderStatus(menu: "菜单状态", scroll: "滚动状态", accessibility: false, sideButtons: "侧键尚未启用：辅助功能权限未授权")
        precondition(controller.statusSummary.contains("侧键尚未启用：辅助功能权限未授权"))
        print("PASS: 侧键总开关、交换方向、独立设置回调及中文状态")
    }

    static func testTrackpadRemainsDisabled() {
        var unsupported = AppPreferences()
        unsupported.reverseTrackpad = true
        var saved: [AppPreferences] = []
        let controller = SettingsWindowController(preferences: unsupported) { saved.append($0) }
        defer { controller.close() }
        let trackpad = controller.control(id: "reverseTrackpad") as! NSButton
        precondition(!trackpad.isEnabled && trackpad.state == .off, "Trackpad reversal must stay disabled even for old saved settings")
        precondition(trackpad.title == "触控板保持系统方向（本版）")
        trackpad.performClick(nil)
        precondition(saved.isEmpty, "A disabled real checkbox must not send preference changes")
        controller.updatePreferences(unsupported)
        precondition(!trackpad.isEnabled && trackpad.state == .off, "Preference refresh must preserve the disabled state")
        trackpad.performClick(nil)
        precondition(saved.isEmpty, "A refreshed disabled checkbox must remain inert")
        // Even a stale queued action must not re-enable an unsupported setting.
        precondition(NSApp.sendAction(trackpad.action!, to: trackpad.target, from: trackpad))
        precondition(saved.isEmpty, "A disabled trackpad action must be ignored")
        (controller.control(id: "reverseMouse") as! NSButton).performClick(nil)
        precondition(saved.count == 1 && !saved[0].reverseTrackpad, "Other controls must never emit an old trackpad reversal value")
        controller.selectTab("scroll")
        func texts(_ view: NSView) -> [String] {
            (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap(texts)
        }
        precondition(texts(controller.window!.contentView!).contains("普通鼠标滚轮支持反转；触控板、苹果多点触控鼠标等连续滚动设备保持系统方向。"))
        print("PASS: native trackpad checkbox stays off and disabled, ignores clicks, and explains supported scrolling")
    }

    static func testCustomDelays() {
        for (seconds, title) in [(3.0, "自定义 3 秒"), (8.0, "自定义 8 秒"), (8.5, "自定义 8.5 秒")] {
            var initial = AppPreferences()
            initial.autoCollapseDelay = seconds
            var saved: [Double] = []
            let controller = SettingsWindowController(preferences: initial) { saved.append($0.autoCollapseDelay) }
            let popup = controller.control(id: "autoCollapseDelay") as! NSPopUpButton

            precondition(popup.titleOfSelectedItem == title, "Initial custom delay \(seconds) must be visible in the real popup")
            precondition(popup.selectedItem?.representedObject as? Double == seconds, "Popup must retain its full Double value")
            for next in [8.0, 8.5, 3.0, 15.0, 120.0, 8.5] {
                var updated = initial
                updated.autoCollapseDelay = next
                controller.updatePreferences(updated)
                precondition(popup.selectedItem?.representedObject as? Double == next, "Refreshing settings must select the exact delay")
                precondition(popup.numberOfItems == ([5.0, 15, 30, 60, 120].contains(next) ? 5 : 6), "A refresh must not accumulate stale custom choices")
            }
            precondition(popup.titleOfSelectedItem == "自定义 8.5 秒")
            precondition(saved.isEmpty, "Displaying a custom delay must not save preferences")
            precondition(NSApp.sendAction(popup.action!, to: popup.target, from: popup))
            precondition(saved == [8.5], "Selecting a custom delay must not truncate the callback")
            let preset = popup.itemArray.first { $0.representedObject as? Double == 30 }!
            popup.select(preset)
            precondition(NSApp.sendAction(popup.action!, to: popup.target, from: popup))
            precondition(saved == [8.5, 30], "Preset choices must use the same Double callback")
            controller.close()
        }
        print("PASS: native popup displays 3/8/8.5 seconds on initialization and refresh, exact custom and preset callbacks")
    }

    static func testLoginItemPresentation() {
        var stale = AppPreferences()
        stale.launchAtLogin = true
        var callbackCount = 0
        let controller = SettingsWindowController(preferences: stale, loginItemState: .requiresApproval) { _ in callbackCount += 1 }
        defer { controller.close() }
        let login = controller.control(id: "launchAtLogin") as! NSButton
        precondition(login.state == .mixed, "Pending OS approval must not appear normally enabled from saved preferences")
        let status = controller.control(id: "loginItemStatus") as! NSTextField
        precondition(status.stringValue.contains("需要批准") && status.stringValue.contains("系统设置"), "Pending login items must explain how to approve them")
        controller.updatePreferences(stale)
        precondition(login.state == .mixed, "Refreshing other settings must preserve the OS approval state")
        for state in [LoginItemState.enabled, .notRegistered, .notFound, .unknown] {
            controller.updateLoginItemState(state)
            precondition(login.state == (state == .enabled ? .on : .off), "Login checkbox must follow the current OS state")
            precondition(!status.stringValue.isEmpty, "Every OS state needs an explicit explanation")
        }
        controller.updateLoginItemState(.enabled)
        (controller.control(id: "reverseMouse") as! NSButton).performClick(nil)
        precondition(callbackCount == 1, "Only a user action may send a preference change")
        controller.updateLoginItemState(.requiresApproval)
        controller.updatePreferences(stale)
        precondition(callbackCount == 1, "Read-only status synchronization must not save or request registration")
        var requested: [Bool] = []
        controller.onLoginItemChange = { requested.append($0) }
        login.performClick(nil)
        precondition(requested == [false], "Clicking a pending login checkbox must send an explicit disable request")
        controller.updateLoginItemState(.notRegistered)
        login.performClick(nil)
        precondition(requested == [false, true], "Only clicking the login checkbox may request registration")
        precondition(callbackCount == 1, "A login action must use its dedicated callback, not resubmit unrelated preferences")
        print("PASS: native login checkbox follows OS status and explicitly displays pending approval without callbacks")
    }
}
