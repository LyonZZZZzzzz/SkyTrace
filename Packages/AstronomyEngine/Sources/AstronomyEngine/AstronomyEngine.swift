import CAstronomyEngine
import Foundation

public enum AstronomyBody: Int, CaseIterable, Sendable {
    case mercury = 0
    case venus = 1
    case earth = 2
    case mars = 3
    case jupiter = 4
    case saturn = 5
    case uranus = 6
    case neptune = 7
    case pluto = 8
    case sun = 9
    case moon = 10

    fileprivate var cValue: astro_body_t {
        switch self {
        case .mercury: BODY_MERCURY
        case .venus: BODY_VENUS
        case .earth: BODY_EARTH
        case .mars: BODY_MARS
        case .jupiter: BODY_JUPITER
        case .saturn: BODY_SATURN
        case .uranus: BODY_URANUS
        case .neptune: BODY_NEPTUNE
        case .pluto: BODY_PLUTO
        case .sun: BODY_SUN
        case .moon: BODY_MOON
        }
    }
}

public struct AstronomyHorizontalCoordinate: Equatable, Sendable {
    public let azimuth: Double
    public let altitude: Double
    public let raHours: Double
    public let decDegrees: Double

    public init(azimuth: Double, altitude: Double, raHours: Double, decDegrees: Double) {
        self.azimuth = azimuth
        self.altitude = altitude
        self.raHours = raHours
        self.decDegrees = decDegrees
    }
}

public struct AstronomyEquatorialCoordinate: Equatable, Sendable {
    public let raHours: Double
    public let decDegrees: Double
    public let distanceAU: Double
}

/// A reusable J2000-to-horizontal matrix. Build it once per time/location update,
/// then transform thousands of catalog stars without repeated ephemeris work.
public struct HorizontalTransform: Sendable {
    private let matrix: [Double]

    fileprivate init(matrix: [Double]) {
        self.matrix = matrix
    }

    public func horizontal(raDegrees: Double, decDegrees: Double) -> AstronomyHorizontalCoordinate {
        let ra = raDegrees * .pi / 180
        let dec = decDegrees * .pi / 180
        let x = cos(dec) * cos(ra)
        let y = cos(dec) * sin(ra)
        let z = sin(dec)
        let hx = matrix[0] * x + matrix[1] * y + matrix[2] * z
        let hy = matrix[3] * x + matrix[4] * y + matrix[5] * z
        let hz = matrix[6] * x + matrix[7] * y + matrix[8] * z
        let horizontal = AstronomyEngine.vectorToHorizontal(x: hx, y: hy, z: hz)
        return AstronomyHorizontalCoordinate(
            azimuth: AstronomyEngine.normalizedDegrees(horizontal.azimuth),
            altitude: horizontal.altitude,
            raHours: raDegrees / 15,
            decDegrees: decDegrees
        )
    }
}

public enum AstronomyEngine {
    public static func horizontalTransform(
        date: Date,
        latitude: Double,
        longitude: Double,
        height: Double = 0
    ) -> HorizontalTransform {
        var time = makeTime(date)
        let observer = Astronomy_MakeObserver(latitude, longitude, height)
        let rotation = Astronomy_Rotation_EQJ_HOR(&time, observer)
        let matrix = [
            rotation.rot.0.0, rotation.rot.0.1, rotation.rot.0.2,
            rotation.rot.1.0, rotation.rot.1.1, rotation.rot.1.2,
            rotation.rot.2.0, rotation.rot.2.1, rotation.rot.2.2
        ]
        return HorizontalTransform(matrix: matrix)
    }

    public static func horizontal(
        body: AstronomyBody,
        date: Date,
        latitude: Double,
        longitude: Double,
        height: Double = 0,
        refraction: Bool = true
    ) -> AstronomyHorizontalCoordinate {
        var time = makeTime(date)
        let observer = Astronomy_MakeObserver(latitude, longitude, height)
        let equatorial = Astronomy_Equator(
            body.cValue,
            &time,
            observer,
            EQUATOR_OF_DATE,
            ABERRATION
        )
        let horizon = Astronomy_Horizon(
            &time,
            observer,
            equatorial.ra,
            equatorial.dec,
            refraction ? REFRACTION_NORMAL : REFRACTION_NONE
        )
        return AstronomyHorizontalCoordinate(
            azimuth: normalizedDegrees(horizon.azimuth),
            altitude: horizon.altitude,
            raHours: equatorial.ra,
            decDegrees: equatorial.dec
        )
    }

    public static func equatorial(body: AstronomyBody, date: Date) -> AstronomyEquatorialCoordinate {
        var time = makeTime(date)
        let observer = Astronomy_MakeObserver(0, 0, 0)
        let equatorial = Astronomy_Equator(body.cValue, &time, observer, EQUATOR_OF_DATE, ABERRATION)
        return AstronomyEquatorialCoordinate(
            raHours: equatorial.ra,
            decDegrees: equatorial.dec,
            distanceAU: equatorial.dist
        )
    }

    public static func moonPhase(date: Date) -> Double {
        let time = makeTime(date)
        return Astronomy_MoonPhase(time).angle
    }

    private static func makeTime(_ date: Date) -> astro_time_t {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        let seconds = Double(components.second ?? 0) + Double(components.nanosecond ?? 0) / 1_000_000_000
        return Astronomy_MakeTime(
            Int32(components.year ?? 2000),
            Int32(components.month ?? 1),
            Int32(components.day ?? 1),
            Int32(components.hour ?? 0),
            Int32(components.minute ?? 0),
            seconds
        )
    }

    fileprivate static func vectorToHorizontal(
        x: Double,
        y: Double,
        z: Double
    ) -> (azimuth: Double, altitude: Double) {
        let time = Astronomy_MakeTime(2000, 1, 1, 12, 0, 0)
        let vector = astro_vector_t(
            status: ASTRO_SUCCESS,
            x: x,
            y: y,
            z: z,
            t: time
        )
        let spherical = Astronomy_HorizonFromVector(vector, REFRACTION_NORMAL)
        return (spherical.lon, spherical.lat)
    }

    fileprivate static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}
