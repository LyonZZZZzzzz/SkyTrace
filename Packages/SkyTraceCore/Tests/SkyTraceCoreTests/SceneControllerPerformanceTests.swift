import SceneKit
import simd
import XCTest
@testable import SkyTraceCore

@MainActor
final class SceneControllerPerformanceTests: XCTestCase {
    private let observer = ObserverContext.shanghai
    private let startDate = Date(timeIntervalSince1970: 1_735_689_600)
    private let astronomy = AstronomyService()

    func testStaticGeometryIsBuiltOnceAcrossCameraAndSnapshotUpdates() async {
        let catalog = makeCatalog()
        let controller = SkySceneController(catalog: catalog)

        controller.update(
            snapshot: makeSnapshot(date: startDate),
            showConstellations: true,
            starScale: 1
        )
        await controller.debugWaitForStaticGeometry()
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
        await controller.debugWaitForStaticGeometry()
        XCTAssertEqual(controller.staticGeometryRebuildCount, initialBuildCount + 1)
    }

    func testRevertingStarScaleCancelsPendingGeometryReplacement() async {
        let controller = SkySceneController(catalog: makeCatalog())
        let snapshot = makeSnapshot(date: startDate)
        controller.update(snapshot: snapshot, showConstellations: true, starScale: 1)
        await controller.debugWaitForStaticGeometry()

        controller.update(snapshot: snapshot, showConstellations: true, starScale: 1.2)
        controller.update(snapshot: snapshot, showConstellations: true, starScale: 1)
        await controller.debugWaitForStaticGeometry()
        XCTAssertEqual(controller.staticGeometryRebuildCount, 1)

        controller.update(snapshot: snapshot, showConstellations: true, starScale: 1.2)
        await controller.debugWaitForStaticGeometry()
        XCTAssertEqual(controller.staticGeometryRebuildCount, 2)
    }

    func testResumingRestartsPendingSnapshotTransition() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.update(snapshot: makeSnapshot(date: startDate), showConstellations: true, starScale: 1)
        controller.setApplicationActive(false, isVisible: false)
        let nextSnapshot = makeSnapshot(date: startDate.addingTimeInterval(3_600))
        controller.update(snapshot: nextSnapshot, showConstellations: true, starScale: 1)

