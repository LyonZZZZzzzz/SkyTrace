import AppKit
import SceneKit
import SkyTraceCore
import SwiftUI

struct MacSkySceneView: NSViewRepresentable {
    let snapshot: SkySnapshot
    let camera: SkyCameraState
    let selectedObjectID: String?
    let showConstellations: Bool
    let starScale: Double

    let onCameraChange: (SkyCameraState) -> Void
    let onSelect: (String?) -> Void
    let onReset: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MacInteractiveSceneView {
        let view = MacInteractiveSceneView(frame: .zero)
        context.coordinator.controller = SkySceneController(sceneView: view)
        view.onOrbit = { context.coordinator.orbit(horizontal: $0, vertical: $1) }
        view.onZoom = { context.coordinator.zoom(by: $0) }
        view.onRotate = { context.coordinator.rotate(by: $0) }
        view.onSelect = { point in context.coordinator.select(at: point) }
        view.onReset = { context.coordinator.parent.onReset() }
        view.onClear = { context.coordinator.parent.onSelect(nil) }
        view.onKeyboardMove = { horizontal, vertical, zoom in
            var state = context.coordinator.parent.camera
            state.azimuth += horizontal
            state.altitude += vertical
            state.fieldOfView += zoom
            context.coordinator.parent.onCameraChange(state)
        }
        context.coordinator.update()
        return view
    }

    func updateNSView(_ nsView: MacInteractiveSceneView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }

    @MainActor
    final class Coordinator {
        var parent: MacSkySceneView
        var controller: SkySceneController!

        init(parent: MacSkySceneView) {
            self.parent = parent
        }

        func update() {
            controller.update(
                snapshot: parent.snapshot,
                showConstellations: parent.showConstellations,
                starScale: CGFloat(parent.starScale)
            )
            controller.updateCamera(parent.camera, selectedObjectID: parent.selectedObjectID)
        }

        func orbit(horizontal: Double, vertical: Double) {
            var state = parent.camera
            let viewport = controller.sceneView.bounds.size
            let horizontalScale = state.fieldOfView / max(Double(viewport.width), 1)
            let verticalScale = state.fieldOfView / max(Double(viewport.height), 1)
            state.azimuth = Self.normalizedDegrees(state.azimuth - horizontal * horizontalScale)
            state.altitude = min(89, max(-89, state.altitude + vertical * verticalScale))
            parent.onCameraChange(state)
        }

        func zoom(by scale: Double) {
            var state = parent.camera
            state.fieldOfView = min(110, max(20, state.fieldOfView / max(scale, 0.05)))
            parent.onCameraChange(state)
        }

        func rotate(by degrees: Double) {
            var state = parent.camera
            state.roll = Self.normalizedDegrees(state.roll + degrees)
            parent.onCameraChange(state)
        }

        func select(at point: CGPoint) {
            parent.onSelect(controller.pick(at: point, in: controller.sceneView.bounds.size))
        }

        private static func normalizedDegrees(_ value: Double) -> Double {
            let result = value.truncatingRemainder(dividingBy: 360)
            return result < 0 ? result + 360 : result
        }
    }
}

final class MacInteractiveSceneView: SCNView {
    var onOrbit: ((Double, Double) -> Void)?
    var onZoom: ((Double) -> Void)?
    var onRotate: ((Double) -> Void)?
    var onSelect: ((CGPoint) -> Void)?
    var onClear: (() -> Void)?
    var onReset: (() -> Void)?
    var onKeyboardMove: ((Double, Double, Double) -> Void)?

    private var mouseDownPoint: CGPoint?
    private var didDrag = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
        if event.clickCount == 2 {
            onReset?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        onOrbit?(Double(event.deltaX) * 3, Double(-event.deltaY) * 3)
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag, let point = mouseDownPoint else { return }
        onSelect?(point)
        mouseDownPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            onZoom?(1 + Double(event.scrollingDeltaY) * 0.01)
        } else {
            onOrbit?(Double(event.scrollingDeltaX) * 2, Double(event.scrollingDeltaY) * 2)
        }
    }

    override func magnify(with event: NSEvent) {
        onZoom?(1 + Double(event.magnification))
    }

    override func rotate(with event: NSEvent) {
        onRotate?(Double(event.rotation) * 180 / .pi)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onKeyboardMove?(-5, 0, 0)
        case 124: onKeyboardMove?(5, 0, 0)
        case 125: onKeyboardMove?(0, -5, 0)
        case 126: onKeyboardMove?(0, 5, 0)
        case 51, 117: onClear?()
        default:
            if event.charactersIgnoringModifiers == "+" || event.charactersIgnoringModifiers == "=" {
                onKeyboardMove?(0, 0, -5)
            } else if event.charactersIgnoringModifiers == "-" {
                onKeyboardMove?(0, 0, 5)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
