import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct DetailsSheet: View {
    @Bindable var viewModel: SkyViewModel
    let object: CelestialObject
    let position: SkyPosition?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ObjectDetailsContent(
                    object: object,
                    position: position,
                    visibility: viewModel.visibility(for: object.id),
                    timeZone: viewModel.observer.timeZone,
                    isFavorite: viewModel.isFavorite(object.id),
                    isReminderEnabled: viewModel.isReminderEnabled(object.id),
                    onToggleFavorite: { viewModel.toggleFavorite(object) },
                    onToggleReminder: {
                        Task { await viewModel.toggleReminder(for: object) }
                    }
                )
                .padding(20)
            }
            .navigationTitle("天体详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
