import XCTest
import SkyTraceCore

final class AstronomyServiceTests: XCTestCase {
    private let service = AstronomyService()
    private let observer = ObserverContext.shanghai

    func testPolarisAltitudeTracksObserverLatitude() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12)))
        let moment = SkyMoment(date: date)
        let transform = service.horizontalTransform(for: moment, observer: observer)
        let polaris = CelestialObject(
            id: "polaris",
            name: "北极星",
            englishName: "Polaris",
            designation: "α UMi",
            kind: .star,
            raDegrees: 37.954,
            decDegrees: 89.264,
            magnitude: 1.98,
            bvColorIndex: 0.6,
            detail: "",
            aliases: []
        )

        let coordinate = service.horizontal(object: polaris, moment: moment, observer: observer, transform: transform)
        XCTAssertEqual(coordinate.altitude, observer.latitude, accuracy: 1.5)
        XCTAssertTrue((0..<360).contains(coordinate.azimuth))
    }

    func testPlanetCoordinatesStayInsideCelestialRange() throws {
        let date = Date(timeIntervalSince1970: 1_789_396_800)
        let moment = SkyMoment(date: date)
        let transform = service.horizontalTransform(for: moment, observer: observer)

        for object in CatalogRepository.standardSolarSystemObjects where object.kind != .sun {
            let coordinate = service.horizontal(
                object: object,
                moment: moment,
                observer: observer,
                transform: transform
            )
            XCTAssertTrue((0..<360).contains(coordinate.azimuth))
            XCTAssertTrue((-91...91).contains(coordinate.altitude))
        }
    }

    func testViewportProjectionCenterAndOppositeDirection() {
        let projection = SkyProjection(
            camera: SkyCameraState(azimuth: 0, altitude: 0, roll: 0, fieldOfView: 70),
            size: CGSize(width: 400, height: 800)
        )

        let center = projection.screenPoint(for: Vector3D(x: 0, y: 0, z: -1))
        XCTAssertEqual(center?.x ?? -1, 200, accuracy: 0.01)
        XCTAssertEqual(center?.y ?? -1, 400, accuracy: 0.01)
        XCTAssertNil(projection.screenPoint(for: Vector3D(x: 0, y: 0, z: 1)))
    }
}