        controller.setApplicationActive(true, isVisible: true)
        XCTAssertEqual(controller.debugRenderPolicy, .animating)
        XCTAssertTrue(controller.debugRendersContinuously)
    }

    func testMotionReadingStartsContinuousRenderingFromIdle() {
        let controller = SkySceneController()
        let reading = SkyMotionReading(azimuth: 30, altitude: 20, roll: 0)
        controller.debugRefreshContinuousRenderingMode()
        XCTAssertEqual(controller.debugRenderPolicy, .idleWarm)

        controller.setMotionReading(reading)
        XCTAssertEqual(controller.debugRenderPolicy, .animating)
        XCTAssertTrue(controller.debugRendersContinuously)

        controller.setMotionReading(nil)
        XCTAssertEqual(controller.debugRenderPolicy, .idleWarm)
        XCTAssertFalse(controller.debugRendersContinuously)

        controller.setApplicationActive(false, isVisible: false)
        controller.setMotionReading(reading)
        controller.setApplicationActive(true, isVisible: true)
        XCTAssertEqual(controller.debugRenderPolicy, .idleWarm)
        XCTAssertFalse(controller.debugRendersContinuously)
    }

    func testSelectionUpdatesWhenCameraStateHasNotChanged() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.update(snapshot: makeSnapshot(date: startDate), showConstellations: true, starScale: 1)
        let camera = controller.currentCameraState
        let sourceRevision = controller.debugLabelSourceRevision
        controller.synchronizeCamera(camera, selectedObjectID: "star-1")
        XCTAssertEqual(controller.debugLabelSourceRevision, sourceRevision + 1)
    }

    func testFirstSnapshotIsAppliedImmediately() async {
        let catalog = makeCatalog()
        let controller = SkySceneController(catalog: catalog)
        let snapshot = makeSnapshot(date: startDate)

        controller.update(snapshot: snapshot, showConstellations: true, starScale: 1)
        await controller.debugWaitForStaticGeometry()

        let expected = astronomy.horizontalTransform(
            for: snapshot.moment,
            observer: snapshot.observer
        ).sceneMatrix
        XCTAssertLessThan(maxMatrixDifference(controller.debugCurrentSceneMatrix, expected), 0.000_01)
        XCTAssertEqual(controller.debugTransitionDuration, 0, accuracy: 0.000_1)
    }

    func testSnapshotTransitionIsContinuousAndEndsAtTarget() async {
        let catalog = makeCatalog()
        let controller = SkySceneController(catalog: catalog)
        let first = makeSnapshot(date: startDate)
        let second = makeSnapshot(date: startDate.addingTimeInterval(12 * 3_600))

        controller.update(snapshot: first, showConstellations: true, starScale: 1)
        await controller.debugWaitForStaticGeometry()
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

    func testRemovedSolarSystemObjectClearsAtTransitionEnd() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.update(snapshot: makeSnapshot(date: startDate), showConstellations: true, starScale: 1)
        XCTAssertNotNil(controller.debugCurrentDynamicVectors["sun"])

        let empty = SkySnapshot(
            observer: observer,
            moment: SkyMoment(date: startDate.addingTimeInterval(3_600)),
            positions: [],
            constellationSegments: [],
            recommendations: []
        )
        controller.update(snapshot: empty, showConstellations: true, starScale: 1)
        let start = controller.debugTransitionStartTime
        let duration = controller.debugTransitionDuration
        controller.debugAdvanceAnimation(to: start + duration * 0.5)
        XCTAssertNotNil(controller.debugCurrentDynamicVectors["sun"])
        controller.debugAdvanceAnimation(to: start + duration + 0.01)
        XCTAssertNil(controller.debugCurrentDynamicVectors["sun"])
    }

    func testLifecyclePausesAndWakesRendering() async {
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

        controller.update(
            snapshot: makeSnapshot(date: startDate),
            showConstellations: true,
            starScale: 1
        )
        await controller.debugWaitForStaticGeometry()
        controller.debugRefreshContinuousRenderingMode()
        controller.update(
            snapshot: makeSnapshot(date: startDate.addingTimeInterval(3_600)),
            showConstellations: true,
            starScale: 1
        )
        await controller.debugWaitForStaticGeometry()
        XCTAssertTrue(controller.debugRendersContinuously)
    }

    func testRenderPolicySwitchesBetweenIdleWarmAndInteraction() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.setApplicationActive(true, isVisible: true)
        controller.debugRefreshContinuousRenderingMode()

        XCTAssertEqual(controller.debugRenderPolicy, .idleWarm)
        XCTAssertFalse(controller.debugRendersContinuously)
        XCTAssertFalse(controller.debugRenderingEnabled)

        controller.beginCameraInteraction()
        controller.debugRefreshContinuousRenderingMode()
        XCTAssertEqual(controller.debugRenderPolicy, .interactive)
        XCTAssertTrue(controller.debugRendersContinuously)

        controller.endCameraInteraction(
            horizontalVelocity: 0,
            verticalVelocity: 0,
            rollVelocity: 0,
            viewportSize: CGSize(width: 1_000, height: 700)
        )
        controller.setApplicationActive(false, isVisible: false)
        XCTAssertEqual(controller.debugRenderPolicy, .suspended)
        XCTAssertFalse(controller.debugRendersContinuously)
    }

    func testIdleWakeupsDoNotPolluteFrameMetrics() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.setApplicationActive(true, isVisible: true)
        controller.debugRefreshContinuousRenderingMode()

        controller.debugSimulateFrame(at: 10)
        controller.debugSimulateFrame(at: 10.5)

        XCTAssertEqual(controller.metrics.sampleWindowCount, 0)
        XCTAssertEqual(controller.metrics.p95FrameInterval, 0, accuracy: 0.000_1)
    }

    func testInteractionProfileHidesFaintStarsAndLimitsLabelsWithoutRebuild() async {
        let catalog = makeInteractionCatalog()
        let controller = SkySceneController(catalog: catalog)
        controller.sceneView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        controller.setApplicationActive(true, isVisible: true)
        controller.update(
            snapshot: makeSnapshot(date: startDate),
            showConstellations: true,
            starScale: 1
        )
        await controller.debugWaitForStaticGeometry()
        controller.updateCamera(
            SkyCameraState(fieldOfView: 110),
            selectedObjectID: nil
        )
        controller.debugRefreshLabels()

        let rebuildCount = controller.staticGeometryRebuildCount
        let brightNode = controller.debugCelestialRootNode.childNode(
            withName: "starsNode",
            recursively: false
        )
        let faintNode = controller.debugCelestialRootNode.childNode(
            withName: "faintStarsNode",
            recursively: false
        )
        XCTAssertEqual(brightNode?.geometry?.sources(for: .vertex).first?.vectorCount, 8)
        XCTAssertEqual(faintNode?.geometry?.sources(for: .vertex).first?.vectorCount, 4)
        XCTAssertFalse(controller.debugFaintStarsIsHidden)

        controller.beginCameraInteraction()

        XCTAssertTrue(controller.debugFaintStarsIsHidden)
        XCTAssertEqual(controller.debugLabelCapacity, 50)
        XCTAssertEqual(controller.debugInteractionRenderProfile.labelCapacityLimit, 50)

        controller.endCameraInteraction(
            horizontalVelocity: 0,
            verticalVelocity: 0,
            rollVelocity: 0,
            viewportSize: CGSize(width: 800, height: 600)
        )

        XCTAssertFalse(controller.debugFaintStarsIsHidden)
        XCTAssertGreaterThan(controller.debugLabelCapacity, 50)
        XCTAssertEqual(controller.debugInteractionRenderProfile, .full)
        XCTAssertEqual(controller.staticGeometryRebuildCount, rebuildCount)
    }

    func testPendingLabelTexturesKeepRenderingUntilWarmupCompletes() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.sceneView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        controller.setApplicationActive(true, isVisible: true)
        controller.updateLabels(magnitudeLimit: 4.2, showCardinals: false)
        controller.debugRefreshContinuousRenderingMode()

        XCTAssertTrue(controller.debugHasPendingLabelTextUpdates)
        XCTAssertTrue(controller.debugRendersContinuously)
        XCTAssertTrue(controller.debugRenderingEnabled)

        for _ in 0..<4 {
            controller.debugRefreshLabels()
        }
        controller.debugRefreshContinuousRenderingMode()

        XCTAssertFalse(controller.debugHasPendingLabelTextUpdates)
        XCTAssertFalse(controller.debugRendersContinuously)
        XCTAssertFalse(controller.debugRenderingEnabled)
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

    func testOverlayProjectionMatchesSceneKitViewCoordinatesAcrossFieldOfView() throws {
        let controller = SkySceneController(catalog: makeCatalog())
        let size = CGSize(width: 800, height: 600)
        controller.sceneView.frame = CGRect(origin: .zero, size: size)
        controller.sceneView.layoutSubtreeIfNeeded()

        for fieldOfView in [20.0, 55, 70, 110] {
            let camera = SkyCameraState(
                azimuth: 137,
                altitude: 42,
                roll: 23,
                fieldOfView: fieldOfView
            )
            controller.updateCamera(camera, selectedObjectID: nil)
            let direction = (camera.basis.forward + camera.basis.right * 0.06).normalized
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
    }

    func testRenderAdaptationAppliesAndRestoresQuality() {
        let controller = SkySceneController(catalog: makeCatalog())

        controller.updateRenderEnvironment(SkyRenderEnvironment())
        XCTAssertEqual(controller.debugRenderAdaptationProfile, .normal)
        XCTAssertEqual(controller.sceneView.preferredFramesPerSecond, 60)

        controller.updateRenderEnvironment(SkyRenderEnvironment(thermalState: .serious))
        XCTAssertEqual(controller.debugRenderAdaptationProfile, .elevated)
        XCTAssertEqual(controller.sceneView.preferredFramesPerSecond, 30)
        XCTAssertEqual(controller.debugLabelCapacity, 80)
        XCTAssertFalse(controller.debugFaintStarsIsHidden)

        controller.updateRenderEnvironment(SkyRenderEnvironment(thermalState: .critical))
        XCTAssertEqual(controller.debugRenderAdaptationProfile, .critical)
        XCTAssertEqual(controller.debugLabelCapacity, 50)
        XCTAssertTrue(controller.debugFaintStarsIsHidden)
        XCTAssertEqual(controller.sceneView.antialiasingMode, .none)

        controller.updateRenderEnvironment(SkyRenderEnvironment())
        XCTAssertEqual(controller.debugRenderAdaptationProfile, .normal)
        XCTAssertEqual(controller.sceneView.antialiasingMode, .multisampling2X)
        XCTAssertFalse(controller.debugFaintStarsIsHidden)

        controller.updateRenderEnvironment(
            SkyRenderEnvironment(memoryPressure: .warning, revision: 1)
        )
        XCTAssertEqual(controller.debugRenderAdaptationProfile, .critical)
        controller.shutdown()
    }

    func testShutdownReleasesRenderingDelegateAndOverlay() {
        let controller = SkySceneController(catalog: makeCatalog())
        controller.setApplicationActive(true, isVisible: true)
        controller.onCameraChange = { _ in }
        controller.onCameraSettled = { _ in }

        controller.shutdown()

        XCTAssertFalse(controller.debugRenderingEnabled)
        XCTAssertNil(controller.sceneView.delegate)
        XCTAssertNil(controller.sceneView.overlaySKScene)
        XCTAssertFalse(controller.sceneView.rendersContinuously)
        XCTAssertFalse(controller.sceneView.isPlaying)
    }

    func testAlwaysVisibleLabelsIgnoreFieldOfViewInteractionAndPressureProfiles() {
        let catalog = makeDenseLabelCatalog(count: 150)
        let controller = SkySceneController(
            catalog: catalog,
            labelVisibilityMode: .alwaysVisible
        )
        controller.sceneView.frame = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        controller.setApplicationActive(true, isVisible: true)
        controller.updateCamera(
            SkyCameraState(fieldOfView: 110),
            selectedObjectID: nil
        )
        controller.updateLabels(magnitudeLimit: 10, showCardinals: false)
        for _ in 0..<24 {
            controller.debugRefreshLabels()
        }

        let expectedCount = controller.debugLabelSourceObjectIDs.count
        XCTAssertEqual(expectedCount, 150)
        XCTAssertEqual(controller.debugLabelCapacity, expectedCount)
        XCTAssertEqual(controller.debugLabelNodeCount, expectedCount)
        XCTAssertFalse(controller.debugDisplayedObjectIDs.isEmpty)

        controller.beginCameraInteraction()
        controller.updateRenderEnvironment(
            SkyRenderEnvironment(
                thermalState: .critical,
                isLowPowerModeEnabled: true,
                memoryPressure: .warning,
                revision: 1
            )
        )
        for _ in 0..<2 {
            controller.debugRefreshLabels()
        }

        XCTAssertEqual(controller.debugLabelCapacity, expectedCount)
        XCTAssertEqual(controller.debugLabelNodeCount, expectedCount)
        XCTAssertEqual(controller.debugLabelSourceObjectIDs.count, expectedCount)
        XCTAssertFalse(controller.debugDisplayedObjectIDs.isEmpty)
        controller.shutdown()
    }

    func testAlwaysVisibleLabelPoolIsBoundedAcrossSnapshotUpdates() async {
        let catalog = makeDenseLabelCatalog(count: 200)
        let controller = SkySceneController(
            catalog: catalog,
            labelVisibilityMode: .alwaysVisible
        )
        controller.sceneView.frame = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        controller.setApplicationActive(true, isVisible: true)
        controller.updateLabels(magnitudeLimit: 10, showCardinals: true)
        controller.update(
            snapshot: makeSnapshot(date: startDate),
            showConstellations: true,
            starScale: 1
        )
        await controller.debugWaitForStaticGeometry()
        for _ in 0..<30 {
            controller.debugRefreshLabels()
        }

        let nodeCount = controller.debugLabelNodeCount
        let rebuildCount = controller.staticGeometryRebuildCount
        let snapshots = (0..<40).map { index in
            makeSnapshot(date: startDate.addingTimeInterval(Double(index) * 60))
        }

        for index in 0..<400 {
            controller.update(
                snapshot: snapshots[index % snapshots.count],
                showConstellations: true,
                starScale: 1
            )
            if index.isMultiple(of: 20) {
                controller.debugRefreshLabels()
            }
        }

        XCTAssertEqual(controller.debugLabelNodeCount, nodeCount)
        XCTAssertEqual(controller.staticGeometryRebuildCount, rebuildCount)
        XCTAssertFalse(controller.debugDisplayedObjectIDs.isEmpty)
        controller.shutdown()
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

    private func makeDenseLabelCatalog(count: Int) -> SkySceneCatalog {
        let stars = (0..<count).map { index in
            makeObject(
                id: "star-\(index)",
                kind: .star,
                ra: Double(index % 360),
                dec: Double((index * 37) % 121) - 60,
                magnitude: Double(index % 9) * 0.5 + 1
            )
        }
        return SkySceneCatalog(objects: stars, constellations: [])
    }

    private func makeInteractionCatalog() -> SkySceneCatalog {
        let brightStar = makeObject(id: "bright-star", kind: .star, ra: 35, dec: 12, magnitude: 2)
        let faintStar = makeObject(id: "faint-star", kind: .star, ra: 36, dec: 12, magnitude: 6)
        let deepSky = makeObject(id: "deepsky-1", kind: .deepSky, ra: 210, dec: -25, magnitude: 4.4)
        return SkySceneCatalog(objects: [brightStar, faintStar, deepSky], constellations: [])
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
