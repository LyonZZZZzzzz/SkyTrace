import simd
import XCTest
@testable import SkyTraceCore

final class CameraBasisTests: XCTestCase {
    func testBasisRemainsOrthonormalAcrossViewingDirections() {
        let azimuths = [0.0, 45, 90, 135, 180, 270, 315]
        let altitudes = [-60.0, 0, 35, 80]
        let rolls = [-45.0, 0, 45]

        for azimuth in azimuths {
            for altitude in altitudes {
                for roll in rolls {
                    let state = SkyCameraState(
                        azimuth: azimuth,
                        altitude: altitude,
                        roll: roll,
                        fieldOfView: 70
                    )
                    let basis = state.basis

                    XCTAssertEqual(basis.forward.length, 1, accuracy: 0.000_001)
                    XCTAssertEqual(basis.right.length, 1, accuracy: 0.000_001)
                    XCTAssertEqual(basis.up.length, 1, accuracy: 0.000_001)
                    XCTAssertEqual(Vector3D.dot(basis.forward, basis.right), 0, accuracy: 0.000_001)
                    XCTAssertEqual(Vector3D.dot(basis.forward, basis.up), 0, accuracy: 0.000_001)
                    XCTAssertEqual(Vector3D.dot(basis.right, basis.up), 0, accuracy: 0.000_001)

                    let backward = Vector3D.cross(basis.right, basis.up)
                    XCTAssertEqual(backward.x, -basis.forward.x, accuracy: 0.000_001)
                    XCTAssertEqual(backward.y, -basis.forward.y, accuracy: 0.000_001)
                    XCTAssertEqual(backward.z, -basis.forward.z, accuracy: 0.000_001)
                }
            }
        }
    }

    @MainActor
    func testSceneKitCameraOrientationMatchesSharedBasis() {
        let controller = SkySceneController()
        let state = SkyCameraState(azimuth: 137, altitude: 42, roll: 23, fieldOfView: 65)
        controller.updateCamera(state, selectedObjectID: nil)

        let orientation = controller.cameraNode.simdOrientation
        let actualRight = orientation.act(SIMD3<Float>(1, 0, 0))
        let actualUp = orientation.act(SIMD3<Float>(0, 1, 0))
        let actualBackward = orientation.act(SIMD3<Float>(0, 0, 1))
        let basis = state.basis

        XCTAssertLessThan(angle(actualRight, basis.right), 0.01)
        XCTAssertLessThan(angle(actualUp, basis.up), 0.01)
        XCTAssertLessThan(angle(actualBackward, basis.forward * -1), 0.01)
    }

    func testProjectionUsesSameCameraBasis() {
        let state = SkyCameraState(azimuth: 90, altitude: 35, roll: 17, fieldOfView: 60)
        let projection = SkyProjection(camera: state, size: CGSize(width: 1200, height: 800))
        let point = projection.screenPoint(for: state.basis.forward)

        XCTAssertEqual(point?.x ?? -1, 600, accuracy: 0.1)
        XCTAssertEqual(point?.y ?? -1, 400, accuracy: 0.1)
    }

    private func angle(_ lhs: SIMD3<Float>, _ rhs: Vector3D) -> Float {
        let right = SIMD3<Float>(Float(rhs.x), Float(rhs.y), Float(rhs.z))
        let cosine = max(-1, min(1, simd_dot(simd_normalize(lhs), simd_normalize(right))))
        return acos(cosine) * 180 / .pi
    }
}
