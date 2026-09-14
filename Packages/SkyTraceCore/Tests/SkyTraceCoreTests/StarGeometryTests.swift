import CoreGraphics
import SceneKit
import XCTest
@testable import SkyTraceCore

#if os(macOS)
import AppKit
import Metal
#endif

final class StarGeometryTests: XCTestCase {
    private let object = CelestialObject(
        id: "test-star",
        name: "测试星",
        englishName: "Test Star",
        designation: "HR 1",
        kind: .star,
        raDegrees: 0,
        decDegrees: 0,
        magnitude: -1,
        bvColorIndex: 0.2,
        detail: "",
        aliases: []
    )

    func testStarGeometryUsesOneQuadPerStar() {
        let position = SkyPosition(object: object, azimuth: 0, altitude: 0)
        let geometry = StarGeometryFactory.makeStars([position])

        XCTAssertEqual(geometry.sources(for: .vertex).first?.vectorCount, 4)
        XCTAssertEqual(geometry.sources(for: .color).first?.vectorCount, 4)
        XCTAssertEqual(geometry.sources(for: .texcoord).first?.vectorCount, 4)
        XCTAssertEqual(geometry.elements.count, 1)
        XCTAssertEqual(geometry.elements[0].primitiveType, .triangles)
        XCTAssertEqual(geometry.elements[0].primitiveCount, 2)
        XCTAssertEqual(geometry.materials.first?.blendMode, .alpha)
        XCTAssertEqual(geometry.materials.first?.transparencyMode, .aOne)
    }

    @MainActor
    func testSceneControllerDisablesBloomPostProcessing() {
        let controller = SkySceneController()
        XCTAssertFalse(controller.camera.wantsHDR)
        XCTAssertEqual(controller.camera.bloomIntensity, 0, accuracy: 0.001)
        XCTAssertEqual(controller.camera.bloomBlurRadius, 0, accuracy: 0.001)
    }

    func testGlowTextureIsTransparentAtCorners() throws {
        let texture = StarGeometryFactory.makeGlowTexture(size: 64)
        let providerData = try XCTUnwrap(texture.dataProvider?.data)
        let data = providerData as Data
        let bytesPerRow = texture.bytesPerRow

        func alpha(x: Int, y: Int) -> UInt8 {
            data[y * bytesPerRow + x * 4 + 3]
        }

        XCTAssertGreaterThan(alpha(x: 32, y: 32), 240)
        XCTAssertLessThan(alpha(x: 0, y: 0), 10)
        XCTAssertLessThan(alpha(x: 63, y: 0), 10)
        XCTAssertLessThan(alpha(x: 0, y: 63), 10)
        XCTAssertLessThan(alpha(x: 63, y: 63), 10)
    }

#if os(macOS)
    func testOffscreenRenderHasBrightCenterAndDarkCorners() throws {
        let scene = SCNScene()
        scene.background.contents = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let position = SkyPosition(object: object, azimuth: 0, altitude: 0)
        let geometry = StarGeometryFactory.makeStars([position], scale: 12)
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        let camera = SCNCamera()
        camera.fieldOfView = 70
        camera.zNear = 0.1
        camera.zFar = 500
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        let image = renderer.snapshot(
            atTime: 0,
            with: CGSize(width: 256, height: 256),
            antialiasingMode: .multisampling2X
        )
        let representation = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation!))

        let center = try XCTUnwrap(representation.colorAt(x: 128, y: 128))
        let squareCorner = try XCTUnwrap(representation.colorAt(x: 141, y: 141))
        XCTAssertGreaterThan(center.brightnessComponent, 0.75)
        XCTAssertGreaterThan(squareCorner.redComponent, 0.75)
        XCTAssertLessThan(squareCorner.greenComponent, 0.15)
        XCTAssertLessThan(squareCorner.blueComponent, 0.15)
    }
#endif
}
