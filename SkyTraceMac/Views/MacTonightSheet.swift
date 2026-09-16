import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacTonightSheet: View {
    @Bindable var viewModel: SkyViewModel
    let onSelect: (CelestialObject) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ObservatoryCenterView(
                plan: viewModel.observationPlan,
                planState: viewModel.observationPlanState,
                favoriteIDs: viewModel.favoriteIDs,
                events: viewModel.astronomyEvents,
                eventState: viewModel.astronomyEventState,
                logs: viewModel.observationLogs,
                timeZone: viewModel.observer.timeZone,
                onSelectObject: onSelect,
                onToggleFavorite: viewModel.toggleFavorite,
                onSelectEvent: { event in
                    viewModel.focus(on: event)
                    dismiss()
                },
                onDeleteLog: { log in
                    Task { await viewModel.deleteObservationLog(id: log.id) }
                }
            )
            .navigationTitle("观星中心")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 620)
        .task { viewModel.ensureTonightDataLoaded() }
    }
}
