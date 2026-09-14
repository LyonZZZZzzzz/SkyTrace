import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct MacInspectorView: View {
    @Bindable var viewModel: SkyViewModel

    var body: some View {
        Group {
            if let object = viewModel.selectedObject {
                ScrollView {
                    ObjectDetailsContent(
                        object: object,
                        position: viewModel.snapshot.positions.first { $0.id == object.id },
                        compact: true
                    )
                    .padding(18)
                }
            } else {
                overview
            }
        }
        .navigationTitle("检查器")
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("观测概览")
                        .font(.title2.bold())
                    Text(viewModel.formattedMoment)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                infoCard {
                    metricRow("位置", viewModel.observerSubtitle)
                    Divider()
                    metricRow("地平线上", "\(aboveHorizonCount) 个目标")
                    Divider()
                    metricRow("推荐目标", "\(viewModel.snapshot.recommendations.count) 个")
                }

                if let sun = position(for: "sun"), let moon = position(for: "moon") {
                    infoCard {
                        metricRow("太阳", "\(sun.azimuthText) · \(sun.altitudeText)")
                        Divider()
                        metricRow("月球", "\(moon.azimuthText) · \(moon.altitudeText)")
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("今晚可见")
                        .font(.headline)
                    ForEach(viewModel.snapshot.recommendations) { position in
                        Button {
                            viewModel.select(position.object)
                        } label: {
                            TonightRecommendationRow(position: position)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(18)
        }
    }

    private var aboveHorizonCount: Int {
        viewModel.snapshot.positions.filter(\.isAboveHorizon).count
    }

    private func position(for id: String) -> SkyPosition? {
        viewModel.snapshot.positions.first { $0.id == id }
    }

    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }
}
