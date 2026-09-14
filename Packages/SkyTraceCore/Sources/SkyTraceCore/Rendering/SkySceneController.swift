import CoreGraphics
import Foundation
import SceneKit
import simd
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
public final class SkySceneController {
    public let sceneView: SCNView
    public let cameraNode: SCNNode
    public let camera: SCNCamera

    private let starsNode: SCNNode
    private let linesNode: SCNNode
    private let horizonNode: SCNNode
    private let selectionNode: SCNNode
    private var geometryKey: GeometryKey?
    private var snapshot: SkySnapshot = .empty
    private var cameraState = SkyCameraState()
    private var selectedObjectID: String?

    public init(sceneView: SCNView = SCNView(frame: .zero)) {
        self.sceneView = sceneView
#if os(macOS)
        sceneView.backgroundColor = NSColor(red: 0.008, green: 0.024, blue: 0.055, alpha: 1)
#else
        sceneView.backgroundColor = UIColor(red: 0.008, green: 0.024, blue: 0.055, alpha: 1)
#endif
        sceneView.antialiasingMode = .multisampling2X
        sceneView.preferredFramesPerSecond = 60
        sceneView.rendersContinuously = false
        sceneView.autoenablesDefaultLighting = false
        sceneView.isPlaying = true

        let scene = SCNScene()
        scene.background.contents = CGColor(red: 0.008, green: 0.024, blue: 0.055, alpha: 1)
        sceneView.scene = scene

        cameraNode = SCNNode()
        camera = SCNCamera()
        camera.fieldOfView = 70
        camera.projectionDirection = .vertical
        camera.zNear = 0.1
        camera.zFar = 500
        camera.wantsHDR = false
        camera.bloomIntensity = 0
        camera.bloomThreshold = 1
        camera.bloomBlurRadius = 0
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        starsNode = SCNNode()
        starsNode.name = "starsNode"
        scene.rootNode.addChildNode(starsNode)

        linesNode = SCNNode()
        linesNode.name = "linesNode"
        scene.rootNode.addChildNode(linesNode)

        horizonNode = SCNNode(geometry: StarGeometryFactory.makeHorizon())
        linesNode.addChildNode(horizonNode)

        selectionNode = StarGeometryFactory.makeSelectionNode()
        selectionNode.isHidden = true
        scene.rootNode.addChildNode(selectionNode)
    }

    public func update(
        snapshot: SkySnapshot,
        showConstellations: Bool,
        starScale: CGFloat
    ) {
        self.snapshot = snapshot
        let key = GeometryKey(
            moment: snapshot.moment.date,
            observer: snapshot.observer,
            showConstellations: showConstellations,
            starScale: starScale
        )
        guard key != geometryKey else { return }
        geometryKey = key
        starsNode.geometry = StarGeometryFactory.makeStars(snapshot.positions, scale: starScale)
        linesNode.geometry = showConstellations
            ? StarGeometryFactory.makeConstellationLines(snapshot.constellationSegments)
            : nil
        horizonNode.isHidden = !showConstellations
        updateSelection()
    }

    public func updateCamera(_ state: SkyCameraState, selectedObjectID: String?) {
        cameraState = state
        self.selectedObjectID = selectedObjectID
        cameraNode.simdOrientation = simd_quatf(state.basis.orientationMatrix)
        camera.fieldOfView = CGFloat(state.fieldOfView)
        updateSelection()
    }

    public func pick(at point: CGPoint, in size: CGSize) -> String? {
        let projection = SkyProjection(camera: cameraState, size: size)
        return snapshot.positions.compactMap { position -> (String, CGFloat)? in
            guard let pointOnScreen = projection.screenPoint(for: position.horizontalVector) else { return nil }
            let distance = hypot(pointOnScreen.x - point.x, pointOnScreen.y - point.y)
            return distance <= 32 ? (position.id, distance) : nil
        }
        .min { $0.1 < $1.1 }?
        .0
    }

    public func orbit(horizontalDelta: Double, verticalDelta: Double, viewportSize: CGSize) {
        let horizontalScale = cameraState.fieldOfView / max(Double(viewportSize.width), 1)
        let verticalScale = cameraState.fieldOfView / max(Double(viewportSize.height), 1)
        cameraState.azimuth = Self.normalizedDegrees(cameraState.azimuth - horizontalDelta * horizontalScale)
        cameraState.altitude = min(89, max(-89, cameraState.altitude + verticalDelta * verticalScale))
        updateCamera(cameraState, selectedObjectID: selectedObjectID)
    }

    public func zoom(by scale: Double) {
        cameraState.fieldOfView = min(110, max(20, cameraState.fieldOfView / max(scale, 0.05)))
        updateCamera(cameraState, selectedObjectID: selectedObjectID)
    }

    public func rotate(by degrees: Double) {
        cameraState.roll = Self.normalizedDegrees(cameraState.roll + degrees)
        updateCamera(cameraState, selectedObjectID: selectedObjectID)
    }

    private func updateSelection() {
        selectionNode.removeAction(forKey: "pulse")
        guard
            let selectedObjectID,
            let position = snapshot.positions.first(where: { $0.id == selectedObjectID })
        else {
            selectionNode.isHidden = true
            return
        }
        let point = position.horizontalVector * (StarGeometryFactory.skyRadius * 0.98)
        selectionNode.position = SCNVector3(Float(point.x), Float(point.y), Float(point.z))
        selectionNode.isHidden = false
        selectionNode.runAction(
            SCNAction.repeatForever(
                SCNAction.sequence([
                    SCNAction.scale(to: 1.25, duration: 0.7),
                    SCNAction.scale(to: 0.92, duration: 0.7)
                ])
            ),
            forKey: "pulse"
        )
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}

private struct GeometryKey: Equatable {
    let moment: Date
    let observer: ObserverContext
    let showConstellations: Bool
    let starScale: CGFloat
}
