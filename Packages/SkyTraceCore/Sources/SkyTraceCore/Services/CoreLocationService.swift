@preconcurrency import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
public final class CoreLocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager: CLLocationManager

    public private(set) var authorizationStatus: SkyLocationAuthorizationStatus
    public private(set) var errorMessage: String?

    @ObservationIgnored public var onLocationUpdate: (@MainActor (LocationSample) -> Void)?
    @ObservationIgnored public var onErrorMessage: (@MainActor (String) -> Void)?

    public override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = Self.mapStatus(manager.authorizationStatus)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    public func requestLocation() {
        errorMessage = nil
        if Self.isAuthorized(manager.authorizationStatus) {
            manager.requestLocation()
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            setError("定位权限不可用，可在设置中选择手动城市。")
        @unknown default:
            setError("当前系统无法确认定位权限。")
        }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = Self.mapStatus(status)
            if Self.isAuthorized(status) {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let sample = LocationSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.errorMessage = nil
            self.onLocationUpdate?(sample)
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.setError(message)
        }
    }

    private func setError(_ message: String) {
        errorMessage = message
        onErrorMessage?(message)
    }

    private static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
#if os(macOS)
        status == .authorized || status == .authorizedAlways
#else
        status == .authorizedAlways || status == .authorizedWhenInUse
#endif
    }

    private static func mapStatus(_ status: CLAuthorizationStatus) -> SkyLocationAuthorizationStatus {
        if isAuthorized(status) { return .authorized }
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedAlways: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unknown
        }
    }
}
