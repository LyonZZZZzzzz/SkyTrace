# SkyTrace 开发过程记录

> 本文件记录从空 Git 仓库到可运行 iOS 与 macOS 工程的完整实现过程。代码、配置、测试和资源均位于当前 VS Code 工作区。

## 1. 环境确认

- 工作区最初是空 Git 仓库，没有提交和已有技术栈。
- 本机确认安装 Xcode 16.4、Swift 6.1.2、Homebrew 和 Visual Studio Code。
- 本机最初没有 XcodeGen，也没有 iOS Simulator Runtime。
- 项目被定为 iOS 17+ 原生应用，采用 SwiftUI、SceneKit、CoreLocation、CoreMotion。
- 运行 `brew install xcodegen` 安装 2.46.0。
- 运行 `xcodebuild -downloadPlatform iOS` 安装 iOS 18.6 Simulator Runtime。

## 2. 工程骨架

- `project.yml` 是 Xcode 工程的唯一配置源。
- `SkyTrace.xcodeproj` 由 XcodeGen 生成，不提交、不手工编辑。
- 配置了 iPhone/iPad 横竖屏、定位权限、运动权限、应用图标和启动背景。
- [`.vscode/tasks.json`](.vscode/tasks.json) 提供生成工程、模拟器构建和测试任务。
- [`.vscode/launch.json`](.vscode/launch.json) 提供 SweetPad 模拟器调试配置。
- [`.vscode/extensions.json`](.vscode/extensions.json) 推荐 Swift、SweetPad 和 CodeLLDB。

## 3. 离线天文数据

- 版本化 [Astronomy Engine](Packages/AstronomyEngine) C 实现，并编写 Swift 封装；不需要构建时联网。
- 使用 NASA ADC / CDS 发布的 Yale Bright Star Catalogue 5th ed.。
- 从 9,110 条原始记录中筛选出 8,404 条带有效 J2000 坐标、视星等不超过 6.5 的记录。
- 二进制记录字段依次为 HR、HIP、赤经、赤纬、视星等、B-V，每条 24 字节。
- 转换 88 个 IAU 星座的 BSD-3-Clause 连线数据。
- 转换 110 个梅西耶天体及其分类、编号、视星等和坐标。
- 引入 4,107 条主要恒星名称记录和 30 个离线城市。
- [目录生成脚本](Tools/generate_catalog.py) 可重复生成全部资源。
- 完整性校验结果：8,404 stars、88 constellations、110 deep-sky、30 cities。

## 4. 天文计算层

- `AstronomyEngine` 本地 Swift Package 使用 C target 封装 Astronomy Engine。
- 实现 UTC 日期、观察者坐标、J2000 赤道坐标到地平坐标的转换。
- 使用 `HorizontalTransform` 预先计算旋转矩阵，8,000 多个恒星无需重复初始化星历。
- 太阳、月球和主要行星使用 Astronomy Engine 的视位置与地平坐标计算。
- 星座连线使用同一旋转矩阵随时间和观察位置实时更新。
- 提供 `AstronomyCalculating` 协议，便于替换计算实现和单元测试。

## 5. 数据与状态层

- `CatalogRepository` 离线加载并验证二进制星表、星座、深空天体、名称和城市。
- 搜索支持中文名、英文名、Bayer/Flamsteed 标识、HR/HIP 编号和梅西耶编号。
- `ObserverContext` 保存地点、纬经度、海拔和时区。
- `SkySnapshot` 聚合天体位置、星座连线和今晚推荐。
- `SkyViewModel` 管理加载状态、时间旅行、播放、定位、姿态、搜索、选择和镜头联动。
- 观测地点保存到 UserDefaults；位置与运动能力失败时自动降级，不阻止星图使用。

## 6. SceneKit 与界面

