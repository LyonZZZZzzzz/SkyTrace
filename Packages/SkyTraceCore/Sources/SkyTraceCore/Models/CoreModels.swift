import Foundation
import simd

public struct Vector3D: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var length: Double {
        sqrt(x * x + y * y + z * z)
    }

    public var normalized: Vector3D {
        let magnitude = max(length, .leastNonzeroMagnitude)
        return Vector3D(x: x / magnitude, y: y / magnitude, z: z / magnitude)
    }

    public static func dot(_ lhs: Vector3D, _ rhs: Vector3D) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    public static func cross(_ lhs: Vector3D, _ rhs: Vector3D) -> Vector3D {
        Vector3D(
            x: lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.z * rhs.x - lhs.x * rhs.z,
            z: lhs.x * rhs.y - lhs.y * rhs.x
        )
    }

    public static func * (lhs: Vector3D, rhs: Double) -> Vector3D {
        Vector3D(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    public static func + (lhs: Vector3D, rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3D, rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }
}

public struct ObserverContext: Codable, Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var timeZoneIdentifier: String

    public init(name: String, latitude: Double, longitude: Double, altitude: Double, timeZoneIdentifier: String) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public static let shanghai = ObserverContext(
        name: "上海",
        latitude: 31.2304,
        longitude: 121.4737,
        altitude: 4,
        timeZoneIdentifier: "Asia/Shanghai"
    )

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}

public struct SkyMoment: Equatable, Sendable {
    public var date: Date

    public init(date: Date) {
        self.date = date
    }

    public static var now: SkyMoment {
        SkyMoment(date: Date())
    }
}

public enum CelestialKind: String, Codable, CaseIterable, Sendable {
    case star
    case constellation
    case deepSky
    case planet
    case sun
    case moon

    public var localizedName: String {
        switch self {
        case .star: "恒星"
        case .constellation: "星座"
        case .deepSky: "深空天体"
        case .planet: "行星"
        case .sun: "太阳"
        case .moon: "月球"
        }
    }

    public var symbolName: String {
        switch self {
        case .star: "sparkle"
        case .constellation: "point.3.connected.trianglepath.dotted"
        case .deepSky: "circle.dotted"
        case .planet: "globe.asia.australia.fill"
        case .sun: "sun.max.fill"
        case .moon: "moon.fill"
        }
    }
}

public struct CelestialObject: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let englishName: String
    public let designation: String
    public let kind: CelestialKind
    public let raDegrees: Double
    public let decDegrees: Double
    public let magnitude: Double?
    public let bvColorIndex: Double?
    public let detail: String
    public let aliases: [String]

    public init(
        id: String,
        name: String,
        englishName: String,
        designation: String,
        kind: CelestialKind,
        raDegrees: Double,
        decDegrees: Double,
        magnitude: Double?,
        bvColorIndex: Double?,
        detail: String,
        aliases: [String]
    ) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.designation = designation
        self.kind = kind
        self.raDegrees = raDegrees
        self.decDegrees = decDegrees
        self.magnitude = magnitude
        self.bvColorIndex = bvColorIndex
        self.detail = detail
        self.aliases = aliases
    }

    public var subtitle: String {
        if !designation.isEmpty, designation != name {
            return "\(kind.localizedName) · \(designation)"
        }
        return kind.localizedName
    }
}

public struct SkyPosition: Identifiable, Hashable, Sendable {
    public let object: CelestialObject
    public let azimuth: Double
    public let altitude: Double

    public init(object: CelestialObject, azimuth: Double, altitude: Double) {
        self.object = object
        self.azimuth = azimuth
        self.altitude = altitude
    }

    public var id: String { object.id }
    public var isAboveHorizon: Bool { altitude >= 0 }
    public var altitudeText: String { String(format: "%.1f°", altitude) }
    public var azimuthText: String { Self.compassDirection(for: azimuth) }

    public var horizontalVector: Vector3D {
        let azimuthRadians = azimuth * .pi / 180
        let altitudeRadians = altitude * .pi / 180
        let horizontal = cos(altitudeRadians)
        return Vector3D(
            x: horizontal * sin(azimuthRadians),
            y: sin(altitudeRadians),
            z: -horizontal * cos(azimuthRadians)
        )
    }

    public static func compassDirection(for azimuth: Double) -> String {
        let directions = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let normalized = (azimuth.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45) % directions.count
        return directions[index]
    }
}

public struct ConstellationSegment: Hashable, Sendable {
    public let constellationID: String
    public let start: Vector3D
    public let end: Vector3D

    public init(constellationID: String, start: Vector3D, end: Vector3D) {
        self.constellationID = constellationID
        self.start = start
        self.end = end
    }
}

public struct SkySnapshot: Equatable, Sendable {
    public let observer: ObserverContext
    public let moment: SkyMoment
    public let positions: [SkyPosition]
    public let constellationSegments: [ConstellationSegment]
    public let recommendations: [SkyPosition]

    public init(
        observer: ObserverContext,
        moment: SkyMoment,
        positions: [SkyPosition],
        constellationSegments: [ConstellationSegment],
        recommendations: [SkyPosition]
    ) {
        self.observer = observer
        self.moment = moment
        self.positions = positions
        self.constellationSegments = constellationSegments
        self.recommendations = recommendations
    }

