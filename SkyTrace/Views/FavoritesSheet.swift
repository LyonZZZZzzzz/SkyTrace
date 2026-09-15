import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct FavoritesSheet: View {
    @Bindable var viewModel: SkyViewModel
    let onSelect: (CelestialObject) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.favoriteObjects.isEmpty {
                    ContentUnavailableView(
                        "还没有收藏",
                        systemImage: "star",
                        description: Text("在搜索、详情或今晚计划中点击星标即可收藏。")
                    )
                } else {
                    List {
                        Section {
                            Toggle(
                                "允许观测提醒",
                                isOn: Binding(
                                    get: { viewModel.favoriteStore.remindersEnabled },
                                    set: { value in
                                        Task { await viewModel.setRemindersEnabled(value) }
                                    }
                                )
                            )
                        } footer: {
                            Text("提醒只在主动开启后请求系统权限，并安排下一次最佳观测时刻。")
                        }

                        Section("收藏目标") {
                            ForEach(viewModel.favoriteObjects) { object in
                                HStack(spacing: 12) {
                                    Button {
                                        onSelect(object)
                                    } label: {
                                        CelestialObjectRow(object: object)
                                    }
                                    .buttonStyle(.plain)

                                    FavoriteButton(
                                        isFavorite: true,
                                        accessibilityLabel: "取消收藏",
                                        action: { viewModel.toggleFavorite(object) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("收藏")
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
