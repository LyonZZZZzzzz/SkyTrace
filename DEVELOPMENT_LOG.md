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

## 16. v1.2 发布硬化与观测闭环

- Bundle ID 更新为 `com.lyonzzzzzzzz.SkyTrace` 与 `.mac`。
- 为 Core、iOS 和 macOS 增加隐私清单，声明不追踪、不收集数据，并说明 UserDefaults 使用原因。
- 增加 Logger 与 Signpost，覆盖星表、快照、观测计划和通知调度。
- 新增轻量观测日志，使用 Application Support JSON 原子存储，支持筛选、编辑、删除和损坏恢复。
- 新增未来 120 天离线天空事件：月相、日月食、行星合和四季节气。
- iOS 和 macOS 的今晚页面升级为“今晚 / 天空事件 / 观测日志”观星中心。
- macOS 侧栏增加事件和日志内容，检查器可快速记录观测。
- 新增隐私清单构建验证、日志仓库测试和离线事件计划测试。
- 版本更新为 1.2.0（build 3）。

## 17. v1.2.1 60 FPS 与本地版本化 App

- 将恒星、深空天体和星座线改为静态 J2000 场景，时间与地点变化只旋转根节点。
- 新增后台快照 worker、latest-wins 请求代次和 60 Hz 渲染插值。
- 标签迁移到固定大小的 SpriteKit overlay，删除 SwiftUI 全量投影层。
- 新增帧指标、慢帧统计和 Debug Signpost。
- 修复 SceneKit 私有渲染队列上的主线程隔离崩溃。
- 工程版本更新为 1.2.1（build 4）。
- 新增 `Scripts/publish_local_macos_app.sh`，将构建产物发布为带版本号的本地 App。
- 本地归档为 `SkyTrace-1.2.0.app` 和 `SkyTrace-1.2.1.app`。

## 18. 相机极点穿越与拖动动画

- 定位到天顶附近基向量参考轴切换导致约 45° 瞬时滚转。
- 相机基向量改为连续极点安全算法，精确天顶和天底仍有稳定正交姿态。
- 新增 `SkyCameraMotionController`，使用四元数插值、指数阻尼和释放速度惯性。
- 移除 ±89° 高度角硬限制，星图现在可以连续穿越南北极点。
- iOS 和 macOS 拖动改为增量目标姿态；鼠标和触摸释放后可按速度平滑滑行。
- 新触摸、点击或方向输入会立即中断惯性。
- 新增 7 项相机运动测试，Core 总计 38 项测试通过。
- macOS/iOS 单元测试和星图拖动 UI 冒烟测试通过。

## 19. 后台暂停与按需渲染

- 复现后台运行约 20 小时后 CPU 仍约 37.8% 的问题。
- SceneKit 改为由应用活动状态、窗口可见性和相机/时间动画共同决定连续渲染。
- 前台无拖动、无惯性、无播放和无快照过渡时暂停持续绘制。
- 进入后台或窗口被遮挡时停止渲染、相机时间基准和动力节点更新。
- 时间播放和 CoreMotion 在后台暂停，返回前台后恢复原状态。
- 后台间隔不再进入 P95/P99 采样。
- 实测前台空闲 CPU 约 0.1%，后台 CPU 约 0.0%。
- Core 42 项测试、macOS/iOS 单元与 UI 流程通过。

## 20. v1.2.2 性能尾延迟优化

- 真机 Animation Hitches 基线：P95 17.177ms、P99 37.541ms、最大 75.07ms。
- 观测计划、天空事件和提醒改为按需加载，避免与首屏渲染竞争。
- 标签文本纹理每帧最多创建 4 个，并使用隐藏节点分批预热中文字形。
- 标签节点按天体 ID 固定绑定，转动时不再因可见顺序变化反复重建文字纹理。
- 标签投影结果按相机、根节点矩阵、视口和选择状态缓存。
- 太阳系动态天体在后台快照中预索引，标签候选按星等预排序，首帧不再扫描并构造 8,404 项字典。
- 帧指标改用固定容量环形缓冲，移除每帧数组头部移动。
- 新增 interactive、animating、idleWarm、suspended 四种渲染策略。
- 可见空闲状态使用 2 Hz 保活帧，热状态严重、低电量或后台时停止。
- 版本更新为 1.2.2（build 5）。

