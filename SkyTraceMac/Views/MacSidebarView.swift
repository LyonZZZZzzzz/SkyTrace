import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacSidebarView: View {
    @Bindable var viewModel: SkyViewModel

    var body: some View {
        List(selection: selection) {
            if !viewModel.favoriteObjects.isEmpty {
                Section("收藏") {
                    ForEach(viewModel.favoriteObjects) { object in
                        objectRow(object)
                            .tag(object.id)
                    }
                }
            }

            Section("今晚观测") {
                ForEach(viewModel.observationPlan?.recommendations ?? []) { visibility in
                    objectRow(visibility.object)
                        .tag(visibility.object.id)
                }
            }

            if !viewModel.astronomyEvents.isEmpty {
                Section("天空事件") {
                    ForEach(viewModel.astronomyEvents.prefix(8).map { $0 }) { event in
                        Button {
                            viewModel.focus(on: event)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(.body.weight(.semibold))
                                Text(event.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !viewModel.observationLogs.isEmpty {
                Section("观测日志") {
                    ForEach(viewModel.observationLogs.prefix(8).map { $0 }) { log in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(log.objectName)
                                .font(.body.weight(.semibold))
                            Text("\(log.observedAt.formatted(date: .abbreviated, time: .shortened)) · \(log.rating) 星")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("太阳系") {
                ForEach(solarSystemObjects) { object in
                    objectRow(object)
                        .tag(object.id)
                }
            }

            Section("亮星") {
                ForEach(brightStars) { object in
                    objectRow(object)
                        .tag(object.id)
                }
            }

            Section("星座") {
                ForEach(constellations) { object in
                    objectRow(object)
                        .tag(object.id)
                }
            }

            Section("梅西耶天体") {
                ForEach(deepSkyObjects) { object in
                    objectRow(object)
                        .tag(object.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("天体目录")
    }

    private var selection: Binding<String?> {
        Binding(
            get: { viewModel.selectedObjectID },
            set: { newValue in
                if let newValue {
                    viewModel.center(on: newValue)
                } else {
                    viewModel.clearSelection()
                }
            }
        )
    }

    private var allObjects: [CelestialObject] {
        viewModel.repository?.allObjects ?? []
    }

    private var solarSystemObjects: [CelestialObject] {
        allObjects.filter { [.sun, .moon, .planet].contains($0.kind) }
    }

    private var brightStars: [CelestialObject] {
        allObjects
            .filter { $0.kind == .star && ($0.magnitude ?? 99) <= 1.5 }
            .sorted { ($0.magnitude ?? 99) < ($1.magnitude ?? 99) }
            .prefix(30)
            .map { $0 }
    }

    private var constellations: [CelestialObject] {
        allObjects
            .filter { $0.kind == .constellation }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var deepSkyObjects: [CelestialObject] {
        allObjects
            .filter { $0.kind == .deepSky }
            .sorted { ($0.magnitude ?? 99) < ($1.magnitude ?? 99) }
    }

    private func objectRow(_ object: CelestialObject) -> some View {
        CelestialObjectRow(object: object)
            .padding(.vertical, 2)
    }
}
