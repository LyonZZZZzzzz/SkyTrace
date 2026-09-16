import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: SkyViewModel
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("SkyTrace.DidShowOnboarding") private var didShowOnboarding = false
    @State private var showSearch = false
    @State private var showFavorites = false
    @State private var showLocation = false
    @State private var showTonight = false
    @State private var showDetails = false
    @State private var showOnboarding = false
    @AppStorage("SkyTrace.ShowConstellations") private var showConstellations = true
    @AppStorage("SkyTrace.StarScale") private var starScale = 1.0
    @AppStorage("SkyTrace.LabelDensity") private var labelDensity = SkyLabelDensity.standard
    @AppStorage("SkyTrace.ShowCardinals") private var showCardinals = true

    var body: some View {
        ZStack {
            Color.skyBackground.ignoresSafeArea()

            switch viewModel.catalogState {
            case .loading:
                ProgressView("正在加载离线星表…")
                    .tint(.skyCyan)
            case .failed(let message):
                ContentUnavailableView(
                    "星表加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .ready:
                skyContent
            }
        }
        .task {
            showOnboarding = !didShowOnboarding
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                didShowOnboarding = true
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showSearch, onDismiss: presentSelectedDetailsIfNeeded) {
            SearchSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showFavorites, onDismiss: presentSelectedDetailsIfNeeded) {
            FavoritesSheet(viewModel: viewModel) { object in
                viewModel.select(object)
                showFavorites = false
            }
        }
        .sheet(isPresented: $showLocation) {
            LocationSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showTonight, onDismiss: presentSelectedDetailsIfNeeded) {
            TonightSheet(viewModel: viewModel) { object in
                viewModel.select(object)
                showTonight = false
            }
        }
        .sheet(isPresented: $showDetails) {
            if let object = viewModel.selectedObject {
                DetailsSheet(
                    viewModel: viewModel,
                    object: object,
                    position: viewModel.snapshot.positions.first { $0.id == object.id }
                )
            }
        }
        .onChange(of: viewModel.selectedObjectID) { _, newValue in
            if newValue == nil {
                showDetails = false
            } else if !showSearch && !showFavorites && !showLocation && !showTonight {
                showDetails = true
            }
        }
    }

    private func presentSelectedDetailsIfNeeded() {
        if viewModel.selectedObjectID != nil, !showSearch, !showFavorites, !showTonight {
            showDetails = true
        }
    }

    private var skyContent: some View {
        ZStack {
            SkySceneView(
                snapshot: viewModel.snapshot,
                catalog: viewModel.sceneCatalog,
                camera: viewModel.camera,
                selectedObjectID: viewModel.selectedObjectID,
                showConstellations: showConstellations,
                starScale: starScale,
                labelMagnitudeLimit: labelDensity.magnitudeLimit,
                showCardinals: showCardinals,
                motionEnabled: viewModel.motionEnabled,
                motionReading: viewModel.motionReading,
                isApplicationActive: scenePhase == .active,
                isTimePlaybackActive: viewModel.isPlaying,
                onCameraChange: { viewModel.camera = $0 },
                onTap: { objectID in
                    if let objectID {
                        viewModel.center(on: objectID)
                    } else {
                        viewModel.clearSelection()
                    }
                },
                onReset: viewModel.resetCamera
            )
            .ignoresSafeArea()


            VStack(spacing: 0) {
                header
                Spacer()
                bottomControls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .skyPanel(cornerRadius: 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 92)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                showLocation = true
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label(viewModel.observer.name, systemImage: "location.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.formattedMoment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            SkyRoundIconButton(
                systemName: "magnifyingglass",
                accessibilityLabel: "搜索天体"
            ) {
                showSearch = true
            }

            SkyRoundIconButton(
                systemName: "star",
                accessibilityLabel: "打开收藏"
            ) {
                showFavorites = true
            }

            SkyRoundIconButton(
                systemName: "sparkles",
                accessibilityLabel: "今晚观测计划"
            ) {
                showTonight = true
            }
        }
        .padding(12)
        .skyPanel(cornerRadius: 18)
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            HStack {
                SkyRoundIconButton(
                    systemName: viewModel.motionEnabled ? "gyroscope" : "hand.draw",
                    accessibilityLabel: viewModel.motionEnabled ? "关闭姿态跟随" : "开启姿态跟随",
                    isActive: viewModel.motionEnabled
                ) {
                    viewModel.motionEnabled.toggle()
                }

                Spacer()

                if !(viewModel.observationPlan?.recommendations.isEmpty ?? true) {
                    Button {
                        showTonight = true
                    } label: {
                        Label("今晚计划", systemImage: "moon.stars.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                SkyRoundIconButton(
                    systemName: "scope",
                    accessibilityLabel: "重置视角"
                ) {
                    viewModel.resetCamera()
                }
            }
            .padding(.horizontal, 2)

            TimeControlsView(viewModel: viewModel)
        }
    }
}
