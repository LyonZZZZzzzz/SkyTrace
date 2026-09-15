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

    var body: some Scene {
        WindowGroup("星迹 SkyTrace") {
            MacContentView(viewModel: viewModel, uiState: uiState)
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
    }
}
