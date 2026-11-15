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
    let renderEnvironment: SkyRenderEnvironment

    let onCameraChange: (SkyCameraState) -> Void
    let onSelect: (String?) -> Void
    let onReset: () -> Void
    let onDiagnosticsChange: (SkyRenderDiagnostics) -> Void
    let onLabelReadinessChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleNSView(_ nsView: MacInteractiveSceneView, coordinator: Coordinator) {
        nsView.tearDown()
        coordinator.controller?.shutdown()
        coordinator.controller = nil
    }

    func makeNSView(context: Context) -> MacInteractiveSceneView {
        let view = MacInteractiveSceneView(frame: .zero)
        let controller = SkySceneController(
            sceneView: view,
            catalog: catalog,
            labelVisibilityMode: .alwaysVisible
        )
        context.coordinator.controller = controller
        controller.onDiagnosticsChange = { [weak coordinator = context.coordinator] diagnostics in
            coordinator?.parent.onDiagnosticsChange(diagnostics)
        }
        controller.onLabelReadinessChange = { [weak coordinator = context.coordinator] ready in
            coordinator?.parent.onLabelReadinessChange(ready)
        }
        view.onLifecycleChange = { [weak coordinator = context.coordinator] active, visible in
            coordinator?.setLifecycle(active: active, visible: visible)
        }
        view.onInteractionStart = { [weak coordinator = context.coordinator] in
            coordinator?.beginInteraction()
        }
        view.onOrbit = { [weak coordinator = context.coordinator] horizontal, vertical, _ in
            coordinator?.orbit(horizontal: horizontal, vertical: vertical)
        }
        view.onScrollOrbit = { [weak coordinator = context.coordinator] horizontal, vertical in
            coordinator?.scrollOrbit(horizontal: horizontal, vertical: vertical)
        }
        view.onZoom = { [weak coordinator = context.coordinator] in
            coordinator?.zoom(by: $0)
        }
        view.onRotate = { [weak coordinator = context.coordinator] in
            coordinator?.rotate(by: $0)
        }
        view.onInteractionEnd = { [weak coordinator = context.coordinator] horizontalVelocity, verticalVelocity in
            coordinator?.endInteraction(
                horizontalVelocity: horizontalVelocity,
                verticalVelocity: verticalVelocity
            )
        }
        view.onSelect = { [weak coordinator = context.coordinator] point in
            coordinator?.select(at: point)
        }
        view.onReset = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onReset()
        }
        view.onClear = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSelect(nil)
        }
        view.onKeyboardMove = { [weak coordinator = context.coordinator] horizontal, vertical, zoom in
            coordinator?.nudge(horizontal: horizontal, vertical: vertical, zoom: zoom)
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
            controller.updateRenderEnvironment(parent.renderEnvironment)
            controller.update(
                snapshot: parent.snapshot,
                showConstellations: parent.showConstellations,
                starScale: parent.starScale
            )
            controller.updateLabels(
                magnitudeLimit: parent.labelMagnitudeLimit,
                showCardinals: parent.showCardinals
            )
            controller.synchronizeCamera(
                parent.camera,
                selectedObjectID: parent.selectedObjectID
            )
            controller.onCameraChange = { [weak coordinator = self] state in
                coordinator?.parent.onCameraChange(state)
            }
            controller.onCameraSettled = { [weak coordinator = self] state in
                coordinator?.parent.onCameraChange(state)
            }
        }

        func setLifecycle(active: Bool, visible: Bool) {
            controller.setApplicationActive(active, isVisible: visible)
        }

        func beginInteraction() {
            controller.beginCameraInteraction()
        }

        func orbit(horizontal: Double, vertical: Double) {
            controller.orbit(
                horizontalDelta: horizontal,
                verticalDelta: vertical,
                viewportSize: controller.sceneView.bounds.size,
                notify: false
            )
        }

        func scrollOrbit(horizontal: Double, vertical: Double) {
            controller.orbit(
                horizontalDelta: horizontal,
                verticalDelta: vertical,
                viewportSize: controller.sceneView.bounds.size,
                notify: false
            )
        }

        func endInteraction(horizontalVelocity: Double, verticalVelocity: Double) {
            controller.endCameraInteraction(
                horizontalVelocity: horizontalVelocity,
                verticalVelocity: verticalVelocity,
                rollVelocity: 0,
                viewportSize: controller.sceneView.bounds.size
            )
        }

        func zoom(by scale: Double) {
            controller.zoom(by: scale, notify: false)
        }

        func rotate(by degrees: Double) {
            controller.rotate(by: degrees, notify: false)
        }

        func nudge(horizontal: Double, vertical: Double, zoom: Double) {
            controller.nudge(horizontal: horizontal, vertical: vertical, zoom: zoom, notify: false)
        }

        func select(at point: CGPoint) {
            parent.onSelect(controller.pick(at: point, in: controller.sceneView.bounds.size))
        }
    }
}

