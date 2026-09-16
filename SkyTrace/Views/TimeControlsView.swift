import SkyTraceCore
import SwiftUI

struct TimeControlsView: View {
    @Bindable var viewModel: SkyViewModel
    @State private var showDatePicker = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                timeButton(symbol: "gobackward.10", label: "后退一天") {
                    viewModel.shiftTime(by: -86_400)
                }
                timeButton(symbol: "minus", label: "后退一小时") {
                    viewModel.shiftTime(by: -3_600)
                }

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 48, height: 40)
                        .foregroundStyle(Color.skyBackground)
                        .background(Color.skyCyan, in: Capsule())
                }
                .accessibilityLabel(viewModel.isPlaying ? "暂停时间" : "播放时间")

                timeButton(symbol: "plus", label: "前进一小时") {
                    viewModel.shiftTime(by: 3_600)
                }
                timeButton(symbol: "goforward.10", label: "前进一天") {
                    viewModel.shiftTime(by: 86_400)
                }
            }

            HStack(spacing: 12) {
                Button("现在") {
                    viewModel.resetToNow()
                }
                .font(.caption.weight(.semibold))

                Button {
                    showDatePicker = true
                } label: {
                    Label("日期", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                }

                Menu {
                    Button("1 秒/秒") { viewModel.playbackDaysPerSecond = SkyViewModel.realTimePlaybackDaysPerSecond }
                    Button("1 分钟/秒") { viewModel.playbackDaysPerSecond = 1.0 / 1440 }
                    Button("1 小时/秒") { viewModel.playbackDaysPerSecond = 1.0 / 24 }
                    Button("1 天/秒") { viewModel.playbackDaysPerSecond = 1 }
                } label: {
                    Label(playbackLabel, systemImage: "speedometer")
                        .font(.caption.weight(.semibold))
                }

                Spacer()

                Text(String(format: "视场 %.0f°", viewModel.fieldOfView))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(12)
        .skyPanel(cornerRadius: 18)
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker(
                    "观测日期与时间",
                    selection: Binding(
                        get: { viewModel.moment.date },
                        set: { viewModel.setDate($0) }
                    ),
                    in: viewModel.dateRange,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("时间旅行")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showDatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var playbackLabel: String {
        if viewModel.playbackDaysPerSecond >= 1 { return "1 天/秒" }
        if viewModel.playbackDaysPerSecond >= 1.0 / 24 { return "1 小时/秒" }
        if viewModel.playbackDaysPerSecond >= 1.0 / 1440 { return "1 分钟/秒" }
        return "1 秒/秒"
    }

    private func timeButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