- `SkySceneView` 使用单点云几何绘制 8,000 多颗恒星。
- 点大小按视星等变化，颜色按 B-V 色指数从蓝白到暖橙插值。
- 星座线、地平圈和选中目标高亮由 SceneKit 绘制。
- SwiftUI 标签层根据相机方向投影亮星、太阳系天体、深空目标和星座标签。
- 支持单指拖动、捏合缩放、双击复位、点击选择。
- 姿态模式使用 CoreMotion，在模拟器或无传感器设备上自动回退触摸操作。
- 主界面包括位置/时间栏、搜索、今晚可见、姿态开关、镜头复位和时间旅行控制。
- 详情面板显示类型、编号、视星等、当前方位、高度和赤经赤纬。
- 首次启动引导说明拖动、定位和时间旅行。

## 7. 资源与测试

- 生成原创 1024×1024 不透明应用图标。
- 添加 3 组单元测试：目录完整性、天文坐标、投影和 ViewModel。
- 添加 UI 启动与搜索流程测试。
- 添加 MIT、BSD 与 BSC5 来源说明：[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- 添加日常开发说明：[README.md](README.md)。

## 8. 验证命令

```bash
xcodegen generate

xcodebuild \
  -project SkyTrace.xcodeproj \
  -scheme SkyTrace \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project SkyTrace.xcodeproj \
  -scheme SkyTrace \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 9. 构建与测试结果

- 完整目录数据通过独立结构校验：8,404 stars、88 constellations、110 deep-sky、30 cities。
- `AstronomyEngine` 通过 macOS 和 iOS Simulator 目标的 SwiftPM 编译。
- SkyTrace 通过 iPhone 16 Pro / iOS 18.6 Simulator 完整构建。
- 单元测试 8/8 通过：目录完整性、离线搜索、星座连线、天体坐标、投影、ViewModel 和时间旅行。
- UI 测试 1/1 通过：首次启动、跳过引导、打开搜索、输入“金星”和显示结果。
- 已实际安装并启动 App，模拟器首屏正常显示星空、星座标签、顶部位置/时间栏和底部时间控制。
- 运行期发现并修复：Metal shader 点尺寸不兼容、UI 测试 MainActor 隔离、搜索框自动化焦点、详情 sheet 呈现时序。

## 10. VS Code 中的查看入口

- [开发过程记录](DEVELOPMENT_LOG.md)
- [项目说明](README.md)
- [XcodeGen 工程配置](project.yml)
- [VS Code 构建与测试任务](.vscode/tasks.json)
- [应用入口](SkyTrace/App/SkyTraceApp.swift)
- [主界面](SkyTrace/Views/ContentView.swift)
- [SceneKit 星图](SkyTrace/Rendering/SkySceneView.swift)
- [星表生成器](Tools/generate_catalog.py)


## 11. macOS 与多平台重构

- 新增 `Packages/SkyTraceCore`，集中模型、目录、位置、天文计算、ViewModel、投影和 SceneKit 控制器。
- 新增 `Packages/SkyTraceUI`，共享主题、按钮、标签、天体列表行和详情内容。
- 离线目录迁移到 `SkyTraceCore` 的 SwiftPM resource bundle，通过 `Bundle.module` 在 iOS 与 macOS 加载。
- iOS 保留原导航和手势结构，只迁移到共享模块与视觉组件。
- 新增原生 `SkyTraceMac` target，要求 macOS 14+ 与 Apple Silicon。
- macOS UI 采用三栏结构：左侧天体目录、中央星空与时间轴、右侧对象检查器。
- 新增 AppKit 鼠标、滚轮、捏合、双指旋转、键盘和双击交互。
- 新增 macOS 菜单命令、快捷键和独立设置窗口。
- 系统浅色/深色外观会更新窗口和面板；星空画布固定使用深色以保证恒星对比度。
- VS Code 增加 macOS 构建、测试、运行和共享 Core 测试任务。
- 保留 iOS 与 Mac 各自的 UserDefaults，不引入 iCloud 或网络同步。

## 12. 多平台验证结果

- SkyTraceCore：3/3 测试通过。
- macOS：构建成功、单元测试 2/2 通过、UI 测试 1/1 通过。
- iOS Simulator：构建成功、单元测试 8/8 通过、UI 测试 1/1 通过。
- macOS UI 测试验证窗口启动、左侧目录、今晚可见、`⌘F` 搜索、输入 `M42` 并显示“猎户座大星云”。
- iOS UI 测试验证首次启动、搜索“金星”、显示结果。
- 已实际运行 macOS App 并确认左侧目录、中央星空、右侧检查器和底部时间轴正常显示。
- macOS 截图：[Docs/SkyTraceMac-Screenshot.png](Docs/SkyTraceMac-Screenshot.png)


## 13. 星空黑色方块修复

- 用户报告后确认问题来自 SceneKit 的 `SCNGeometryPrimitiveType.point`：点图元会按方形栅格绘制，`pointSize` 只改变方块大小。
- 将每颗恒星改为切线平面上的四边形公告板，四边形始终朝向位于球心的相机。
- 使用 64×64 径向渐变透明纹理，让星点呈现亮核和柔和边缘，不再出现方形轮廓。
- 单个几何包含全部恒星，无额外节点开销；继续保留视星等大小和 B-V 颜色映射。
- 新增几何结构测试、纹理四角透明度测试和 Metal 离屏渲染测试，验证中心明亮、方形角落透明。
- 第二轮复核进一步确认：星点几何已为圆形，但加法混合忽略纹理 Alpha、HDR/Bloom 后处理和标签阴影仍可能产生方形层。
- 星点材质改为 Alpha 混合，关闭相机 HDR/Bloom，并移除文字标签的黑色阴影层。
- 离屏测试改用红色背景，明确验证四边形角落显示背景色而非黑色方块。
- SkyTraceCore 7/7、macOS 单元/UI 测试、iOS 单元/UI 测试全部通过。
- 最终截图检测：macOS 中央星空黑色方形连通域 0 个，iOS 黑色方形连通域 0 个。
- macOS 与 iOS 最终截图已更新至 `Docs/`。


## 14. 星座标签旋转同步修复

- 确认根因：SceneKit 相机使用最短弧四元数设置姿态，标签投影使用世界向上向量，二者在非正北方向会产生不同滚转。
- 数学复现误差：方位角 45°、90°、180° 时，相机基向量偏差分别约为 14.9°、35°、180°。
- 新增 `SkyCameraBasis`，统一维护相机的 forward、right、up 和 roll。
- `SkyProjection` 和 `SkySceneController` 现在使用同一个 `SkyCameraState.basis`，SceneKit 相机矩阵直接由该基向量构造。
- 天顶和天底附近增加备用参考轴，避免相机基向量退化。
- 星座名称改为显示在所有连线中点的长度加权几何中心，不再使用简单赤经赤纬平均值。
- 新增跨方位角、高度角和滚转角的相机正交测试，CameraKit 姿态角度误差要求小于 0.01°。
- 新增星座几何锚点测试，确认标签与实际连线网络使用同一中心。
- SkyTraceCore 11/11、macOS 单元/UI 测试、iOS 单元/UI 测试全部通过。
- 最终 macOS 与 iOS 截图已更新至 `Docs/`。

## 15. v1.1 观测助手

- 新增观测夜晚、三级暮光、月相、月亮升落和目标可见窗口模型。
- 新增后台 `ObservationPlanner`，按 10 分钟采样并细化可见时间，过滤短窗口。
- 推荐评分加入目标类型、亮度、高度、时长和月光干扰。
- 新增恒星、行星、太阳、月球、星座和梅西耶天体的收藏持久化。
- 新增用户主动开启的本地通知调度，权限拒绝时保持收藏和计划可用。
- iOS 增加收藏入口、今晚计划时间线和详情提醒。
- macOS 增加收藏侧栏、检查器提醒和设置中的全局通知开关。
- 新增上海暮光/月相、高纬度极昼、短窗口过滤、收藏持久化和拒绝通知测试。
- 版本更新为 1.1.0（build 2）。
