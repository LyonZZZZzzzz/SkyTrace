import SceneKit
import SkyTraceCore
import SwiftUI
import UIKit

struct SkySceneView: UIViewRepresentable {
    let snapshot: SkySnapshot
    let camera: SkyCameraState
    let selectedObjectID: String?
    let showConstellations: Bool
    let starScale: Double

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
        let controller = SkySceneController()
        private var panStartCamera = SkyCameraState()
        private var pinchStartFieldOfView = 70.0
        private var rotationStartRoll = 0.0

        init(parent: SkySceneView) {
            self.parent = parent
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
            controller.updateCamera(parent.camera, selectedObjectID: parent.selectedObjectID)
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
                panStartCamera = parent.camera
            case .changed:
                let translation = gesture.translation(in: view)
                var state = panStartCamera
                let horizontalScale = state.fieldOfView / max(Double(view.bounds.width), 1)
                let verticalScale = state.fieldOfView / max(Double(view.bounds.height), 1)
                state.azimuth = Self.normalizedDegrees(state.azimuth - Double(translation.x) * horizontalScale)
                state.altitude = min(89, max(-89, state.altitude + Double(translation.y) * verticalScale))
                parent.onCameraChange(state)
            default:
                break
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchStartFieldOfView = parent.camera.fieldOfView
            case .changed:
                var state = parent.camera
                state.fieldOfView = min(110, max(20, pinchStartFieldOfView / Double(gesture.scale)))
                parent.onCameraChange(state)
            default:
                break
            }
        }

        @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            switch gesture.state {
            case .began:
                rotationStartRoll = parent.camera.roll
            case .changed:
                var state = parent.camera
                state.roll = Self.normalizedDegrees(rotationStartRoll + Double(gesture.rotation) * 180 / .pi)
                parent.onCameraChange(state)
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

        private static func normalizedDegrees(_ value: Double) -> Double {
            let result = value.truncatingRemainder(dividingBy: 360)
            return result < 0 ? result + 360 : result
        }
    }
}
