import AstronomyEngine
import simd

public extension HorizontalTransform {
    /// Rotation from J2000 right-handed equatorial coordinates into the
    /// SceneKit convention used by SkyTrace: x=east, y=up, z=south.
    var sceneMatrix: simd_float3x3 {
        let m = matrixElements
        let row0 = SIMD3<Float>(Float(-m[3]), Float(-m[4]), Float(-m[5]))
        let row1 = SIMD3<Float>(Float(m[6]), Float(m[7]), Float(m[8]))
        let row2 = SIMD3<Float>(Float(-m[0]), Float(-m[1]), Float(-m[2]))
        return simd_float3x3(
            columns: (
                SIMD3<Float>(row0.x, row1.x, row2.x),
                SIMD3<Float>(row0.y, row1.y, row2.y),
                SIMD3<Float>(row0.z, row1.z, row2.z)
            )
        )
    }

    func sceneVector(x: Double, y: Double, z: Double) -> Vector3D {
        let m = matrixElements
        let hx = m[0] * x + m[1] * y + m[2] * z
        let hy = m[3] * x + m[4] * y + m[5] * z
        let hz = m[6] * x + m[7] * y + m[8] * z
        return Vector3D(x: -hy, y: hz, z: -hx).normalized
    }
}
