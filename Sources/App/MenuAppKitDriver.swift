import AppKit

protocol MenuStatusItemAccess: AnyObject {
    var separatorLength: Double { get set }
    var separatorVisible: Bool { get set }
    var layout: MenuBarLayout? { get }
    func removeSeparator()
}

final class MenuAppKitDriver: MenuBarDriving {
    private let items: MenuStatusItemAccess
    private let shortcut: MenuShortcutRegistering
    private let competingManager: () -> Bool
    var layout: MenuBarLayout? { items.layout }
    var hasCompetingManager: Bool { competingManager() }

    init(items: MenuStatusItemAccess, shortcut: MenuShortcutRegistering,
         competingManager: @escaping () -> Bool = MenuAppKitDriver.runningIBar) {
        self.items = items
        self.shortcut = shortcut
        self.competingManager = competingManager
    }

    func setSeparator(visible: Bool, length: Double) {
        // Always restore width before hiding so disabling cannot leave icons displaced.
        items.separatorLength = length
        items.separatorVisible = visible
    }
    func registerShortcut(_ action: @escaping () -> Void) -> MenuShortcutResult { shortcut.register(action) }
    func unregisterShortcut() { shortcut.unregister() }
    func removeSeparator() { items.removeSeparator() }

    static func isIBar(bundleIdentifier: String?, name: String?) -> Bool {
        name?.lowercased() == "ibar" || bundleIdentifier?.lowercased().split(separator: ".").last == "ibar"
    }
    static func runningIBar() -> Bool {
        NSWorkspace.shared.runningApplications.contains { isIBar(bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName) }
    }
}

/// The separator is created lazily only after the user enables hiding.
final class MenuAppKitStatusItems: MenuStatusItemAccess {
    static let separatorIdentity = "BarFlow.MenuSeparator.v1"
    private let anchor: NSStatusItem
    private var separator: NSStatusItem?
    private var requestedLength: Double = 20

    init(anchor: NSStatusItem) { self.anchor = anchor }

    var separatorLength: Double {
        get { requestedLength }
        set { requestedLength = newValue; separator?.length = CGFloat(newValue) }
    }
    var separatorVisible: Bool {
        get { separator?.isVisible ?? false }
        set {
            if newValue && separator == nil {
                let item = NSStatusBar.system.statusItem(withLength: CGFloat(requestedLength))
                item.autosaveName = Self.separatorIdentity
                item.behavior = [] // The separator is not independently removable.
                item.button?.identifier = NSUserInterfaceItemIdentifier(Self.separatorIdentity)
                item.button?.title = "┆"
                item.button?.toolTip = "轻栏分隔符：按住 ⌘ 拖到待隐藏图标右侧；轻栏图标须保持在此分隔符右侧。"
                item.button?.setAccessibilityLabel("轻栏菜单栏分隔符")
                separator = item
            }
            separator?.isVisible = newValue
        }
    }

    var layout: MenuBarLayout? {
        guard let separator = separator, separator.isVisible, anchor.isVisible,
              let separatorButton = separator.button, let anchorButton = anchor.button,
              let separatorWindow = separatorButton.window, let anchorWindow = anchorButton.window,
              let separatorScreen = separatorWindow.screen, let anchorScreen = anchorWindow.screen,
              let separatorID = separatorScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let anchorID = anchorScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let separatorFrame = separatorWindow.convertToScreen(separatorButton.convert(separatorButton.bounds, to: nil))
        let anchorFrame = anchorWindow.convertToScreen(anchorButton.convert(anchorButton.bounds, to: nil))
        return MenuBarLayout(separatorFrame: separatorFrame, anchorFrame: anchorFrame,
                             screenFrame: anchorScreen.frame, separatorScreenID: separatorID.uint32Value,
                             anchorScreenID: anchorID.uint32Value)
    }

    func removeSeparator() {
        guard let item = separator else { return }
        item.length = 20
        NSStatusBar.system.removeStatusItem(item)
        separator = nil
        requestedLength = 20
    }
}
