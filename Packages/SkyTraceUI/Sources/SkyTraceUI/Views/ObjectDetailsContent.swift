import SkyTraceCore
import SwiftUI

public struct ObjectDetailsContent: View {
    public let object: CelestialObject
    public let position: SkyPosition?
    public var compact: Bool

    public init(object: CelestialObject, position: SkyPosition?, compact: Bool = false) {
        self.object = object
        self.position = position
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: object.kind.symbolName)
                    .font(.system(size: compact ? 23 : 30, weight: .semibold))
                    .foregroundStyle(Color.skyCyan)
                    .frame(width: compact ? 48 : 62, height: compact ? 48 : 62)
                    .background(Color.skyCyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 5) {
                    Text(object.name)
                        .font(compact ? .title2.bold() : .largeTitle.bold())
                    Text(object.englishName.isEmpty ? object.kind.localizedName : object.englishName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if object.kind == .sun {
                Label("不要用肉眼或光学设备直视太阳。", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(12)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            }

            Text(object.detail)
                .font(.body)
                .lineSpacing(5)

            VStack(spacing: 0) {
                detailRow("类型", object.kind.localizedName)
                Divider()
                detailRow("目录编号", object.designation.isEmpty ? "—" : object.designation)
                Divider()
                detailRow("视星等", object.magnitude.map { String(format: "%.2f", $0) } ?? "—")
                Divider()
                detailRow("当前方位", position?.azimuthText ?? "—")
                Divider()
                detailRow("当前高度", position?.altitudeText ?? "—")
                if object.kind != .sun, object.kind != .moon, object.kind != .planet {
                    Divider()
                    detailRow("赤经", String(format: "%.2f°", object.raDegrees))
                    Divider()
                    detailRow("赤纬", String(format: "%+.2f°", object.decDegrees))
                }
            }
            .padding(.horizontal, 14)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }
}
