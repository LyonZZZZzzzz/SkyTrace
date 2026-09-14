import SkyTraceCore
import SwiftUI

@main
struct SkyTraceApp: App {
    @State private var viewModel = SkyViewModel(
        locationService: CoreLocationService(),
        motionService: MotionService(),
        astronomy: AstronomyService()
    )

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(nil)
        }
    }
}
