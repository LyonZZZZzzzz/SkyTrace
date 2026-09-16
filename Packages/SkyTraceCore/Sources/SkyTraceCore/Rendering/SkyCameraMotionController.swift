import Foundation
import simd

struct SkyCameraMotionSnapshot {
    let orientation: simd_quatf
    let basis: SkyCameraBasis
    let state: SkyCameraState
    let isMoving: Bool
}

/// Quaternion-based camera motion used by the render loop.
///
/// Gesture input updates a target orientation. The render loop follows that
/// target with exponential damping and can continue with angular velocity
/// after a gesture ends. Using quaternions avoids the gimbal flip that used to
/// occur near the zenith and allows continuous travel across either pole.
struct SkyCameraMotionController {
    private(set) var orientation: simd_quatf
    private(set) var targetOrientation: simd_quatf
    private(set) var fieldOfView: Double
    private(set) var targetFieldOfView: Double
    private(set) var isInteracting = false

    private var horizontalVelocity = 0.0
    private var verticalVelocity = 0.0
    private var rollVelocity = 0.0
    private var lastUpdateTime: TimeInterval?

    private let orientationTimeConstant = 0.060
    private let fieldOfViewTimeConstant = 0.075
    private let inertiaTimeConstant = 0.180
    private let minimumInertiaVelocity = 1.5
    private let maximumInertiaVelocity = 260.0

    init(state: SkyCameraState = SkyCameraState()) {
        let quaternion = state.basis.orientationQuaternion
        orientation = quaternion
        targetOrientation = quaternion
        fieldOfView = state.fieldOfView
        targetFieldOfView = state.fieldOfView
    }

    var basis: SkyCameraBasis {
        SkyCameraBasis(orientation: orientation)
    }

    var state: SkyCameraState {
        SkyCameraState(basis: basis, fieldOfView: fieldOfView)
    }

    var isMoving: Bool {
        if isInteracting {
            return true
        }
        if abs(horizontalVelocity) > 0.01 ||
            abs(verticalVelocity) > 0.01 ||
            abs(rollVelocity) > 0.01 {
            return true
        }
        return angularDistance(orientation, targetOrientation) > 0.02 ||
            abs(fieldOfView - targetFieldOfView) > 0.02
    }

    mutating func setImmediate(_ state: SkyCameraState) {
        let quaternion = state.basis.orientationQuaternion
        orientation = quaternion
        targetOrientation = quaternion
        fieldOfView = state.fieldOfView
        targetFieldOfView = state.fieldOfView
        horizontalVelocity = 0
        verticalVelocity = 0
        rollVelocity = 0
        isInteracting = false
        lastUpdateTime = nil
    }

    mutating func animate(to state: SkyCameraState) {
        targetOrientation = state.basis.orientationQuaternion
        targetFieldOfView = min(110, max(20, state.fieldOfView))
        horizontalVelocity = 0
        verticalVelocity = 0
        rollVelocity = 0
    }

    mutating func suspend() {
        isInteracting = false
        horizontalVelocity = 0
        verticalVelocity = 0
        rollVelocity = 0
        targetOrientation = orientation
        targetFieldOfView = fieldOfView
        lastUpdateTime = nil
    }

    mutating func beginInteraction() {
        isInteracting = true
        horizontalVelocity = 0
        verticalVelocity = 0
        rollVelocity = 0
        targetOrientation = orientation
        targetFieldOfView = fieldOfView
        lastUpdateTime = nil
    }

    mutating func rotate(
        horizontalDegrees: Double,
        verticalDegrees: Double,
        rollDegrees: Double
    ) {
        Self.applyRotation(
            horizontalDegrees: horizontalDegrees,
            verticalDegrees: verticalDegrees,
            rollDegrees: rollDegrees,
            to: &targetOrientation
        )
    }

    mutating func zoom(by scale: Double) {
        targetFieldOfView = min(110, max(20, targetFieldOfView / max(scale, 0.05)))
    }