    public static let empty = SkySnapshot(
        observer: .shanghai,
        moment: .now,
        positions: [],
        constellationSegments: [],
        recommendations: []
    )
}

public struct TonightRecommendation: Identifiable, Hashable, Sendable {
    public let object: CelestialObject
    public let altitude: Double
    public let azimuth: Double
    public let score: Double

    public init(object: CelestialObject, altitude: Double, azimuth: Double, score: Double) {
        self.object = object
        self.altitude = altitude
        self.azimuth = azimuth
        self.score = score
    }

    public var id: String { object.id }
}

public enum SelectionState: Equatable, Sendable {
    case none
    case selected(String)
    case focused(String)
}

public struct City: Codable, Identifiable, Hashable, Sendable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let timeZone: String

    public init(name: String, latitude: Double, longitude: Double, timeZone: String) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
    }

    public var id: String { "\(name)-\(latitude)-\(longitude)" }
    public var observer: ObserverContext {
        ObserverContext(
            name: name,
            latitude: latitude,
            longitude: longitude,
            altitude: 0,
            timeZoneIdentifier: timeZone
        )
    }
}

public struct SkyCameraBasis: Equatable, Sendable {
    public let forward: Vector3D
    public let right: Vector3D
    public let up: Vector3D

    public init(forward: Vector3D, right: Vector3D, up: Vector3D) {
        self.forward = forward.normalized
        self.right = right.normalized
        self.up = up.normalized
    }

    public init(camera: SkyCameraState) {
        let forward = camera.direction.normalized
        let azimuth = camera.azimuth * .pi / 180
        let basisRight = Vector3D(
            x: cos(azimuth),
            y: 0,
            z: sin(azimuth)
        ).normalized
        let basisUp = Vector3D.cross(basisRight, forward).normalized
        let roll = camera.roll * .pi / 180
        let right = (basisRight * cos(roll) + basisUp * sin(roll)).normalized
        let up = (basisUp * cos(roll) - basisRight * sin(roll)).normalized
        self.init(forward: forward, right: right, up: up)
    }

    public init(orientation: simd_quatf) {
        let quaternion = simd_normalize(orientation)
        let forward = quaternion.act(SIMD3<Float>(0, 0, -1))
        let right = quaternion.act(SIMD3<Float>(1, 0, 0))
        let up = quaternion.act(SIMD3<Float>(0, 1, 0))
        self.init(
            forward: Vector3D(x: Double(forward.x), y: Double(forward.y), z: Double(forward.z)),
            right: Vector3D(x: Double(right.x), y: Double(right.y), z: Double(right.z)),
            up: Vector3D(x: Double(up.x), y: Double(up.y), z: Double(up.z))
        )
    }

    public var orientationQuaternion: simd_quatf {
        simd_normalize(simd_quatf(orientationMatrix))
    }

    public var orientationMatrix: simd_float3x3 {
        simd_float3x3(columns: (
            SIMD3<Float>(Float(right.x), Float(right.y), Float(right.z)),
            SIMD3<Float>(Float(up.x), Float(up.y), Float(up.z)),
            SIMD3<Float>(Float(-forward.x), Float(-forward.y), Float(-forward.z))
        ))
    }
}

public struct SkyCameraState: Equatable, Sendable {
    public var azimuth: Double
    public var altitude: Double
    public var roll: Double
    public var fieldOfView: Double

    public init(azimuth: Double = 0, altitude: Double = 35, roll: Double = 0, fieldOfView: Double = 70) {
        self.azimuth = azimuth
        self.altitude = altitude
        self.roll = roll
        self.fieldOfView = fieldOfView
    }

    public init(basis: SkyCameraBasis, fieldOfView: Double) {
        let forward = basis.forward.normalized
        let altitude = asin(min(1, max(-1, forward.y))) * 180 / .pi
        let azimuth: Double
        if abs(forward.x) < 0.000_000_1, abs(forward.z) < 0.000_000_1 {
            azimuth = 0
        } else {
            azimuth = Self.normalizedDegrees(atan2(forward.x, -forward.z) * 180 / .pi)
        }

        let azimuthRadians = azimuth * .pi / 180
        let canonicalRight = Vector3D(
            x: cos(azimuthRadians),
            y: 0,
            z: sin(azimuthRadians)
        ).normalized
        let canonicalUp = Vector3D.cross(canonicalRight, forward).normalized
        let roll = atan2(
            Vector3D.dot(basis.right, canonicalUp),
            Vector3D.dot(basis.right, canonicalRight)
        ) * 180 / .pi

        self.init(
            azimuth: azimuth,
            altitude: altitude,
            roll: Self.normalizedDegrees(roll),
            fieldOfView: fieldOfView
        )
    }

    public static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }

    public var basis: SkyCameraBasis {
        SkyCameraBasis(camera: self)
    }

    public var direction: Vector3D {
        let azimuthRadians = azimuth * .pi / 180
        let altitudeRadians = altitude * .pi / 180
        let horizontal = cos(altitudeRadians)
        return Vector3D(
            x: horizontal * sin(azimuthRadians),
            y: sin(altitudeRadians),
            z: -horizontal * cos(azimuthRadians)
        )
    }
}
