import SkyTraceCore
import SwiftUI

struct LocationSheet: View {
    @Bindable var viewModel: SkyViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var name = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        viewModel.useCurrentLocation()
                    } label: {
                        Label("使用当前位置", systemImage: "location.fill")
                    }

                    if let error = viewModel.locationErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("定位")
                } footer: {
                    Text("定位仅用于本地天文计算，不会上传或保存到服务器。")
                }

                Section("手动坐标") {
                    TextField("地点名称", text: $name)
                    TextField("纬度（−90…90）", text: $latitudeText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("经度（−180…180）", text: $longitudeText)
                        .keyboardType(.numbersAndPunctuation)

                    Button("应用坐标") {
                        applyCoordinates()
                    }
                    .disabled(latitudeText.isEmpty || longitudeText.isEmpty)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

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
            .navigationTitle("观测位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
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