    mutating func endInteraction(
        horizontalVelocity: Double,
        verticalVelocity: Double,
        rollVelocity: Double
    ) {
        isInteracting = false
        var velocity = SIMD3<Double>(
            horizontalVelocity,
            verticalVelocity,
            rollVelocity
        )
        let speed = simd_length(velocity)
        if speed > maximumInertiaVelocity {
            velocity *= maximumInertiaVelocity / speed
        }
        self.horizontalVelocity = velocity.x
        self.verticalVelocity = velocity.y
        self.rollVelocity = velocity.z
        lastUpdateTime = nil
    }

    mutating func update(at time: TimeInterval) -> SkyCameraMotionSnapshot {
        guard let lastUpdateTime else {
            self.lastUpdateTime = time
            return snapshot
        }
        let deltaTime = min(max(time - lastUpdateTime, 0), 1.0 / 20.0)
        self.lastUpdateTime = time

        if !isInteracting, deltaTime > 0 {
            if abs(horizontalVelocity) > minimumInertiaVelocity ||
                abs(verticalVelocity) > minimumInertiaVelocity ||
                abs(rollVelocity) > minimumInertiaVelocity {
                Self.applyRotation(
                    horizontalDegrees: horizontalVelocity * deltaTime,
                    verticalDegrees: verticalVelocity * deltaTime,
                    rollDegrees: rollVelocity * deltaTime,
                    to: &targetOrientation
                )
                let decay = exp(-deltaTime / inertiaTimeConstant)
                horizontalVelocity *= decay
                verticalVelocity *= decay
                rollVelocity *= decay
            } else {
                horizontalVelocity = 0
                verticalVelocity = 0
                rollVelocity = 0
            }
        }

        if deltaTime > 0 {
            let follow = 1 - exp(-deltaTime / orientationTimeConstant)
            orientation = simd_slerp(orientation, targetOrientation, Float(follow))
            let fovFollow = 1 - exp(-deltaTime / fieldOfViewTimeConstant)
            fieldOfView += (targetFieldOfView - fieldOfView) * fovFollow
        }

        if !isMoving {
            orientation = targetOrientation
            fieldOfView = targetFieldOfView
        }

        return snapshot
    }

    private var snapshot: SkyCameraMotionSnapshot {
        let currentBasis = basis
        return SkyCameraMotionSnapshot(
            orientation: orientation,
            basis: currentBasis,
            state: SkyCameraState(basis: currentBasis, fieldOfView: fieldOfView),
            isMoving: isMoving
        )
    }

    private static func applyRotation(
        horizontalDegrees: Double,
        verticalDegrees: Double,
        rollDegrees: Double,
        to orientation: inout simd_quatf
    ) {
        if horizontalDegrees != 0 {
            orientation = Self.applyingRotation(
                to: orientation,
                degrees: -horizontalDegrees,
                axis: SIMD3<Float>(0, 1, 0)
            )
        }

        if verticalDegrees != 0 {
            let right = orientation.act(SIMD3<Float>(1, 0, 0))
            orientation = Self.applyingRotation(
                to: orientation,
                degrees: verticalDegrees,
                axis: right
            )
        }

        if rollDegrees != 0 {
            let forward = orientation.act(SIMD3<Float>(0, 0, -1))
            orientation = Self.applyingRotation(
                to: orientation,
                degrees: -rollDegrees,
                axis: forward
            )
        }

        orientation = simd_normalize(orientation)
    }

    private static func applyingRotation(
        to orientation: simd_quatf,
        degrees: Double,
        axis: SIMD3<Float>
    ) -> simd_quatf {
        let length = simd_length(axis)
        guard length > 0.000_000_1 else { return orientation }
        let delta = simd_quatf(
            angle: Float(degrees * .pi / 180),
            axis: axis / length
        )
        return simd_normalize(delta * orientation)
    }

    private func angularDistance(_ lhs: simd_quatf, _ rhs: simd_quatf) -> Double {
        let dot = abs(simd_dot(simd_normalize(lhs), simd_normalize(rhs)))
        let clamped = min(1, max(-1, Double(dot)))
        return acos(clamped) * 180 / .pi
    }
}
