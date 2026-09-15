import SkyTraceCore
import SwiftUI

public struct ObservationLogForm: View {
    public let object: CelestialObject
    public let observer: ObserverContext
    public let existingEntry: ObservationLogEntry?
    public let onSave: (ObservationLogEntry) -> Void
    public let onCancel: () -> Void

    @State private var observedAt: Date
    @State private var rating: Int
    @State private var weather: WeatherCondition
    @State private var equipment: ObservationEquipment
    @State private var notes: String

    public init(
        object: CelestialObject,
        observer: ObserverContext,
        existingEntry: ObservationLogEntry? = nil,
        onSave: @escaping (ObservationLogEntry) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.object = object
        self.observer = observer
        self.existingEntry = existingEntry
        self.onSave = onSave
        self.onCancel = onCancel
        _observedAt = State(initialValue: existingEntry?.observedAt ?? Date())
        _rating = State(initialValue: existingEntry?.rating ?? 4)
        _weather = State(initialValue: existingEntry?.weather ?? .clear)
        _equipment = State(initialValue: existingEntry?.equipment ?? .nakedEye)
        _notes = State(initialValue: existingEntry?.notes ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    LabeledContent("天体", value: object.name)
                    LabeledContent("地点", value: observer.name)
                    DatePicker("观测时间", selection: $observedAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section("观测条件") {
                    Picker("天气", selection: $weather) {
                        ForEach(WeatherCondition.allCases, id: \.self) { condition in
                            Label(condition.localizedName, systemImage: condition.symbolName).tag(condition)
                        }
                    }
                    Picker("设备", selection: $equipment) {
                        ForEach(ObservationEquipment.allCases, id: \.self) { item in
                            Text(item.localizedName).tag(item)
                        }
                    }
                    Stepper(value: $rating, in: 1...5) {
                        HStack {
                            Text("评分")
                            Spacer()
                            Text(String(repeating: "★", count: rating))
                                .foregroundStyle(Color.skyOrange)
                        }
                    }
                }

                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(existingEntry == nil ? "记录观测" : "编辑观测")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(
                            ObservationLogEntry(
                                id: existingEntry?.id ?? UUID(),
                                objectID: object.id,
                                objectName: object.name,
                                observedAt: observedAt,
                                observer: observer,
                                rating: rating,
                                weather: weather,
                                equipment: equipment,
                                notes: notes,
                                createdAt: existingEntry?.createdAt ?? Date(),
                                updatedAt: Date()
                            )
                        )
                    }
                }
            }
        }
    }
}
