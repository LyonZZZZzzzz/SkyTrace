@preconcurrency import CoreMotion
import Foundation
import Observation
import SkyTraceCore

@MainActor
@Observable
final class MotionService: DeviceMotionProviding {
    private let manager = CMMotionManager()

    let isAvailable: Bool
    private(set) var isActive = false
    @ObservationIgnored var onReading: (@MainActor (SkyMotionReading) -> Void)?
    @ObservationIgnored var onErrorMessage: (@MainActor (String) -> Void)?

    init() {
        isAvailable = manager.isDeviceMotionAvailable
    }

    func start() {
        guard isAvailable, !isActive else {
            if !isAvailable {
                onErrorMessage?("当前设备没有可用的运动传感器。")
            }
            return
        }

        let availableFrames = CMMotionManager.availableAttitudeReferenceFrames()
        let referenceFrame: CMAttitudeReferenceFrame = availableFrames.contains(.xTrueNorthZVertical)
            ? .xTrueNorthZVertical
            : .xArbitraryZVertical

        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: referenceFrame, to: .main) { [weak self] motion, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.onErrorMessage?(error.localizedDescription)
                    self.stop()
                    return
                }
                guard let motion else { return }
                self.onReading?(self.makeReading(from: motion))
            }
        }
        isActive = true
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isActive = false
    }

    private func makeReading(from motion: CMDeviceMotion) -> SkyMotionReading {
        let azimuth = Self.normalizedDegrees(-motion.attitude.yaw * 180 / .pi)
        let altitude = min(89, max(-20, motion.attitude.pitch * 180 / .pi))
        let roll = motion.attitude.roll * 180 / .pi
        return SkyMotionReading(azimuth: azimuth, altitude: altitude, roll: roll)
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}
