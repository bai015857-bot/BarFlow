import ApplicationServices

/// 与tap同寿命，回调仅弱引用引擎；移除后已进入的回调也不能复活监听。
final class SideButtonTapContext {
    weak var owner: SideButtonEngine?
    let generation: UInt64
    var active = true
    init(owner: SideButtonEngine, generation: UInt64) {
        self.owner = owner
        self.generation = generation
    }
}

final class SideButtonTapResources {
    let port: CFMachPort
    let source: CFRunLoopSource
    let runLoop: CFRunLoop
    let context: SideButtonTapContext
    init(port: CFMachPort, source: CFRunLoopSource, runLoop: CFRunLoop, context: SideButtonTapContext) {
        self.port = port
        self.source = source
        self.runLoop = runLoop
        self.context = context
    }
    func invalidate() {
        context.active = false
        context.owner = nil
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFRunLoopSourceInvalidate(source)
        CFMachPortInvalidate(port)
    }
    deinit { invalidate() }
}
