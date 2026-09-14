import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct TonightSheet: View {
    @Bindable var viewModel: SkyViewModel
    let onSelect: (CelestialObject) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.snapshot.recommendations.isEmpty {
                    ContentUnavailableView(
                        "当前没有推荐目标",
                        systemImage: "moon.zzz",
                        description: Text("尝试调整时间，让更多目标升到地平线上方。")
                    )
                } else {
                    Section {
                        ForEach(viewModel.snapshot.recommendations) { position in
                            Button {
                                onSelect(position.object)
                            } label: {
                                TonightRecommendationRow(position: position)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("按高度、类型与亮度综合排序")
                    } footer: {
                        Text("推荐依据当前观测位置、\(viewModel.formattedMoment) 和天体地平高度计算，未包含天气与光污染。")
                    }
                }
            }
            .navigationTitle("今晚可见")
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
