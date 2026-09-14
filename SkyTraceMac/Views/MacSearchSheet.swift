import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacSearchSheet: View {
    @Bindable var viewModel: SkyViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.searchQuery.isEmpty {
                    List {
                        Section("太阳系") {
                            ForEach(solarSystemObjects) { object in
                                resultRow(object)
                            }
                        }
                        Section("热门深空") {
                            ForEach(deepSkyObjects) { object in
                                resultRow(object)
                            }
                        }
                    }
                } else if viewModel.searchResults.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchQuery)
                } else {
                    List(viewModel.searchResults) { object in
                        resultRow(object)
                    }
                }
            }
            .navigationTitle("搜索天空")
            .searchable(text: $viewModel.searchQuery, prompt: "恒星、行星、星座、梅西耶编号")
            .onChange(of: viewModel.searchQuery) { _, _ in viewModel.search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 500, idealHeight: 680)
    }

    private var solarSystemObjects: [CelestialObject] {
        (viewModel.repository?.allObjects ?? []).filter {
            [.sun, .moon, .planet].contains($0.kind)
        }
    }

    private var deepSkyObjects: [CelestialObject] {
        (viewModel.repository?.allObjects ?? [])
            .filter { $0.kind == .deepSky && ($0.magnitude ?? 99) <= 6 }
            .sorted { ($0.magnitude ?? 99) < ($1.magnitude ?? 99) }
            .prefix(20)
            .map { $0 }
    }

    private func resultRow(_ object: CelestialObject) -> some View {
        Button {
            viewModel.select(object)
            dismiss()
        } label: {
            CelestialObjectRow(object: object)
        }
        .buttonStyle(.plain)
    }
}
