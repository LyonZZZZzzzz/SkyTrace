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


public enum AstronomyDirection: Sendable {
    case rising
    case setting

    fileprivate var cValue: astro_direction_t {
        switch self {
        case .rising: DIRECTION_RISE
        case .setting: DIRECTION_SET
        }
    }
}

public struct AstronomyRiseSet: Equatable, Sendable {
    public let rise: Date?
    public let set: Date?

    public init(rise: Date?, set: Date?) {
        self.rise = rise
        self.set = set
    }
}

public struct AstronomyMoonInfo: Equatable, Sendable {
    public let phaseAngle: Double
    public let illuminationFraction: Double
    public let magnitude: Double

    public init(phaseAngle: Double, illuminationFraction: Double, magnitude: Double) {
        self.phaseAngle = phaseAngle
        self.illuminationFraction = illuminationFraction
        self.magnitude = magnitude
    }
}

public enum AstronomyMoonQuarterKind: Int, Sendable {
    case newMoon = 0
    case firstQuarter = 1
    case fullMoon = 2
    case lastQuarter = 3
}

public struct AstronomyMoonQuarter: Equatable, Sendable {
    public let kind: AstronomyMoonQuarterKind
    public let date: Date
}

public enum AstronomyEclipseKind: Int, Sendable {
    case none = 0
    case penumbral = 1
    case partial = 2
    case annular = 3
    case total = 4
}

public struct AstronomyEclipse: Equatable, Sendable {
    public let kind: AstronomyEclipseKind
    public let peak: Date
    public let obscuration: Double
    public let altitude: Double
}

public struct AstronomySeasonEvents: Equatable, Sendable {
    public let marchEquinox: Date
    public let juneSolstice: Date
    public let septemberEquinox: Date
    public let decemberSolstice: Date
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

    public static func moonInfo(date: Date) -> AstronomyMoonInfo {
        let time = makeTime(date)
        let result = Astronomy_Illumination(BODY_MOON, time)
        return AstronomyMoonInfo(
            phaseAngle: result.phase_angle,
            illuminationFraction: result.phase_fraction,
            magnitude: result.mag
        )
    }

    public static func riseSet(
        body: AstronomyBody,
        startDate: Date,
        latitude: Double,
        longitude: Double,
        height: Double = 0,
        searchDays: Double = 2
    ) -> AstronomyRiseSet {
        let observer = Astronomy_MakeObserver(latitude, longitude, height)
        let startTime = makeTime(startDate)
        let riseResult = Astronomy_SearchRiseSetEx(
            body.cValue,
            observer,
            DIRECTION_RISE,
            startTime,
            searchDays,
            height
        )
        let setResult = Astronomy_SearchRiseSetEx(
            body.cValue,
            observer,
            DIRECTION_SET,
            startTime,
            searchDays,
            height
        )
        return AstronomyRiseSet(
            rise: riseResult.status == ASTRO_SUCCESS ? date(from: riseResult.time) : nil,
            set: setResult.status == ASTRO_SUCCESS ? date(from: setResult.time) : nil
        )
    }

    public static func altitudeCrossing(
        body: AstronomyBody,
        direction: AstronomyDirection,
        altitude: Double,
        startDate: Date,
        latitude: Double,
        longitude: Double,
        height: Double = 0,
        searchDays: Double = 2
    ) -> Date? {
        let observer = Astronomy_MakeObserver(latitude, longitude, height)
        let startTime = makeTime(startDate)
        let result = Astronomy_SearchAltitude(
            body.cValue,
            observer,
            direction.cValue,
            startTime,
            searchDays,
            altitude
        )
        return result.status == ASTRO_SUCCESS ? date(from: result.time) : nil
    }

    public static func nextMoonQuarter(after date: Date) -> AstronomyMoonQuarter? {
        let result = Astronomy_SearchMoonQuarter(makeTime(date))
        guard result.status == ASTRO_SUCCESS else { return nil }
        guard let kind = AstronomyMoonQuarterKind(rawValue: Int(result.quarter)) else { return nil }
        return AstronomyMoonQuarter(kind: kind, date: self.date(from: result.time))
    }

    public static func nextLunarEclipse(
        after date: Date,
        latitude: Double,
        longitude: Double,
        height: Double = 0
    ) -> AstronomyEclipse? {
        let start = makeTime(date)
        let result = Astronomy_SearchLunarEclipse(start)
        guard result.status == ASTRO_SUCCESS,
              let kind = AstronomyEclipseKind(rawValue: Int(result.kind.rawValue)) else { return nil }
        let peak = self.date(from: result.peak)
        let coordinate = horizontal(
            body: .moon,
            date: peak,
            latitude: latitude,
            longitude: longitude,
            height: height
        )
        return AstronomyEclipse(
            kind: kind,
            peak: peak,
            obscuration: result.obscuration,
            altitude: coordinate.altitude
        )
    }

    public static func nextLocalSolarEclipse(
        after date: Date,
        latitude: Double,
        longitude: Double,
        height: Double = 0
    ) -> AstronomyEclipse? {
        let observer = Astronomy_MakeObserver(latitude, longitude, height)
        let result = Astronomy_SearchLocalSolarEclipse(makeTime(date), observer)
        guard result.status == ASTRO_SUCCESS,
              let kind = AstronomyEclipseKind(rawValue: Int(result.kind.rawValue)) else { return nil }
        return AstronomyEclipse(
            kind: kind,
            peak: self.date(from: result.peak.time),
            obscuration: result.obscuration,
            altitude: result.peak.altitude
        )
    }

    public static func seasons(year: Int) -> AstronomySeasonEvents? {
        let result = Astronomy_Seasons(Int32(year))
        guard result.status == ASTRO_SUCCESS else { return nil }
        return AstronomySeasonEvents(
            marchEquinox: date(from: result.mar_equinox),
            juneSolstice: date(from: result.jun_solstice),
            septemberEquinox: date(from: result.sep_equinox),
            decemberSolstice: date(from: result.dec_solstice)
        )
    }

    private static func date(from time: astro_time_t) -> Date {
        let utc = Astronomy_UtcFromTime(time)
        let wholeSeconds = Int(utc.second.rounded(.down))
        let nanoseconds = Int(((utc.second - Double(wholeSeconds)) * 1_000_000_000).rounded())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            year: Int(utc.year),
            month: Int(utc.month),
            day: Int(utc.day),
            hour: Int(utc.hour),
            minute: Int(utc.minute),
            second: wholeSeconds,
            nanosecond: nanoseconds
        )) ?? .distantPast
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
