# SkyTrace macOS 渲染器生命周期专项报告

2026 年 11 月 13 日。基准为分支 `codex/ios-stability-hardening` 上的 `0ce5e2a352cade5938a5d1eff04939b13500d4c6` 及暂停时的工作区改动。环境为 Mac15,12、macOS 27.2（26B123）、Xcode 27.0（27A266a）。原始资料位于 Git 忽略目录 `build/renderer-lifecycle/`。

## 已定位并修复的问题

回归测试在调用 `shutdown()` 两次后送入迟到的可见性、快照、标签、姿态与相机更新。修复前，控制器重新进入连续渲染，并安装一次新的星点几何。修复后，终止状态阻止这些更新，帧邮箱永久关闭，在途几何任务取消，SceneKit 委托与标签场景解除关联。测试同时等待已取消的构建任务，并确认重建次数为零。应用路径仍在主线程调用同步的 `shutdown()`。

使用 `--trace-renderer-lifecycle` 启动应用时，诊断记录每个控制器的创建、恢复请求、首个 SceneKit 渲染完成回调、停止渲染、解除关联与开始析构。完成析构由 XCTest 在 autoreleasepool 排空后检查控制器及 SCNView 的弱引用。首帧以 SceneKit 回调为测量终点。

## 优先级反转的证据

- 原始 Debug 测试三轮均通过，每轮 20 次创建与释放，每轮报告一次 User-interactive 等待 Default 的警告。增加终止保护后三轮同样通过，仍各报告一次。Release 前后对照各报告一次。
- `prior-test-summary.json` 保存 111 帧原始回溯地址。XCTest 结果与测试进程内的诊断尝试均未提供可确认的警告符号栈。具体同步原语、等待线程身份以及第一个应用栈帧尚未确认。
- 独立样例 `SceneKitLifecycleRepro.swift` 仅使用 AppKit、SceneKit 和 SpriteKit。System Trace 的 CPU 样本包含 `-[SCNView initWithFrame:options:]`、`-[SCNMTLRenderContext initWithDevice:engineContext:]` 和 Metal 资源管理器初始化。该样例未复现相同的 XCTest 优先级反转警告。单独的框架测试还观察到 autoreleasepool 排空后有 SCNView 暂时存活，未测量后续释放时机。这些证据不足以将原警告归因于框架初始化、框架析构或应用任务。
- 未根据警告行号调整 SceneKit 启停顺序或 QoS。优先级反转仍待定位。

## 测量

创建和释放的耗时为 XCTest 墙钟时间。每组首轮独立列出。受宿主应用预热影响，首轮指标不等同于应用冷启动。Release 对照在同一机器、同一测试代码和同一构建参数下运行，基线副本使用暂停时的控制器和诊断源码。

| 指标 | Debug 分段基线 | Debug 修复后 | Release 基线 | Release 修复后 |
|---|---:|---:|---:|---:|
| 预热样本数 | 19 | 57 | 19 | 19 |
| 首轮总耗时，毫秒 | 80.770 | 48.606／55.030／56.978 | 44.492 | 18.095 |
| 预热总耗时 P95，毫秒 | 5.139 | 5.886 | 4.865 | 7.454 |
| 预热总耗时最大值，毫秒 | 5.139 | 8.053 | 4.865 | 7.454 |
| 预热 shutdown P95，毫秒 | 0.0050 | 0.0085 | 0.0050 | 0.0047 |
| 排空 autoreleasepool P95，毫秒 | 3.912 | 5.138 | 3.703 | 3.672 |
| 优先级反转警告数 | 1 | 3 | 1 | 1 |

真实 Release 窗口测试的 System Trace 捕获 5 次完整控制器创建、5 次完整终止、6 次从恢复请求到首帧。创建 P95 和最大值均为 1.390 毫秒，终止均为 0.041 毫秒，恢复首帧均为 20.746 毫秒。导出的 thread-state 表在这 10 个控制器创建和终止区间内没有记录与主线程 Blocked 状态重叠的事件。采样范围不含完整窗口关闭路径、控制器创建前的 SCNView 初始化以及最终视图释放，100 毫秒主线程阻塞目标仅能对已采样区间评估。没有进行修复前的同场景窗口采样，不能用这些数据比较窗口性能变化。

## 验证结果

| 场景 | 结果 |
|---|---|
| 共享控制器 | Core 严格并发模式 105 项通过，覆盖终止后迟到更新和在途几何任务取消 |
| macOS Debug | 三轮单测各 4 项通过，控制器与 SCNView 每轮均释放 |
| macOS Release 关闭重开 | Launch Services 同进程完成 20 轮，时间控件每轮恢复，首轮和末轮执行拖动 |
| macOS Release 暂停恢复 | 最小化恢复 20 轮、切换到 Finder 再返回 20 轮通过 |
| iOS 18.6 模拟器 | 9 项单测与后台恢复拖动 UI 测试通过 |
| 未验收路径 | 菜单栏重开、独立的完全遮挡恢复、重开后实际选星，以及窗口在标签准备和几何构建中的定点关闭。几何任务取消已由 Core 测试验证 |

本机的 XCTest 查询未暴露菜单栏状态项，直接查询辅助功能树返回 AXError -25211。Release 窗口测试改用 Launch Services，确认重开前后 PID 一致。

## 证据与复现

- `baseline-1/2/3.*`、`instrumented-baseline.*`、`followup-1/2/3.*` 与 `comparison-debug.json` 保存 Debug 对照。
- `release-phase-before.*` 和 `release-phase-after.*` 保存 Release 对照。两次均运行 `SkyTraceMacTests/MacUITests/testRendererControllerDeallocatesAcrossRepeatedLifecycles`。
- `reopen-launch-services.*`、`switch-release.*`、`ios.*` 和 `core.log` 保存功能验证。Core 命令为 `swift test --package-path Packages/SkyTraceCore -Xswiftc -strict-concurrency=complete`。
- `reopen-system.trace`、`reopen-os-signpost.xml`、`reopen-thread-state.xml` 和 `release-trace-summary.json` 保存 Release 窗口采样。使用 `xcrun xctrace record --template 'System Trace' --attach <PID> --time-limit 35s --output <路径>` 录制。
- `standalone-system.trace`、`standalone-profiler.trace` 和 `framework-only.log` 保存系统框架对照。最小样例可用 `swiftc -O -parse-as-library SceneKitLifecycleRepro.swift -o SceneKitLifecycleRepro` 编译。
- 暂停前的全进程试采样报告 iOS 模拟器动态库地址重叠。本轮用进程定向采样完成了导出。
- `baseline.patch`、`baseline-status.txt` 和 `paused-workspace.patch` 保存任务开始及暂停时的工作区状态。

Release 窗口回归可在图形会话执行以下命令。构建参数用于使测试目标和应用目标采用相同架构，并允许单测导入应用模块。

```bash
xcodebuild -project SkyTrace.xcodeproj -scheme SkyTraceMac \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/renderer-lifecycle/DerivedData \
  CODE_SIGN_IDENTITY=- ENABLE_TESTABILITY=YES ARCHS=arm64 \
  -parallel-testing-enabled NO \
  -only-testing:SkyTraceMacUITests/SkyTraceMacUITests/testReopenStarMapViaLaunchServices \
  -only-testing:SkyTraceMacUITests/SkyTraceMacUITests/testStarMapRecoversAfterMinimizeAndApplicationSwitch test
```
