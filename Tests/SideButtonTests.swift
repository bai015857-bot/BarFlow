import Foundation
import ApplicationServices

private struct Failure: Error, CustomStringConvertible { let description: String }
private func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected { throw Failure(description: "\(message)：期望 \(expected)，实际 \(actual)") }
}
private func input(_ kind: SideButtonInput.Kind, button: Int64 = 3,
                   flags: UInt64 = 0, pid: Int64 = 0, state: Int64 = 1,
                   tag: Int64 = 0) -> SideButtonInput {
    SideButtonInput(kind: kind, button: button, modifiers: flags,
                    sourcePID: pid, sourceState: state, sourceTag: tag)
}

@main
struct SideButtonTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("安全默认值与成功按下抬起配对", testPair),
            ("来源和修饰键安全过滤且失败不吃半对", testSafeFiltering),
            ("长按只发送一次且快速连击整对节流", testRepeatAndThrottle),
            ("交换方向不影响配对及不相关鼠标", testSwapAndUnrelated),
            ("桌面快捷键缺省默认与标准自定义只读解析", testShortcutParsing),
            ("合法稀疏快捷键覆盖按ID继承默认并合并自定义", testSparseShortcutOverrides),
            ("显式停用及畸形快捷键必须安全拒绝", testMalformedShortcuts),
            ("真实键盘序列修饰键包围方向键且完整构造", testKeyboardSequence),
            ("左右方向键包含实际桌面切换所需Fn标志且适配器严格验证", testArrowFunctionFlag),
            ("真实鼠标事件经生产转换入口安全消费与失败放行", testRealEventPipeline),
            ("设置变更中途保留已消费配对而停止新动作", testMidClickPreferences),
            ("引擎默认无副作用及权限失败与创建失败", testEnginePreflight),
            ("本地真实Mach资源及生产回调启动停止清理", testEngineResources),
            ("超时恢复保留配对且系统停用不会自动复活", testEngineControls),
            ("引擎设置关闭中途仅排空已消费配对", testEngineDrain),
            ("公开系统适配器只读配置与预检同步有界发送", testSystemAdapter),
            ("生产reader经引擎预检让合法稀疏配置到达tap创建", testSparseReaderToEngine),
            ("恢复失败与连续超时不虚报运行且旧代回调无效", testRecoveryFailures),
            ("关闭排空期间超时仍安全恢复配对", testDrainTimeout),
            ("不支持键码与相同左右快捷键拒绝启用", testUnsupportedKeys),
            ("超时恢复前验证权限且异常控制不误触发", testRecoveryPermission),
            ("apply刷新快捷键不重建tap且保持交换中途配对", testShortcutRefresh),
            ("诊断只读且明确实际系统切换尚未验收", testDiagnosticLimits)
        ]
        let filter = ProcessInfo.processInfo.environment["TEST_FILTER"] ?? ""
        let selected = tests.filter { filter.isEmpty || $0.0.contains(filter) }
        var failures = 0
        for (name, test) in selected {
            do { try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name)：\(error)") }
        }
        print("\(selected.count - failures)/\(selected.count) side-button tests passed")
        if failures > 0 || selected.isEmpty { exit(1) }
    }

    private final class TapFixture {
        var callback: CGEventTapCallBack?
        var context: UnsafeMutableRawPointer?
        var retainedContext: SideButtonTapContext?
        var port: CFMachPort?
        var source: CFRunLoopSource?
        var enabled = false
        var allowEnable = true
        var trusted = true
        var enables = 0
        var creations = 0
        var now: TimeInterval = 1
        var captures: [[CGEvent]] = []
        func create(_ callback: CGEventTapCallBack, _ context: UnsafeMutableRawPointer) -> CFMachPort? {
            creations += 1
            self.callback = callback
            self.context = context
            retainedContext = Unmanaged<SideButtonTapContext>.fromOpaque(context).takeUnretainedValue()
            var portContext = CFMachPortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
            let port = CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, &portContext, nil)
            self.port = port
            if let port = port { source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) }
            return port
        }
        func engine(provider: @escaping () -> SideButtonShortcutConfiguration = { .resolve(symbolicHotkeys: nil) }) -> SideButtonEngine {
            SideButtonEngine(accessibilityCheck: { [self] in trusted }, shortcutConfigurationProvider: provider,
                tapCreator: { [self] in create($0, $1) },
                eventPoster: { [self] in captures.append($0); return true },
                tapEnable: { [self] _, value in enables += 1; enabled = value && allowEnable },
                tapIsEnabled: { [self] _ in enabled }, clock: { [self] in now })
        }
        func send(_ type: CGEventType, button: Int64 = 3) -> Bool {
            let event: CGEvent = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
                ? CGEvent(source: nil)! : SideButtonTests.mouse(type, button: button)
            return callback?(OpaquePointer(bitPattern: 1)!, type, event, context) == nil
        }
    }

    static func testDiagnosticLimits() throws {
        let before = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys") as NSDictionary?
        let result = SideButtonEngine.diagnosticSnapshot()
        let after = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys") as NSDictionary?
        try expect(before, after, "诊断不修改系统快捷键")
        try expect(result["deliveryConfirmationAvailable"] as? Bool, false, "不虚报WindowServer确认")
        try expect(result["hardwareAcceptancePerformed"] as? Bool, false, "不虚报硬件验收")
        try expect(result["shortcutConfigurationAvailable"] is Bool, true, "报告只读配置可用性")
        try expect(result["subscribedEvents"] as? [String], ["otherMouseDown", "otherMouseUp", "otherMouseDragged"], "不订阅滚轮及左右键")
        try expect(JSONSerialization.isValidJSONObject(result), true, "可序列化")
    }

    static func testShortcutRefresh() throws {
        let fixture = TapFixture()
        var config = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: nil)
        let engine = fixture.engine { config }
        engine.apply(SideButtonPreferences(enabled: true))
        try expect(fixture.send(.otherMouseDown), true, "按下")
        config = .resolve(symbolicHotkeys: ["AppleSymbolicHotKeys": [
            "79": ["enabled": true, "value": ["type": "standard", "parameters": [65535, 18, CGEventFlags.maskCommand.rawValue]]],
            "81": ["enabled": true, "value": ["type": "standard", "parameters": [65535, 19, CGEventFlags.maskControl.rawValue]]]
        ]])
        engine.apply(SideButtonPreferences(enabled: true, swapDirections: true))
        try expect(fixture.send(.otherMouseUp), true, "变更后消费原配对")
        try expect(fixture.captures.count, 1, "变更不重复发送")
        fixture.now = 2
        try expect(fixture.send(.otherMouseDown), true, "变更后下一点击")
        try expect(fixture.captures.last?[1].getIntegerValueField(.keyboardEventKeycode), 19, "交换后读取新右快捷键")
        try expect(fixture.creations, 1, "配置刷新不重建tap")
    }

    static func testRecoveryPermission() throws {
        let fixture = TapFixture()
        let engine = fixture.engine()
        engine.apply(SideButtonPreferences(enabled: true))
        let event = CGEvent(source: nil)!
        let unknown = fixture.callback!(OpaquePointer(bitPattern: 1)!, .null, event, fixture.context)
        try expect(unknown != nil, true, "未知类型原样通过")
        try expect(fixture.captures.count, 0, "未知不触发切换")
        fixture.trusted = false
        fixture.enabled = false
        let enables = fixture.enables
        _ = fixture.send(.tapDisabledByTimeout)
        try expect(fixture.enables, enables, "权限撤销后不尝试恢复")
        try expect(engine.isRunning, false, "权限撤销即停止")
        try expect(engine.statusText.contains("辅助功能"), true, "明确权限原因")
    }

    static func testUnsupportedKeys() throws {
        for code: CGKeyCode in [52, 66, 68, 70, 72, 73, 74, 77, 108, 112] {
            try expect(SideButtonShortcut(keyCode: code, flags: .maskControl).isSupported, false, "未定义或媒体键不应模拟")
        }
        let entry: [String: Any] = ["enabled": true, "value": ["type": "standard", "parameters": [65535, 18, CGEventFlags.maskControl.rawValue]]]
        let duplicate = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: ["AppleSymbolicHotKeys": ["79": entry, "81": entry]])
        try expect(duplicate.isAvailable, false, "相同左右映射不能声称支持两方向")
        let absent = SideButtonSystemAdapter.readShortcutConfiguration { nil }
        try expect(absent.isAvailable, true, "读取缺省时回退默认")
    }

    static func testDrainTimeout() throws {
        let fixture = TapFixture()
        let engine = fixture.engine()
        engine.apply(SideButtonPreferences(enabled: true))
        try expect(fixture.send(.otherMouseDown), true, "按下")
        engine.apply(SideButtonPreferences())
        fixture.enabled = false
        _ = fixture.send(.tapDisabledByTimeout)
        try expect(engine.isRunning, false, "恢复排空不等于功能启用")
        try expect(fixture.enabled, true, "可恢复排空tap")
        try expect(fixture.send(.otherMouseUp), true, "排空超时后吞配对up")
        try expect(CFMachPortIsValid(fixture.port!), false, "完成后释放")
        try expect(fixture.captures.count, 1, "恢复不发送新快捷键")
    }

    static func testRecoveryFailures() throws {
        let fixture = TapFixture()
        let engine = fixture.engine()
        engine.apply(SideButtonPreferences(enabled: true))
        let oldCallback = fixture.callback!
        let oldContext = fixture.retainedContext!
        engine.stop()
        engine.apply(SideButtonPreferences(enabled: true))
        let enables = fixture.enables
        let event = CGEvent(source: nil)!
        let stale = oldCallback(OpaquePointer(bitPattern: 1)!, .tapDisabledByTimeout, event,
            Unmanaged.passUnretained(oldContext).toOpaque())
        try expect(stale != nil, true, "旧代控制消息放行")
        try expect(fixture.enables, enables, "旧代不可操作新资源")
        fixture.allowEnable = false
        fixture.enabled = false
        _ = fixture.send(.tapDisabledByTimeout)
        try expect(engine.isRunning, false, "启用检查失败不报告恢复")
        try expect(engine.statusText.contains("恢复失败"), true, "恢复失败中文")
        try expect(CFMachPortIsValid(fixture.port!), false, "失败清理")
        engine.apply(SideButtonPreferences())
        fixture.allowEnable = true
        engine.apply(SideButtonPreferences(enabled: true))
        fixture.enabled = false
        _ = fixture.send(.tapDisabledByTimeout)
        fixture.now += 1
        fixture.enabled = false
        _ = fixture.send(.tapDisabledByTimeout)
        try expect(engine.isRunning, false, "连续超时暂停")
        try expect(engine.statusText.contains("连续超时"), true, "避免无界恢复循环")
        let failedStart = TapFixture()
        failedStart.allowEnable = false
        let failedEngine = failedStart.engine()
        failedEngine.apply(SideButtonPreferences(enabled: true))
        try expect(failedEngine.isRunning, false, "首次enable失败")
        try expect(CFMachPortIsValid(failedStart.port!), false, "首次失败清理port")
    }

    static func testSystemAdapter() throws {
        let expectedMask = [CGEventType.otherMouseDown, .otherMouseUp, .otherMouseDragged].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        try expect(SideButtonSystemAdapter.eventMask, expectedMask, "只订阅侧键三类鼠标消息")
        var reads = 0
        let denied = SideButtonSystemAdapter.readShortcutConfiguration {
            reads += 1
            return ["AppleSymbolicHotKeys": ["81": ["enabled": false]]]
        }
        try expect(reads, 1, "只读一次域")
        try expect(denied.isAvailable, false, "读取到禁用配置")
        let sequence = SideButtonKeyboardBuilder.build(SideButtonShortcut(keyCode: 124, flags: .maskControl))!
        var captures: [CGEvent] = []
        try expect(SideButtonSystemAdapter.post(sequence, permissionCheck: { true }, postEvent: { captures.append($0) }), true, "完整序列同步交付")
        try expect(captures.count, 4, "公开发送路径注入捕获而非实际post")
        try expect(SideButtonSystemAdapter.post(sequence, permissionCheck: { false }, postEvent: { captures.append($0) }), false, "发送前权限失败")
        try expect(captures.count, 4, "失败无部分发送")
        try expect(SideButtonSystemAdapter.post([], permissionCheck: { true }, postEvent: { captures.append($0) }), false, "空序列拒绝")
        try expect(SideButtonSystemAdapter.post([sequence[0]], permissionCheck: { true }, postEvent: { captures.append($0) }), false, "半对序列拒绝")
        let untagged = CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true)!
        try expect(SideButtonSystemAdapter.post([untagged, sequence[2], sequence[3], sequence[3]], permissionCheck: { true }, postEvent: { captures.append($0) }), false, "畸形序列拒绝")
        try expect(captures.count, 4, "不发错误序列")
    }

    static func testSparseReaderToEngine() throws {
        let custom: [String: Any] = ["enabled": true, "value": ["type": "standard",
            "parameters": [65535, 18, CGEventFlags.maskCommand.rawValue]]]
        let cases: [(String, Any?, Bool)] = [
            ("缺省域", nil, true),
            ("双enabled-only", ["AppleSymbolicHotKeys": ["79": ["enabled": true], "81": ["enabled": 1]]], true),
            ("仅左覆盖", ["AppleSymbolicHotKeys": ["79": ["enabled": 1]]], true),
            ("仅右覆盖", ["AppleSymbolicHotKeys": ["81": ["enabled": true]]], true),
            ("稀疏左与自定义右", ["AppleSymbolicHotKeys": ["79": ["enabled": true], "81": custom]], true),
            ("显式停用", ["AppleSymbolicHotKeys": ["79": ["enabled": false]]], false),
            ("显式空值", ["AppleSymbolicHotKeys": ["81": ["enabled": true, "value": NSNull()]]], false)
        ]
        for (name, domain, available) in cases {
            var checks = 0, providers = 0, reads = 0, creates = 0, posts = 0
            let engine = SideButtonEngine(accessibilityCheck: { checks += 1; return true },
                shortcutConfigurationProvider: {
                    providers += 1
                    return SideButtonSystemAdapter.readShortcutConfiguration(reader: { reads += 1; return domain })
                },
                tapCreator: { _, _ in creates += 1; return nil },
                eventPoster: { _ in posts += 1; return false })
            engine.apply(SideButtonPreferences(enabled: true))
            try expect(checks, 1, "\(name)：注入授权检查不请求真实权限")
            try expect(providers, 1, "\(name)：启用经生产配置provider")
            try expect(reads, 1, "\(name)：生产reader只读取一次注入域")
            try expect(creates, available ? 1 : 0, "\(name)：合法配置到达tap创建，非法配置在解析处拒绝")
            try expect(engine.statusText.contains(available ? "无法创建" : "快捷键"), true, "\(name)：区分创建失败与解析阻断")
            try expect(engine.isRunning, false, "\(name)：nil工厂不安装真实tap且不虚报运行")
            try expect(posts, 0, "\(name)：不发送全局输入")
            engine.stop()
        }
    }

    static func testEngineDrain() throws {
        let fixture = TapFixture()
        var configuration = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: nil)
        var reads = 0
        let engine = fixture.engine { reads += 1; return configuration }
        engine.apply(SideButtonPreferences(enabled: true))
        try expect(fixture.send(.otherMouseDown), true, "关闭前消费按下")
        engine.apply(SideButtonPreferences())
        try expect(engine.isRunning, false, "关闭即停止新动作")
        try expect(CFMachPortIsValid(fixture.port!), true, "仅保留排空所需资源")
        try expect(fixture.send(.otherMouseDown, button: 4), false, "排空不消费另一新按下")
        try expect(fixture.send(.otherMouseUp), true, "关闭后配对up仍消费")
        try expect(CFMachPortIsValid(fixture.port!), false, "排空后马上清理")
        try expect(fixture.captures.count, 1, "排空不发送键盘")
        engine.apply(SideButtonPreferences(enabled: true))
        fixture.now = 2
        try expect(fixture.send(.otherMouseDown), true, "新周期按下")
        configuration = .resolve(symbolicHotkeys: ["AppleSymbolicHotKeys": ["79": ["enabled": false]]])
        engine.apply(SideButtonPreferences(enabled: true))
        try expect(engine.isRunning, false, "配置失效立即停止切换")
        try expect(fixture.send(.otherMouseUp), true, "配置失效仍消费配对up")
        try expect(CFMachPortIsValid(fixture.port!), false, "失效排空后清理")
        try expect(reads, 3, "每次启用apply刷新配置")
    }

    static func testEngineControls() throws {
        let fixture = TapFixture()
        let engine = fixture.engine()
        engine.apply(SideButtonPreferences(enabled: true))
        try expect(fixture.send(.otherMouseDown), true, "timeout前按下")
        fixture.enabled = false
        try expect(fixture.send(.tapDisabledByTimeout), false, "控制消息不消费")
        try expect(engine.isRunning, true, "真实启用检查通过才报告恢复")
        try expect(engine.statusText.contains("超时恢复"), true, "中文恢复状态")
        try expect(fixture.send(.otherMouseUp), true, "timeout后仍吞配对up")
        try expect(fixture.captures.count, 1, "timeout不重复快捷键")
        fixture.enabled = false
        _ = fixture.send(.tapDisabledByUserInput)
        try expect(engine.isRunning, false, "系统停用停止")
        try expect(engine.statusText.contains("系统停用"), true, "系统停用原因")
        let enables = fixture.enables
        engine.apply(SideButtonPreferences(enabled: true, swapDirections: true))
        try expect(fixture.enables, enables, "不相关apply不能解除安全暂停")
        try expect(engine.isRunning, false, "暂停持续")
        _ = fixture.send(.tapDisabledByTimeout)
        try expect(fixture.enables, enables, "旧控制回调不可复活")
        engine.apply(SideButtonPreferences())
        engine.apply(SideButtonPreferences(enabled: true))
        try expect(engine.isRunning, true, "显式关闭再启用可恢复")
    }

    static func testEngineResources() throws {
        let fixture = TapFixture()
        let engine = fixture.engine()
        engine.apply(SideButtonPreferences(enabled: true))
        try expect(engine.isRunning, true, "真实本地资源启用状态")
        try expect(fixture.creations, 1, "工厂仅创建本地MachPort不是全局tap")
        try expect(CFRunLoopContainsSource(CFRunLoopGetMain(), fixture.source, .commonModes), true, "注册同一真实source")
        try expect(fixture.send(.otherMouseDown), true, "生产回调返回nil消费按下")
        try expect(fixture.send(.otherMouseUp), true, "生产回调消费抬起")
        try expect(fixture.captures.count, 1, "同步捕获真实键盘序列")
        engine.stop()
        try expect(engine.isRunning, false, "停止不运行")
        try expect(CFMachPortIsValid(fixture.port!), false, "停止失效port")
        try expect(CFRunLoopSourceIsValid(fixture.source!), false, "停止失效source")
        try expect(CFRunLoopContainsSource(CFRunLoopGetMain(), fixture.source, .commonModes), false, "停止移除source")
        try expect(fixture.send(.otherMouseDown), false, "停止后旧回调放行")
        let enables = fixture.enables
        try expect(fixture.send(.tapDisabledByTimeout), false, "旧timeout回调放行")
        try expect(fixture.enables, enables, "停止后不复活")
        let deinitFixture = TapFixture()
        var owned: SideButtonEngine? = deinitFixture.engine()
        weak var weakOwner = owned
        owned?.apply(SideButtonPreferences(enabled: true))
        owned = nil
        try expect(weakOwner == nil, true, "无回调强引用环")
        try expect(CFMachPortIsValid(deinitFixture.port!), false, "析构清理port")
        try expect(CFRunLoopSourceIsValid(deinitFixture.source!), false, "析构清理source")
    }

    static func testEnginePreflight() throws {
        var trusted = false
        var checks = 0, reads = 0, creates = 0, posts = 0
        var config = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: nil)
        let engine = SideButtonEngine(accessibilityCheck: { checks += 1; return trusted },
            shortcutConfigurationProvider: { reads += 1; return config },
            tapCreator: { _, _ in creates += 1; return nil },
            eventPoster: { _ in posts += 1; return true })
        var statuses: [String] = []
        engine.onStatusChange = { statuses.append($0) }
        engine.apply(SideButtonPreferences())
        engine.stop()
        try expect(checks + reads + creates + posts, 0, "默认关闭不查询不安装不发送")
        engine.apply(SideButtonPreferences(enabled: true))
        try expect(engine.statusText.contains("辅助功能"), true, "权限失败中文说明")
        try expect(creates, 0, "获权限前不创建")
        try expect(engine.isRunning, false, "拒绝后不虚报")
        trusted = true
        config = .resolve(symbolicHotkeys: ["AppleSymbolicHotKeys": ["79": ["enabled": false]]])
        engine.apply(SideButtonPreferences(enabled: true))
        try expect(engine.statusText.contains("快捷键"), true, "停用快捷键原因")
        try expect(creates, 0, "不可用配置不安装")
        config = .resolve(symbolicHotkeys: nil)
        engine.apply(SideButtonPreferences(enabled: true))
        try expect(creates, 1, "注入创建失败")
        try expect(engine.statusText.contains("无法创建"), true, "创建失败中文说明")
        try expect(engine.isRunning, false, "创建失败不运行")
        try expect(posts, 0, "无全局post")
        engine.stop()
        engine.stop()
        try expect(statuses.filter { $0 == "已关闭" }.count, 1, "状态重复去重")
        let diagnostics = SideButtonEngine.diagnosticSnapshot()
        try expect(diagnostics["defaultEnabled"] as? Bool, false, "诊断默认关闭")
        try expect(diagnostics["permissionPrompted"] as? Bool, false, "诊断不申请权限")
        try expect(JSONSerialization.isValidJSONObject(diagnostics), true, "诊断可序列化")
    }

    static func testMidClickPreferences() throws {
        let processor = SideButtonEventProcessor()
        processor.apply(SideButtonPreferences(enabled: true))
        var batches = 0
        let poster: ([CGEvent]) -> Bool = { _ in batches += 1; return true }
        try expect(processor.process(type: .otherMouseDown, event: mouse(.otherMouseDown), now: 1, poster: poster), true, "先消费按下")
        processor.apply(SideButtonPreferences())
        try expect(processor.process(type: .otherMouseDown, event: mouse(.otherMouseDown), now: 2, poster: poster), true, "关闭后已吞长按不能漏出")
        try expect(processor.process(type: .otherMouseUp, event: mouse(.otherMouseUp), now: 2.1, poster: poster), true, "关闭后仍吞配对抬起")
        try expect(processor.process(type: .otherMouseDown, event: mouse(.otherMouseDown), now: 3, poster: poster), false, "关闭后不消费新点击")
        processor.apply(SideButtonPreferences(enabled: true, swapDirections: true))
        try expect(processor.process(type: .otherMouseDown, event: mouse(.otherMouseDown), now: 3.2, poster: poster), false, "已放行长按不能因启用变成消费")
        try expect(processor.process(type: .otherMouseUp, event: mouse(.otherMouseUp), now: 3.3, poster: poster), false, "放行配对仍放行")
        try expect(batches, 1, "变化中不额外发送")
    }

    static func mouse(_ type: CGEventType, button: Int64 = 3, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
                            mouseCursorPosition: CGPoint(x: 30, y: 40), mouseButton: CGMouseButton(rawValue: UInt32(button))!)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.flags = flags
        return event
    }

    static func testRealEventPipeline() throws {
        let processor = SideButtonEventProcessor()
        processor.apply(SideButtonPreferences(enabled: true))
        var captured: [[CGEvent]] = []
        let poster: ([CGEvent]) -> Bool = { captured.append($0); return true }
        let down = mouse(.otherMouseDown)
        let originalLocation = down.location
        try expect(processor.process(type: .otherMouseDown, event: down, now: 1, poster: poster), true, "真实按下成功消费")
        try expect(processor.process(type: .otherMouseUp, event: mouse(.otherMouseUp), now: 1.1, poster: poster), true, "真实抬起配对消费")
        try expect(captured.count, 1, "仅捕获一次完整序列而非实际post")
        try expect(captured[0][1].getIntegerValueField(.keyboardEventKeycode), 123, "真实后退路由左")
        try expect(down.location, originalLocation, "不改坐标")
        try expect(down.type, .otherMouseDown, "不改原事件")
        for flags: CGEventFlags in [.maskAlphaShift, .maskSecondaryFn, [.maskAlphaShift, .maskSecondaryFn]] {
            processor.reset()
            try expect(processor.process(type: .otherMouseDown, event: mouse(.otherMouseDown, flags: flags), now: 2, poster: poster), true, "CapsLock与Fn不误判实际修饰")
        }
        for flag: CGEventFlags in [.maskCommand, .maskAlternate, .maskControl, .maskShift] {
            processor.reset()
            try expect(processor.process(type: .otherMouseDown, event: mouse(.otherMouseDown, flags: flag), now: 2, poster: poster), false, "修饰组合原样放行")
        }
        processor.reset()
        try expect(processor.process(type: .otherMouseDown, event: mouse(.otherMouseDown), now: 3) { _ in false }, false, "post拒绝不消费")
        try expect(processor.process(type: .otherMouseUp, event: mouse(.otherMouseUp), now: 3.1, poster: poster), false, "post失败抬起不消费")
        processor.reset()
        try expect(processor.process(type: .otherMouseDown, event: mouse(.otherMouseDown), now: 4,
            builder: { _ in nil }, poster: poster), false, "构造失败不消费")
        processor.reset()
        let tagged = mouse(.otherMouseDown)
        tagged.setIntegerValueField(.eventSourceUserData, value: SideButtonKeyboardBuilder.sourceTag)
        try expect(processor.process(type: .otherMouseDown, event: tagged, now: 5, poster: poster), false, "标记过滤")
        let synthetic = CGEvent(mouseEventSource: CGEventSource(stateID: .privateState), mouseType: .otherMouseDown,
            mouseCursorPosition: .zero, mouseButton: CGMouseButton(rawValue: 3)!)!
        synthetic.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        try expect(processor.process(type: .otherMouseDown, event: synthetic, now: 6, poster: poster), false, "真实私有来源过滤")
        for type: CGEventType in [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .scrollWheel, .keyDown] {
            try expect(processor.process(type: type, event: mouse(.otherMouseDown), now: 7, poster: poster), false, "不订阅的事件不受影响")
        }
        processor.reset()
        try expect(processor.process(type: .otherMouseDown, event: mouse(.otherMouseUp), now: 8, poster: poster), false, "不一致事件类型放行")
    }

    static func testKeyboardSequence() throws {
        let shortcut = SideButtonShortcut(keyCode: 123, flags: .maskControl)
        guard let events = SideButtonKeyboardBuilder.build(shortcut) else {
            throw Failure(description: "必须构造完整的真实CGEvent序列")
        }
        try expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [59, 123, 123, 59], "Control包围方向键")
        try expect(events.map { $0.type.rawValue }, [CGEventType.flagsChanged.rawValue, CGEventType.keyDown.rawValue,
            CGEventType.keyUp.rawValue, CGEventType.flagsChanged.rawValue], "正确事件类型")
        try expect(events.map { $0.flags.rawValue }, [CGEventFlags.maskControl.rawValue,
            CGEventFlags.maskControl.union(.maskSecondaryFn).rawValue,
            CGEventFlags.maskControl.union(.maskSecondaryFn).rawValue, 0], "方向键两事件flags一致且最终释放")
        for event in events {
            try expect(event.getIntegerValueField(.eventSourceUserData), SideButtonKeyboardBuilder.sourceTag, "独立来源标记")
            let sourceState = event.getIntegerValueField(.eventSourceStateID)
            try expect(sourceState == 0 || sourceState == 1, false, "私有来源使用独立不透明状态而非物理0/1")
            try expect(event.getIntegerValueField(.keyboardEventAutorepeat), 0, "不重复")
        }
        let multi = SideButtonShortcut(keyCode: 19, flags: [.maskControl, .maskAlternate, .maskShift, .maskCommand])
        let sequence = SideButtonKeyboardBuilder.build(multi)!
        try expect(sequence.count, 10, "多修饰键均显式按下和释放")
        try expect(sequence[4].flags, multi.flags, "按下全部修饰")
        try expect(sequence[5].flags, multi.flags, "抬起仍有全部修饰")
        try expect(sequence.last?.flags.rawValue, 0, "最终无残留")
        var created = 0
        let failed = SideButtonKeyboardBuilder.build(shortcut) { source, key, down in
            created += 1
            return created == 3 ? nil : CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
        }
        try expect(failed == nil, true, "中途构造失败不返回半对")
        try expect(SideButtonKeyboardBuilder.build(SideButtonShortcut(keyCode: 999, flags: .maskControl)) == nil, true, "发送前再次验证")
    }

    static func testArrowFunctionFlag() throws {
        for code: CGKeyCode in [123, 124] {
            let shortcut = SideButtonShortcut(keyCode: code, flags: .maskControl)
            let events = SideButtonKeyboardBuilder.build(shortcut)!
            try expect(events[1].flags, CGEventFlags.maskControl.union(.maskSecondaryFn), "macOS左右桌面方向键按下需要Fn导航标志")
            try expect(events[2].flags, events[1].flags, "方向键释放保持相同导航标志")
            try expect(events[0].flags, .maskControl, "修饰键事件不伪造Fn按下")
            try expect(events[3].flags.rawValue, 0, "修饰键最终全部释放")
            var submitted = 0
            let accepted = SideButtonSystemAdapter.post(events, permissionCheck: { true }, postEvent: { _ in submitted += 1 })
            try expect(accepted, true, "生产适配器接受带平台导航标志的完整方向键序列")
            try expect(submitted, 4, "仍提交四个事件不插入额外按键")
            events[1].flags.remove(.maskSecondaryFn)
            try expect(SideButtonSystemAdapter.post(events, permissionCheck: { true }, postEvent: { _ in submitted += 1 }), false,
                       "缺少平台导航标志的畸形序列拒绝提交")
            try expect(submitted, 4, "拒绝前必须未提交任何部分")
        }
        let custom = SideButtonKeyboardBuilder.build(SideButtonShortcut(keyCode: 18, flags: .maskControl))!
        try expect(custom[1].flags, .maskControl, "非方向键自定义组合不添加Fn")
        try expect(custom[2].flags, .maskControl, "非方向键释放保持原组合")
        custom[1].flags.insert(.maskSecondaryFn)
        custom[2].flags.insert(.maskSecondaryFn)
        try expect(SideButtonSystemAdapter.post(custom, permissionCheck: { true }, postEvent: { _ in }), false,
                   "不放宽任意快捷键Fn权限")
    }

    static func testMalformedShortcuts() throws {
        func entry(_ enabled: Any = true, key: Any = 123, flags: Any = CGEventFlags.maskControl.rawValue,
                   character: Any = 65535, type: String = "standard") -> [String: Any] {
            ["enabled": enabled, "value": ["type": type, "parameters": [character, key, flags]]]
        }
        let invalid: [Any] = [
            entry(false), entry(0), entry("1"), entry(1.5), entry(key: -1), entry(key: 127),
            entry(key: 123.5), entry(key: true), entry(key: 56), entry(key: 63),
            entry(flags: 0), entry(flags: -1), entry(flags: CGEventFlags.maskAlphaShift.rawValue),
            entry(flags: CGEventFlags.maskControl.union(.maskSecondaryFn).rawValue),
            entry(flags: CGEventFlags.maskControl.rawValue | 1), entry(flags: true),
            entry(character: -1), entry(character: 65536), entry(character: "65535"),
            entry(type: "unknown"), "invalid"
        ]
        for (index, raw) in invalid.enumerated() {
            let config = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: ["AppleSymbolicHotKeys": ["79": raw]])
            try expect(config.isAvailable, false, "畸形配置 \(index)")
            try expect(config.unavailableReason?.isEmpty, false, "提供中文原因")
        }
        let invalidSparse: [Any] = [
            [String: Any](), ["enabled": false], ["enabled": 0], ["enabled": "1"],
            ["enabled": 1.5], ["enabled": NSNull()],
            ["value": ["type": "standard", "parameters": [65535, 123, CGEventFlags.maskControl.rawValue]]]
        ]
        let invalidValues: [Any] = [NSNull(), "invalid", false, 0, [Any](), [String: Any](),
            ["type": "standard"], ["parameters": [65535, 123, CGEventFlags.maskControl.rawValue]],
            ["type": "standard", "parameters": NSNull()],
            ["type": "standard", "parameters": [65535, 123]],
            ["type": "standard", "parameters": [65535, 123, CGEventFlags.maskControl.rawValue, 0]]]
        for (index, raw) in (invalidSparse + invalidValues.map { ["enabled": true, "value": $0] }).enumerated() {
            for id in ["79", "81"] {
                let config = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: ["AppleSymbolicHotKeys": [id: raw]])
                try expect(config.isAvailable, false, "ID \(id)无效enabled或显式畸形value \(index)不可回退默认")
                try expect(config.unavailableReason?.isEmpty, false, "提供拒绝原因")
            }
        }
        for root: Any in ["invalid", ["AppleSymbolicHotKeys": "invalid"]] {
            try expect(SideButtonShortcutConfiguration.resolve(symbolicHotkeys: root).isAvailable, false, "畸形根配置")
        }
        let numericPad = CGEventFlags.maskControl.union(.maskNumericPad)
        let accepted = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: ["AppleSymbolicHotKeys": ["79": entry(flags: numericPad.rawValue)]])
        try expect(accepted.left?.flags, numericPad, "允许方向键的数字键盘标志")
    }

    static func testSparseShortcutOverrides() throws {
        let left = SideButtonShortcut(keyCode: 123, flags: .maskControl)
        let right = SideButtonShortcut(keyCode: 124, flags: .maskControl)
        let custom = SideButtonShortcut(keyCode: 18, flags: .maskCommand)
        let enabledValues: [Any] = [true, 1]
        for leftEnabled in enabledValues {
            for rightEnabled in enabledValues {
                let config = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: ["AppleSymbolicHotKeys": [
                    "79": ["enabled": leftEnabled], "81": ["enabled": rightEnabled]
                ]])
                try expect(config.isAvailable, true, "双enabled-only合法覆盖")
                try expect(config.left, left, "79继承Control+左")
                try expect(config.right, right, "81继承Control+右")
                try expect(config.unavailableReason, nil, "合法覆盖无不可用原因")
            }
        }
        for (id, otherID) in [("79", "81"), ("81", "79")] {
            for enabled in enabledValues {
                for customOther in [false, true] {
                    var entries: [String: Any] = [id: ["enabled": enabled]]
                    if customOther {
                        entries[otherID] = ["enabled": true, "value": ["type": "standard",
                            "parameters": [65535, custom.keyCode, custom.flags.rawValue]]]
                    }
                    let config = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: ["AppleSymbolicHotKeys": entries])
                    try expect(config.isAvailable, true, "单个ID \(id)稀疏覆盖与另一侧缺省或自定义合并")
                    try expect(config.left, customOther && otherID == "79" ? custom : left, "左保持对应默认或显式自定义")
                    try expect(config.right, customOther && otherID == "81" ? custom : right, "右保持对应默认或显式自定义")
                }
                let duplicateKey = id == "79" ? left.keyCode : right.keyCode
                let duplicate = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: ["AppleSymbolicHotKeys": [
                    id: ["enabled": enabled],
                    otherID: ["enabled": true, "value": ["type": "standard",
                        "parameters": [65535, duplicateKey, CGEventFlags.maskControl.rawValue]]]
                ]])
                try expect(duplicate.isAvailable, false, "稀疏默认与自定义相同仍拒绝")
            }
        }
    }

    static func testShortcutParsing() throws {
        for absent: Any? in [nil, [String: Any](), ["AppleSymbolicHotKeys": [String: Any]()]] {
            let config = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: absent)
            try expect(config.isAvailable, true, "缺省使用系统默认")
            try expect(config.left, SideButtonShortcut(keyCode: 123, flags: .maskControl), "左默认")
            try expect(config.right, SideButtonShortcut(keyCode: 124, flags: .maskControl), "右默认")
        }
        let custom: [String: Any] = ["AppleSymbolicHotKeys": [
            "79": ["enabled": true, "value": ["type": "standard", "parameters": [65535, 18, CGEventFlags.maskCommand.rawValue]]],
            "81": ["enabled": 1, "value": ["type": "standard", "parameters": [65535, 19, CGEventFlags.maskControl.union(.maskAlternate).rawValue]]]
        ]]
        let config = SideButtonShortcutConfiguration.resolve(symbolicHotkeys: custom)
        try expect(config.isAvailable, true, "自定义可用")
        try expect(config.left?.keyCode, 18, "左自定义键码")
        try expect(config.left?.flags, .maskCommand, "左自定义修饰")
        try expect(config.right?.keyCode, 19, "右自定义键码")
        try expect(config.right?.flags, CGEventFlags.maskControl.union(.maskAlternate), "右自定义修饰")
    }

    static func testSafeFiltering() throws {
        var policy = SideButtonPolicy()
        policy.preferences.enabled = true
        var sends = 0
        let disallowed = [input(.down, pid: 2), input(.down, state: -1),
            input(.down, state: 99), input(.down, tag: 5)] +
            [CGEventFlags.maskCommand, .maskAlternate, .maskControl, .maskShift].map {
                input(.down, flags: $0.rawValue)
            }
        for event in disallowed {
            policy.reset()
            try expect(policy.process(event, now: 1) { _ in sends += 1; return true }, false, "禁止拦截来源或组合点击")
            try expect(policy.process(input(.up), now: 1.1) { _ in sends += 1; return true }, false, "放行配对抬起")
        }
        try expect(sends, 0, "过滤后不发送快捷键")
        policy.reset()
        try expect(policy.process(input(.down), now: 2) { _ in false }, false, "发送失败放行")
        try expect(policy.process(input(.down), now: 2.1) { _ in sends += 1; return true }, false, "已放行的按下不可中途吞掉重复")
        try expect(policy.process(input(.up), now: 2.2) { _ in true }, false, "失败整对放行")
        try expect(policy.process(input(.up, button: 4), now: 3) { _ in true }, false, "无匹配抬起放行")
    }

    static func testRepeatAndThrottle() throws {
        var policy = SideButtonPolicy()
        policy.preferences.enabled = true
        var sends = 0
        let send: (SideButtonDirection) -> Bool = { _ in sends += 1; return true }
        try expect(policy.process(input(.down), now: 1, send: send), true, "首按")
        try expect(policy.process(input(.down), now: 1.5, send: send), true, "长按重复继续吞")
        try expect(policy.process(input(.dragged), now: 1.6, send: send), true, "配对拖动吞掉")
        try expect(policy.process(input(.up, flags: CGEventFlags.maskShift.rawValue), now: 1.7, send: send), true, "已吞下的抬起即使修饰键变化仍吞")
        try expect(sends, 1, "长按不重复切换")
        try expect(policy.process(input(.down), now: 2, send: send), true, "下次正常按下")
        try expect(policy.process(input(.up), now: 2.01, send: send), true, "正常抬起")
        try expect(policy.process(input(.down, button: 4), now: 2.249, send: send), true, "250ms内侧键整对节流")
        try expect(policy.process(input(.up, button: 4), now: 2.6, send: send), true, "节流的抬起仍吞")
        try expect(sends, 2, "节流不发送")
        try expect(policy.process(input(.down, button: 4), now: 2.6, send: send), true, "窗口结束后重试")
        try expect(sends, 3, "节流按下不延长窗口")
        policy.reset()
        try expect(policy.process(input(.up, button: 4), now: 3, send: send), false, "重置清理配对")
    }

    static func testSwapAndUnrelated() throws {
        var policy = SideButtonPolicy()
        policy.preferences = SideButtonPreferences(enabled: true, swapDirections: true)
        var sends: [SideButtonDirection] = []
        for button: Int64 in [0, 1, 2, 5, 31, -1] {
            for kind: SideButtonInput.Kind in [.down, .up, .dragged, .other] {
                try expect(policy.process(input(kind, button: button), now: 1) { sends.append($0); return true }, false, "其他鼠标原样通过")
            }
        }
        try expect(policy.process(input(.down), now: 2) { sends.append($0); return true }, true, "交换方向后按下")
        try expect(sends, [.right], "后退交换为右")
    }

    static func testPair() throws {
        let defaults = SideButtonPreferences()
        try expect(defaults.enabled, false, "默认关闭")
        try expect(defaults.swapDirections, false, "默认不交换")
        try expect(try JSONDecoder().decode(SideButtonPreferences.self,
            from: JSONEncoder().encode(defaults)), defaults, "可独立保存")
        var policy = SideButtonPolicy()
        var sends: [SideButtonDirection] = []
        try expect(policy.process(input(.down), now: 1) { sends.append($0); return true }, false, "关闭不拦截")
        policy.reset()
        policy.preferences.enabled = true
        try expect(policy.process(input(.down), now: 2) { sends.append($0); return true }, true, "发送成功才吞下按下")
        try expect(policy.process(input(.up), now: 2.01) { sends.append($0); return true }, true, "吞下配对抬起")
        try expect(sends, [.left], "后退映射左桌面且只发送一次")
        try expect(policy.process(input(.down, button: 4), now: 3) { sends.append($0); return true }, true, "前进按下")
        try expect(policy.process(input(.up, button: 4), now: 3.1) { sends.append($0); return true }, true, "前进抬起")
        try expect(sends, [.left, .right], "前进映射右桌面")
    }
}
