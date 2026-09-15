# SkyTrace 开发指南

本文档面向准备参与 SkyTrace 开发、构建或调试的贡献者。项目采用 Swift 6、SwiftUI 和 SceneKit，共享同一套天文核心，并分别提供 iOS/iPadOS 与原生 macOS 应用。

## 1. 技术目标

SkyTrace 的核心目标：

- 离线运行，不依赖第三方天文 API
- 同时在 iPhone、iPad 和 Apple Silicon Mac 上提供原生体验
- 使用真实星表、时间、位置和行星计算
- 将平台无关逻辑集中在 `SkyTraceCore`
- 将共享视觉组件集中在 `SkyTraceUI`
- 保证相机、标签、星座线和天体拾取使用同一坐标基准

## 2. 开发环境

必需组件：

| 组件 | 最低版本 |
| --- | --- |
| macOS | 14 |
| Xcode | 16.4 |
| Swift | 6.1 |
| XcodeGen | 2.46 |
| iOS Simulator | iOS 18 Runtime，仅 iOS 测试需要 |

安装 XcodeGen：

```bash
brew install xcodegen
```

安装 iOS Simulator Runtime：

```bash
xcodebuild -downloadPlatform iOS
```

VS Code 推荐扩展：

- `swiftlang.swift-vscode`
- `sweetpad.sweetpad`
- `vadimcn.vscode-lldb`

## 3. 获取和生成工程

```bash
git clone https://github.com/LyonZZZZzzzz/SkyTrace.git
cd SkyTrace
xcodegen generate
```

`SkyTrace.xcodeproj` 是生成物，不提交、不手工修改。所有 target、资源和签名配置都来自 `project.yml`。

## 4. 工程结构

```text
SkyTrace/
├── Packages/
│   ├── AstronomyEngine/   # C 天文计算引擎与 Swift 封装
│   ├── SkyTraceCore/      # 模型、数据、计算、ViewModel、SceneKit 控制器
│   └── SkyTraceUI/        # 跨平台 SwiftUI 组件
├── SkyTrace/              # iOS/iPadOS App
├── SkyTraceMac/           # macOS App
├── SkyTraceTests/         # iOS 单元测试
├── SkyTraceUITests/       # iOS UI 测试
├── SkyTraceMacTests/      # macOS 单元测试
├── SkyTraceMacUITests/    # macOS UI 测试
├── Tools/                 # 星表生成工具
├── Docs/                  # 截图和开发文档
└── project.yml            # XcodeGen 单一配置源
```

## 5. 离线数据生成

数据流程：

```text
BSC5 原始星表 + D3-Celestial 星座/梅西耶 JSON
                    │
                    ▼
          Tools/generate_catalog.py
                    │
                    ▼
  SkyTraceCore/Sources/SkyTraceCore/Resources
```

生成命令：

```bash
python3 Tools/generate_catalog.py \
  --bsc path/to/bsc5/catalog \
  --constellations path/to/constellations.lines.json \
  --messier path/to/messier.json \
  --star-names-cn path/to/starnames.cn.json \
  --star-names-en path/to/starnames.json \
  --output Packages/SkyTraceCore/Sources/SkyTraceCore/Resources
```

产物：

- `Stars.bin`：8,404 颗视星等不高于 6.5 的恒星
- `Constellations.json`：88 个 IAU 星座连线
- `DeepSky.json`：110 个梅西耶天体
- `StarLabels.json`：恒星中文名、英文名和目录标识
- `Cities.json`：离线城市位置

资源通过 SwiftPM `Bundle.module` 加载，因此 iOS 与 macOS 使用完全相同的数据。

## 6. Astronomy Engine 集成

`Packages/AstronomyEngine` 同时包含：

- C target：`CAstronomyEngine`
- Swift 包装 target：`AstronomyEngine`

主要能力：

- UTC 日期转换
- J2000 赤道坐标到地平坐标
- 太阳、月球和行星视位置
- 恒星时、升落和观测者位置计算

高层服务由 `AstronomyCalculating` 协议定义，默认实现是 `AstronomyService`。视图模型只依赖协议，便于测试和替换。

## 7. SkyTraceCore 数据流

