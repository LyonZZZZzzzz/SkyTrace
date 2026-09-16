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

    func testSceneCatalogSeparatesStaticAndDynamicObjects() throws {
        let catalog = try CatalogRepository()
        let sceneCatalog = SkySceneCatalog(
            objects: catalog.allObjects,
            constellations: catalog.constellations
        )
        let expectedSegments = catalog.constellations
            .flatMap(\.segments)
            .reduce(0) { $0 + max($1.count - 1, 0) }

        XCTAssertEqual(
            sceneCatalog.staticObjects.count,
            catalog.stars.count + catalog.deepSkyObjects.count
        )
        XCTAssertEqual(sceneCatalog.solarSystemObjects.count, 9)
        XCTAssertEqual(sceneCatalog.segments.count, expectedSegments)
        XCTAssertEqual(
            sceneCatalog.directionsJ2000.count,
            catalog.stars.count + catalog.deepSkyObjects.count + catalog.constellations.count
        )
    }

    @MainActor
    func testRapidTimeRequestsApplyOnlyLatestSnapshot() async throws {
        let viewModel = SkyViewModel(catalog: try CatalogRepository())
        let original = viewModel.moment.date
        viewModel.setDate(original.addingTimeInterval(3_600))
        viewModel.setDate(original.addingTimeInterval(7_200))
        await viewModel.waitForSnapshotUpdate()

        XCTAssertEqual(viewModel.moment.date.timeIntervalSince(original), 7_200, accuracy: 0.1)
        XCTAssertEqual(viewModel.snapshot.moment.date, viewModel.moment.date)
    }

    @MainActor
    func testApplicationLifecyclePausesPlaybackAndMotion() throws {
        let motion = TestMotionProvider()
        let viewModel = SkyViewModel(
            locationService: CoreLocationService(),
            motionService: motion,
            astronomy: AstronomyService(),
            catalog: try CatalogRepository()
        )
        viewModel.motionEnabled = true
        viewModel.togglePlayback()

        XCTAssertTrue(motion.isActive)
        XCTAssertTrue(viewModel.isPlaying)

        viewModel.setApplicationActive(false)
        XCTAssertFalse(motion.isActive)
        XCTAssertFalse(viewModel.isPlaying)

        viewModel.setApplicationActive(true)
        XCTAssertTrue(motion.isActive)
        XCTAssertTrue(viewModel.isPlaying)

        viewModel.togglePlayback()
    }

    @MainActor
    func testViewModelTimeTravelUsesSharedCore() async throws {
        let viewModel = try XCTUnwrap(SkyViewModel(catalog: try CatalogRepository()) as SkyViewModel?)
        let original = viewModel.moment.date
        viewModel.shiftTime(by: 3_600)
        await viewModel.waitForSnapshotUpdate()

        XCTAssertEqual(viewModel.moment.date.timeIntervalSince(original), 3_600, accuracy: 0.1)
        XCTAssertEqual(viewModel.snapshot.moment.date, viewModel.moment.date)
    }
}

@MainActor
private final class TestMotionProvider: DeviceMotionProviding {
    let isAvailable = true
    private(set) var isActive = false
    var onReading: (@MainActor (SkyMotionReading) -> Void)?
    var onErrorMessage: (@MainActor (String) -> Void)?

    func start() {
        isActive = true
    }

    func stop() {
        isActive = false
    }
}
