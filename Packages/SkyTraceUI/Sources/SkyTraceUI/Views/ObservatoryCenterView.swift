import SkyTraceCore
import SwiftUI

public enum ObservatorySection: String, CaseIterable, Identifiable, Sendable {
    case tonight
    case events
    case logs

    public var id: String { rawValue }
    public var localizedName: String {
        switch self {
        case .tonight: "今晚"
        case .events: "天空事件"
        case .logs: "观测日志"
        }
    }
}

public struct ObservatoryCenterView: View {
    @State private var section: ObservatorySection

    public let plan: ObservationPlan?
    public let planState: ObservationPlanState
    public let favoriteIDs: Set<String>
    public let events: [AstronomyEvent]
    public let eventState: ObservationPlanState
    public let logs: [ObservationLogEntry]
    public let timeZone: TimeZone
    public let onSelectObject: (CelestialObject) -> Void
    public let onToggleFavorite: (CelestialObject) -> Void
    public let onSelectEvent: (AstronomyEvent) -> Void
    public let onDeleteLog: (ObservationLogEntry) -> Void

    public init(
        initialSection: ObservatorySection = .tonight,
        plan: ObservationPlan?,
        planState: ObservationPlanState,
        favoriteIDs: Set<String>,
        events: [AstronomyEvent],
        eventState: ObservationPlanState,
        logs: [ObservationLogEntry],
        timeZone: TimeZone,
        onSelectObject: @escaping (CelestialObject) -> Void,
        onToggleFavorite: @escaping (CelestialObject) -> Void,
        onSelectEvent: @escaping (AstronomyEvent) -> Void,
        onDeleteLog: @escaping (ObservationLogEntry) -> Void
    ) {
        _section = State(initialValue: initialSection)
        self.plan = plan
        self.planState = planState
        self.favoriteIDs = favoriteIDs
        self.events = events
        self.eventState = eventState
        self.logs = logs
        self.timeZone = timeZone
        self.onSelectObject = onSelectObject
        self.onToggleFavorite = onToggleFavorite
        self.onSelectEvent = onSelectEvent
        self.onDeleteLog = onDeleteLog
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("观星中心", selection: $section) {
                ForEach(ObservatorySection.allCases) { item in
                    Text(item.localizedName).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(14)

            Divider()

            switch section {
            case .tonight:
                TonightPlanContent(
                    plan: plan,
                    state: planState,
                    favoriteIDs: favoriteIDs,
                    onSelect: onSelectObject,
                    onToggleFavorite: onToggleFavorite
                )
            case .events:
                eventsContent
            case .logs:
                logsContent
            }
        }
    }

    private var eventsContent: some View {
        Group {
            switch eventState {
            case .loading where events.isEmpty:
                ProgressView("正在计算未来 120 天事件…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView("无法生成天空事件", systemImage: "calendar.badge.exclamationmark", description: Text(message))
            default:
                if events.isEmpty {
                    ContentUnavailableView("未来没有可用事件", systemImage: "calendar")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(events) { event in
                                Button {
                                    onSelectEvent(event)
                                } label: {
                                    eventRow(event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
    }

    private var logsContent: some View {
        Group {
            if logs.isEmpty {
                ContentUnavailableView(
                    "还没有观测记录",
                    systemImage: "book.closed",
                    description: Text("在天体详情中点击“记录观测”，建立你的观测日志。")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(logs) { log in
                            logRow(log)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func eventRow(_ event: AstronomyEvent) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: event.kind.symbolName)
                .font(.title3)
                .foregroundStyle(Color.skyCyan)
                .frame(width: 34, height: 34)
                .background(Color.skyCyan.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(event.title)
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text(dateText(event.date, includeDate: true))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(event.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let altitude = event.altitude {
                    Text("当地高度 \(String(format: "%.0f°", altitude))")
                        .font(.caption2)
                        .foregroundStyle(Color.skyMint)
                }
            }
        }
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
    }

    private func logRow(_ log: ObservationLogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(log.objectName)
                        .font(.body.weight(.semibold))
                    Text(String(repeating: "★", count: log.rating))
                        .font(.caption)
                        .foregroundStyle(Color.skyOrange)
                }
                Text(dateText(log.observedAt, includeDate: true))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(log.weather.localizedName) · \(log.equipment.localizedName)")
                    .font(.caption)
                    .foregroundStyle(Color.skyCyan)
                if !log.notes.isEmpty {
                    Text(log.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer()
            Button(role: .destructive) {
                onDeleteLog(log)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除观测记录")
        }
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
    }

    private func dateText(_ date: Date, includeDate: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = includeDate ? "M月d日 HH:mm" : "HH:mm"
        return formatter.string(from: date)
    }
}
