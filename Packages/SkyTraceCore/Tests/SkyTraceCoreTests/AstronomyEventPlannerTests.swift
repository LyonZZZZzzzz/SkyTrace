import XCTest
@testable import SkyTraceCore

final class AstronomyEventPlannerTests: XCTestCase {
    func testEventPlanIsSortedWithinRange() async throws {
        let start = Date(timeIntervalSince1970: 1_789_430_400)
        let end = start.addingTimeInterval(120 * 24 * 3600)
        let planner = AstronomyEventPlanner()
        let objects = CatalogRepository.standardSolarSystemObjects

        let events = await planner.events(
            from: start,
            through: end,
            observer: .shanghai,
            objects: objects
        )

        XCTAssertEqual(events, events.sorted { $0.date < $1.date })
        XCTAssertTrue(events.allSatisfy { $0.date >= start && $0.date <= end })
        XCTAssertTrue(events.contains { $0.kind == .newMoon })
        XCTAssertTrue(events.contains { $0.kind == .fullMoon })
        XCTAssertTrue(events.contains { $0.kind == .season })
        XCTAssertTrue(events.contains { $0.kind == .moonPlanetConjunction })
    }

    func testConjunctionThresholdRejectsWidePairs() async throws {
        let start = Date(timeIntervalSince1970: 1_789_430_400)
        let end = start.addingTimeInterval(60 * 24 * 3600)
        let planner = AstronomyEventPlanner(conjunctionThreshold: 0.01)
        let planets = CatalogRepository.standardSolarSystemObjects.filter { $0.kind == .planet }

        let events = await planner.events(
            from: start,
            through: end,
            observer: .shanghai,
            objects: planets
        )

        XCTAssertTrue(events.allSatisfy { event in
            event.kind != .planetConjunction || event.summary.contains("0.0")
        })
    }
}
