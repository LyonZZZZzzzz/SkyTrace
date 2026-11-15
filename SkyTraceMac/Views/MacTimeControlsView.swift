import SkyTraceCore
import SwiftUI

struct MacTimeControlsView: View {
    @Bindable var viewModel: SkyViewModel

    var body: some View {
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
            .accessibilityIdentifier("time.now")

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
            .environment(\.timeZone, viewModel.observer.timeZone)
            .accessibilityIdentifier("time.datePicker")
            .frame(maxWidth: 240)

            Spacer(minLength: 0)
        }
        .padding(12)
        .skyPanel(cornerRadius: 18)
    }
}
