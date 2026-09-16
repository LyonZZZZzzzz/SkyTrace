import SceneKit
import simd
import XCTest
@testable import SkyTraceCore

@MainActor
final class SceneControllerPerformanceTests: XCTestCase {
    private let observer = ObserverContext.shanghai
    private let startDate = Date(timeIntervalSince1970: 1_735_689_600)
    private let astronomy = AstronomyService()

    func testStaticGeometryIsBuiltOnceAcrossCameraAndSnapshotUpdates() {
        let catalog = makeCatalog()
        let controller = SkySceneController(catalog: catalog)

        controller.update(
            snapshot: makeSnapshot(date: startDate),
            showConstellations: true,
            starScale: 1
        )
        let initialBuildCount = controller.staticGeometryRebuildCount
        XCTAssertEqual(initialBuildCount, 1)

        controller.updateCamera(
            SkyCameraState(azimuth: 75, altitude: 20, roll: 12, fieldOfView: 55),
            selectedObjectID: "star-1"
        )
        controller.updateLabels(magnitudeLimit: 4.2, showCardinals: false)
        controller.orbit(
            horizontalDelta: 120,
            verticalDelta: 30,
            viewportSize: CGSize(width: 1_200, height: 800)
        )
        controller.update(
            snapshot: makeSnapshot(date: startDate.addingTimeInterval(7_200)),
            showConstellations: true,
            starScale: 1
        )

        XCTAssertEqual(controller.staticGeometryRebuildCount, initialBuildCount)

        controller.update(
            snapshot: makeSnapshot(date: startDate.addingTimeInterval(14_400)),
            showConstellations: true,
            starScale: 1.2
        )
        XCTAssertEqual(controller.staticGeometryRebuildCount, initialBuildCount + 1)
    }

    func testFirstSnapshotIsAppliedImmediately() {
        let catalog = makeCatalog()
        let controller = SkySceneController(catalog: catalog)
        let snapshot = makeSnapshot(date: startDate)

        controller.update(snapshot: snapshot, showConstellations: true, starScale: 1)

        let expected = astronomy.horizontalTransform(
            for: snapshot.moment,
            observer: snapshot.observer
        ).sceneMatrix
        XCTAssertLessThan(maxMatrixDifference(controller.debugCurrentSceneMatrix, expected), 0.000_01)
        XCTAssertEqual(controller.debugTransitionDuration, 0, accuracy: 0.000_1)
    }

    func testSnapshotTransitionIsContinuousAndEndsAtTarget() {
        let catalog = makeCatalog()
        let controller = SkySceneController(catalog: catalog)
        let first = makeSnapshot(date: startDate)
        let second = makeSnapshot(date: startDate.addingTimeInterval(12 * 3_600))

        controller.update(snapshot: first, showConstellations: true, starScale: 1)
        let before = controller.debugCurrentSceneMatrix
        controller.update(snapshot: second, showConstellations: true, starScale: 1)
        let start = controller.debugTransitionStartTime
        let duration = controller.debugTransitionDuration
        let expectedTarget = astronomy.horizontalTransform(
            for: second.moment,
            observer: second.observer
        ).sceneMatrix
        XCTAssertEqual(duration, 0.22, accuracy: 0.000_1)

        controller.debugAdvanceAnimation(to: start + duration * 0.5)
        let middle = controller.debugCurrentSceneMatrix
        XCTAssertGreaterThan(maxMatrixDifference(before, middle), 0.000_1)
        XCTAssertGreaterThan(maxMatrixDifference(middle, expectedTarget), 0.000_1)

        controller.debugAdvanceAnimation(to: start + duration + 0.01)
        XCTAssertLessThan(maxMatrixDifference(controller.debugCurrentSceneMatrix, expectedTarget), 0.000_1)
        XCTAssertNotNil(controller.debugCurrentDynamicVectors["sun"])
    }

    func testLifecyclePausesAndWakesRendering() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.debugRefreshContinuousRenderingMode()
        XCTAssertFalse(controller.debugRendersContinuously)

        controller.setApplicationActive(false, isVisible: false)
        XCTAssertFalse(controller.debugRendersContinuously)
        XCTAssertFalse(controller.debugSceneIsPlaying)
        XCTAssertFalse(controller.debugRenderingEnabled)

