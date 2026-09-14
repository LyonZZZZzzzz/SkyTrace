import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct SearchSheet: View {
    @Bindable var viewModel: SkyViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.searchQuery.isEmpty {
                    quickSearch
                } else if viewModel.searchResults.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchQuery)
                } else {
                    resultList
                }
            }
            .navigationTitle("搜索天空")
            .searchable(text: $viewModel.searchQuery, prompt: "恒星、行星、星座、梅西耶编号")
            .onChange(of: viewModel.searchQuery) { _, _ in
                viewModel.search()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var quickSearch: some View {
        List {
            Section("太阳系") {
                ForEach(Array((viewModel.repository?.allObjects ?? []).filter {
                    [.sun, .moon, .planet].contains($0.kind)
                }.prefix(10))) { object in
                    resultRow(object)
                }
            }

            Section("热门深空") {
                ForEach(Array((viewModel.repository?.allObjects ?? []).filter {
                    $0.kind == .deepSky && ($0.magnitude ?? 99) <= 6
                }.sorted { ($0.magnitude ?? 99) < ($1.magnitude ?? 99) }.prefix(14))) { object in
                    resultRow(object)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var resultList: some View {
        List(viewModel.searchResults) { object in
            resultRow(object)
        }
        .listStyle(.insetGrouped)
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