```text
CatalogRepository
        │
        ▼
SkyViewModel + ObserverContext + SkyMoment
        │
        ▼
AstronomyService / HorizontalTransform
        │
        ▼
SkySnapshot / SkySceneCatalog
        │
        ▼
SkySceneController
├── 静态 J2000 恒星与星座根节点
├── Sun / Moon / 行星动态节点
├── 60 Hz 四元数与位置插值
└── SpriteKit overlay 标签层
```

`SkySnapshot` 是检查器、观测计划和搜索的唯一数据来源。渲染层使用同一份
`SkySceneCatalog` 构建静态星空，并在每一帧只旋转一个根节点；星座线、标签、
拾取和选择环共用同一条无折射相机矩阵，避免低空折射差异造成像素错位。

### 60 FPS 渲染约定

- 恒星、深空天体与星座线只在目录或星点缩放变化时重建几何
- 时间播放每 250 ms 请求一个后台快照，SceneKit 在渲染帧之间插值
- SwiftUI 只接收手势结束后的相机状态，不参与每帧标签定位
- 标签最多 100 个，使用固定 `SKLabelNode` 池并仅在文本变化时重建纹理
- `SkyFrameMetrics` 记录 P95/P99、连续慢帧、几何重建和标签投影耗时；真机最终以 Instruments 的 Animation Hitches 与 Time Profiler 为准

## 8. iOS 与 iPadOS 界面

iOS target 保留移动端优先结构：

- 全屏 SceneKit 星空
- 顶部位置和时间状态
- 底部时间旅行与姿态模式
- 搜索、位置、今晚可见和详情 sheet
- 触摸拖动、捏合缩放、双指旋转和点击选择

平台专属代码只负责 UIKit 手势和展示，不实现天文或标签投影逻辑。

## 9. macOS 界面

macOS target 使用三栏 `NavigationSplitView`：

- 左侧：今晚推荐、太阳系、亮星、星座和梅西耶目录
- 中间：SceneKit 星空和底部时间轴
- 右侧：天体详情或观测概览

原生能力：

- 菜单栏和键盘快捷键
- `⌘F` 搜索
- `⌘L` 位置
- `⌘T` 今晚可见
- 空格播放/暂停
- 鼠标、滚轮、触控板捏合和双指旋转
- 独立设置窗口

## 10. 相机基向量

相机方向由 `SkyCameraState` 表示：

- `azimuth`
- `altitude`
- `roll`
- `fieldOfView`

`SkyCameraBasis` 统一计算：

```text
forward = direction(azimuth, altitude)
right   = normalize(cross(forward, referenceUp))
up      = cross(right, forward)
```

随后根据 `roll` 同时旋转 `right` 和 `up`。接近天顶或天底时自动使用备用参考轴。

SceneKit 相机的局部轴必须严格对应：

```text
local X = basis.right
local Y = basis.up
local Z = -basis.forward
```

SwiftUI 标签层必须使用同一个 `basis` 投影。禁止在平台手势代码中重新计算相机姿态。

## 11. 星点渲染和黑色方块修复

早期实现使用 `SCNGeometryPrimitiveType.point`，SceneKit 会把点绘制成实心方块。正确实现是：

1. 每颗恒星创建位于球面切线平面的四边形
2. 四边形使用 64×64 径向透明纹理
3. 使用 Alpha 混合，不使用忽略透明度的 Add 混合
4. 关闭 HDR 和 Bloom，避免透明区域被后处理采样成方块
5. 标签不使用黑色阴影层
6. 避免创建 8,000 多个独立节点

几何结构：

- 4 个顶点/恒星
- 2 个三角形/恒星
- 视星等决定大小
- B-V 色指数决定颜色

## 12. 星座标签锚点

星座名称不能使用简单赤经赤纬平均值。当前实现会：

1. 将所有星座线端点转换到地平坐标系
2. 计算每段线的三维中点
3. 按线段长度加权
4. 归一化后得到几何中心
5. 使用同一个 `SkyPosition` 参与投影和标签显示

这样名称会稳定落在对应连线网络的中心。

## 13. 观测计划、日志与事件

v1.1 新增 `ObservationPlanner`：

