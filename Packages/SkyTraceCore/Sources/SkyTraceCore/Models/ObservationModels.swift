import Foundation

public enum ObservationNightQuality: String, Codable, Equatable, Sendable {
    case astronomical
    case nautical
    case civil
    case polarDay

    public var localizedName: String {
        switch self {
        case .astronomical: "天文暗夜"
        case .nautical: "航海暮光"
        case .civil: "民用暮光"
        case .polarDay: "极昼"
        }
    }
}

public struct ObservationNight: Equatable, Sendable {
    public let anchorDate: Date
    public let sunset: Date?
    public let sunrise: Date?
    public let civilDusk: Date?
    public let civilDawn: Date?
    public let nauticalDusk: Date?
    public let nauticalDawn: Date?
    public let astronomicalDusk: Date?
    public let astronomicalDawn: Date?
    public let effectiveDarkStart: Date?
    public let effectiveDarkEnd: Date?
    public let quality: ObservationNightQuality

    public init(
        anchorDate: Date,
        sunset: Date?,
        sunrise: Date?,
        civilDusk: Date?,
        civilDawn: Date?,
        nauticalDusk: Date?,
        nauticalDawn: Date?,
        astronomicalDusk: Date?,
        astronomicalDawn: Date?,
        effectiveDarkStart: Date?,
        effectiveDarkEnd: Date?,
        quality: ObservationNightQuality
    ) {
        self.anchorDate = anchorDate
        self.sunset = sunset
        self.sunrise = sunrise
        self.civilDusk = civilDusk
        self.civilDawn = civilDawn
        self.nauticalDusk = nauticalDusk
        self.nauticalDawn = nauticalDawn
        self.astronomicalDusk = astronomicalDusk
        self.astronomicalDawn = astronomicalDawn
        self.effectiveDarkStart = effectiveDarkStart
        self.effectiveDarkEnd = effectiveDarkEnd
        self.quality = quality
    }
}

public enum LunarPhase: String, Codable, CaseIterable, Equatable, Sendable {
    case newMoon
    case waxingCrescent
    case firstQuarter
    case waxingGibbous
    case fullMoon
    case waningGibbous
    case lastQuarter
    case waningCrescent

    public var localizedName: String {
        switch self {
        case .newMoon: "新月"
        case .waxingCrescent: "娥眉月"
        case .firstQuarter: "上弦月"
        case .waxingGibbous: "盈凸月"
        case .fullMoon: "满月"
        case .waningGibbous: "亏凸月"
        case .lastQuarter: "下弦月"
        case .waningCrescent: "残月"
        }
    }

    public var symbolName: String {
        switch self {
        case .newMoon: "moon.fill"
        case .waxingCrescent: "moonphase.waxing.crescent"
        case .firstQuarter: "moonphase.first.quarter"
        case .waxingGibbous: "moonphase.waxing.gibbous"
        case .fullMoon: "moonphase.full.moon"
        case .waningGibbous: "moonphase.waning.gibbous"
        case .lastQuarter: "moonphase.last.quarter"
        case .waningCrescent: "moonphase.waning.crescent"
        }
    }
}

public struct MoonObservation: Equatable, Sendable {
    public let phase: LunarPhase
    public let phaseAngle: Double
    public let illuminationFraction: Double
    public let magnitude: Double
    public let rise: Date?
    public let set: Date?
    public let altitudeAtBestTime: Double?
    public let azimuthAtBestTime: Double?

    public init(
        phase: LunarPhase,
        phaseAngle: Double,
        illuminationFraction: Double,
        magnitude: Double,
        rise: Date?,
        set: Date?,
        altitudeAtBestTime: Double?,
        azimuthAtBestTime: Double?
    ) {
        self.phase = phase
        self.phaseAngle = phaseAngle
        self.illuminationFraction = illuminationFraction
        self.magnitude = magnitude
        self.rise = rise
        self.set = set
        self.altitudeAtBestTime = altitudeAtBestTime
        self.azimuthAtBestTime = azimuthAtBestTime
    }

    public var illuminationText: String {
        String(format: "%.0f%% 被照亮", illuminationFraction * 100)
    }
}

public enum ObservationReason: String, Codable, Equatable, Sendable {
    case allNight
    case bestAfterDark
    case bestBeforeDawn
    case bestBeforeMoonrise
    case bestAfterMoonset
    case shortWindow

    public var localizedText: String {
        switch self {
        case .allNight: "整夜可见"
        case .bestAfterDark: "天黑后进入最佳状态"
        case .bestBeforeDawn: "天亮前最佳"
        case .bestBeforeMoonrise: "月亮升起前最佳"
        case .bestAfterMoonset: "月亮落下后最佳"
        case .shortWindow: "可见窗口较短"
        }
    }
}

public struct ObservationVisibility: Identifiable, Equatable, Sendable {
    public let object: CelestialObject
    public let start: Date
    public let end: Date
    public let bestTime: Date
    public let maximumAltitude: Double
    public let duration: TimeInterval
    public let score: Double
    public let reason: ObservationReason
    public let moonSeparation: Double?

    public init(
        object: CelestialObject,
        start: Date,
        end: Date,
        bestTime: Date,
        maximumAltitude: Double,
        duration: TimeInterval,
        score: Double,
        reason: ObservationReason,
        moonSeparation: Double?
    ) {
        self.object = object
        self.start = start
        self.end = end
        self.bestTime = bestTime
        self.maximumAltitude = maximumAltitude
        self.duration = duration
        self.score = score
        self.reason = reason
        self.moonSeparation = moonSeparation
    }

    public var id: String { object.id }

    public var durationText: String {
        let minutes = max(0, Int(duration / 60))
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 { return "\(remainingMinutes) 分钟" }
        if remainingMinutes == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(remainingMinutes) 分钟"
    }
}

public struct ObservationPlan: Equatable, Sendable {
    public let moment: SkyMoment
    public let observer: ObserverContext
    public let night: ObservationNight
    public let moon: MoonObservation
    public let recommendations: [ObservationVisibility]
    public let favoriteVisibilities: [ObservationVisibility]
    public let warningMessage: String?

    public init(
        moment: SkyMoment,
        observer: ObserverContext,
        night: ObservationNight,
        moon: MoonObservation,
        recommendations: [ObservationVisibility],
        favoriteVisibilities: [ObservationVisibility],
        warningMessage: String?
    ) {
        self.moment = moment
        self.observer = observer
        self.night = night
        self.moon = moon
        self.recommendations = recommendations
        self.favoriteVisibilities = favoriteVisibilities
        self.warningMessage = warningMessage
    }
}

public enum ObservationPlanState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
}
