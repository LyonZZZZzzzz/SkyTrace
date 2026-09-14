import CoreGraphics
import SceneKit

public enum StarGeometryFactory {
    public static let skyRadius = 100.0

    public static func makeStars(_ positions: [SkyPosition], scale: CGFloat = 1) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var textureCoordinates: [CGPoint] = []
        var colors: [SCNVector4] = []
        var indices: [Int32] = []

        let vertexCount = positions.count * 4
        vertices.reserveCapacity(vertexCount)
        textureCoordinates.reserveCapacity(vertexCount)
        colors.reserveCapacity(vertexCount)
        indices.reserveCapacity(positions.count * 6)

        for (index, position) in positions.enumerated() {
            let direction = position.horizontalVector.normalized
            let center = direction * skyRadius
            let basis = tangentBasis(for: direction)
            let halfSize = starSize(for: position.object.magnitude) * Double(scale) * 0.5

            let bottomLeft = center + basis.right * -halfSize + basis.up * -halfSize
            let bottomRight = center + basis.right * halfSize + basis.up * -halfSize
            let topRight = center + basis.right * halfSize + basis.up * halfSize
            let topLeft = center + basis.right * -halfSize + basis.up * halfSize

            vertices.append(contentsOf: [
                SCNVector3(Float(bottomLeft.x), Float(bottomLeft.y), Float(bottomLeft.z)),
                SCNVector3(Float(bottomRight.x), Float(bottomRight.y), Float(bottomRight.z)),
                SCNVector3(Float(topRight.x), Float(topRight.y), Float(topRight.z)),
                SCNVector3(Float(topLeft.x), Float(topLeft.y), Float(topLeft.z))
            ])
            textureCoordinates.append(contentsOf: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 1, y: 0),
                CGPoint(x: 1, y: 1),
                CGPoint(x: 0, y: 1)
            ])

            let rgb = color(for: position.object.bvColorIndex ?? 0.65)
            let color = SCNVector4(rgb.x, rgb.y, rgb.z, 1)
            colors.append(contentsOf: [color, color, color, color])

            let base = Int32(index * 4)
            indices.append(contentsOf: [
                base,
                base + 1,
                base + 2,
                base,
                base + 2,
                base + 3
            ])
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                colorSource(colors),
                SCNGeometrySource(textureCoordinates: textureCoordinates)
            ],
            elements: [
                SCNGeometryElement(indices: indices, primitiveType: .triangles)
            ]
        )

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = makeGlowTexture()
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.isDoubleSided = true
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        geometry.materials = [material]
        geometry.name = "stars"
        return geometry
    }

    public static func makeConstellationLines(_ segments: [ConstellationSegment]) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        vertices.reserveCapacity(segments.count * 2)
        for segment in segments {
            let start = segment.start * (skyRadius * 0.995)
            let end = segment.end * (skyRadius * 0.995)
            vertices.append(SCNVector3(Float(start.x), Float(start.y), Float(start.z)))
            vertices.append(SCNVector3(Float(end.x), Float(end.y), Float(end.z)))
        }
        let indices = vertices.indices.map(Int32.init)
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .line)]
        )
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = CGColor(red: 0.28, green: 0.82, blue: 0.95, alpha: 0.34)
        material.emission.contents = CGColor(red: 0.10, green: 0.42, blue: 0.58, alpha: 0.25)
        material.writesToDepthBuffer = false
        material.blendMode = .add
        geometry.materials = [material]
        geometry.name = "constellations"
        return geometry
    }

    public static func makeHorizon() -> SCNGeometry {
        var vertices: [SCNVector3] = []
        let count = 240
        for index in 0..<count {
            let startAngle = Double(index) / Double(count) * 2 * .pi
            let endAngle = Double(index + 1) / Double(count) * 2 * .pi
            let start = Vector3D(x: cos(startAngle), y: 0, z: sin(startAngle)) * skyRadius
            let end = Vector3D(x: cos(endAngle), y: 0, z: sin(endAngle)) * skyRadius
            vertices.append(SCNVector3(Float(start.x), Float(start.y), Float(start.z)))
            vertices.append(SCNVector3(Float(end.x), Float(end.y), Float(end.z)))
        }
        let indices = vertices.indices.map(Int32.init)
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .line)]
        )
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = CGColor(red: 0.24, green: 0.72, blue: 0.91, alpha: 0.55)
        material.emission.contents = CGColor(red: 0.12, green: 0.43, blue: 0.62, alpha: 0.40)
        material.writesToDepthBuffer = false
        geometry.materials = [material]
        geometry.name = "horizon"
        return geometry
    }

    public static func makeSelectionNode() -> SCNNode {
        let sphere = SCNSphere(radius: 1.25)
        sphere.segmentCount = 16
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = CGColor(red: 1, green: 0.66, blue: 0.24, alpha: 1)
        material.emission.contents = CGColor(red: 1, green: 0.44, blue: 0.12, alpha: 1)
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere)
        node.name = "selection"
        node.renderingOrder = 50
        return node
    }

    public static func color(for bv: Double) -> SCNVector3 {
        let t = min(1, max(0, (bv + 0.4) / 2.4))
        let cold = (r: 0.72, g: 0.82, b: 1.0)
        let warm = (r: 1.0, g: 0.60, b: 0.30)
        return SCNVector3(
            Float(cold.r + (warm.r - cold.r) * t),
            Float(cold.g + (warm.g - cold.g) * t),
            Float(cold.b + (warm.b - cold.b) * t)
        )
    }

    static func starSize(for magnitude: Double?) -> Double {
        let magnitude = magnitude ?? 6.5
        return min(1.3, max(0.16, (6.8 - magnitude) * 0.18))
    }

    static func makeGlowTexture(size: Int = 64) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = size * 4
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))

        let colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            CGColor(red: 0.92, green: 0.96, blue: 1, alpha: 0.28),
            CGColor(red: 0.85, green: 0.92, blue: 1, alpha: 0)
        ] as CFArray
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors,
            locations: [0, 0.18, 0.52, 1]
        )!
        let center = CGPoint(x: Double(size) / 2, y: Double(size) / 2)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: Double(size) / 2,
            options: []
        )
        return context.makeImage()!
    }

    private static func tangentBasis(for direction: Vector3D) -> (right: Vector3D, up: Vector3D) {
        let reference = abs(direction.y) > 0.96
            ? Vector3D(x: 0, y: 0, z: 1)
            : Vector3D(x: 0, y: 1, z: 0)
        let right = Vector3D.cross(reference, direction).normalized
        let up = Vector3D.cross(direction, right).normalized
        return (right, up)
    }

    private static func colorSource(_ colors: [SCNVector4]) -> SCNGeometrySource {
        let data = colors.withUnsafeBytes { Data($0) }
        return SCNGeometrySource(
            data: data,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector4>.stride
        )
    }
}