final class MacInteractiveSceneView: SCNView {
    var onLifecycleChange: ((Bool, Bool) -> Void)?
    var onInteractionStart: (() -> Void)?
    var onOrbit: ((Double, Double, TimeInterval) -> Void)?
    var onScrollOrbit: ((Double, Double) -> Void)?
    var onZoom: ((Double) -> Void)?
    var onRotate: ((Double) -> Void)?
    var onInteractionEnd: ((Double, Double) -> Void)?
    var onSelect: ((CGPoint) -> Void)?
    var onClear: (() -> Void)?
    var onReset: (() -> Void)?
    var onKeyboardMove: ((Double, Double, Double) -> Void)?

    private var mouseDownPoint: CGPoint?
    private var didDrag = false
    private var lastDragTimestamp: TimeInterval?
    private var lastHorizontalVelocity = 0.0
    private var lastVerticalVelocity = 0.0
    private nonisolated(unsafe) var lifecycleObservers: [NSObjectProtocol] = []

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll(keepingCapacity: true)

        guard let window else {
            onLifecycleChange?(false, false)
            return
        }
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.notifyLifecycleChange() }
            },
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.notifyLifecycleChange() }
            },
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.notifyLifecycleChange() }
            },
            center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.notifyLifecycleChange() }
            },
            center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.notifyLifecycleChange() }
            }
        ]
        notifyLifecycleChange()
    }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll(keepingCapacity: false)
    }

    func tearDown() {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll(keepingCapacity: false)
        onLifecycleChange = nil
        onInteractionStart = nil
        onOrbit = nil
        onScrollOrbit = nil
        onZoom = nil
        onRotate = nil
        onInteractionEnd = nil
        onSelect = nil
        onClear = nil
        onReset = nil
        onKeyboardMove = nil
    }

    private func notifyLifecycleChange() {
        let applicationActive = NSApp.isActive
        let windowVisible = window?.isVisible == true &&
            window?.isMiniaturized == false &&
            window?.occlusionState.contains(.visible) == true
        onLifecycleChange?(applicationActive, windowVisible)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
        lastDragTimestamp = nil
        lastHorizontalVelocity = 0
        lastVerticalVelocity = 0

        if event.clickCount == 2 {
            mouseDownPoint = nil
            onReset?()
        } else {
            onInteractionStart?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard mouseDownPoint != nil else { return }
        didDrag = true
        let horizontal = Double(event.deltaX) * 3
        let vertical = Double(-event.deltaY) * 3
        let timestamp = event.timestamp
        let deltaTime = lastDragTimestamp.map { max(timestamp - $0, 1.0 / 240.0) } ?? (1.0 / 60.0)
        lastDragTimestamp = timestamp
        lastHorizontalVelocity = horizontal / deltaTime
        lastVerticalVelocity = vertical / deltaTime
        onOrbit?(horizontal, vertical, deltaTime)
    }

    override func mouseUp(with event: NSEvent) {
        guard let point = mouseDownPoint else { return }
        if !didDrag {
            let skyPoint = CGPoint(
                x: point.x - bounds.minX,
                y: isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
            )
            onInteractionEnd?(0, 0)
            onSelect?(skyPoint)
        } else {
            onInteractionEnd?(lastHorizontalVelocity, lastVerticalVelocity)
        }
        mouseDownPoint = nil
        lastDragTimestamp = nil
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            onZoom?(1 + Double(event.scrollingDeltaY) * 0.01)
        } else {
            onScrollOrbit?(Double(event.scrollingDeltaX) * 2, Double(event.scrollingDeltaY) * 2)
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
