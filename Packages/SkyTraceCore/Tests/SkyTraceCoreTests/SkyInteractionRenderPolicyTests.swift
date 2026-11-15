import XCTest
@testable import SkyTraceCore

final class SkyInteractionRenderPolicyTests: XCTestCase {
    func testInteractionLimitsLabelsAtEveryFieldOfView() {
        var policy = SkyInteractionRenderPolicy()

        let narrow = policy.update(isInteractionActive: true, fieldOfView: 70)
        XCTAssertEqual(narrow.labelCapacityLimit, 50)
        XCTAssertFalse(narrow.hidesFaintStars)

        let wide = policy.update(isInteractionActive: true, fieldOfView: 95)
        XCTAssertEqual(wide.labelCapacityLimit, 50)
        XCTAssertTrue(wide.hidesFaintStars)
    }

    func testFaintStarReductionUsesFieldOfViewHysteresis() {
        var policy = SkyInteractionRenderPolicy()

        XCTAssertFalse(policy.update(isInteractionActive: true, fieldOfView: 94).hidesFaintStars)
        XCTAssertTrue(policy.update(isInteractionActive: true, fieldOfView: 95).hidesFaintStars)
        XCTAssertTrue(policy.update(isInteractionActive: true, fieldOfView: 90).hidesFaintStars)
        XCTAssertFalse(policy.update(isInteractionActive: true, fieldOfView: 88).hidesFaintStars)
        XCTAssertFalse(policy.update(isInteractionActive: true, fieldOfView: 94).hidesFaintStars)
        XCTAssertTrue(policy.update(isInteractionActive: true, fieldOfView: 95).hidesFaintStars)
    }

    func testEndingInteractionRestoresFullProfile() {
        var policy = SkyInteractionRenderPolicy()

        _ = policy.update(isInteractionActive: true, fieldOfView: 110)
        let settled = policy.update(isInteractionActive: false, fieldOfView: 110)

        XCTAssertEqual(settled, .full)
        XCTAssertFalse(policy.hidesFaintStars)
    }

    func testFaintStarClassificationKeepsDeepSkyObjects() {
        let faintStar = makeObject(id: "faint", kind: .star, magnitude: 5.6)
        let brightStar = makeObject(id: "bright", kind: .star, magnitude: 5.5)
        let deepSky = makeObject(id: "deep", kind: .deepSky, magnitude: 6.0)

        XCTAssertTrue(SkyInteractionRenderPolicy.isFaintStar(faintStar))
        XCTAssertFalse(SkyInteractionRenderPolicy.isFaintStar(brightStar))
        XCTAssertFalse(SkyInteractionRenderPolicy.isFaintStar(deepSky))
    }

    private func makeObject(
        id: String,
        kind: CelestialKind,
        magnitude: Double
    ) -> CelestialObject {
        CelestialObject(
            id: id,
            name: id,
            englishName: id,
            designation: id,
            kind: kind,
            raDegrees: 0,
            decDegrees: 0,
            magnitude: magnitude,
            bvColorIndex: 0.4,
            detail: "",
            aliases: []
        )
    }
}
