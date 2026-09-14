import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacTimelineView: View {
    @Bindable var viewModel: SkyViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    viewModel.shiftTime(by: -86_400)
                } label: {
                    Image(systemName: "gobackward.10")
                }
                .help("后退一天")

                Button {
                    viewModel.shiftTime(by: -3_600)
                } label: {
                    Image(systemName: "minus")
                }
                .help("后退一小时")

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.skyCyan)
                .help(viewModel.isPlaying ? "暂停时间" : "播放时间")

                Button {
                    viewModel.shiftTime(by: 3_600)
                } label: {
                    Image(systemName: "plus")
                }
                .help("前进一小时")

                Button {
                    viewModel.shiftTime(by: 86_400)
                } label: {
                    Image(systemName: "goforward.10")
                }
                .help("前进一天")

                Button("现在") {
                    viewModel.resetToNow()
                }

                DatePicker(
                    "时间",
                    selection: Binding(
                        get: { viewModel.moment.date },
                        set: { viewModel.setDate($0) }
                    ),
                    in: viewModel.dateRange,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .frame(maxWidth: 210)

                Menu {
                    Button("1 分钟/秒") { viewModel.playbackDaysPerSecond = 1.0 / 1440 }
                    Button("1 小时/秒") { viewModel.playbackDaysPerSecond = 1.0 / 24 }
                    Button("1 天/秒") { viewModel.playbackDaysPerSecond = 1 }
                } label: {
                    Label(playbackLabel, systemImage: "speedometer")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Slider(
                value: Binding(
                    get: { viewModel.moment.date.timeIntervalSince1970 },
                    set: { viewModel.setDate(Date(timeIntervalSince1970: $0)) }
                ),
                in: viewModel.dateRange.lowerBound.timeIntervalSince1970...viewModel.dateRange.upperBound.timeIntervalSince1970
            )
            .tint(.skyCyan)
        }
        .padding(12)
        .skyPanel(cornerRadius: 18)
    }

    private var playbackLabel: String {
        if viewModel.playbackDaysPerSecond >= 1 { return "1 天/秒" }
        if viewModel.playbackDaysPerSecond >= 1.0 / 24 { return "1 小时/秒" }
        return "1 分钟/秒"
    }
}
