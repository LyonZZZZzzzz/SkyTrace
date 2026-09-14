import Foundation
import Observation

public struct SkyMotionReading: Equatable, Sendable {
    public let azimuth: Double
    public let altitude: Double
    public let roll: Double

    public init(azimuth: Double, altitude: Double, roll: Double) {
        self.azimuth = azimuth
        self.altitude = altitude
        self.roll = roll
    }
}

@MainActor
public protocol DeviceMotionProviding: AnyObject {
    var isAvailable: Bool { get }
    var isActive: Bool { get }
    var onReading: (@MainActor (SkyMotionReading) -> Void)? { get set }
    var onErrorMessage: (@MainActor (String) -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
public final class NoopDeviceMotionProvider: DeviceMotionProviding {
    public let isAvailable = false
    public private(set) var isActive = false
    @ObservationIgnored public var onReading: (@MainActor (SkyMotionReading) -> Void)?
    @ObservationIgnored public var onErrorMessage: (@MainActor (String) -> Void)?

    public init() {}

    public func start() {
        onErrorMessage?("当前平台没有可用的设备姿态传感器。")
    }

    public func stop() {
        isActive = false
    }
}