        controller.setApplicationActive(true, isVisible: true)
        controller.debugRefreshContinuousRenderingMode()
        XCTAssertFalse(controller.debugRendersContinuously)

        XCTAssertFalse(controller.debugRendersContinuously)
        XCTAssertFalse(controller.debugRenderingEnabled)

        controller.beginCameraInteraction()
        XCTAssertTrue(controller.debugRendersContinuously)
        controller.orbit(
            horizontalDelta: 80,
            verticalDelta: 20,
            viewportSize: CGSize(width: 1_200, height: 800),
            notify: false
        )
        controller.endCameraInteraction(
            horizontalVelocity: 0,
            verticalVelocity: 0,
            rollVelocity: 0,
            viewportSize: CGSize(width: 1_200, height: 800)
        )
        for frame in 0..<120 {
            controller.debugAdvanceAnimation(to: Double(frame) / 60)
        }
        controller.debugRefreshContinuousRenderingMode()
        XCTAssertFalse(controller.debugRendersContinuously)

        controller.setTimePlaybackActive(true)
        XCTAssertTrue(controller.debugRendersContinuously)
        controller.setTimePlaybackActive(false)
        controller.debugRefreshContinuousRenderingMode()
        XCTAssertFalse(controller.debugRendersContinuously)

        controller.update(
            snapshot: makeSnapshot(date: startDate),
            showConstellations: true,
            starScale: 1
        )
        controller.debugRefreshContinuousRenderingMode()
        controller.update(
            snapshot: makeSnapshot(date: startDate.addingTimeInterval(3_600)),
            showConstellations: true,
            starScale: 1
        )
        XCTAssertTrue(controller.debugRendersContinuously)
    }

    func testRenderPolicySwitchesBetweenIdleWarmAndInteraction() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.setApplicationActive(true, isVisible: true)
        controller.debugRefreshContinuousRenderingMode()

        XCTAssertEqual(controller.debugRenderPolicy, .idleWarm)
        XCTAssertTrue(controller.debugKeepAliveScheduled)

        controller.beginCameraInteraction()
        controller.debugRefreshContinuousRenderingMode()
        XCTAssertEqual(controller.debugRenderPolicy, .interactive)
        XCTAssertFalse(controller.debugKeepAliveScheduled)

        controller.endCameraInteraction(
            horizontalVelocity: 0,
            verticalVelocity: 0,
            rollVelocity: 0,
            viewportSize: CGSize(width: 1_000, height: 700)
        )
        controller.setApplicationActive(false, isVisible: false)
        XCTAssertEqual(controller.debugRenderPolicy, .suspended)
        XCTAssertFalse(controller.debugKeepAliveScheduled)
    }

    func testLabelProjectionCacheSkipsUnchangedFrames() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.sceneView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        controller.updateCamera(SkyCameraState(), selectedObjectID: nil)

        controller.debugRefreshLabels()
        let firstCount = controller.debugLabelProjectionRecomputeCount
        controller.debugRefreshLabels()

        XCTAssertEqual(controller.debugLabelProjectionRecomputeCount, firstCount)
    }

    func testUnchangedLabelSettingsDoNotRebuildLabelSources() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.updateLabels(magnitudeLimit: 4.2, showCardinals: true)
        let revision = controller.debugLabelSourceRevision

        controller.updateLabels(magnitudeLimit: 4.2, showCardinals: true)

        XCTAssertEqual(controller.debugLabelSourceRevision, revision)

        controller.updateLabels(magnitudeLimit: 4.4, showCardinals: true)
        XCTAssertGreaterThan(controller.debugLabelSourceRevision, revision)
    }

    func testLabelPriorityIsStableAcrossKindsAndMagnitudes() {
        let controller = SkySceneController(catalog: makeLabelPriorityCatalog())
        controller.updateCamera(SkyCameraState(), selectedObjectID: "star-a")
        controller.updateLabels(magnitudeLimit: 4.2, showCardinals: false)

        XCTAssertEqual(
            controller.debugLabelSourceObjectIDs,
            ["star-a", "sun", "moon", "planet", "constellation-test", "star-b", "deepsky-1"]
        )
    }

    func testOverlayProjectionMatchesSceneKitViewCoordinates() throws {
        let controller = SkySceneController(catalog: makeCatalog())
        let size = CGSize(width: 800, height: 600)
        controller.sceneView.frame = CGRect(origin: .zero, size: size)
        controller.sceneView.layoutSubtreeIfNeeded()

        let camera = SkyCameraState(azimuth: 137, altitude: 42, roll: 23, fieldOfView: 65)
        controller.updateCamera(camera, selectedObjectID: nil)
        let direction = camera.basis.forward
        controller.sceneView.sceneTime = 0
        _ = controller.sceneView.snapshot()

        let actual = try XCTUnwrap(
            controller.debugOverlayPoint(for: direction, renderer: controller.sceneView)
        )
        let expected = try XCTUnwrap(
            SkyProjection(camera: camera, size: size).screenPoint(for: direction)
        )
        XCTAssertEqual(actual.x, expected.x, accuracy: 1)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1)
    }

    private func makeCatalog() -> SkySceneCatalog {
        let star = makeObject(id: "star-1", kind: .star, ra: 35, dec: 12, magnitude: 1.2)
        let deepSky = makeObject(id: "deepsky-1", kind: .deepSky, ra: 210, dec: -25, magnitude: 4.4)
        let sun = makeObject(id: "sun", kind: .sun, ra: 0, dec: 0, magnitude: -26.7)
        let constellation = ConstellationRecord(
            id: "test",
            name: "测试座",
            englishName: "Testus",
            segments: [[[0, 0], [10, 2], [20, 5]]]
        )
        return SkySceneCatalog(
            objects: [star, deepSky, sun],
            constellations: [constellation]
        )
    }

    private func makeLabelPriorityCatalog() -> SkySceneCatalog {
        let selectedStar = makeObject(id: "star-a", kind: .star, ra: 35, dec: 12, magnitude: 2)
        let peerStar = makeObject(id: "star-b", kind: .star, ra: 36, dec: 12, magnitude: 2)
        let constellation = makeObject(
            id: "constellation-test",
            kind: .constellation,
            ra: 10,
            dec: 5,
            magnitude: nil
        )
        let deepSky = makeObject(id: "deepsky-1", kind: .deepSky, ra: 210, dec: -25, magnitude: 4.4)
        let sun = makeObject(id: "sun", kind: .sun, ra: 0, dec: 0, magnitude: -26.7)
        let moon = makeObject(id: "moon", kind: .moon, ra: 15, dec: 5, magnitude: -12.7)
        let planet = makeObject(id: "planet", kind: .planet, ra: 25, dec: 8, magnitude: -2)
        return SkySceneCatalog(
            objects: [deepSky, peerStar, constellation, planet, moon, sun, selectedStar],
            constellations: []
        )
    }

    private func makeSnapshot(date: Date) -> SkySnapshot {
        SkySnapshotBuilder.makeSnapshot(
            objects: makeCatalog().objects,
            constellations: [
                ConstellationRecord(
                    id: "test",
                    name: "测试座",
                    englishName: "Testus",
                    segments: [[[0, 0], [10, 2], [20, 5]]]
                )
            ],
            moment: SkyMoment(date: date),
            observer: observer,
            astronomy: astronomy
        )
    }

    private func makeObject(
        id: String,
        kind: CelestialKind,
        ra: Double,
        dec: Double,
        magnitude: Double?
    ) -> CelestialObject {
        CelestialObject(
            id: id,
            name: id,
            englishName: id,
            designation: id,
            kind: kind,
            raDegrees: ra,
            decDegrees: dec,
            magnitude: magnitude,
            bvColorIndex: kind == .star ? 0.4 : nil,
            detail: "",
            aliases: []
        )
    }

    private func maxMatrixDifference(_ lhs: simd_float3x3, _ rhs: simd_float3x3) -> Float {
        var maximum: Float = 0
        for column in 0..<3 {
            for row in 0..<3 {
                maximum = max(maximum, abs(lhs[column][row] - rhs[column][row]))
            }
        }
        return maximum
    }
}
