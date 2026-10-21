# BarFlow 滚动模块

## 接口与安全默认值

`ScrollPreferences` 是 `Codable, Equatable`，默认值：

```swift
ScrollPreferences(
    enabled: false,
    reverseMouse: true,
    reverseTrackpad: false,
    reverseVertical: true,
    reverseHorizontal: false,
    ignoreSynthetic: true
)
```

主线程创建与使用 `ScrollEngine()`。公开接口为 `apply(_:)`、`stop()`、`isRunning`、`statusText`、`onStatusChange` 和只读 `diagnosticSnapshot()`。初始化、默认禁用、诊断和测试均不创建全局 tap。`onStatusChange` 只在状态文字变化时回调；正常滚动逐帧不发送 UI 回调。

启用只检查 `AXIsProcessTrusted()`，不调用任何请求授权或弹出权限提示的 API。权限不足会保持停止并提示用户手动到系统设置授予辅助功能权限。默认 active tap 为公开 `CGEvent.tapCreate`，session/tailAppend、仅订阅 `scrollWheel`，运行在主 RunLoop 的 common modes。

检测到 bundle ID `com.pilotmoon.scroll-reverser` 的应用正在运行时，启用会失败并提示用户手动暂停或退出。由于无法公开、可靠地读取该应用的“暂停”状态，只要进程仍在运行仍会保守拒绝；用户可手动退出后重试。模块不会退出、修改或控制其他应用。每次 `apply` 会重新检查权限和冲突；没有持续观察后续启动的第三方进程。

## 设备识别范围

**当前产品运行层支持离散鼠标滚轮，连续来源保持原方向。**

公开 CGEvent 的 `scrollWheelEventIsContinuous` 不能可靠区分 Magic Mouse 与触控板。当前没有添加手势时间相关性推断，也没有使用未公开 IOHID 函数。因此 classifier 将非连续输入作为离散鼠标候选，将全部连续输入标为 `.unknown` 并保留；动量 phase 不用于推断设备类型。这意味着 Magic Mouse、触控板和某些提供连续事件的鼠标驱动不会被翻转。

`reverseTrackpad` 仅保留历史配置解码兼容，transformer 对显式已知 `.trackpad` 的分支有离线覆盖，但产品运行层不会产生这一识别结果。界面禁用该控件、显示触控板保持系统方向；偏好归一化清除该标记，不能把它展示为已实现的精确触控板控制。`diagnosticSnapshot()["trackpadReversalAvailable"]` 为 `false`。

`ignoreSynthetic` 默认跳过非零来源 PID、非零来源 tag、非系统来源状态 ID 的事件。真实 private CGEventSource 会得到独立正整数状态 ID，并非构造时使用的 `privateState == -1` 标记。此过滤是基于公开元数据的保守策略，无法证明每个 PID 为零的事件都来自物理硬件，也无法保证第三方驱动没有伪装或省略元数据。

## 变换与生命周期

对所选设备和所选轴，将 line、fixed-point、point 三组 delta 分别反号，保留各自幅值。写 line delta 会使 CoreGraphics 内部重写其他表示，所以先读取同一轴的所有原值，再依次写 line、fixed、point。横纵选择相互独立，第三轴和 phase 元数据保持不变。

本机 macOS 15.6.1 ARM64 的离线 CGEvent 实测表明，line 整数字段存储为 Int16、point 为 Int32，虽然读取 API 返回 Int64。实现按对应宽度饱和，避免最小负数翻转后绕回负数。16.16 fixed 的边界由 CoreGraphics setter 自身饱和，测试使用真实事件核对。Int64.min 的辅助翻转也不执行会溢出的直接取负。

回调首先处理 tap 控制消息，不把超时/停用消息转换为 NSEvent。超时在运行态请求 `CGEvent.tapEnable`，失败则停止；系统 user-input 停用会立即关闭变换状态并异步清理资源、要求用户重新启用。停止后的迟到超时不重启 tap。状态消息转到主队列，带有资源代次检查，避免旧回调覆盖新启动或停止状态。`stop()`、资源 invalidation 以及 deinit 清理是幂等的。

