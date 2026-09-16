import SceneKit
import XCTest
@testable import SkyTraceCore

final class SkyCameraMotionTests: XCTestCase {
    func testBasisIsContinuousAcrossFormerZenithThreshold() {
        var previous: SkyCameraBasis?

        for altitude in stride(from: 80.0, through: 89.99, by: 0.01) {
            let basis = SkyCameraState(
                azimuth: 45,
                altitude: altitude,
                roll: 0,
                fieldOfView: 70
            ).basis

            if let previous {
                XCTAssertLessThan(angle(previous.forward, basis.forward), 0.05)
                XCTAssertLessThan(angle(previous.right, basis.right), 0.05)
                XCTAssertLessThan(angle(previous.up, basis.up), 0.05)
            }
            previous = basis
        }
    }

    func testExactPoleBasisIsStableAndOrthonormal() {
        for altitude in [-90.0, 90.0] {
            let state = SkyCameraState(azimuth: 137, altitude: altitude, roll: 23, fieldOfView: 70)
            let basis = state.basis
            XCTAssertEqual(basis.forward.length, 1, accuracy: 0.000_001)
            XCTAssertEqual(basis.right.length, 1, accuracy: 0.000_001)
            XCTAssertEqual(basis.up.length, 1, accuracy: 0.000_001)
            XCTAssertEqual(Vector3D.dot(basis.forward, basis.right), 0, accuracy: 0.000_001)
            XCTAssertEqual(Vector3D.dot(basis.forward, basis.up), 0, accuracy: 0.000_001)
            XCTAssertEqual(Vector3D.dot(basis.right, basis.up), 0, accuracy: 0.000_001)
        }
    }

    func testQuaternionMotionCrossesNorthPoleContinuously() {
        var motion = SkyCameraMotionController(
            state: SkyCameraState(azimuth: 0, altitude: 80, roll: 0, fieldOfView: 70)
        )
        motion.beginInteraction()
        var previous = motion.basis
        var maximumStep = 0.0
        var maximumForwardY = -1.0

        for frame in 0..<120 {
            motion.rotate(horizontalDegrees: 0, verticalDegrees: 0.25, rollDegrees: 0)
            let snapshot = motion.update(at: Double(frame) / 60)
            maximumStep = max(
                maximumStep,
                angle(previous.forward, snapshot.basis.forward),
                angle(previous.right, snapshot.basis.right),
                angle(previous.up, snapshot.basis.up)
            )
            maximumForwardY = max(maximumForwardY, snapshot.basis.forward.y)
            previous = snapshot.basis
        }

        XCTAssertLessThan(maximumStep, 0.5)
        XCTAssertGreaterThan(maximumForwardY, 0.999)
        XCTAssertGreaterThan(motion.basis.forward.z, 0.1)
    }

    func testAnimatedCameraApproachesTargetMonotonically() {
        var motion = SkyCameraMotionController()
        let target = SkyCameraState(azimuth: 60, altitude: 20, roll: 0, fieldOfView: 55)
        motion.animate(to: target)
        var errors: [Double] = []
        var previousTime = 0.0

        for frame in 0..<120 {
            let time = Double(frame) / 60
            if frame == 0 {
                _ = motion.update(at: previousTime)
            } else {
                let snapshot = motion.update(at: time)
                errors.append(angle(snapshot.basis.forward, target.basis.forward))
            }
            previousTime = time
        }

        XCTAssertTrue(zip(errors, errors.dropFirst()).allSatisfy { $1 <= $0 + 0.000_001 })
        XCTAssertLessThan(errors.last ?? .infinity, 0.05)
        XCTAssertFalse(motion.isMoving)
    }

    func testInertiaDecaysAndStopsWithinOneSecond() {
        var motion = SkyCameraMotionController()
        motion.beginInteraction()
        motion.rotate(horizontalDegrees: 0, verticalDegrees: 8, rollDegrees: 0)
        _ = motion.update(at: 0)
        let beforeRelease = motion.basis.forward
        motion.endInteraction(horizontalVelocity: 0, verticalVelocity: 220, rollVelocity: 0)

        var maximumStep = 0.0
        var previous = motion.basis
        for frame in 1...120 {
            let snapshot = motion.update(at: Double(frame) / 60)
            maximumStep = max(
                maximumStep,
                angle(previous.forward, snapshot.basis.forward),
                angle(previous.right, snapshot.basis.right),
                angle(previous.up, snapshot.basis.up)
            )
            previous = snapshot.basis
        }

        XCTAssertLessThan(maximumStep, 5)
        XCTAssertGreaterThan(angle(beforeRelease, motion.basis.forward), 1)
        XCTAssertFalse(motion.isMoving)
    }

    func testNewInteractionInterruptsInertia() {
        var motion = SkyCameraMotionController()
        motion.beginInteraction()
        motion.rotate(horizontalDegrees: 0, verticalDegrees: 10, rollDegrees: 0)
        _ = motion.update(at: 0)
        motion.endInteraction(horizontalVelocity: 0, verticalVelocity: 240, rollVelocity: 0)
        _ = motion.update(at: 1.0 / 60.0)
        motion.beginInteraction()
        let interrupted = motion.basis.forward

        for frame in 2...60 {
            _ = motion.update(at: Double(frame) / 60)
        }

        XCTAssertLessThan(angle(interrupted, motion.basis.forward), 0.01)
    }

    func testSuspendStopsInertiaAndResetsTimeBase() {
        var motion = SkyCameraMotionController()
        motion.beginInteraction()
        motion.rotate(horizontalDegrees: 0, verticalDegrees: 10, rollDegrees: 0)
        _ = motion.update(at: 0)
        motion.endInteraction(horizontalVelocity: 0, verticalVelocity: 240, rollVelocity: 0)
        _ = motion.update(at: 1.0 / 60.0)

        motion.suspend()
        let suspended = motion.basis.forward
        for frame in 2...120 {
            _ = motion.update(at: Double(frame) / 60)
        }

        XCTAssertLessThan(angle(suspended, motion.basis.forward), 0.000_1)
        XCTAssertFalse(motion.isMoving)
    }

    @MainActor
    func testMotionBasedProjectionMatchesSceneKitView() throws {
        let controller = SkySceneController()
        let size = CGSize(width: 800, height: 600)
        controller.sceneView.frame = CGRect(origin: .zero, size: size)
        controller.sceneView.layoutSubtreeIfNeeded()
        controller.beginCameraInteraction()
        controller.rotate(by: 15, notify: false)

        for frame in 0..<60 {
            controller.debugAdvanceAnimation(to: Double(frame) / 60)
        }
        controller.sceneView.sceneTime = 1
        _ = controller.sceneView.snapshot()

        let direction = controller.debugCurrentCameraBasis.forward
        let actual = try XCTUnwrap(
            controller.debugOverlayPoint(for: direction, renderer: controller.sceneView)
        )
        let expected = try XCTUnwrap(
            SkyProjection(
                camera: controller.currentCameraState,
                basis: controller.debugCurrentCameraBasis,
                size: size
            ).screenPoint(for: direction)
        )

        XCTAssertEqual(actual.x, expected.x, accuracy: 1)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1)
    }

    private func angle(_ lhs: Vector3D, _ rhs: Vector3D) -> Double {
        let dot = min(1, max(-1, Vector3D.dot(lhs.normalized, rhs.normalized)))
        return acos(dot) * 180 / .pi
    }
}
