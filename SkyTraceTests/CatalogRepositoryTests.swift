import XCTest
import SkyTraceCore

final class CatalogRepositoryTests: XCTestCase {
    func testBundledCatalogIntegrity() throws {
        let repository = try CatalogRepository()

        XCTAssertGreaterThan(repository.stars.count, 8_000)
        XCTAssertLessThanOrEqual(repository.stars.count, 9_110)
        XCTAssertEqual(repository.constellations.count, 88)
        XCTAssertEqual(repository.deepSkyObjects.count, 110)
        XCTAssertGreaterThanOrEqual(repository.cities.count, 20)

        let ids = repository.allObjects.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)

        for star in repository.stars {
            XCTAssertTrue((0..<360).contains(Double(star.raDegrees)))
            XCTAssertTrue((-90...90).contains(Double(star.decDegrees)))
            XCTAssertLessThanOrEqual(star.magnitude, 6.5)
        }
    }

    func testOfflineSearchFindsChineseAndCatalogNames() throws {
        let repository = try CatalogRepository()

        XCTAssertTrue(repository.search("猎户").contains { $0.name.contains("猎户") })
        XCTAssertFalse(repository.search("Jupiter").isEmpty)
        XCTAssertFalse(repository.search("M42").isEmpty)
    }

    func testConstellationSegmentEndpointsAreValid() throws {
        let repository = try CatalogRepository()
        let validCodes = Set(repository.constellations.map(\.id))

        XCTAssertEqual(validCodes.count, 88)
        for constellation in repository.constellations {
            XCTAssertFalse(constellation.segments.isEmpty)
            for segment in constellation.segments {
                for point in segment {
                    XCTAssertEqual(point.count, 2)
                    XCTAssertTrue((0..<360).contains(point[0]))
                    XCTAssertTrue((-90...90).contains(point[1]))
                }
            }
        }
    }
}
