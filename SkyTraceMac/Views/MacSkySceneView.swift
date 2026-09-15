import AppKit
import SceneKit
import SkyTraceCore
import SwiftUI

struct MacSkySceneView: NSViewRepresentable {
    let snapshot: SkySnapshot
    let catalog: SkySceneCatalog?
    let camera: SkyCameraState
    let selectedObjectID: String?
    let showConstellations: Bool
    let starScale: Double
    let labelMagnitudeLimit: Double
    let showCardinals: Bool

    let onCameraChange: (SkyCameraState) -> Void
    let onSelect: (String?) -> Void
    let onReset: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MacInteractiveSceneView {
        let view = MacInteractiveSceneView(frame: .zero)
        let controller = SkySceneController(sceneView: view, catalog: catalog)
        context.coordinator.controller = controller
        view.onOrbit = { context.coordinator.orbit(horizontal: $0, vertical: $1) }
        view.onZoom = { context.coordinator.zoom(by: $0) }
        view.onRotate = { context.coordinator.rotate(by: $0) }
        view.onSelect = { point in context.coordinator.select(at: point) }
        view.onReset = { context.coordinator.parent.onReset() }
        view.onClear = { context.coordinator.parent.onSelect(nil) }
        view.onKeyboardMove = { horizontal, vertical, zoom in
            context.coordinator.nudge(horizontal: horizontal, vertical: vertical, zoom: zoom)
        }
        view.onInteractionEnd = { context.coordinator.finishInteraction() }
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
        private var cameraSyncTask: Task<Void, Never>?

        init(parent: MacSkySceneView) {
            self.parent = parent
        }

        func update() {
            controller.update(
                snapshot: parent.snapshot,
                showConstellations: parent.showConstellations,
                starScale: parent.starScale
            )
            controller.updateLabels(
                magnitudeLimit: parent.labelMagnitudeLimit,
                showCardinals: parent.showCardinals
            )
            if !controller.isUserInteracting {
                controller.updateCamera(parent.camera, selectedObjectID: parent.selectedObjectID, notify: false)
            } else {
                controller.updateCamera(
                    controller.currentCameraState,
                    selectedObjectID: parent.selectedObjectID,
                    notify: false
                )
            }
            controller.onCameraChange = parent.onCameraChange
        }

        func orbit(horizontal: Double, vertical: Double) {
            controller.orbit(
                horizontalDelta: horizontal,
                verticalDelta: vertical,
                viewportSize: controller.sceneView.bounds.size,
                notify: false
            )
            scheduleCameraSync()
        }

        func zoom(by scale: Double) {
            controller.zoom(by: scale, notify: false)
            scheduleCameraSync()
        }

        func rotate(by degrees: Double) {
            controller.rotate(by: degrees, notify: false)
            scheduleCameraSync()
        }

        func nudge(horizontal: Double, vertical: Double, zoom: Double) {
            controller.nudge(horizontal: horizontal, vertical: vertical, zoom: zoom, notify: false)
            scheduleCameraSync()
        }

        func select(at point: CGPoint) {
            parent.onSelect(controller.pick(at: point, in: controller.sceneView.bounds.size))
        }

        func finishInteraction() {
            controller.isUserInteracting = false
            cameraSyncTask?.cancel()
            parent.onCameraChange(controller.currentCameraState)
        }

        private func scheduleCameraSync() {
            controller.isUserInteracting = true
            cameraSyncTask?.cancel()
            cameraSyncTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled, let self else { return }
                self.controller.isUserInteracting = false
                self.parent.onCameraChange(self.controller.currentCameraState)
            }
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
    var onInteractionEnd: (() -> Void)?

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
        guard let point = mouseDownPoint else { return }
        if !didDrag {
            onSelect?(point)
        }
        mouseDownPoint = nil
        onInteractionEnd?()
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
