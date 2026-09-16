import Foundation

/// Immutable render data prepared once from the bundled catalog.
///
/// The expensive work (equatorial direction calculation and constellation
/// anchor calculation) happens here, while the SceneKit hot path only applies
/// one rotation to the whole static root and updates a handful of solar-system
/// nodes.
public struct SkySceneCatalog: Sendable {
    public let objects: [CelestialObject]
    public let staticObjects: [CelestialObject]
    public let constellationObjects: [CelestialObject]
    public let solarSystemObjects: [CelestialObject]
    public let starsByMagnitude: [CelestialObject]
    public let deepSkyByMagnitude: [CelestialObject]
    public let segments: [ConstellationSegment]
    public let directionsJ2000: [String: Vector3D]
    public let constellationAnchorsJ2000: [String: Vector3D]

    public init(objects: [CelestialObject], constellations: [ConstellationRecord]) {
        self.objects = objects
        self.staticObjects = objects.filter { $0.kind == .star || $0.kind == .deepSky }
        self.constellationObjects = objects.filter { $0.kind == .constellation }
        self.solarSystemObjects = objects.filter {
            $0.kind == .sun || $0.kind == .moon || $0.kind == .planet
        }
        self.starsByMagnitude = objects
            .filter { $0.kind == .star }
            .sorted { ($0.magnitude ?? 99) < ($1.magnitude ?? 99) }
        self.deepSkyByMagnitude = objects
            .filter { $0.kind == .deepSky }
            .sorted { ($0.magnitude ?? 99) < ($1.magnitude ?? 99) }

        var directions: [String: Vector3D] = [:]
        for object in self.staticObjects {
            directions[object.id] = Self.direction(raDegrees: object.raDegrees, decDegrees: object.decDegrees)
        }

        var segmentList: [ConstellationSegment] = []
        var weightedSums: [String: Vector3D] = [:]
        var weights: [String: Double] = [:]

        for constellation in constellations {
            for line in constellation.segments {
                guard line.count > 1 else { continue }
                for index in 1..<line.count {
                    let startPoint = line[index - 1]
                    let endPoint = line[index]
                    guard startPoint.count >= 2, endPoint.count >= 2 else { continue }

                    let start = Self.direction(raDegrees: startPoint[0], decDegrees: startPoint[1])
                    let end = Self.direction(raDegrees: endPoint[0], decDegrees: endPoint[1])
                    segmentList.append(
                        ConstellationSegment(
                            constellationID: constellation.id,
                            start: start,
                            end: end
                        )
                    )

                    let length = (end - start).length
                    guard length > 0 else { continue }
                    weightedSums[constellation.id, default: Vector3D(x: 0, y: 0, z: 0)] =
                        weightedSums[constellation.id, default: Vector3D(x: 0, y: 0, z: 0)] +
                        (start + end) * (length * 0.5)
                    weights[constellation.id, default: 0] += length
                }
            }
        }

        var anchors: [String: Vector3D] = [:]
        for constellation in constellations {
            let objectID = "constellation-\(constellation.id)"
            if let sum = weightedSums[constellation.id], let weight = weights[constellation.id], weight > 0 {
                anchors[objectID] = sum.normalized
            } else if let center = constellation.center {
                anchors[objectID] = Self.direction(raDegrees: center.ra, decDegrees: center.dec)
            }
        }

        for object in self.constellationObjects {
            directions[object.id] = anchors[object.id] ??
                Self.direction(raDegrees: object.raDegrees, decDegrees: object.decDegrees)
        }

        self.segments = segmentList
        self.directionsJ2000 = directions
        self.constellationAnchorsJ2000 = anchors
    }

    public func directionJ2000(for objectID: String) -> Vector3D? {
        directionsJ2000[objectID]
    }

    public func directionJ2000(for object: CelestialObject) -> Vector3D? {
        directionsJ2000[object.id] ??
            Self.direction(raDegrees: object.raDegrees, decDegrees: object.decDegrees)
    }

    public static func direction(raDegrees: Double, decDegrees: Double) -> Vector3D {
        let ra = raDegrees * .pi / 180
        let dec = decDegrees * .pi / 180
        let horizontal = cos(dec)
        return Vector3D(
            x: horizontal * cos(ra),
            y: horizontal * sin(ra),
            z: sin(dec)
        ).normalized
    }
}