## 21. v1.2.3 标签重叠治理

- 标签优先级调整为选中目标、日月行星、星座、亮星、深空天体。
- SpriteKit 标签层加入屏幕空间碰撞检测，重叠时隐藏低优先级名称。
- 选中目标和方位标签参与同一碰撞队列，选中目标始终优先保留。
- 标签尺寸仅在文本或字号变化时测量，并使用对象 ID 保持节点复用。
- 被隐藏标签在缩放或转动释放空间后自动恢复，不重建文字纹理。
- 新增标签优先级、重叠隐藏、选中优先、尺寸缓存和自动恢复测试。
- 版本更新为 1.2.3（build 6）。

## 22. v1.2.4 标签边界闪动修复

- 复现标签在拖动或缩放停止后反复显示/隐藏的问题。
- 根因是相机阻尼停稳前后的微小位移让标签碰撞框在单一阈值附近反复相交。
- 标签碰撞改为双阈值迟滞：隐藏标签需要更大间距才恢复，已显示标签允许轻微接近后再隐藏。
- 对象标签和方位标签使用同一套迟滞状态。
- 新增边界抖动回归测试，版本更新为 1.2.4（build 7）。

## 23. v1.2.5 标签原地抖动修复

- 定位到生产标签使用 SceneKit 实时投影，FOV 阻尼收敛时可能读取到尚未提交的相机状态。
- 标签投影改为使用同一相机状态、基向量和视口构建的共享 SkyProjection。
- SCNView.projectPoint 只保留在调试比较测试中。
- 标签位置量化到 0.25pt，并忽略小于该阈值的位置变化。
- 新增重复投影、FOV 单调收敛、跨视场 SceneKit 对齐和亚像素稳定测试。
- 版本更新为 1.2.5（build 8）。

## 24. v1.2.6 标签对齐与抖动修复

- 真机验证发现共享数学投影与 SceneKit 投影仍有细微差异，导致旋转或缩放时标签与星点错位。
- 生产标签投影恢复为 SceneKit 原生 projectPoint，确保与星点使用同一渲染坐标。
- 保留 0.25pt 位置死区和量化，只抑制亚像素抖动，不再替换投影算法。
- 碰撞检测改用稳定后的节点位置，避免显示位置与碰撞位置不一致。
- 版本更新为 1.2.6（build 9）。

## 25. v1.2.7 字体纹理闪动修复

- 定位到 SKLabelNode 的 fontColor 和 alpha 即使值未变化也被每帧写入。
- 新增 SkyLabelStyle，按选中、星座、深空、太阳系和普通恒星缓存节点样式。
- 只有文字、类别或选中状态真正变化时才更新字号、颜色和透明度。
- 样式变化时才清理文字尺寸缓存，位置和可见性继续逐帧更新。
- 新增重复刷新、顺序变化、选中切换和 100 标签位置更新测试。
- 版本更新为 1.2.7（build 10）。

## 26. v1.2.8 最小缩放标签闪动优化

- 最大 FOV 下标签在屏幕边缘会反复进入和离开 100 个候选位置。
- 新增 SkyLabelEligibilityPolicy，新标签使用严格边界，已显示标签使用 60/48pt 放宽边界。
- 文本预热队列新增待处理状态，预热期间保持连续渲染，完成后恢复 2 Hz 保活。
- 新增边缘迟滞、待处理文字状态和渲染策略回归测试。
- 版本更新为 1.2.8（build 11）。

## 27. v1.2.9 最大视场标签容量优化

- 最大 FOV 下标签数量超过稳定显示能力，旋转时前 100 个名额持续竞争。
- 新增 SkyLabelCapacityPolicy，按 FOV 使用 100/90/80 三档容量，并设置 5° 迟滞。
- 新增驻留标签优先分配，必选、驻留、新进入标签依次占用名额。
- 普通观察 FOV 继续最多显示 100 个标签，最大 FOV 下稳定显示约 80 个。
- 版本更新为 1.2.9（build 12）。
