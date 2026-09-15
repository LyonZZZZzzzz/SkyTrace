import Foundation

public enum WeatherCondition: String, Codable, CaseIterable, Sendable {
    case clear
    case mostlyClear
    case partlyCloudy
    case cloudy
    case rain
    case snow
    case haze
    case unknown

    public var localizedName: String {
        switch self {
        case .clear: "晴朗"
        case .mostlyClear: "少云"
        case .partlyCloudy: "多云"
        case .cloudy: "阴天"
        case .rain: "降雨"
        case .snow: "降雪"
        case .haze: "雾霾"
        case .unknown: "未记录"
        }
    }

    public var symbolName: String {
        switch self {
        case .clear: "sun.max"
        case .mostlyClear: "cloud.sun"
        case .partlyCloudy: "cloud"
        case .cloudy: "cloud.fill"
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        case .haze: "sun.haze"
        case .unknown: "questionmark.circle"
        }
    }
}

public enum ObservationEquipment: String, Codable, CaseIterable, Sendable {
    case nakedEye
    case binoculars
    case telescope
    case camera
    case other

    public var localizedName: String {
        switch self {
        case .nakedEye: "肉眼"
        case .binoculars: "双筒望远镜"
        case .telescope: "天文望远镜"
        case .camera: "相机"
        case .other: "其他"
        }
    }
}

public struct ObservationLogEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var objectID: String
    public var objectName: String
    public var observedAt: Date
    public var observerName: String
    public var latitude: Double
    public var longitude: Double
    public var timeZoneIdentifier: String
    public var rating: Int
    public var weather: WeatherCondition
    public var equipment: ObservationEquipment
    public var notes: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        objectID: String,
        objectName: String,
        observedAt: Date,
        observer: ObserverContext,
        rating: Int,
        weather: WeatherCondition,
        equipment: ObservationEquipment,
        notes: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.objectID = objectID
        self.objectName = objectName
        self.observedAt = observedAt
        self.observerName = observer.name
        latitude = observer.latitude
        longitude = observer.longitude
        timeZoneIdentifier = observer.timeZoneIdentifier
        self.rating = min(5, max(1, rating))
        self.weather = weather
        self.equipment = equipment
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ObservationLogFilter: Equatable, Sendable {
    public var objectID: String?
    public var minimumRating: Int?
    public var startDate: Date?
    public var endDate: Date?

    public init(
        objectID: String? = nil,
        minimumRating: Int? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.objectID = objectID
        self.minimumRating = minimumRating
        self.startDate = startDate
        self.endDate = endDate
    }
}
