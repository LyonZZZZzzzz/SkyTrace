import SkyTraceCore
import SwiftUI

public struct CelestialObjectRow: View {
    public let object: CelestialObject
    public var showsMagnitude: Bool

    public init(object: CelestialObject, showsMagnitude: Bool = true) {
        self.object = object
        self.showsMagnitude = showsMagnitude
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: object.kind.symbolName)
                .foregroundStyle(object.kind == .sun ? Color.skyOrange : Color.skyCyan)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(object.name)
                    .font(.body.weight(.semibold))
                Text(object.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsMagnitude, let magnitude = object.magnitude {
                Text(String(format: "%.1f 等", magnitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

public struct TonightRecommendationRow: View {
    public let position: SkyPosition

    public init(position: SkyPosition) {
        self.position = position
    }

    public var body: some View {
        HStack(spacing: 13) {
            Image(systemName: position.object.kind.symbolName)
                .font(.title3)
                .foregroundStyle(Color.skyCyan)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(position.object.name)
                    .font(.body.weight(.semibold))
                Text("\(position.azimuthText) · 高度 \(position.altitudeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let magnitude = position.object.magnitude {
                Text(String(format: "%.1f 等", magnitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
