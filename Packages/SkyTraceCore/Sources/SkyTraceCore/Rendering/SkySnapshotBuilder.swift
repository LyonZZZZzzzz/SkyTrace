import Foundation

/// Pure snapshot construction. It is intentionally independent from the main
/// actor so the same implementation can be called synchronously by tests and
/// by the background worker used during time playback.
public enum SkySnapshotBuilder {
    public static func makeSnapshot(
        objects: [CelestialObject],
        constellations: [ConstellationRecord],
        moment: SkyMoment,
        observer: ObserverContext,
        astronomy: any AstronomyCalculating
    ) -> SkySnapshot {
        SkyTraceDiagnostics.event("SnapshotBuildStarted")
        defer { SkyTraceDiagnostics.event("SnapshotBuildCompleted") }
        let transform = astronomy.horizontalTransform(for: moment, observer: observer)

        var segments: [ConstellationSegment] = []
        var anchorWeightedSums: [String: Vector3D] = [:]
        var anchorWeights: [String: Double] = [:]

        for constellation in constellations {
            for line in constellation.segments {
                guard line.count > 1 else { continue }
                for index in 1..<line.count {
                    let start = line[index - 1]
                    let end = line[index]
                    guard start.count >= 2, end.count >= 2 else { continue }

                    let startHorizontal = transform.horizontal(raDegrees: start[0], decDegrees: start[1])
                    let endHorizontal = transform.horizontal(raDegrees: end[0], decDegrees: end[1])
                    let startVector = vector(
                        azimuth: startHorizontal.azimuth,
                        altitude: startHorizontal.altitude
                    )
                    let endVector = vector(
                        azimuth: endHorizontal.azimuth,
                        altitude: endHorizontal.altitude
                    )
                    segments.append(
                        ConstellationSegment(
                            constellationID: constellation.id,
                            start: startVector,
                            end: endVector
                        )
                    )

                    let segmentLength = (endVector - startVector).length
                    guard segmentLength > 0 else { continue }
                    let midpoint = (startVector + endVector) * 0.5
                    anchorWeightedSums[constellation.id, default: Vector3D(x: 0, y: 0, z: 0)] =
                        anchorWeightedSums[constellation.id, default: Vector3D(x: 0, y: 0, z: 0)] +
                        midpoint * segmentLength
                    anchorWeights[constellation.id, default: 0] += segmentLength
                }
            }
        }

        var positions: [SkyPosition] = []
        positions.reserveCapacity(objects.count)
        for object in objects {
            let coordinate: (azimuth: Double, altitude: Double)

            if
                let constellationID = constellationID(for: object),
                let weightedSum = anchorWeightedSums[constellationID],
                let weight = anchorWeights[constellationID],
                weight > 0
            {
                let anchor = weightedSum.normalized
                coordinate = (
                    azimuth: normalizedDegrees(atan2(anchor.x, -anchor.z) * 180 / .pi),
                    altitude: asin(min(1, max(-1, anchor.y))) * 180 / .pi
                )
            } else {
                coordinate = astronomy.horizontal(
                    object: object,
                    moment: moment,
                    observer: observer,
                    transform: transform
                )
            }

            positions.append(
                SkyPosition(
                    object: object,
                    azimuth: coordinate.azimuth,
                    altitude: coordinate.altitude
                )
            )
        }

        return SkySnapshot(
            observer: observer,
            moment: moment,
            positions: positions,
            constellationSegments: segments,
            recommendations: Array(bestRecommendations(from: positions).prefix(6))
        )
    }

    private static func constellationID(for object: CelestialObject) -> String? {
        guard object.kind == .constellation else { return nil }
        let prefix = "constellation-"
        guard object.id.hasPrefix(prefix) else { return nil }
        return String(object.id.dropFirst(prefix.count))
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }

    private static func vector(azimuth: Double, altitude: Double) -> Vector3D {
        let az = azimuth * .pi / 180
        let alt = altitude * .pi / 180
        let horizontal = cos(alt)
        return Vector3D(
            x: horizontal * sin(az),
            y: sin(alt),
            z: -horizontal * cos(az)
        )
    }

    private static func bestRecommendations(from positions: [SkyPosition]) -> [SkyPosition] {
        positions
            .filter { position in
                guard position.object.kind != .constellation, position.object.kind != .sun else { return false }
                return position.altitude >= 12
            }
            .sorted { recommendationScore($0) > recommendationScore($1) }
    }

    private static func recommendationScore(_ position: SkyPosition) -> Double {
        let priority: Double
        switch position.object.kind {
        case .moon: priority = 65
        case .planet: priority = 60
        case .deepSky: priority = 45
        case .star: priority = 35
        case .constellation: priority = 0
        case .sun: priority = -100
        }
        let magnitudeBonus = max(0, 7 - (position.object.magnitude ?? 7)) * 1.5
        let altitudeBonus = min(position.altitude, 70) * 0.25
        return priority + magnitudeBonus + altitudeBonus
    }
}

/// Serializes expensive snapshot calculations away from the main actor.
public actor SkySnapshotWorker {
    public init() {}

    public func makeSnapshot(
        objects: [CelestialObject],
        constellations: [ConstellationRecord],
        moment: SkyMoment,
        observer: ObserverContext,
        astronomy: any AstronomyCalculating
    ) -> SkySnapshot {
        SkySnapshotBuilder.makeSnapshot(
            objects: objects,
            constellations: constellations,
            moment: moment,
            observer: observer,
            astronomy: astronomy
        )
    }
}
