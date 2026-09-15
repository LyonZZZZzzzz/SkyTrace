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
        private var panStartCamera = SkyCameraState()
        private var pinchStartFieldOfView = 70.0
        private var rotationStartRoll = 0.0

        init(parent: SkySceneView) {
            self.parent = parent
            controller = SkySceneController(catalog: parent.catalog)
            panStartCamera = parent.camera
            pinchStartFieldOfView = parent.camera.fieldOfView
            rotationStartRoll = parent.camera.roll
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
            controller.setMotionReading(
                parent.motionEnabled && !controller.isUserInteracting ? parent.motionReading : nil
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
                controller.isUserInteracting = true
                panStartCamera = controller.currentCameraState
            case .changed:
                let translation = gesture.translation(in: view)
                var state = panStartCamera
                let horizontalScale = state.fieldOfView / max(Double(view.bounds.width), 1)
                let verticalScale = state.fieldOfView / max(Double(view.bounds.height), 1)
                state.azimuth = Self.normalizedDegrees(state.azimuth - Double(translation.x) * horizontalScale)
                state.altitude = min(89, max(-89, state.altitude + Double(translation.y) * verticalScale))
                controller.updateCamera(state, selectedObjectID: parent.selectedObjectID, notify: false)
            case .ended, .cancelled, .failed:
                finishInteraction()
            default:
                break
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                controller.setMotionReading(nil)
                controller.isUserInteracting = true
                pinchStartFieldOfView = controller.currentCameraState.fieldOfView
            case .changed:
                var state = controller.currentCameraState
                state.fieldOfView = min(110, max(20, pinchStartFieldOfView / Double(gesture.scale)))
                controller.updateCamera(state, selectedObjectID: parent.selectedObjectID, notify: false)
            case .ended, .cancelled, .failed:
                finishInteraction()
            default:
                break
            }
        }

        @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            switch gesture.state {
            case .began:
                controller.setMotionReading(nil)
                controller.isUserInteracting = true
                rotationStartRoll = controller.currentCameraState.roll
            case .changed:
                var state = controller.currentCameraState
                state.roll = Self.normalizedDegrees(rotationStartRoll + Double(gesture.rotation) * 180 / .pi)
                controller.updateCamera(state, selectedObjectID: parent.selectedObjectID, notify: false)
            case .ended, .cancelled, .failed:
                finishInteraction()
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

        private func finishInteraction() {
            controller.isUserInteracting = false
            parent.onCameraChange(controller.currentCameraState)
        }

        private static func normalizedDegrees(_ value: Double) -> Double {
            let result = value.truncatingRemainder(dividingBy: 360)
            return result < 0 ? result + 360 : result
        }
    }
}
