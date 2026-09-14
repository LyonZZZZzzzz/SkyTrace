import XCTest
@testable import SkyTraceCore

final class CoreTests: XCTestCase {
    func testCatalogLoadsFromPackageResources() throws {
        let catalog = try CatalogRepository()

        XCTAssertGreaterThan(catalog.stars.count, 8_000)
        XCTAssertEqual(catalog.constellations.count, 88)
        XCTAssertEqual(catalog.deepSkyObjects.count, 110)
        XCTAssertFalse(catalog.search("M42").isEmpty)
    }

    func testCameraStateDirectionAndRollProjection() {
        let camera = SkyCameraState(azimuth: 0, altitude: 0, roll: 0, fieldOfView: 70)
        let projection = SkyProjection(camera: camera, size: CGSize(width: 400, height: 800))
        let point = projection.screenPoint(for: Vector3D(x: 0, y: 0, z: -1))

        XCTAssertEqual(point?.x ?? -1, 200, accuracy: 0.01)
        XCTAssertEqual(point?.y ?? -1, 400, accuracy: 0.01)
    }

    @MainActor
    func testViewModelTimeTravelUsesSharedCore() throws {
        let viewModel = try XCTUnwrap(SkyViewModel(catalog: try CatalogRepository()) as SkyViewModel?)
        let original = viewModel.moment.date
        viewModel.shiftTime(by: 3_600)

        XCTAssertEqual(viewModel.moment.date.timeIntervalSince(original), 3_600, accuracy: 0.1)
        XCTAssertEqual(viewModel.snapshot.moment.date, viewModel.moment.date)
    }
}