1. 根据用户本地时间和日期确定观测夜晚。
2. 计算日落、日出、民用/航海/天文暮光。
3. 计算月相、照亮比例、月升和月落。
4. 在有效暗夜中按 10 分钟采样目标高度。
5. 细化高度穿越时间并过滤短于 20 分钟的窗口。
6. 综合目标类型、亮度、最高高度、持续时间和月光干扰评分。
7. 输出最佳时刻、时长和大众化推荐原因。

收藏通过 `FavoriteStore` 保存在各平台 UserDefaults。通知使用
`ObservationReminderScheduling` 协议，iOS/macOS App 注入真实
`UserNotificationScheduler`，Core 测试使用 Noop 或测试替身。

通知权限只在用户主动开启提醒时请求，拒绝权限不会影响收藏和星图使用。

观测日志使用 Application Support 下的 `observation-log.json`：

- 原子写入，避免中断造成半写入文件
- 支持创建、编辑、删除和筛选
- 损坏文件会先备份为 `observation-log-corrupt-<timestamp>.json`
- 首版不保存照片，也不上传日志

离线天空事件由 `AstronomyEventPlanner` 生成：

- 默认范围 120 天
- 月相和季节直接调用 Astronomy Engine
- 日月食按当地观测者计算
- 行星合按 6 小时采样和三分法细化，阈值为 5°
- 结果按地点和日期范围缓存

## 14. 构建

生成工程：

```bash
xcodegen generate
```

macOS：

```bash
xcodebuild \
  -project SkyTrace.xcodeproj \
  -scheme SkyTraceMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- \
  build
```

iOS Simulator：

```bash
xcodebuild \
  -project SkyTrace.xcodeproj \
  -scheme SkyTrace \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### 本地版本化 macOS App

将当前 Debug 构建发布为 `~/Applications/SkyTrace/SkyTrace-<版本>.app`：

```bash
Scripts/publish_local_macos_app.sh \
  build/Build/Products/Debug/SkyTrace.app \
  --replace
```

脚本会从 `Info.plist` 读取版本号和 build 号，验证 Bundle ID，只修改副本的
`CFBundleDisplayName`，随后重新执行 ad-hoc 签名并校验。目标已存在时必须显式传入
`--replace`。不同版本保留相同 Bundle ID，因此同一时间只应运行一个版本。

## 15. 测试

Core：

```bash
swift test --package-path Packages/SkyTraceCore
```

macOS 全部测试：

```bash
xcodebuild \
  -project SkyTrace.xcodeproj \
  -scheme SkyTraceMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- \
  test
```

iOS 全部测试：

```bash
xcodebuild \
  -project SkyTrace.xcodeproj \
  -scheme SkyTrace \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

GitHub Actions 会执行 Core、macOS 构建/单元测试和 iOS 构建/单元测试。UI 测试由于依赖桌面会话，保留为本地验收。

## 16. 常见问题

### Xcode 找不到 iOS Simulator

```bash
xcodebuild -downloadPlatform iOS
xcrun simctl list devices available
```

### `SkyTrace.xcodeproj` 不存在

```bash
brew install xcodegen
xcodegen generate
```

### Swift Package 依赖异常

```bash
swift package --package-path Packages/SkyTraceCore reset
xcodebuild -resolvePackageDependencies -project SkyTrace.xcodeproj
```

### SceneKit 星点变成方块

检查：

- 是否存在 `SCNGeometryPrimitiveType.point`
- 是否使用 `.alpha` 混合
- 相机 Bloom 是否为 0
- 标签是否残留黑色阴影
- 径向纹理四角 alpha 是否为 0

### 星座名称和星图不一致

检查：

- SceneKit 相机是否使用 `SkyCameraBasis.orientationMatrix`
- 标签是否使用 `SkyCameraState.basis`
- 星座锚点是否来自 `SkySnapshot`
- 是否绕开共享投影自行计算屏幕坐标

## 17. 贡献和发布

提交前：

```bash
git diff --check
swift test --package-path Packages/SkyTraceCore
```

Pull Request 必须说明平台影响，并附上测试结果和 UI 截图。详细约定见根目录 `CONTRIBUTING.md`。

当前开源版本使用 MIT License，第三方组件和数据来源见 `THIRD_PARTY_NOTICES.md`。
