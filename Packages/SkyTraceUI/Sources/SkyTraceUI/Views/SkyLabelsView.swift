import SkyTraceCore
import SwiftUI

public struct SkyLabelsView: View {
    public let snapshot: SkySnapshot
    public let camera: SkyCameraState
    public let selectedObjectID: String?
    public let density: SkyLabelDensity
    public let showCardinals: Bool

    public init(
        snapshot: SkySnapshot,
        camera: SkyCameraState,
        selectedObjectID: String?,
        density: SkyLabelDensity = .standard,
        showCardinals: Bool = true
    ) {
        self.snapshot = snapshot
        self.camera = camera
        self.selectedObjectID = selectedObjectID
        self.density = density
        self.showCardinals = showCardinals
    }

    public var body: some View {
        GeometryReader { proxy in
            let projection = SkyProjection(camera: camera, size: proxy.size)
            ZStack(alignment: .topLeading) {
                if showCardinals {
                    ForEach(cardinalPoints, id: \.label) { cardinal in
                        if let point = projection.screenPoint(for: cardinal.vector) {
                            CardinalMarker(label: cardinal.label)
                                .position(point)
                        }
                    }
                }

                ForEach(labelCandidates(projection: projection)) { candidate in
                    ObjectLabel(candidate: candidate, selected: candidate.id == selectedObjectID)
                        .position(candidate.point)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var cardinalPoints: [(label: String, vector: Vector3D)] {
        [
            ("北", vector(azimuth: 0, altitude: 0)),
            ("东", vector(azimuth: 90, altitude: 0)),
            ("南", vector(azimuth: 180, altitude: 0)),
            ("西", vector(azimuth: 270, altitude: 0))
        ].map { ($0.0, $0.1) }
    }

    private func labelCandidates(projection: SkyProjection) -> [LabelCandidate] {
        let maximumMagnitude = max(density.magnitudeLimit, camera.fieldOfView < 45 ? density.magnitudeLimit + 0.8 : density.magnitudeLimit)
        return snapshot.positions.compactMap { position in
            let shouldShow: Bool
            switch position.object.kind {
            case .star:
                shouldShow = (position.object.magnitude ?? 99) <= maximumMagnitude
            case .planet, .sun, .moon:
                shouldShow = position.altitude > -10
            case .deepSky:
                shouldShow = (position.object.magnitude ?? 99) <= 5.0 || position.id == selectedObjectID
            case .constellation:
                shouldShow = camera.fieldOfView <= 100
            }
            guard position.id == selectedObjectID || shouldShow else { return nil }
            guard let point = projection.screenPoint(for: position.horizontalVector) else { return nil }
            return LabelCandidate(
                id: position.id,
                text: position.object.name,
                point: point,
                kind: position.object.kind,
                selected: position.id == selectedObjectID
            )
        }
        .sorted { lhs, rhs in
            if lhs.selected != rhs.selected { return lhs.selected }
            return lhs.kind.sortPriority < rhs.kind.sortPriority
        }
        .prefix(100)
        .map { $0 }
    }

    private func vector(azimuth: Double, altitude: Double) -> Vector3D {
        let az = azimuth * .pi / 180
        let alt = altitude * .pi / 180
        let horizontal = cos(alt)
        return Vector3D(x: horizontal * sin(az), y: sin(alt), z: -horizontal * cos(az))
    }
}

private struct LabelCandidate: Identifiable {
    let id: String
    let text: String
    let point: CGPoint
    let kind: CelestialKind
    let selected: Bool
}

private extension CelestialKind {
    var sortPriority: Int {
        switch self {
        case .sun: 0
        case .moon: 1
        case .planet: 2
        case .star: 3
        case .deepSky: 4
        case .constellation: 5
        }
    }
}

private struct ObjectLabel: View {
    let candidate: LabelCandidate
    let selected: Bool

    var body: some View {
        Text(candidate.text)
            .font(selected ? .caption.weight(.bold) : .caption2.weight(.medium))
            .foregroundStyle(selected ? Color.skyOrange : labelColor)
            .padding(.horizontal, selected ? 8 : 5)
            .padding(.vertical, selected ? 4 : 2)
            .background(selected ? Color.black.opacity(0.72) : Color.clear, in: Capsule())
            .overlay {
                if selected {
                    Capsule().stroke(Color.skyOrange.opacity(0.65), lineWidth: 0.8)
                }
            }
    }

    private var labelColor: Color {
        switch candidate.kind {
        case .constellation: .skyCyan.opacity(0.78)
        case .deepSky: .skyMint.opacity(0.85)
        case .planet, .sun, .moon: .white
        case .star: .white.opacity(0.86)
        }
    }
}

private struct CardinalMarker: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.black))
            .foregroundStyle(Color.skyCyan.opacity(0.88))
            .frame(width: 24, height: 24)
            .background(.black.opacity(0.36), in: Circle())
            .overlay(Circle().stroke(Color.skyCyan.opacity(0.35), lineWidth: 0.6))
    }
}
