import Carbon

protocol MenuShortcutRegistering: AnyObject {
    func register(_ action: @escaping () -> Void) -> MenuShortcutResult
    func unregister()
}

/// Native calls are injectable so tests never reserve a real global shortcut.
struct MenuCarbonFunctions {
    var install: (EventHandlerUPP?, UnsafeMutableRawPointer?, UnsafeMutablePointer<EventHandlerRef?>) -> OSStatus
    var register: (UInt32, UInt32, EventHotKeyID, UnsafeMutablePointer<EventHotKeyRef?>) -> OSStatus
    var unregister: (EventHotKeyRef) -> OSStatus
    var removeHandler: (EventHandlerRef) -> OSStatus

    static var live: MenuCarbonFunctions {
        MenuCarbonFunctions(
            install: { callback, context, output in
                var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
                return InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, context, output)
            },
            register: { key, modifiers, identifier, output in
                RegisterEventHotKey(key, modifiers, identifier, GetApplicationEventTarget(), 0, output)
            },
            unregister: { UnregisterEventHotKey($0) },
            removeHandler: { RemoveEventHandler($0) })
    }
}

final class MenuCarbonShortcut: MenuShortcutRegistering {
    static let signature: OSType = 0x42464C57 // BFLW; distinct from other applications.
    private let functions: MenuCarbonFunctions
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var action: (() -> Void)?

    init(functions: MenuCarbonFunctions = .live) { self.functions = functions }

    func register(_ action: @escaping () -> Void) -> MenuShortcutResult {
        if hotKey != nil { self.action = action; return .registered }
        let installStatus = functions.install(menuCarbonEventHandler, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installStatus == noErr, handler != nil else {
            unregister()
            return .unavailable(installStatus == noErr ? Int32(paramErr) : installStatus)
        }
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = functions.register(UInt32(kVK_ANSI_B), UInt32(optionKey | cmdKey), identifier, &hotKey)
        guard status == noErr, hotKey != nil else {
            unregister()
            return .unavailable(status == noErr ? Int32(paramErr) : status)
        }
        self.action = action
        return .registered
    }

    func unregister() {
        action = nil
        if let key = hotKey { _ = functions.unregister(key); hotKey = nil }
        if let installed = handler { _ = functions.removeHandler(installed); handler = nil }
    }

    deinit { unregister() }

    fileprivate func handle(_ event: EventRef) -> OSStatus {
        guard hotKey != nil,
              GetEventClass(event) == OSType(kEventClassKeyboard),
              GetEventKind(event) == UInt32(kEventHotKeyPressed) else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &identifier)
        guard status == noErr, identifier.signature == Self.signature, identifier.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }
        action?()
        return noErr
    }
}

private let menuCarbonEventHandler: EventHandlerUPP = { _, event, context in
    guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
    return Unmanaged<MenuCarbonShortcut>.fromOpaque(context).takeUnretainedValue().handle(event)
}
