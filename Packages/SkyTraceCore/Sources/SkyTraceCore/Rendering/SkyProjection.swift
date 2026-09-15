import CoreGraphics
import Foundation

public struct SkyProjection: Sendable {
    public let camera: SkyCameraState
    public let size: CGSize
    private let cameraBasis: SkyCameraBasis

    public init(
        camera: SkyCameraState,
        basis: SkyCameraBasis? = nil,
        size: CGSize
    ) {
        self.camera = camera
        self.cameraBasis = basis ?? camera.basis
        self.size = size
    }

    public func screenPoint(for direction: Vector3D) -> CGPoint? {
        let target = direction.normalized
        let basis = cameraBasis
        let forward = basis.forward
        let right = basis.right
        let up = basis.up

        let depth = Vector3D.dot(target, forward)
        guard depth > 0.02 else { return nil }

        let aspect = max(size.width / max(size.height, 1), 0.1)
        let tangent = tan(camera.fieldOfView * .pi / 360)
        let xNDC = Vector3D.dot(target, right) / depth / tangent / aspect
        let yNDC = Vector3D.dot(target, up) / depth / tangent
        guard abs(xNDC) <= 1.25, abs(yNDC) <= 1.25 else { return nil }

        return CGPoint(
            x: (xNDC + 1) * size.width / 2,
            y: (1 - yNDC) * size.height / 2
        )
    }
}
