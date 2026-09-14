import SkyTraceCore
import SwiftUI

struct MacLocationSheet: View {
    @Bindable var viewModel: SkyViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var name = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section("当前定位") {
                        Button("使用本机位置", systemImage: "location.fill") {
                            viewModel.useCurrentLocation()
                        }
                        if let error = viewModel.locationErrorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Section("手动坐标") {
                        TextField("地点名称", text: $name)
                        TextField("纬度（−90…90）", text: $latitudeText)
                        TextField("经度（−180…180）", text: $longitudeText)
                        Button("应用坐标") { applyCoordinates() }
                            .disabled(latitudeText.isEmpty || longitudeText.isEmpty)
                        if let validationMessage {
                            Text(validationMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(width: 330)

                Divider()

                List {
                    Section("主要城市") {
                        ForEach(viewModel.repository?.cities ?? []) { city in
                            Button {
                                viewModel.setObserver(city.observer)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(city.name)
                                    Spacer()
                                    Text(String(format: "%.1f°, %.1f°", city.latitude, city.longitude))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 300)
            }
            .navigationTitle("观测位置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .frame(minWidth: 660, minHeight: 520)
        .onAppear {
            name = viewModel.observer.name
            latitudeText = String(format: "%.4f", viewModel.observer.latitude)
            longitudeText = String(format: "%.4f", viewModel.observer.longitude)
        }
    }

    private func applyCoordinates() {
        guard
            let latitude = Double(latitudeText.replacingOccurrences(of: "，", with: ".")),
            let longitude = Double(longitudeText.replacingOccurrences(of: "，", with: "."))
        else {
            validationMessage = "请输入有效数字。"
            return
        }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            validationMessage = "纬度需在 ±90°、经度需在 ±180° 范围内。"
            return
        }
        viewModel.setObserver(
            ObserverContext(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "自定义位置" : name,
                latitude: latitude,
                longitude: longitude,
                altitude: 0,
                timeZoneIdentifier: viewModel.observer.timeZoneIdentifier
            )
        )
        dismiss()
    }
}
