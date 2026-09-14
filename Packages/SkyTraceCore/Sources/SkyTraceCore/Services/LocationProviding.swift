import Foundation

public enum SkyLocationAuthorizationStatus: String, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unknown
}

public struct LocationSample: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let horizontalAccuracy: Double
    public let timestamp: Date

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        horizontalAccuracy: Double,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

@MainActor
public protocol LocationProviding: AnyObject {
    var authorizationStatus: SkyLocationAuthorizationStatus { get }
    var errorMessage: String? { get }
    var onLocationUpdate: (@MainActor (LocationSample) -> Void)? { get set }
    var onErrorMessage: (@MainActor (String) -> Void)? { get set }

    func requestLocation()
}
