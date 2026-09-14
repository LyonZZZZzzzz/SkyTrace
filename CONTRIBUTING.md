# Contributing to SkyTrace

感谢你愿意参与 SkyTrace。本文档说明开发环境、代码规范、测试要求和 Pull Request 流程。

## 开始之前

- 阅读 [README.md](README.md) 和 [ARCHITECTURE.md](ARCHITECTURE.md)
- 搜索已有 Issue，避免重复报告
- 大型功能请先创建 Feature Request，说明目标、界面和验收标准
- 不要提交 Apple 开发者证书、描述文件、API Token、设备 UDID 或个人位置数据

## 开发环境

- macOS 14+
- Xcode 16.4+
- Swift 6.1+
- XcodeGen 2.46+
- iOS 18 Simulator Runtime，用于 iOS 测试
- VS Code 可选；推荐 Swift、SweetPad 和 CodeLLDB 扩展

```bash
brew install xcodegen
xcodegen generate
```

## 构建与测试

Core：

```bash
swift test --package-path Packages/SkyTraceCore
```

macOS：

```bash
xcodebuild \
  -project SkyTrace.xcodeproj \
  -scheme SkyTraceMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- \
  test
```

iOS：

```bash
xcodebuild \
  -project SkyTrace.xcodeproj \
  -scheme SkyTrace \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

涉及 SceneKit 的修改必须补充或运行以下测试：

- 相机基向量正交性
- SceneKit 姿态与 `SkyCameraBasis` 一致性
- 星点纹理四角透明度
- 黑色背景与彩色背景离屏渲染
- 星座标签几何锚点

## 代码规范

- 遵循 Swift API Design Guidelines
- 使用 Swift 6，不引入不必要的外部依赖
- 平台无关逻辑放在 `SkyTraceCore`
- 共享 SwiftUI 组件放在 `SkyTraceUI`
- iOS 与 macOS 的窗口、手势和平台适配留在各自 App target
- 不在 View 中重复实现相机、坐标或天文计算
- 所有新增数据必须记录来源和许可证

## 分支和提交

- 从最新 `main` 创建分支
- 推荐分支前缀：`feature/`、`fix/`、`docs/`、`chore/`
- 使用 Conventional Commits：
  - `feat(core): ...`
  - `fix(render): ...`
  - `test(ios): ...`
  - `docs: ...`

## Pull Request

Pull Request 必须包含：

- 修改目的和用户可见行为
- 关联 Issue
- 测试命令与结果
- UI 修改前后截图
- 数据或许可证变化
- 平台影响：iOS、iPadOS、macOS

提交 PR 前执行：

```bash
git diff --check
swift test --package-path Packages/SkyTraceCore
```

## 数据与许可证

- 目录数据必须属于公共领域或使用 MIT/BSD/Apache-2.0 兼容许可证
- 新增第三方代码必须更新 `THIRD_PARTY_NOTICES.md`
- 不得直接复制 GPL 或不兼容许可证的星表、纹理或代码

## 行为准则

参与项目即表示同意遵守 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。
