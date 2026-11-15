import AppKit
import SkyTraceCore
import SwiftUI

@main
struct SkyTraceMacApp: App {
    @State private var viewModel = SkyViewModel(
        locationService: CoreLocationService(),
        motionService: NoopDeviceMotionProvider(),
        astronomy: AstronomyService(),
        reminderScheduler: UserNotificationScheduler()
    )
    @State private var uiState = MacUIState()
    @State private var renderEnvironment = SkyRenderEnvironmentMonitor()

    var body: some Scene {
        WindowGroup("星迹 SkyTrace", id: "main") {
            MacContentView(
                viewModel: viewModel,
                uiState: uiState,
                renderEnvironment: renderEnvironment
            )
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(nil)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            SkyTraceMacCommands(viewModel: viewModel, uiState: uiState)
        }

        Settings {
            MacSettingsView(viewModel: viewModel, uiState: uiState)
        }

        MenuBarExtra {
            MacMenuBarMenu(uiState: uiState)
        } label: {
            MacMenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MacMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var uiState: MacUIState

    var body: some View {
        Button("显示主窗口") {
            showMainWindow()
        }

        Divider()

        Button("搜索天空…") {
            uiState.showSearch = true
            showMainWindow()
        }

        Button("今晚可见…") {
            uiState.showTonight = true
            showMainWindow()
        }

        Divider()

        SettingsLink {
            Text("设置…")
        }

        Divider()

        Button("退出 SkyTrace") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}


private struct MacMenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .accessibilityLabel("星迹")
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    let hasVisibleContentWindow = NSApplication.shared.windows.contains {
                        $0.isVisible && $0.frame.height > 100
                    }
                    guard !hasVisibleContentWindow else { return }
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
    }
}
