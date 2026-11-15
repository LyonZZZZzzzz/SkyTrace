import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacContentView: View {
    @Bindable var viewModel: SkyViewModel
    @Bindable var uiState: MacUIState
    @Bindable var renderEnvironment: SkyRenderEnvironmentMonitor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch viewModel.catalogState {
            case .loading:
                ProgressView("正在加载离线星表…")
                    .tint(.skyCyan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView(
                    "星表加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                readyContent
            }
        }
        .task {
            await viewModel.prepare()
        }
        .task(id: scenePhase) {
            viewModel.setApplicationActive(scenePhase == .active)
        }
        .sheet(isPresented: $uiState.showSearch) {
            MacSearchSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $uiState.showLocation) {
            MacLocationSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $uiState.showTonight) {
            MacTonightSheet(viewModel: viewModel) { object in
                viewModel.select(object)
                uiState.showTonight = false
            }
        }
        .background(colorScheme == .dark ? Color.black : Color(nsColor: .windowBackgroundColor))
    }

    private var readyContent: some View {
        NavigationSplitView(columnVisibility: $uiState.columnVisibility) {
            MacSidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } content: {
            MacSkyWorkspaceView(
                viewModel: viewModel,
                uiState: uiState,
                renderEnvironment: renderEnvironment.environment
            )
                .navigationSplitViewColumnWidth(min: 620, ideal: 860)
        } detail: {
            MacInspectorView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 330, max: 420)
        }
        .navigationTitle("星迹 SkyTrace")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    uiState.showSearch = true
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .help("搜索天体（⌘F）")

                Button {
                    uiState.showLocation = true
                } label: {
                    Label("观测位置", systemImage: "location")
                }
                .help("选择观测位置（⌘L）")

                Button {
                    uiState.showTonight = true
                } label: {
                    Label("今晚可见", systemImage: "moon.stars")
                }
                .help("查看今晚可见目标（⌘T）")

                Button {
                    uiState.showConstellations.toggle()
                } label: {
                    Label("星座线", systemImage: uiState.showConstellations ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted")
                }
                .help("显示或隐藏星座线")

                Button {
                    viewModel.resetCamera()
                } label: {
                    Label("重置视角", systemImage: "scope")
                }
                .help("重置方位与视场")
            }
        }
    }
}
