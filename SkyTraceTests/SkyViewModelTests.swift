import UIKit
import XCTest
import SkyTraceCore
@testable import SkyTrace

@MainActor
final class SkyViewModelTests: XCTestCase {
    func testStarMapInstallsSingleAndDoubleTapRecognizers() {
        let scene = SkySceneView(
            snapshot: .empty,
            catalog: nil,
            camera: SkyCameraState(),
            selectedObjectID: nil,
            showConstellations: true,
            starScale: 1,
            labelMagnitudeLimit: 2.8,
            showCardinals: true,
            motionEnabled: false,
            motionReading: nil,
            isApplicationActive: true,
            renderEnvironment: SkyRenderEnvironment(),
            onCameraChange: { _ in },
            onTap: { _ in },
            onReset: {}
        )
        let coordinator = scene.makeCoordinator()
        let view = coordinator.controller.sceneView
        defer { coordinator.controller.shutdown() }
        let existingRecognizers = Set((view.gestureRecognizers ?? []).map(ObjectIdentifier.init))
        coordinator.installGestures(on: view)

        let tapCounts = (view.gestureRecognizers ?? [])
            .filter { !existingRecognizers.contains(ObjectIdentifier($0)) }
            .compactMap { ($0 as? UITapGestureRecognizer)?.numberOfTapsRequired }
        XCTAssertEqual(tapCounts.sorted(), [1, 2])
    }

    func testSnapshotContainsFullCatalogAndRecommendations() async throws {
        let viewModel = SkyViewModel()
        await viewModel.prepare()
        guard case .ready = viewModel.catalogState else {
            return XCTFail("Catalog failed to load")
        }

        XCTAssertEqual(viewModel.snapshot.positions.count, viewModel.repository?.allObjects.count)
        XCTAssertFalse(viewModel.snapshot.constellationSegments.isEmpty)
        XCTAssertLessThanOrEqual(viewModel.snapshot.recommendations.count, 6)
    }

    func testManualTimeSelectionUpdatesSnapshotMoment() async {
        let viewModel = SkyViewModel()
        await viewModel.prepare()
        let originalDate = viewModel.moment.date
        viewModel.shiftTime(by: 3_600)
        await viewModel.waitForSnapshotUpdate()

        XCTAssertEqual(viewModel.moment.date.timeIntervalSince(originalDate), 3_600, accuracy: 0.1)
        XCTAssertEqual(viewModel.snapshot.moment.date, viewModel.moment.date)
    }
}
