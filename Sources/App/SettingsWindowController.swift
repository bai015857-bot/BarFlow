import AppKit

final class SettingsWindowController: NSWindowController {
    private var preferences: AppPreferences
    private var loginItemState: LoginItemState
    private let onChange: (AppPreferences) -> Void
    private var controls: [String: NSControl] = [:]
    private var tabs: NSTabView!
    private let menuStatus = SettingsText("菜单栏管理未启用")
    private let scrollStatus = SettingsText("滚动控制未启用")
    private let sideButtonStatus = SettingsText("侧键切桌面未启用")
    private let permissionStatus = SettingsText("辅助功能权限：未检查")
    private let loginItemStatus = SettingsText("")
    private let backMapping = SettingsText("← 左侧桌面")
    private let forwardMapping = SettingsText("右侧桌面 →")
    var onLoginItemChange: ((Bool) -> Void)?
    var onRevealAll: (() -> Void)?
    var onToggleMenu: (() -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onOpenPrivacy: (() -> Void)?
    var onQuit: (() -> Void)?

    var statusSummary: String { [menuStatus, scrollStatus, sideButtonStatus, permissionStatus].map(\.stringValue).joined(separator: "\n") }

    init(preferences: AppPreferences, loginItemState: LoginItemState = .notRegistered, onChange: @escaping (AppPreferences) -> Void) {
        self.preferences = preferences.sanitized()
        self.loginItemState = loginItemState
        self.onChange = onChange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "轻栏"
        window.contentMinSize = NSSize(width: 880, height: 660)
        window.backgroundColor = SettingsPalette.background
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildContent()
        updateLoginItemState(loginItemState)
        updateSideButtonMapping()
    }

    required init?(coder: NSCoder) { nil }
    func control(id: String) -> NSControl? { controls[id] }

    func selectTab(_ id: String) {
        guard let item = tabs.tabViewItems.first(where: { ($0.identifier as? String) == id }) else { return }
        tabs.selectTabViewItem(item)
        for tab in tabs.tabViewItems {
            if let name = tab.identifier as? String, let button = controls["nav.\(name)"] as? NSButton {
                button.state = name == id ? .on : .off
            }
        }
    }

    func updateLoginItemState(_ value: LoginItemState) {
        loginItemState = value
        preferences.launchAtLogin = value.isEnabled
        if let button = controls["launchAtLogin"] as? NSButton {
            button.allowsMixedState = value == .requiresApproval
            button.state = value == .requiresApproval ? .mixed : (value.isEnabled ? .on : .off)
        }
        loginItemStatus.stringValue = value.statusText
    }

    func updatePreferences(_ value: AppPreferences) {
        let value = value.sanitized()
        preferences = value
        for (id, control) in controls {
            if let button = control as? NSButton, let key = Self.boolKeys[id] {
                button.state = value[keyPath: key] ? .on : .off
                if id == "reverseTrackpad" { button.isEnabled = false }
            }
        }
        if let popup = controls["autoCollapseDelay"] as? NSPopUpButton {
            populateDelayMenu(popup, seconds: value.autoCollapseDelay)
        }
        updateLoginItemState(loginItemState)
        updateSideButtonMapping()
    }

    func renderStatus(menu: String, scroll: String, accessibility: Bool, sideButtons: String = "侧键切桌面未启用") {
        menuStatus.stringValue = menu
        scrollStatus.stringValue = scroll
        sideButtonStatus.stringValue = sideButtons
        permissionStatus.stringValue = accessibility ? "辅助功能权限：已授权" : "辅助功能权限：未授权（滚动控制和侧键切桌面需要）"
    }

    private static let boolKeys: [String: WritableKeyPath<AppPreferences, Bool>] = [
        "launchAtLogin": \.launchAtLogin,
        "menuEnabled": \.menuEnabled, "autoCollapse": \.autoCollapse, "hotKeyEnabled": \.hotKeyEnabled,
        "scrollEnabled": \.scrollEnabled, "reverseMouse": \.reverseMouse, "reverseTrackpad": \.reverseTrackpad,
        "reverseVertical": \.reverseVertical, "reverseHorizontal": \.reverseHorizontal, "ignoreSynthetic": \.ignoreSynthetic,
        "sideButtonsEnabled": \.sideButtonsEnabled, "swapSideButtons": \.swapSideButtons
    ]

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let background = SettingsSurface(kind: .background)
        background.identifier = NSUserInterfaceItemIdentifier("settings.obsidianBackdrop")
        pin(background, in: content)
        let sidebar = SettingsSurface(kind: .sidebar)
        sidebar.identifier = NSUserInterfaceItemIdentifier("settings.sidebar")
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 200)
        ])
        let brand = NSStackView()
        brand.orientation = .horizontal
        brand.alignment = .centerY
        brand.spacing = 11
        brand.translatesAutoresizingMaskIntoConstraints = false
        let mark = SettingsEmblem(symbol: "menubar.rectangle", size: 36)
        brand.addArrangedSubview(mark)
        let brandTitles = vertical(spacing: 4)
        brandTitles.addArrangedSubview(label("轻栏", size: 21, weight: .semibold))
        brandTitles.addArrangedSubview(label("少一点干扰", size: 11, color: .secondaryLabelColor))
        brand.addArrangedSubview(brandTitles)
        sidebar.addSubview(brand)
        NSLayoutConstraint.activate([
            brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22),
            brand.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 30)
        ])
        let navigation = vertical(spacing: 5)
        sidebar.addSubview(navigation)
        NSLayoutConstraint.activate([
            navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            navigation.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            navigation.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 30)
        ])
        let definitions: [(String, String, String, NSView)] = [
            ("menu", "菜单栏", "menubar.rectangle", menuPane()),
            ("scroll", "滚动控制", "computermouse", scrollPane()),
            ("sideButtons", "侧键切桌面", "rectangle.2.swap", sideButtonPane()),
            ("about", "关于与权限", "info.circle", aboutPane())
        ]
        let tabs = NSTabView()
        self.tabs = tabs
        tabs.tabViewType = .noTabsNoBorder
        tabs.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabs)
        for (id, title, symbol, pane) in definitions {
            let item = NSTabViewItem(identifier: id)
            item.label = title
            item.view = pane
            tabs.addTabViewItem(item)
            let nav = SettingsNavigationButton(title: title, symbol: symbol, target: self, action: #selector(navigate(_:)))
            nav.identifier = NSUserInterfaceItemIdentifier("nav.\(id)")
            nav.setAccessibilityIdentifier("nav.\(id)")
            controls["nav.\(id)"] = nav
            navigation.addArrangedSubview(nav)
            nav.widthAnchor.constraint(equalTo: navigation.widthAnchor).isActive = true
            nav.heightAnchor.constraint(equalToConstant: 46).isActive = true
        }
        let sidebarFooter = vertical(spacing: 7)
        sidebarFooter.addArrangedSubview(label("曜石精密 · 跟随系统外观", size: 11, weight: .medium, color: SettingsPalette.accent))
        sidebarFooter.addArrangedSubview(label("本地处理 · 无遥测", size: 11, color: .secondaryLabelColor))
        sidebarFooter.addArrangedSubview(label("版本 0.2.2", size: 11, color: .secondaryLabelColor))
        sidebar.addSubview(sidebarFooter)
        NSLayoutConstraint.activate([
            sidebarFooter.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22),
            sidebarFooter.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            sidebarFooter.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -24)
        ])
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(divider)
        let actions = NSStackView(views: [label("全局操作", size: 11, color: .secondaryLabelColor), NSView(), button("安全展开全部图标", action: #selector(reveal)), button("退出", action: #selector(quit))])
        actions.spacing = 12
        actions.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(actions)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: content.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 64),
            divider.topAnchor.constraint(equalTo: footer.topAnchor),
            divider.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            actions.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 30),
            actions.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -30),
            actions.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
        selectTab("menu")
    }

    private func pane(_ title: String, subtitle: String) -> (NSScrollView, NSStackView) {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let stack = vertical(spacing: 18)
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -30)
        ])
        let heading = vertical(spacing: 9)
        add(label("偏好设置  /  \(title)", size: 11, color: .secondaryLabelColor), to: heading)
        add(label(title, size: 27, weight: .semibold), to: heading)
        add(label(subtitle, size: 13, color: .secondaryLabelColor), to: heading)
        let page: String
        switch title {
        case "菜单栏": page = "menu"
        case "滚动控制": page = "scroll"
        case "侧键切桌面": page = "sideButtons"
        default: page = "about"
        }
        heading.identifier = NSUserInterfaceItemIdentifier("header.\(page)")
        add(heading, to: stack)
        return (scroll, stack)
    }

    private func menuPane() -> NSView {
        let (view, stack) = pane("菜单栏", subtitle: "收起不常用的图标，让常用入口留在眼前。")
        add(card("card.menu.primary", rows: [
            setting("启用菜单栏折叠", description: "按需展开与收起，首次启动不会自动折叠。", id: "menuEnabled"),
            insetNote("按住 ⌘ 拖动菜单栏的分隔符「│」：需要隐藏的图标放在它左侧，轻栏的图标放在它右侧。")
        ]), to: stack)
        add(section("展开与收起", rows: [
            setting("展开后自动收起", description: "展开后，等待所选时间再收起图标。", id: "autoCollapse"),
            row("等待时间", description: "仅在自动收起开启时生效。", trailing: delayMenu()),
            setting("启用快捷键 ⌥⌘B（展开／收起）", description: "无需打开设置，即可切换菜单栏状态。", id: "hotKeyEnabled"),
            row("手动切换", description: "立即展开或收起当前图标。", trailing: button("立即展开／收起", action: #selector(toggle)))
        ]), to: stack)
        add(statusCard(menuStatus), to: stack)
        add(note("安全保护：折叠前检查恢复入口位置，退出时自动展开。其他菜单栏管理软件运行时，请先手动暂停其管理功能。本版不含截图聚合面板。"), to: stack)
        return view
    }

    private func scrollPane() -> NSView {
        let (view, stack) = pane("滚动控制", subtitle: "为鼠标滚轮调整方向，连续滚动保持系统习惯。")
        add(card("card.scroll.primary", rows: [
            setting("启用滚动方向控制", description: "建议系统保持“自然滚动”，在这里仅反转鼠标。", id: "scrollEnabled")
        ]), to: stack)
        add(section("设备与方向", rows: [
            setting("反转鼠标", description: "适用于普通鼠标的非连续滚轮。", id: "reverseMouse"),
            setting("触控板保持系统方向（本版）", description: "本版不提供触控板独立反转，此项不可更改。", id: "reverseTrackpad"),
            setting("反转纵向", description: "调整上下滚动的方向。", id: "reverseVertical"),
            setting("反转横向", description: "调整左右滚动的方向。", id: "reverseHorizontal"),
            setting("忽略其他软件生成的滚动（远程桌面更安全）", description: "不改写其他软件合成的滚动事件。", id: "ignoreSynthetic")
        ]), to: stack)
        add(statusCard(scrollStatus), to: stack)
        add(note("启用前请手动退出原滚动反转软件，避免重复反转；轻栏不会替你关闭其他软件。"), to: stack)
        add(note("普通鼠标滚轮支持反转；触控板、苹果多点触控鼠标等连续滚动设备保持系统方向。"), to: stack)
        return view
    }

    private func sideButtonPane() -> NSView {
        let (view, stack) = pane("侧键切桌面", subtitle: "把常用的桌面切换，交给拇指。")
        let main = vertical(spacing: 18)
        main.identifier = NSUserInterfaceItemIdentifier("sideButtons.main")
        add(card("card.sideButtons.primary", rows: [
            setting("启用鼠标侧键切换桌面", description: "替代网页前进／后退，关闭后恢复原作用。", id: "sideButtonsEnabled"),
            setting("交换两个侧键的切换方向", description: "调换后退侧键与前进侧键对应的桌面。", id: "swapSideButtons")
        ]), to: main)
        backMapping.identifier = NSUserInterfaceItemIdentifier("mapping.back")
        forwardMapping.identifier = NSUserInterfaceItemIdentifier("mapping.forward")
        for field in [backMapping, forwardMapping] {
            field.font = .systemFont(ofSize: 12, weight: .medium)
            field.textColor = SettingsPalette.primary
        }
        add(section("预设按键映射 · 主开关开启后生效", rows: [
            row("后退侧键", description: "鼠标第 4 键", trailing: backMapping),
            row("前进侧键", description: "鼠标第 5 键", trailing: forwardMapping)
        ]), to: main)
        add(statusCard(sideButtonStatus), to: main)
        add(note("按住修饰键时保留原点击；长按不会连续切换。\n不改变左键、右键、中键和滚轮。"), to: main)
        let preparation = vertical(spacing: 20)
        preparation.identifier = NSUserInterfaceItemIdentifier("sideButtons.preparation")
        // 右栏按内容收紧；不能被左栏长状态拉高并任意分配段落空白。
        preparation.setHuggingPriority(.required, for: .vertical)
        add(label("使用前准备", size: 13, weight: .medium), to: preparation)
        for (number, title, detail) in [
            ("1", "辅助功能权限", "在“关于与权限”中手动授予轻栏。"),
            ("2", "桌面切换快捷键", "系统设置 → 键盘\n键盘快捷键 → 调度中心\n启用“向左移动一个空间”\n以及“向右移动一个空间”。"),
            ("3", "至少两个桌面", "默认快捷键：⌃←／⌃→\n到达桌面边界时不会循环。")
        ] {
            let item = vertical(spacing: 7)
            add(label("\(number)  \(title)", size: 12, weight: .medium), to: item)
            add(note(detail), to: item)
            add(item, to: preparation)
        }
        add(note("兼容性\n鼠标驱动若已改写侧键，请先恢复默认映射。"), to: preparation)
        let rule = SettingsSurface(kind: .separator)
        rule.translatesAutoresizingMaskIntoConstraints = false
        rule.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let columns = NSView()
        columns.translatesAutoresizingMaskIntoConstraints = false
        for child in [main, rule, preparation] { columns.addSubview(child) }
        // 两列高度独立：左侧长运行状态不能把右侧段落间距强制拉大。
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: columns.leadingAnchor),
            main.topAnchor.constraint(equalTo: columns.topAnchor),
            main.bottomAnchor.constraint(equalTo: columns.bottomAnchor),
            main.trailingAnchor.constraint(equalTo: rule.leadingAnchor, constant: -22),
            rule.topAnchor.constraint(equalTo: columns.topAnchor),
            rule.heightAnchor.constraint(equalTo: preparation.heightAnchor),
            rule.trailingAnchor.constraint(equalTo: preparation.leadingAnchor, constant: -22),
            preparation.topAnchor.constraint(equalTo: columns.topAnchor),
            preparation.trailingAnchor.constraint(equalTo: columns.trailingAnchor),
            preparation.widthAnchor.constraint(equalToConstant: 180),
            preparation.bottomAnchor.constraint(lessThanOrEqualTo: columns.bottomAnchor)
        ])
        add(columns, to: stack)
        return view
    }

    private func aboutPane() -> NSView {
        let (view, stack) = pane("关于与权限", subtitle: "轻栏 0.2.2 · 为日常操作减一点负担。")
        add(card("card.about.primary", rows: [insetNote("原创菜单栏与滚动控制工具。所有处理在本机完成，不接入账户、云服务或统计。本软件为独立项目，非其他同类软件的官方版本。")]), to: stack)
        loginItemStatus.identifier = NSUserInterfaceItemIdentifier("loginItemStatus")
        controls["loginItemStatus"] = loginItemStatus
        add(section("启动", rows: [
            setting("登录时启动轻栏", description: "登录状态以系统实际注册结果为准。", id: "launchAtLogin"),
            inset(loginItemStatus)
        ]), to: stack)
        let permissionButtons = NSStackView(views: [button("申请辅助功能权限…", action: #selector(requestAccessibility)), button("打开隐私设置…", action: #selector(openPrivacy))])
        permissionButtons.spacing = 10
        add(section("辅助功能权限", rows: [
            inset(permissionStatus),
            insetNote("权限只由你在系统设置中授予。菜单栏折叠不需要辅助功能；滚动控制和侧键切桌面需要。本软件不截屏，不申请屏幕录制。"),
            inset(permissionButtons)
        ]), to: stack)
        add(note("开源参考：滚动反转项目（原项目名称：Scroll Reverser，作者：Nick Moore）。随包保留原始许可证与来源声明。\n构建：本机开发签名，未经苹果公证；当前版本适用于苹果芯片电脑。"), to: stack)
        return view
    }

    private func section(_ title: String, rows: [NSView]) -> NSView {
        let stack = vertical(spacing: 9)
        add(label(title, size: 12, weight: .medium, color: .secondaryLabelColor), to: stack)
        add(card(nil, rows: rows), to: stack)
        return stack
    }

    private func card(_ id: String?, rows: [NSView]) -> NSView {
        let surface = SettingsSurface(kind: .card)
        if let id = id { surface.identifier = NSUserInterfaceItemIdentifier(id) }
        let stack = vertical(spacing: 0)
        pin(stack, in: surface)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = SettingsSurface(kind: .separator)
                separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                add(separator, to: stack)
            }
            add(row, to: stack)
        }
        return surface
    }

    private func statusCard(_ field: NSTextField) -> NSView {
        let stack = vertical(spacing: 7)
        add(label("当前状态", size: 11, weight: .medium, color: .secondaryLabelColor), to: stack)
        field.font = .systemFont(ofSize: 12)
        field.textColor = SettingsPalette.secondary
        add(field, to: stack)
        return card(nil, rows: [inset(stack)])
    }

    private func setting(_ title: String, description: String, id: String) -> NSView {
        row(title, description: description, trailing: check(title, id: id))
    }

    private func row(_ title: String, description: String, trailing: NSView) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        let text = vertical(spacing: 5)
        add(label(title, size: 13, weight: .medium), to: text)
        add(note(description), to: text)
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailing.translatesAutoresizingMaskIntoConstraints = false
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.addSubview(text)
        view.addSubview(trailing)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            text.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            text.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -20),
            trailing.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            trailing.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            trailing.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 12),
            trailing.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
        return view
    }

    private func insetNote(_ text: String) -> NSView { inset(note(text)) }
    private func inset(_ child: NSView) -> NSView {
        let view = NSView()
        pin(child, in: view, inset: 18)
        return view
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let field = SettingsText(text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color == .secondaryLabelColor ? SettingsPalette.secondary : (color == .labelColor ? SettingsPalette.primary : color)
        return field
    }
    private func note(_ text: String) -> NSTextField { label(text, size: 12, color: .secondaryLabelColor) }
    private func vertical(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    private func add(_ child: NSView, to stack: NSStackView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func pin(_ child: NSView, in parent: NSView, inset: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }

    private func check(_ title: String, id: String) -> NSButton {
        let check = SettingsToggleButton(checkboxWithTitle: title, target: self, action: #selector(changed(_:)))
        check.identifier = NSUserInterfaceItemIdentifier(id)
        check.setAccessibilityIdentifier(id)
        check.setAccessibilityLabel(title)
        check.imagePosition = .imageOnly
        // AppKit exposes the cell, not the ignored single-cell NSButton view.
        check.cell?.setAccessibilityLabel(title)
        check.contentTintColor = SettingsPalette.accent
        check.toolTip = title
        if let key = Self.boolKeys[id] { check.state = preferences[keyPath: key] ? .on : .off }
        if id == "reverseTrackpad" { check.isEnabled = false }
        controls[id] = check
        return check
    }

    private func delayMenu() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        populateDelayMenu(popup, seconds: preferences.autoCollapseDelay)
        popup.identifier = NSUserInterfaceItemIdentifier("autoCollapseDelay")
        popup.setAccessibilityLabel("自动收起等待时间")
        popup.target = self
        popup.action = #selector(delayChanged(_:))
        controls["autoCollapseDelay"] = popup
        return popup
    }

    private func populateDelayMenu(_ popup: NSPopUpButton, seconds: Double) {
        let presets: [Double] = [5, 15, 30, 60, 120]
        popup.removeAllItems()
        for preset in presets {
            popup.addItem(withTitle: "\(Int(preset)) 秒")
            popup.lastItem?.representedObject = preset
        }
        if !presets.contains(seconds) {
            let text = seconds.rounded() == seconds ? String(Int(seconds)) : String(seconds)
            popup.addItem(withTitle: "自定义 \(text) 秒")
            popup.lastItem?.representedObject = seconds
        }
        popup.select(popup.itemArray.first { $0.representedObject as? Double == seconds })
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        button.contentTintColor = SettingsPalette.accent
        return button
    }
    @objc private func navigate(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, id.hasPrefix("nav.") else { return }
        selectTab(String(id.dropFirst(4)))
    }
    @objc private func changed(_ sender: NSButton) {
        guard sender.isEnabled, let id = sender.identifier?.rawValue, let key = Self.boolKeys[id] else { return }
        if id == "launchAtLogin" {
            onLoginItemChange?(loginItemState == .requiresApproval ? false : sender.state == .on)
            return
        }
        preferences[keyPath: key] = sender.state == .on
        updateSideButtonMapping()
        onChange(preferences)
    }

    private func updateSideButtonMapping() {
        backMapping.stringValue = preferences.swapSideButtons ? "右侧桌面 →" : "← 左侧桌面"
        forwardMapping.stringValue = preferences.swapSideButtons ? "← 左侧桌面" : "右侧桌面 →"
    }
    @objc private func delayChanged(_ sender: NSPopUpButton) {
        guard let seconds = sender.selectedItem?.representedObject as? Double else { return }
        preferences.autoCollapseDelay = seconds
        onChange(preferences)
    }
    @objc private func reveal() { onRevealAll?() }
    @objc private func toggle() { onToggleMenu?() }
    @objc private func requestAccessibility() { onRequestAccessibility?() }
    @objc private func openPrivacy() { onOpenPrivacy?() }
    @objc private func quit() { onQuit?() }
}

/// Uses the actual constrained width so long runtime messages grow vertically.
private final class SettingsText: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        cell?.wraps = true
        cell?.isScrollable = false
        cell?.usesSingleLineMode = false
        lineBreakMode = .byWordWrapping
        font = .systemFont(ofSize: 12)
        textColor = SettingsPalette.primary
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { nil }
    override var stringValue: String {
        didSet { invalidateIntrinsicContentSize() }
    }
    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if changed { invalidateIntrinsicContentSize() }
    }
    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 1 ? bounds.width : 500
        let height = cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 100000)).height ?? 18
        return NSSize(width: super.intrinsicContentSize.width, height: ceil(height))
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// 曜石精密：不透明石墨灰／暖白表面；颜色随系统即时解析。
private enum SettingsPalette {
    static func color(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    static let accent = color(hex(0x805733), hex(0xE7BD9A))
    static let primary = color(hex(0x302B27), hex(0xF1F0EF))
    static let secondary = color(hex(0x69605A), hex(0xB2B1B9))
    static let background = color(hex(0xFCFAF7), hex(0x15171B))
    static let sidebar = color(hex(0xF1EDE7), hex(0x111317))
    static let card = color(hex(0xFFFFFF), hex(0x1C1E23))
    static let raised = color(hex(0xF4F0EB), hex(0x28292F))
    static let border = color(hex(0xD8D0C7), hex(0x363841))
    static let track = color(hex(0xD9D0C5), hex(0x30323A))
    static let thumb = color(hex(0xFFFFFF), hex(0xCECED4))
    static let selectedThumb = color(hex(0xFFFFFF), hex(0x252326))
}

/// 重新解析图层颜色，避免系统外观切换后残留旧CGColor；无动画、无定时器。
private final class SettingsSurface: NSView {
    enum Kind { case background, sidebar, card, separator }
    private let kind: Kind
    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        if kind == .card {
            layer?.cornerRadius = 12
            layer?.borderWidth = 0.7
            layer?.masksToBounds = true
        }
        updateColors()
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        needsDisplay = true
    }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch kind {
            case .background: layer?.backgroundColor = SettingsPalette.background.cgColor
            case .sidebar: layer?.backgroundColor = SettingsPalette.sidebar.cgColor
            case .card:
                layer?.backgroundColor = SettingsPalette.card.cgColor
                layer?.borderColor = SettingsPalette.border.cgColor
            case .separator: layer?.backgroundColor = SettingsPalette.border.cgColor
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        switch kind {
        case .sidebar:
            SettingsPalette.border.setStroke()
            let edge = NSBezierPath()
            edge.lineWidth = 0.7
            edge.move(to: NSPoint(x: bounds.maxX - 0.5, y: 0))
            edge.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
            edge.stroke()
        case .card:
            let highlight = NSBezierPath()
            highlight.move(to: NSPoint(x: 12, y: bounds.maxY - 1))
            highlight.line(to: NSPoint(x: bounds.maxX - 12, y: bounds.maxY - 1))
            NSColor.white.withAlphaComponent(0.045).setStroke()
            highlight.lineWidth = 0.7
            highlight.stroke()
        case .background, .separator: break
        }
    }
}

