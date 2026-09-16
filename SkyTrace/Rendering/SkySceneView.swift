import SceneKit
import SkyTraceCore
import SwiftUI
import UIKit

struct SkySceneView: UIViewRepresentable {
    let snapshot: SkySnapshot
    let catalog: SkySceneCatalog?
    let camera: SkyCameraState
    let selectedObjectID: String?
    let showConstellations: Bool
    let starScale: Double
    let labelMagnitudeLimit: Double
    let showCardinals: Bool
    let motionEnabled: Bool
    let motionReading: SkyMotionReading?
    let isApplicationActive: Bool
    let isTimePlaybackActive: Bool

    let onCameraChange: (SkyCameraState) -> Void
    let onTap: (String?) -> Void
    let onReset: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = context.coordinator.controller.sceneView
        context.coordinator.installGestures(on: view)
        context.coordinator.update()
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SkySceneView
        var controller: SkySceneController!
        private var lastPanTranslation = CGPoint.zero
        private var lastPinchScale = 1.0
        private var lastRotation = 0.0

        init(parent: SkySceneView) {
            self.parent = parent
            controller = SkySceneController(catalog: parent.catalog)
        }

        func update() {
            controller.setApplicationActive(parent.isApplicationActive, isVisible: true)
            controller.setTimePlaybackActive(parent.isTimePlaybackActive)
            controller.update(
                snapshot: parent.snapshot,
                showConstellations: parent.showConstellations,
                starScale: parent.starScale
            )
            controller.updateLabels(
                magnitudeLimit: parent.labelMagnitudeLimit,
                showCardinals: parent.showCardinals
            )
            controller.setMotionReading(
                parent.motionEnabled && !controller.isUserInteracting ? parent.motionReading : nil
            )
            controller.synchronizeCamera(
                parent.camera,
                selectedObjectID: parent.selectedObjectID
            )
            controller.onCameraChange = parent.onCameraChange
            controller.onCameraSettled = parent.onCameraChange
        }

        func installGestures(on view: SCNView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            view.addGestureRecognizer(pinch)

            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            view.addGestureRecognizer(rotation)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            view.addGestureRecognizer(tap)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            tap.require(toFail: doubleTap)
            view.addGestureRecognizer(doubleTap)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .began:
                controller.setMotionReading(nil)
                controller.beginCameraInteraction()
                lastPanTranslation = .zero
            case .changed:
                let translation = gesture.translation(in: view)
                let delta = CGPoint(
                    x: translation.x - lastPanTranslation.x,
                    y: translation.y - lastPanTranslation.y
                )
                lastPanTranslation = translation
                controller.orbit(
                    horizontalDelta: Double(delta.x),
                    verticalDelta: Double(delta.y),
                    viewportSize: view.bounds.size,
                    notify: false
                )
            case .ended:
                let velocity = gesture.velocity(in: view)
                controller.endCameraInteraction(
                    horizontalVelocity: Double(velocity.x),
                    verticalVelocity: Double(velocity.y),
                    rollVelocity: 0,
                    viewportSize: view.bounds.size
                )
            case .cancelled, .failed:
                controller.endCameraInteraction(
                    horizontalVelocity: 0,
                    verticalVelocity: 0,
                    rollVelocity: 0,
                    viewportSize: view.bounds.size
                )
            default:
                break
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .began:
                controller.setMotionReading(nil)
                controller.beginCameraInteraction()
                lastPinchScale = 1
            case .changed:
                let ratio = Double(gesture.scale / max(lastPinchScale, 0.001))
                lastPinchScale = gesture.scale
                controller.zoom(by: ratio, notify: false)
            case .ended, .cancelled, .failed:
                controller.endCameraInteraction(
                    horizontalVelocity: 0,
                    verticalVelocity: 0,
                    rollVelocity: 0,
                    viewportSize: view.bounds.size
                )
            default:
                break
            }
        }

        @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .began:
                controller.setMotionReading(nil)
                controller.beginCameraInteraction()
                lastRotation = 0
            case .changed:
                let delta = gesture.rotation - lastRotation
                lastRotation = gesture.rotation
                controller.rotate(
                    by: Double(delta) * 180 / .pi,
                    notify: false
                )
            case .ended, .cancelled, .failed:
                let rollVelocity = gesture.state == .ended
                    ? Double(gesture.velocity) * 180 / .pi
                    : 0
                controller.endCameraInteraction(
                    horizontalVelocity: 0,
                    verticalVelocity: 0,
                    rollVelocity: rollVelocity,
                    viewportSize: view.bounds.size
                )
            default:
                break
            }
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            parent.onTap(controller.pick(at: gesture.location(in: view), in: view.bounds.size))
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            parent.onReset()
        }
    }
}
