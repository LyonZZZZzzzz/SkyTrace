import XCTest
@testable import SkyTraceCore

final class SkyRenderAdaptationPolicyTests: XCTestCase {
    func testNormalEnvironmentKeepsFullQuality() {
        let profile = SkyRenderAdaptationPolicy.profile(
            thermalState: .nominal,
            isLowPowerModeEnabled: false,
            memoryPressure: .normal
        )

        XCTAssertEqual(profile, .normal)
        XCTAssertEqual(profile.preferredFramesPerSecond, 60)
        XCTAssertEqual(profile.antialiasing, .multisampling2X)
        XCTAssertNil(profile.labelCapacityLimit)
        XCTAssertFalse(profile.hidesFaintStars)
    }

    func testLowPowerAndSeriousThermalUseElevatedProfile() {
        let lowPower = SkyRenderAdaptationPolicy.profile(
            thermalState: .nominal,
            isLowPowerModeEnabled: true,
            memoryPressure: .normal
        )
        let serious = SkyRenderAdaptationPolicy.profile(
            thermalState: .serious,
            isLowPowerModeEnabled: false,
            memoryPressure: .normal
        )

        XCTAssertEqual(lowPower, .elevated)
        XCTAssertEqual(serious, .elevated)
        XCTAssertEqual(lowPower.preferredFramesPerSecond, 30)
        XCTAssertEqual(lowPower.labelCapacityLimit, 80)
        XCTAssertFalse(lowPower.hidesFaintStars)
    }

    func testCriticalThermalAndMemoryWarningUseCriticalProfile() {
        let thermal = SkyRenderAdaptationPolicy.profile(
            thermalState: .critical,
            isLowPowerModeEnabled: false,
            memoryPressure: .normal
        )
        let memory = SkyRenderAdaptationPolicy.profile(
            thermalState: .nominal,
            isLowPowerModeEnabled: false,
            memoryPressure: .warning
        )

        XCTAssertEqual(thermal, .critical)
        XCTAssertEqual(memory, .critical)
        XCTAssertEqual(memory.preferredFramesPerSecond, 30)
        XCTAssertEqual(memory.antialiasing, .disabled)
        XCTAssertEqual(memory.labelCapacityLimit, 50)
        XCTAssertTrue(memory.hidesFaintStars)
    }

    func testCriticalPressureWinsOverLowPower() {
        let profile = SkyRenderAdaptationPolicy.profile(
            thermalState: .critical,
            isLowPowerModeEnabled: true,
            memoryPressure: .normal
        )

        XCTAssertEqual(profile.quality, .critical)
    }
}
