import Foundation

public enum AstronomyEventKind: String, Codable, CaseIterable, Sendable {
    case newMoon
    case firstQuarter
    case fullMoon
    case lastQuarter
    case lunarEclipse
    case solarEclipse
    case planetConjunction
    case moonPlanetConjunction
    case season

    public var localizedName: String {
        switch self {
        case .newMoon: "新月"
        case .firstQuarter: "上弦月"
        case .fullMoon: "满月"
        case .lastQuarter: "下弦月"
        case .lunarEclipse: "月食"
        case .solarEclipse: "日食"
        case .planetConjunction: "行星合"
        case .moonPlanetConjunction: "行星合月"
        case .season: "节气"
        }
    }

    public var symbolName: String {
        switch self {
        case .newMoon: "moon.fill"
        case .firstQuarter: "moonphase.first.quarter"
        case .fullMoon: "moonphase.full.moon"
        case .lastQuarter: "moonphase.last.quarter"
        case .lunarEclipse: "moon.circle.fill"
        case .solarEclipse: "sun.max.circle.fill"
        case .planetConjunction: "circle.grid.cross"
        case .moonPlanetConjunction: "moon.stars"
        case .season: "calendar"
        }
    }
}

public struct AstronomyEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: AstronomyEventKind
    public let date: Date
    public let title: String
    public let summary: String
    public let objectIDs: [String]
    public let altitude: Double?

    public init(
        id: String,
        kind: AstronomyEventKind,
        date: Date,
        title: String,
        summary: String,
        objectIDs: [String],
        altitude: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.summary = summary
        self.objectIDs = objectIDs
        self.altitude = altitude
    }
}

public protocol AstronomyEventPlanning: Sendable {
    func events(
        from startDate: Date,
        through endDate: Date,
        observer: ObserverContext,
        objects: [CelestialObject]
    ) async -> [AstronomyEvent]
}