private final class SettingsEmblem: NSView {
    private let symbol: String
    private let size: CGFloat
    init(symbol: String, size: CGFloat) {
        self.symbol = symbol
        self.size = size
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: size, height: size) }
    override func draw(_ dirtyRect: NSRect) {
        let tile = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: tile, xRadius: 9, yRadius: 9)
        NSGradient(starting: SettingsPalette.raised, ending: SettingsPalette.card)?.draw(in: path, angle: -90)
        SettingsPalette.border.setStroke()
        path.lineWidth = 0.8
        path.stroke()
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size * 0.44, weight: .medium)) {
            let inset = size * 0.24
            let rect = bounds.insetBy(dx: inset, dy: inset)
            let tinted = NSImage(size: rect.size, flipped: false) { target in
                image.draw(in: target)
                SettingsPalette.accent.setFill()
                target.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect)
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// 保留NSButton原生切换、键盘及无障碍语义，只绘制更清楚的横向轨道。
private final class SettingsToggleButton: NSButton {
    override var intrinsicContentSize: NSSize { NSSize(width: 50, height: 32) }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 2, dy: 3) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 13, yRadius: 13).fill()
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: (bounds.width - 42) / 2, y: (bounds.height - 24) / 2, width: 42, height: 24)
        let selected = state == .on
        let mixed = state == .mixed
        let alpha: CGFloat = isEnabled ? (isHighlighted ? 0.8 : 1) : 0.38
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        if selected {
            SettingsPalette.accent.withAlphaComponent(alpha).setFill()
            path.fill()
        } else {
            let track: NSColor = mixed ? .systemOrange : SettingsPalette.track
            track.withAlphaComponent(track.alphaComponent * alpha).setFill()
            path.fill()
        }
        SettingsPalette.border.withAlphaComponent(alpha).setStroke()
        path.lineWidth = 0.7
        path.stroke()
        let offset: CGFloat = mixed ? 11 : (selected ? 20 : 2)
        let thumb = NSRect(x: rect.minX + offset, y: rect.minY + 2, width: 20, height: 20)
        (selected ? SettingsPalette.selectedThumb : SettingsPalette.thumb).withAlphaComponent(isEnabled ? 1 : 0.75).setFill()
        NSBezierPath(ovalIn: thumb).fill()
        if mixed {
            NSColor.systemOrange.setStroke()
            let mark = NSBezierPath()
            mark.lineWidth = 1.5
            mark.move(to: NSPoint(x: thumb.midX - 4, y: thumb.midY))
            mark.line(to: NSPoint(x: thumb.midX + 4, y: thumb.midY))
            mark.stroke()
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class SettingsNavigationButton: NSButton {
    init(title: String, symbol: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        setButtonType(.toggle)
        isBordered = false
        focusRingType = .exterior
        setAccessibilityLabel(title)
        cell?.setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { nil }
    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }
    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 2, dy: 2) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 8, yRadius: 8).fill()
    }
    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let panel = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 7, yRadius: 7)
        if selected {
            SettingsPalette.raised.setFill()
            panel.fill()
            SettingsPalette.border.setStroke()
            panel.lineWidth = 0.8
            panel.stroke()
            SettingsPalette.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 14, y: bounds.midY - 2, width: 4, height: 4)).fill()
        } else if isHighlighted {
            SettingsPalette.raised.setFill()
            panel.fill()
        }
        let color: NSColor = selected ? SettingsPalette.accent : SettingsPalette.secondary
        if let symbol = image?.withSymbolConfiguration(.init(pointSize: 16, weight: selected ? .semibold : .regular)) {
            let rect = NSRect(x: 13, y: (bounds.height - 19) / 2, width: 21, height: 19)
            let tinted = NSImage(size: rect.size, flipped: false) { target in
                symbol.draw(in: target)
                color.setFill()
                target.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect)
        }
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular),
            .foregroundColor: selected ? SettingsPalette.primary : SettingsPalette.secondary
        ])
        text.draw(at: NSPoint(x: 44, y: (bounds.height - text.size().height) / 2))
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
