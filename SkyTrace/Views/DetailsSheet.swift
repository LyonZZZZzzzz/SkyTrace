import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct DetailsSheet: View {
    @Bindable var viewModel: SkyViewModel
    let object: CelestialObject
    let position: SkyPosition?
    @Environment(\.dismiss) private var dismiss
    @State private var showLogForm = false

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
                    },
                    onAddLog: { showLogForm = true }
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
        .sheet(isPresented: $showLogForm) {
            ObservationLogForm(
                object: object,
                observer: viewModel.observer,
                onSave: { entry in
                    Task {
                        if await viewModel.saveObservationLog(entry) {
                            showLogForm = false
                        }
                    }
                },
                onCancel: { showLogForm = false }
            )
        }
    }
}
