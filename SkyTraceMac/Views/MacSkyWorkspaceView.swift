import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacSkyWorkspaceView: View {
    @Bindable var viewModel: SkyViewModel
    @Bindable var uiState: MacUIState
    let renderEnvironment: SkyRenderEnvironment

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
                renderEnvironment: renderEnvironment,
                onCameraChange: { viewModel.camera = $0 },
                onSelect: { objectID in
                    if let objectID {
                        viewModel.center(on: objectID)
                    } else {
                        viewModel.clearSelection()
                    }
                },
                onReset: viewModel.resetCamera,
                onDiagnosticsChange: { diagnostics in
                    uiState.renderDiagnostics = diagnostics
                },
                onLabelReadinessChange: { ready in
                    Task { @MainActor in
                        uiState.isLabelPreparationComplete = ready
                    }
                }
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

            if !uiState.isLabelPreparationComplete {
                Text("正在准备完整星名…")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .skyPanel(cornerRadius: 10)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 92)
                    .accessibilityIdentifier("sky-label-preparation-status")
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
            MacTimeControlsView(viewModel: viewModel)
                .padding(14)
        }
    }
}
