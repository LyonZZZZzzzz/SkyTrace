import CoreLocation
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

    func testCatalogValidationRejectsDuplicateStarIDs() throws {
        let star = StarRecord(
            hr: 1,
            hip: 1,
            raDegrees: 10,
            decDegrees: 20,
            magnitude: 2,
            bvColorIndex: 0.5
        )

        XCTAssertThrowsError(
            try CatalogRepository.validate(
                stars: [star, star],
                labels: [],
                constellations: [],
                deepSkyObjects: [],
                cities: [],
                enforceExpectedCounts: false
            )
        ) { error in
            guard case CatalogLoadError.invalidRecord = error else {
                return XCTFail("Expected invalidRecord, got \(error)")
            }
        }
    }

    func testCatalogValidationRejectsNonFiniteCoordinates() throws {
        let star = StarRecord(
            hr: 1,
            hip: 1,
            raDegrees: .nan,
            decDegrees: 20,
            magnitude: 2,
            bvColorIndex: 0.5
        )

        XCTAssertThrowsError(
            try CatalogRepository.validate(
                stars: [star],
                labels: [],
                constellations: [],
                deepSkyObjects: [],
                cities: [],
                enforceExpectedCounts: false
            )
        ) { error in
            guard case CatalogLoadError.invalidRecord = error else {
                return XCTFail("Expected invalidRecord, got \(error)")
            }
        }
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
    func testTonightDataLoadsOnlyWhenRequested() throws {
        let viewModel = SkyViewModel(
            locationService: CoreLocationService(),
            motionService: NoopDeviceMotionProvider(),
            astronomy: AstronomyService(),
            catalog: try CatalogRepository()
        )

        XCTAssertNil(viewModel.observationPlan)
        XCTAssertEqual(viewModel.observationPlanState, .idle)
        XCTAssertEqual(viewModel.astronomyEventState, .idle)

        viewModel.ensureTonightDataLoaded()
        XCTAssertEqual(viewModel.observationPlanState, .loading)
        XCTAssertEqual(viewModel.astronomyEventState, .loading)
    }

    @MainActor
    func testViewModelDefaultsToCurrentTime() throws {
        let before = Date()
        let viewModel = SkyViewModel(catalog: try CatalogRepository())
        let after = Date()

        XCTAssertGreaterThanOrEqual(viewModel.moment.date, before)
        XCTAssertLessThanOrEqual(viewModel.moment.date, after)
        XCTAssertEqual(viewModel.snapshot.moment.date, viewModel.moment.date)
    }

    @MainActor
    func testApplicationLifecyclePausesMotionAndResetsToNowWhenActive() throws {
        let motion = TestMotionProvider()
        let viewModel = SkyViewModel(
            locationService: CoreLocationService(),
            motionService: motion,
            astronomy: AstronomyService(),
            catalog: try CatalogRepository()
        )
        viewModel.motionEnabled = true
        XCTAssertTrue(motion.isActive)

        viewModel.setDate(Date(timeIntervalSince1970: 1_000_000))
        viewModel.setApplicationActive(false)
        XCTAssertFalse(motion.isActive)

        viewModel.setApplicationActive(true)
        XCTAssertTrue(motion.isActive)
        XCTAssertEqual(viewModel.moment.date.timeIntervalSinceNow, 0, accuracy: 1)
    }

    @MainActor
    func testManualTimeSelectionClampsToSupportedRange() throws {
        let viewModel = SkyViewModel(catalog: try CatalogRepository())

        viewModel.setDate(viewModel.dateRange.upperBound.addingTimeInterval(86_400))
        XCTAssertEqual(viewModel.moment.date, viewModel.dateRange.upperBound)

        viewModel.setDate(viewModel.dateRange.lowerBound.addingTimeInterval(-86_400))
        XCTAssertEqual(viewModel.moment.date, viewModel.dateRange.lowerBound)
    }

    @MainActor
    func testViewModelManualTimeSelectionUsesSharedCore() async throws {
        let viewModel = try XCTUnwrap(SkyViewModel(catalog: try CatalogRepository()) as SkyViewModel?)
        let original = viewModel.moment.date
        viewModel.shiftTime(by: 3_600)
        await viewModel.waitForSnapshotUpdate()

        XCTAssertEqual(viewModel.moment.date.timeIntervalSince(original), 3_600, accuracy: 0.1)
        XCTAssertEqual(viewModel.snapshot.moment.date, viewModel.moment.date)
    }

    @MainActor
    func testLocationServiceFiltersLowAccuracySamples() async {
        let service = CoreLocationService()
        var received: [LocationSample] = []
        service.onLocationUpdate = { received.append($0) }
        let manager = CLLocationManager()
        let invalid = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.2, longitude: 121.4),
            altitude: 0,
            horizontalAccuracy: 100_000,
            verticalAccuracy: -1,
            timestamp: Date()
        )

        service.locationManager(manager, didUpdateLocations: [invalid])
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(received.isEmpty)

        let valid = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.2, longitude: 121.4),
            altitude: 4,
            horizontalAccuracy: 1_000,
            verticalAccuracy: -1,
            timestamp: Date()
        )
        service.locationManager(manager, didUpdateLocations: [valid])
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.latitude ?? 0, 31.2, accuracy: 0.000_1)
        XCTAssertEqual(received.first?.longitude ?? 0, 121.4, accuracy: 0.000_1)
    }

    func testCancelledPlannersReturnNoStaleResults() async throws {
        let catalog = try CatalogRepository()
        let moment = SkyMoment.now
        let plannerTask = Task {
            await ObservationPlanner().makePlan(
                for: moment,
                observer: .shanghai,
                candidates: catalog.allObjects,
                favoriteIDs: [],
                minimumAltitude: 10
            )
        }
        plannerTask.cancel()
        let plan = await plannerTask.value
        XCTAssertTrue(plan.recommendations.isEmpty)

        let eventTask = Task {
            await AstronomyEventPlanner().events(
                from: moment.date,
                through: moment.date.addingTimeInterval(120 * 24 * 3600),
                observer: .shanghai,
                objects: catalog.allObjects
            )
        }
        eventTask.cancel()
        let events = await eventTask.value
        XCTAssertTrue(events.isEmpty)
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
