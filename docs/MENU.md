# BarFlow 菜单栏折叠模块

该模块使用原创 Swift/AppKit 代码，只拥有自己的分隔符。没有网络依赖，不使用 Accessibility 全局键盘监听，也不会退出或改动 iBar。

## 接入

在主线程创建并持有控制器，传入应用已有的恢复入口 `NSStatusItem`：

```swift
let menuController = MenuBarController(anchor: statusItem)
menuController.onStateChange = { collapsed in
    // 更新应用菜单里的折叠/展开标题。
}
menuController.onStatusChange = { text in
    // 显示状态说明或布局错误；同时可读取 statusText 获得初始提示。
}
menuController.apply(preferences.menu)
```

接口为 `MenuPreferences: Codable, Equatable`，以及 `MenuBarController.init(anchor:)`、`apply(_:)`、`toggle()`、`expand()`、`cleanup()`、`isCollapsed`、`statusText` 和两个回调。控制器及其方法、回调都应由主线程使用。退出时主应用可以调用 `cleanup()`；控制器也会响应 `NSApplication.willTerminateNotification`，析构时再次安全清理。

默认 `enabled = false`、`autoCollapse = true`、`autoCollapseDelay = 15`、`hotKeyEnabled = true`。初始化保持展开，不创建分隔符，不注册快捷键。主 UI 应先显示 `statusText` 中关于 iBar 的兼容性提示，再由用户明确开启。`apply` 接收用户选择，不会自动弹窗确认。

## 用户安排与恢复

开启后显示标识为 `BarFlow.MenuSeparator.v1` 的 20 点分隔符，图形为文本 `┆`。它有独立的 autosave 名称、控件标识和辅助功能标签。显式显示前会清除本项保存的隐藏状态；创建、隐藏和移除期间保留已有有效的分隔符位置，不改其他图标位置或偏好。按住 ⌘ 拖动分隔符到需要隐藏的图标右侧；BarFlow 主入口必须保持在分隔符右侧、同一屏幕。分隔符起初创建在系统选择的位置，由用户决定最终边界。

每次折叠前验证两个按钮的屏幕编号、有效几何尺寸、同一菜单栏高度、左右关系，以及恢复入口完整处于屏幕内。验证失败维持展开并提示安排分隔符，自动折叠暂停。重复应用相同设置、修改快捷键或自动折叠延迟不会解除暂停；关闭后重新开启自动折叠或整个模块可恢复倒计时，明确展开/折叠仍沿用手动控制行为。折叠将分隔符长度置为 5000；展开恢复为 20。父 UI 应始终保留可见的主入口及展开菜单项。

折叠后每秒检查入口和分隔符布局，异常立即恢复并暂停自动折叠。独立计时器每 90 秒复查恢复入口几何；位置正常时保持折叠，不因经过时限就永久暂停。位置异常才安全展开并暂停；反复 `apply` 不推迟复查。定时器处于主 RunLoop 的 common modes，菜单跟踪时也可执行。主线程被阻塞、系统睡眠或进程被强制终止时，运行循环计时器不提供硬实时保证；AppKit 进程终止会移除该进程的状态栏项。

自动折叠只在启用、当前展开、没有安全暂停且没有检测到 iBar 时安排；延迟约束为 3–3600 秒，NaN/无穷值使用 15 秒。禁用、展开和退出会取消不再适用的计时器。清理先将宽度恢复为 20，再隐藏和删除自己的分隔符，并注销快捷键。`cleanup()` 幂等，之后的操作和迟到回调都不再重建分隔符；需要重新启用时创建新控制器。

## 全局快捷键与共存

固定 ⌥⌘B，通过 Carbon `InstallEventHandler` / `RegisterEventHotKey` 注册，使用 BarFlow 的 `BFLW` 签名及 ID 1。仅在折叠模块和快捷键选项都启用时注册。关闭选项、禁用模块或清理时注销。注册冲突返回状态说明和 OSStatus，仍可从主菜单手动操作；再次应用设置可重试。没有使用需要 AX 权限的全局按键监听。

iBar 检测读取 `NSWorkspace.runningApplications` 的应用名或 bundle 最后一段是否为 `iBar`（忽略大小写）。检测到时保留手动控制，停用自动折叠，并在状态中持续提示冲突。计时器触发前再次检测，防止等待期间启动 iBar 后仍自动隐藏。此检测是尽力而为，不保证识别所有改名或不同 bundle 结构的版本。不会改变其他工具的运行状态。

## 编译与测试

```sh
./scripts/test-menu.sh
```

脚本仅编译 `Sources/Core/Menu*.swift`、`Sources/App/Menu*.swift` 与 `Tests/MenuCoreTests.swift`，使用 `swiftc -parse-as-library -swift-version 5 -warnings-as-errors`，链接 AppKit 和 Carbon。编译产物位于 `$TMPDIR` 下的独立目录，结束自动删除；不需要完整 Xcode。

菜单测试执行成功：149 个断言通过。覆盖默认值/Codable、禁用透传、5000/20 宽度、展开折叠、布局拒绝、回调、延迟上下限与非有限值、健康布局跨越 90 秒仍折叠、展开后再次按设置自动收起、独立 90 秒异常复查、重复应用不重置复查时限、异常恢复、安全暂停在重复应用设置及修改快捷键或延迟后保持、关闭再开启自动折叠或模块后恢复、iBar 共存、快捷键重复注册失败、Carbon 本地事件分发、清理顺序和迟到回调、控制器析构和终止通知、真实主 RunLoop 计时器。

本次先新增“健康布局保持折叠超过 90 秒”的回归，观察到旧实现无条件展开并暂停的行为失败后，再修改为几何复查并通过。历史版本曾将无条件 90 秒展开视为安全上限；现已替换，恢复入口异常仍必须展开并暂停。

系统边界采用注入对象：测试没有创建任何真实 `NSStatusItem`，没有注册真实全局快捷键，没有启动应用，也没有改变实际菜单栏或 iBar。Carbon 测试仅创建本进程内的事件并直接调用捕获的处理器。真实分隔符拖动、多屏/刘海屏布局、系统空间切换、全屏模式和真实快捷键冲突仍需主代理在后续获准运行 UI 时验证。通过编译与自动测试不等于这些系统 UI 场景已实测。
