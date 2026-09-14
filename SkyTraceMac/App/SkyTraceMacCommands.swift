import SkyTraceCore
import SwiftUI

struct SkyTraceMacCommands: Commands {
    @Bindable var viewModel: SkyViewModel
    @Bindable var uiState: MacUIState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("导航") {
            Button("搜索天空…") { uiState.showSearch = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("观测位置…") { uiState.showLocation = true }
                .keyboardShortcut("l", modifiers: .command)
            Button("今晚可见…") { uiState.showTonight = true }
                .keyboardShortcut("t", modifiers: .command)
            Divider()
            Button("清除选择") { viewModel.clearSelection() }
                .keyboardShortcut(.delete, modifiers: [])
        }

        CommandMenu("时间") {
            Button("现在") { viewModel.resetToNow() }
                .keyboardShortcut("0", modifiers: .command)
            Button(viewModel.isPlaying ? "暂停" : "播放") { viewModel.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
            Divider()
            Button("后退一天") { viewModel.shiftTime(by: -86_400) }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
            Button("前进一天") { viewModel.shiftTime(by: 86_400) }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
        }

        CommandMenu("视图") {
            Toggle("显示星座线", isOn: $uiState.showConstellations)
            Toggle("显示方位标记", isOn: $uiState.showCardinals)
            Divider()
            Button("放大") { viewModel.nudge(zoom: -5) }
                .keyboardShortcut("+", modifiers: .command)
            Button("缩小") { viewModel.nudge(zoom: 5) }
                .keyboardShortcut("-", modifiers: .command)
            Button("重置视角") { viewModel.resetCamera() }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            Button("切换检查器") { uiState.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
