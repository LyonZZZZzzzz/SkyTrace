import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct TonightSheet: View {
    @Bindable var viewModel: SkyViewModel
    let onSelect: (CelestialObject) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TonightPlanContent(
                plan: viewModel.observationPlan,
                state: viewModel.observationPlanState,
                favoriteIDs: viewModel.favoriteIDs,
                onSelect: onSelect,
                onToggleFavorite: viewModel.toggleFavorite
            )
            .navigationTitle("今晚观测计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
