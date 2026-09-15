import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacSettingsView: View {
    @Bindable var viewModel: SkyViewModel
    @Bindable var uiState: MacUIState

    var body: some View {
        TabView {
            Form {
                Toggle("显示星座线", isOn: $uiState.showConstellations)
                Toggle("显示方位标记", isOn: $uiState.showCardinals)

                Picker("标签密度", selection: $uiState.labelDensity) {
                    ForEach(SkyLabelDensity.allCases, id: \.self) { density in
                        Text(density.localizedName).tag(density)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("星点大小")
                    Slider(value: $uiState.starScale, in: 0.6...1.6, step: 0.1)
                    Text(String(format: "%.1f×", uiState.starScale))
                        .font(.caption.monospacedDigit())
                        .frame(width: 42, alignment: .trailing)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("显示", systemImage: "sparkles") }

            Form {
                Section("观测提醒") {
                    Toggle(
                        "允许观测提醒",
                        isOn: Binding(
                            get: { viewModel.favoriteStore.remindersEnabled },
                            set: { value in
                                Task { await viewModel.setRemindersEnabled(value) }
                            }
                        )
                    )
                    Text("首次开启时才会请求系统权限；提醒只调度下一次最佳观测时刻。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("观测位置、时间与相机状态会随主窗口自动恢复。")
                    Text("Mac 与 iPhone 的设置彼此独立，不会上传到服务器。")
                }
                Section {
                    Button("恢复默认显示设置") {
                        uiState.resetDisplaySettings()
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 46))
                    .foregroundStyle(Color.skyCyan)
                Text("星迹 SkyTrace")
                    .font(.title2.bold())
                Text("离线星图观测台 · macOS")
                    .foregroundStyle(.secondary)
                Text("天文计算：Astronomy Engine（MIT）\n星表：Yale Bright Star Catalogue\n星座线：D3-Celestial（BSD-3-Clause）")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 360)
    }
}
