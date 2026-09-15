import SkyTraceCore
import SwiftUI

public struct TonightPlanContent: View {
    public let plan: ObservationPlan?
    public let state: ObservationPlanState
    public let favoriteIDs: Set<String>
    public let onSelect: (CelestialObject) -> Void
    public let onToggleFavorite: (CelestialObject) -> Void

    public init(
        plan: ObservationPlan?,
        state: ObservationPlanState,
        favoriteIDs: Set<String>,
        onSelect: @escaping (CelestialObject) -> Void,
        onToggleFavorite: @escaping (CelestialObject) -> Void
    ) {
        self.plan = plan
        self.state = state
        self.favoriteIDs = favoriteIDs
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
    }

    public var body: some View {
        Group {
            switch state {
            case .idle:
                if let plan {
                    planContent(plan)
                } else {
                    ProgressView("正在计算今晚观测条件…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            case .loading:
                if let plan {
                    planContent(plan)
                } else {
                    ProgressView("正在计算今晚观测条件…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            case .failed(let message):
                ContentUnavailableView("无法生成观测计划", systemImage: "exclamationmark.triangle", description: Text(message))
            default:
                if let plan {
                    planContent(plan)
                } else {
                    ContentUnavailableView("当前没有观测计划", systemImage: "moon.zzz")
                }
            }
        }
    }

    private func planContent(_ plan: ObservationPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                twilightCard(plan)
                moonCard(plan.moon, timeZone: plan.observer.timeZone)

                if let warning = plan.warningMessage {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("推荐目标")
                        .font(.title3.bold())
                    if plan.recommendations.isEmpty {
                        Text("当前没有达到最低高度和持续时间的推荐目标。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(plan.recommendations) { visibility in
                            visibilityRow(visibility, timeZone: plan.observer.timeZone)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func twilightCard(_ plan: ObservationPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("今夜时间线", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Text(plan.night.quality.localizedName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.skyCyan)
            }

            HStack(spacing: 0) {
                timelinePoint("日落", plan.night.sunset, color: .orange, timeZone: plan.observer.timeZone)
                timelineLine()
                timelinePoint("民用暮光", plan.night.civilDusk, color: .orange.opacity(0.7), timeZone: plan.observer.timeZone)
                timelineLine()
                timelinePoint(plan.night.quality == .astronomical ? "天文暗夜" : "有效暗夜", plan.night.effectiveDarkStart, color: .skyCyan, timeZone: plan.observer.timeZone)
                timelineLine()
                timelinePoint("日出", plan.night.sunrise, color: .orange, timeZone: plan.observer.timeZone)
            }

            Divider()

            VStack(spacing: 7) {
                twilightRow("民用暮光", start: plan.night.civilDusk, end: plan.night.civilDawn, timeZone: plan.observer.timeZone)
                twilightRow("航海暮光", start: plan.night.nauticalDusk, end: plan.night.nauticalDawn, timeZone: plan.observer.timeZone)
                twilightRow("天文暗夜", start: plan.night.astronomicalDusk, end: plan.night.astronomicalDawn, timeZone: plan.observer.timeZone)
            }
        }
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }

    private func moonCard(_ moon: MoonObservation, timeZone: TimeZone) -> some View {
        HStack(spacing: 16) {
            Image(systemName: moon.phase.symbolName)
                .font(.system(size: 34))
                .foregroundStyle(Color.skyCyan)
                .frame(width: 56, height: 56)
                .background(Color.skyCyan.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(moon.phase.localizedName)
                    .font(.headline)
                Text(moon.illuminationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let rise = moon.rise, let set = moon.set {
                    Text("月升 \(timeText(rise, timeZone: timeZone)) · 月落 \(timeText(set, timeZone: timeZone))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("当前时段月亮不升或持续可见")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }

    private func visibilityRow(_ visibility: ObservationVisibility, timeZone: TimeZone) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onSelect(visibility.object)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: visibility.object.kind.symbolName)
                            .foregroundStyle(Color.skyCyan)
                        Text(visibility.object.name)
                            .font(.body.weight(.semibold))
                    }
                    Text("最佳 \(timeText(visibility.bestTime, timeZone: timeZone)) · 高度 \(String(format: "%.0f°", visibility.maximumAltitude))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(visibility.reason.localizedText) · 可见 \(visibility.durationText)")
                        .font(.caption)
                        .foregroundStyle(Color.skyMint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            FavoriteButton(
                isFavorite: favoriteIDs.contains(visibility.object.id),
                action: { onToggleFavorite(visibility.object) }
            )
        }
        .padding(12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
    }

    private func twilightRow(_ title: String, start: Date?, end: Date?, timeZone: TimeZone) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(start.map { timeText($0, timeZone: timeZone) } ?? "—")
            Text("→")
                .foregroundStyle(.tertiary)
            Text(end.map { timeText($0, timeZone: timeZone) } ?? "—")
        }
        .font(.caption.monospacedDigit())
    }

    private func timelinePoint(_ title: String, _ date: Date?, color: Color, timeZone: TimeZone) -> some View {
        VStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(date.map { timeText($0, timeZone: timeZone) } ?? "—")
                .font(.caption2.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private func timelineLine() -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 1)
            .offset(y: -18)
    }

    private func timeText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
