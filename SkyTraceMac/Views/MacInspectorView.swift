import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacInspectorView: View {
    @Bindable var viewModel: SkyViewModel

    var body: some View {
        Group {
            if let object = viewModel.selectedObject {
                ScrollView {
                    ObjectDetailsContent(
                        object: object,
                        position: viewModel.snapshot.positions.first { $0.id == object.id },
                        compact: true,
                        visibility: viewModel.visibility(for: object.id),
                        timeZone: viewModel.observer.timeZone,
                        isFavorite: viewModel.isFavorite(object.id),
                        isReminderEnabled: viewModel.isReminderEnabled(object.id),
                        onToggleFavorite: { viewModel.toggleFavorite(object) },
                        onToggleReminder: {
                            Task { await viewModel.toggleReminder(for: object) }
                        }
                    )
                    .padding(18)
                }
            } else {
                overview
            }
        }
        .navigationTitle("检查器")
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("观测概览")
                        .font(.title2.bold())
                    Text(viewModel.formattedMoment)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                infoCard {
                    metricRow("位置", viewModel.observerSubtitle)
                    Divider()
                    metricRow("地平线上", "\(aboveHorizonCount) 个目标")
                    Divider()
                    metricRow("推荐目标", "\(viewModel.snapshot.recommendations.count) 个")
                }

                if let plan = viewModel.observationPlan {
                    infoCard {
                        metricRow("有效暗夜", plan.night.effectiveDarkStart.map { timeText($0) } ?? "—")
                        Divider()
                        metricRow("暗夜结束", plan.night.effectiveDarkEnd.map { timeText($0) } ?? "—")
                        Divider()
                        metricRow("月相", "\(plan.moon.phase.localizedName) · \(plan.moon.illuminationText)")
                    }
                } else if case .loading = viewModel.observationPlanState {
                    ProgressView("正在计算今晚观测计划…")
                        .frame(maxWidth: .infinity)
                        .padding(18)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("今晚推荐")
                        .font(.headline)
                    ForEach(viewModel.observationPlan?.recommendations.prefix(5).map { $0 } ?? []) { visibility in
                        Button {
                            viewModel.select(visibility.object)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(visibility.object.name)
                                    .font(.body.weight(.semibold))
                                Text("\(timeText(visibility.bestTime)) · 高度 \(String(format: "%.0f°", visibility.maximumAltitude)) · \(visibility.durationText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(18)
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = viewModel.observer.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var aboveHorizonCount: Int {
        viewModel.snapshot.positions.filter(\.isAboveHorizon).count
    }

    private func position(for id: String) -> SkyPosition? {
        viewModel.snapshot.positions.first { $0.id == id }
    }

    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }
}