## 本地验证

执行：

```bash
cd BarFlow
bash scripts/test-scroll.sh
```

脚本只编译 `Sources/Core/Scroll*.swift`、`Sources/App/Scroll*.swift` 和 `Tests/ScrollCoreTests.swift`，使用 Swift 5 语言模式、warnings-as-errors、AppKit 和 ApplicationServices，不依赖 Xcode、SPM 或 XCTest。二进制位于 `$TMPDIR` 的独立临时目录，退出时删除。

开发过程首先用无行为的 transformer seam 实际运行行为测试，得到：

```text
FAIL mouse vertical reversal: mouse vertical line delta: expected -3, got 3
0/1 scroll tests passed
```

此后按行为逐项 RED → GREEN 实现，最后补充已实现不变量的回归覆盖。安全复核曾发现“双指时间与任意连续输入混淆”的问题，独立探针与新增处理器测试实际得到 expected 3, got -3；该实验路径现已完整撤回，生产层只对离散滚轮分类。当前完整运行返回 `22/22 scroll tests passed`，新增手势事件与不同连续来源／动量交错保持原样的回归。退出码为 0（Swift 6.1.2 编译器，Swift 5 语言模式，warnings-as-errors）。覆盖默认禁用、配置 Codable、鼠标/触控板偏好隔离、连续未知输入、纵横独立、PID/tag/private-source 过滤、动量不改变来源类型、三组 delta 一致翻转、极值饱和、第三轴/phase/未选轴保留、超时恢复状态模型、停用后不复活、真实 CFRunLoopSource/CFMachPort 的停止与析构销毁、权限/冲突/创建失败及状态回调去重。

测试中的 CGEvent 仅在进程内构造和变换，从不 post。销毁验证使用普通本地 Mach port 和真实 RunLoop source，不是 event tap。创建失败验证注入 nil，验证的是实际 engine 的失败路径，不代表真实 tap 创建成功。超时动作的离线状态模型和真实资源清理都有覆盖；`CGEvent.tapEnable` 的系统级效果未执行验证。

上述自动化测试不创建全局事件监听，也不代替硬件验收。0.2.2 已在一台 macOS 15.6.1 ARM64 设备上另行完成授权、正常重启及用户物理滚轮方向确认；这一结果不代表所有鼠标驱动、多屏或全屏场景均已验证。触控板与所有未知连续来源仍保持系统方向。

## 文件归属

- `Sources/Core/ScrollPreferences.swift`：配置与设备枚举。
- `Sources/Core/ScrollStartPolicy.swift`：启用前置决策。
- `Sources/Core/ScrollTapLifecycle.swift`：运行、恢复与停止状态模型。
- `Sources/App/ScrollSourceClassifier.swift`：保守设备来源分类。
- `Sources/App/ScrollEventTransformer.swift`：真实 CGEvent 字段变换。
- `Sources/App/ScrollEventProcessor.swift`：轻量回调处理和控制动作。
- `Sources/App/ScrollTapResources.swift`：RunLoop source / Mach port 资源所有权与销毁。
- `Sources/App/ScrollEngine.swift`：真实 tap 适配、权限/冲突检查和状态接口。
- `Tests/ScrollCoreTests.swift`：自定义 `@main` 离线测试。
- `scripts/test-scroll.sh`：独立编译与运行。
- `docs/SCROLL.md`：本文。

实现参考了 Scroll Reverser v1.9.1 `MouseTap.m` 的公开字段写入顺序和控制消息优先处理方式，使用 Swift 及公开 API 重新实现。未采用上游的未公开 IOHID 调用或连续设备猜测；上游 Apache-2.0 归属与许可证由主工程统一提供。
