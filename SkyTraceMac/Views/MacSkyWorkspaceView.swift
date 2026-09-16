import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacSkyWorkspaceView: View {
    @Bindable var viewModel: SkyViewModel
    @Bindable var uiState: MacUIState

    var body: some View {
        ZStack {
            Color.skyBackground

            MacSkySceneView(
                snapshot: viewModel.snapshot,
                catalog: viewModel.sceneCatalog,
                camera: viewModel.camera,
                selectedObjectID: viewModel.selectedObjectID,
                showConstellations: uiState.showConstellations,
                starScale: uiState.starScale,
                labelMagnitudeLimit: uiState.labelDensity.magnitudeLimit,
                showCardinals: uiState.showCardinals,
                isTimePlaybackActive: viewModel.isPlaying,
                onCameraChange: { viewModel.camera = $0 },
                onSelect: { objectID in
                    if let objectID {
                        viewModel.center(on: objectID)
                    } else {
                        viewModel.clearSelection()
                    }
                },
                onReset: viewModel.resetCamera
            )


            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.observer.name)
                            .font(.headline)
                        Text(viewModel.formattedMoment)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .skyPanel(cornerRadius: 14)

                    Spacer()

                    Text(String(format: "视场 %.0f°", viewModel.camera.fieldOfView))
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .skyPanel(cornerRadius: 12)
                }
                .padding(14)

                Spacer()
            }

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .skyPanel(cornerRadius: 14)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 72)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MacTimelineView(viewModel: viewModel)
                .padding(14)
        }
    }
}
