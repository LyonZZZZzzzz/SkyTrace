import Foundation

public enum SkyRenderQuality: String, Equatable, Sendable {
    case normal
    case elevated
    case critical
}

enum SkyAntialiasingLevel: Equatable, Sendable {
    case multisampling2X
    case disabled
}

struct SkyRenderAdaptationProfile: Equatable, Sendable {
    let quality: SkyRenderQuality
    let preferredFramesPerSecond: Int
    let antialiasing: SkyAntialiasingLevel
    let labelCapacityLimit: Int?
    let hidesFaintStars: Bool

    static let normal = SkyRenderAdaptationProfile(
        quality: .normal,
        preferredFramesPerSecond: 60,
        antialiasing: .multisampling2X,
        labelCapacityLimit: nil,
        hidesFaintStars: false
    )

    static let elevated = SkyRenderAdaptationProfile(
        quality: .elevated,
        preferredFramesPerSecond: 30,
        antialiasing: .multisampling2X,
        labelCapacityLimit: 80,
        hidesFaintStars: false
    )

    static let critical = SkyRenderAdaptationProfile(
        quality: .critical,
        preferredFramesPerSecond: 30,
        antialiasing: .disabled,
        labelCapacityLimit: 50,
        hidesFaintStars: true
    )
}

struct SkyRenderAdaptationPolicy {
    static func profile(
        thermalState: ProcessInfo.ThermalState,
        isLowPowerModeEnabled: Bool,
        memoryPressure: SkyMemoryPressure
    ) -> SkyRenderAdaptationProfile {
        if thermalState == .critical || memoryPressure != .normal {
            return .critical
        }
        if thermalState == .serious || isLowPowerModeEnabled {
            return .elevated
        }
        return .normal
    }

    static func profile(for environment: SkyRenderEnvironment) -> SkyRenderAdaptationProfile {
        profile(
            thermalState: environment.thermalState,
            isLowPowerModeEnabled: environment.isLowPowerModeEnabled,
            memoryPressure: environment.memoryPressure
        )
    }

    static func mostConstrained(
        _ lhs: SkyRenderAdaptationProfile,
        _ rhs: SkyRenderAdaptationProfile
    ) -> SkyRenderAdaptationProfile {
        qualityRank(lhs.quality) >= qualityRank(rhs.quality) ? lhs : rhs
    }

    private static func qualityRank(_ quality: SkyRenderQuality) -> Int {
        switch quality {
        case .normal: 0
        case .elevated: 1
        case .critical: 2
        }
    }
}
