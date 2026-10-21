import ApplicationServices

final class ScrollTapResources {
    let port: CFMachPort
    let source: CFRunLoopSource
    let runLoop: CFRunLoop

    init(port: CFMachPort, source: CFRunLoopSource, runLoop: CFRunLoop) {
        self.port = port
        self.source = source
        self.runLoop = runLoop
    }

    func invalidate() {
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFRunLoopSourceInvalidate(source)
        CFMachPortInvalidate(port)
    }

    deinit { invalidate() }
}
