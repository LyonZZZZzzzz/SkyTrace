import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacSidebarView: View {
    @Bindable var viewModel: SkyViewModel

    var body: some View {
        List(selection: selection) {
            Section("今晚可见") {
                ForEach(viewModel.snapshot.recommendations) { position in
                    objectRow(position.object)
                        .tag(position.object.id)
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
