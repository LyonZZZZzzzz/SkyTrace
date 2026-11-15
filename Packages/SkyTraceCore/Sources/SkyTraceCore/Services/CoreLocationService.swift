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
#if !os(macOS)
        case .authorizedWhenInUse:
            manager.requestLocation()
#endif
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
            } else if status == .denied || status == .restricted {
                self.setError("定位权限不可用，可在设置中选择手动城市。")
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.reversed().first(where: Self.isUsableLocation),
              let sample = Self.makeSample(from: location) else {
            Task { @MainActor [weak self] in
                self?.setError("未获得可用的当前位置，请重试或手动选择城市。")
            }
            return
        }
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

    private nonisolated static func isUsableLocation(_ location: CLLocation) -> Bool {
        let coordinate = location.coordinate
        guard coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude),
              location.altitude.isFinite,
              location.horizontalAccuracy.isFinite,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 50_000 else { return false }
        let age = Date().timeIntervalSince(location.timestamp)
        return age >= -60 && age <= 15 * 60
    }

    private nonisolated static func makeSample(from location: CLLocation) -> LocationSample? {
        guard isUsableLocation(location) else { return nil }
        return LocationSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
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
#if !os(macOS)
        case .authorizedWhenInUse: return .authorized
#endif
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unknown
        }
    }
}
