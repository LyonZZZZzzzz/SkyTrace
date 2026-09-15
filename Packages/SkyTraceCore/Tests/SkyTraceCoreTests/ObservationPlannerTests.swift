import AstronomyEngine
import XCTest
@testable import SkyTraceCore

final class ObservationPlannerTests: XCTestCase {
    func testShanghaiNightPlanContainsTwilightAndMoon() async throws {
        let repository = try CatalogRepository()
        let observer = ObserverContext.shanghai
        let moment = SkyMoment(date: try date(2026, 9, 14, 12, 0))
        let planner = ObservationPlanner()

        let plan = await planner.makePlan(
            for: moment,
            observer: observer,
            candidates: repository.allObjects,
            favoriteIDs: [],
            minimumAltitude: 10
        )

        XCTAssertNotNil(plan.night.sunset)
        XCTAssertNotNil(plan.night.sunrise)
        XCTAssertNotNil(plan.night.effectiveDarkStart)
        XCTAssertNotNil(plan.night.effectiveDarkEnd)
        XCTAssertGreaterThanOrEqual(plan.moon.illuminationFraction, 0)
        XCTAssertLessThanOrEqual(plan.moon.illuminationFraction, 1)
        XCTAssertFalse(plan.recommendations.isEmpty)

        let ordered = [
            plan.night.sunset,
            plan.night.civilDusk,
            plan.night.nauticalDusk,
            plan.night.astronomicalDusk,
            plan.night.astronomicalDawn,
            plan.night.nauticalDawn,
            plan.night.civilDawn,
            plan.night.sunrise
        ].compactMap { $0 }
        XCTAssertEqual(ordered, ordered.sorted())
    }

    func testPolarDayReturnsExplicitWarning() async throws {
        let observer = ObserverContext(
            name: "北极",
            latitude: 89,
            longitude: 0,
            altitude: 0,
            timeZoneIdentifier: "UTC"
        )
        let moment = SkyMoment(date: try date(2026, 6, 21, 12, 0))
        let planner = ObservationPlanner(sampleInterval: 30 * 60)
        let object = CatalogRepository.standardSolarSystemObjects[0]

        let plan = await planner.makePlan(
            for: moment,
            observer: observer,
            candidates: [object],
            favoriteIDs: [],
            minimumAltitude: 10
        )

        XCTAssertEqual(plan.night.quality, ObservationNightQuality.polarDay)
        XCTAssertTrue(plan.recommendations.isEmpty)
        XCTAssertNotNil(plan.warningMessage)
    }

    func testShortVisibilityWindowIsFiltered() async throws {
        let base = try date(2026, 9, 14, 18, 0)
        let astronomy = ShortWindowAstronomy(base: base)
        let planner = ObservationPlanner(
            astronomy: astronomy,
            sampleInterval: 10 * 60,
            minimumWindowDuration: 20 * 60
        )
        let planet = CatalogRepository.standardSolarSystemObjects.first { $0.id == "planet-jupiter" }!

        let plan = await planner.makePlan(
            for: SkyMoment(date: base),
            observer: .shanghai,
            candidates: [planet],
            favoriteIDs: [],
            minimumAltitude: 10
        )

        XCTAssertTrue(plan.recommendations.isEmpty)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }
}

private struct ShortWindowAstronomy: AstronomyCalculating {
    let base: Date
    let fallback = AstronomyService()

    func horizontalTransform(for moment: SkyMoment, observer: ObserverContext) -> HorizontalTransform {
        fallback.horizontalTransform(for: moment, observer: observer)
    }

    func riseSet(
        body: AstronomyBody,
        startDate: Date,
        observer: ObserverContext,
        searchDays: Double
    ) -> AstronomyRiseSet {
        switch body {
        case .sun:
            return AstronomyRiseSet(
                rise: base.addingTimeInterval(18 * 3600),
                set: base.addingTimeInterval(6 * 3600)
            )
        case .moon:
            return AstronomyRiseSet(rise: base.addingTimeInterval(20 * 3600), set: nil)
        default:
            return AstronomyRiseSet(rise: nil, set: nil)
        }
    }

    func altitudeCrossing(
        body: AstronomyBody,
        direction: AstronomyDirection,
        altitude: Double,
        startDate: Date,
        observer: ObserverContext,
        searchDays: Double
    ) -> Date? {
        guard body == .sun else { return nil }
        return base.addingTimeInterval(direction == .setting ? 8 * 3600 : 16 * 3600)
    }

    func nextMoonQuarter(after date: Date) -> AstronomyMoonQuarter? { nil }
    func nextLunarEclipse(after date: Date, observer: ObserverContext) -> AstronomyEclipse? { nil }
    func nextLocalSolarEclipse(after date: Date, observer: ObserverContext) -> AstronomyEclipse? { nil }
    func seasons(year: Int) -> AstronomySeasonEvents? { nil }

    func moonInfo(date: Date) -> AstronomyMoonInfo {
        AstronomyMoonInfo(phaseAngle: 180, illuminationFraction: 1, magnitude: -12)
    }

    func horizontal(
        body: AstronomyBody,
        date: Date,
        latitude: Double,
        longitude: Double,
        height: Double
    ) -> AstronomyHorizontalCoordinate {
        if body == .jupiter {
            let offset = date.timeIntervalSince(base)
            let altitude = (offset >= 9.5 * 3600 && offset <= 9.7 * 3600) ? 30.0 : -10.0
            return AstronomyHorizontalCoordinate(azimuth: 180, altitude: altitude, raHours: 0, decDegrees: 0)
        }
        if body == .moon {
            return AstronomyHorizontalCoordinate(azimuth: 270, altitude: -20, raHours: 0, decDegrees: 0)
        }
        if body == .sun {
            let offset = date.timeIntervalSince(base)
            let altitude = offset < 8 * 3600 ? 10.0 : -20.0
            return AstronomyHorizontalCoordinate(azimuth: 180, altitude: altitude, raHours: 0, decDegrees: 0)
        }
        return AstronomyHorizontalCoordinate(azimuth: 0, altitude: -30, raHours: 0, decDegrees: 0)
    }

    func horizontal(
        object: CelestialObject,
        moment: SkyMoment,
        observer: ObserverContext,
        transform: HorizontalTransform
    ) -> (azimuth: Double, altitude: Double) {
        (0, -30)
    }
}
