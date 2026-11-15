import CoreGraphics
import Foundation
import SceneKit
import os
import simd
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
public final class SkySceneController: NSObject, SCNSceneRendererDelegate {
    public let sceneView: SCNView
    public let cameraNode: SCNNode
    public let camera: SCNCamera

    public private(set) var metrics = SkyFrameMetrics()
    public private(set) var staticGeometryRebuildCount = 0
    public var onCameraChange: ((SkyCameraState) -> Void)?
    public var onCameraSettled: ((SkyCameraState) -> Void)?
    public var onDiagnosticsChange: ((SkyRenderDiagnostics) -> Void)?
    public var onLabelReadinessChange: ((Bool) -> Void)? {
        didSet { onLabelReadinessChange?(isLabelPreparationComplete) }
    }
    public var isLabelPreparationComplete: Bool { labelPreparationComplete }
    public var isUserInteracting = false
    public var isCameraMoving: Bool { cameraMotion.isMoving }
    public var currentCameraState: SkyCameraState { cameraMotion.state }

    private let catalog: SkySceneCatalog?
    private let astronomy: any AstronomyCalculating
    private let labelVisibilityMode: SkyLabelVisibilityMode
    private let celestialRootNode: SCNNode
    private let starsNode: SCNNode
    private let faintStarsNode: SCNNode
    private let linesNode: SCNNode
    private let horizonNode: SCNNode
    private let dynamicRootNode: SCNNode
    private let selectionNode: SCNNode
    private let labelOverlayScene: SkyLabelOverlayScene
    private var dynamicNodes: [String: SCNNode] = [:]
    private var targetSnapshot: SkySnapshot = .empty
    private var hasAppliedSceneTarget = false
    private var currentSnapshotVectors: [String: Vector3D] = [:]
    private var previousDynamicVectors: [String: Vector3D] = [:]
    private var targetDynamicVectors: [String: Vector3D] = [:]
    private var currentDynamicVectors: [String: Vector3D] = [:]
    private var currentSceneMatrix = matrix_identity_float3x3
    private var previousSceneMatrix = matrix_identity_float3x3
    private var targetSceneMatrix = matrix_identity_float3x3
    private var previousQuaternion = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var targetQuaternion = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var transitionStartTime: TimeInterval = 0
    private var transitionDuration: TimeInterval = 0
    private var showConstellations = true
    private var starScale: CGFloat = 1
    private var hasBuiltStaticGeometry = false
    private var staticGeometryScale: CGFloat?
    private var staticGeometryTask: Task<Void, Never>?
    private var staticGeometryGeneration = 0
    private var staticGeometryScaleInFlight: CGFloat?
    private var geometryKey: GeometryKey?
    private var cameraMotion = SkyCameraMotionController()
    private var wasCameraMoving = false
    private var selectedObjectID: String?
    private var labelMagnitudeLimit = 2.8
    private var showCardinals = true
    private var labelSources: [LabelSource] = []
    private var labelSourceKey: LabelSourceKey?
    private var labelSourceRevision = 0
    private var labelCapacityPolicy = SkyLabelCapacityPolicy()
    private var labelProjectionKey: LabelProjectionKey?
    private var cachedObjectVisuals: [SkyLabelVisual] = []
    private var cachedCardinalVisuals: [SkyLabelVisual] = []
    private var labelProjectionRecomputeCount = 0
    private var labelPreparationComplete: Bool
    private var lastDiagnosticsTime: TimeInterval = 0
    private var lastDiagnosticsLogTime: TimeInterval = 0
    private var motionTarget: SkyMotionReading?
    private var lastPublishedCameraState: SkyCameraState?
    private var isApplicationActive = true
    private var isViewVisible = true
    private var renderingSuspended = false
    private var renderPolicy: SkyRenderPolicy = .idleWarm
    private var interactionRenderPolicy = SkyInteractionRenderPolicy()
    private var interactionRenderProfile = SkyInteractionRenderProfile.full
    private var isInteractionPerformanceWindowActive = false
    private var environmentRenderAdaptationProfile = SkyRenderAdaptationProfile.normal
    private var renderAdaptationProfile = SkyRenderAdaptationProfile.normal
    private var performanceGovernor = SkyPerformanceGovernor()
    private var lastRenderEnvironment: SkyRenderEnvironment?
    private var debugFrameCounter = 0
    private nonisolated let frameMailbox = FrameUpdateMailbox()
    private var frameConsumerTask: Task<Void, Never>?

    public init(
        sceneView: SCNView = SCNView(frame: .zero),
        catalog: SkySceneCatalog? = nil,
        astronomy: any AstronomyCalculating = AstronomyService(),
        labelVisibilityMode: SkyLabelVisibilityMode = .adaptive
    ) {
        self.sceneView = sceneView
        self.catalog = catalog
        self.astronomy = astronomy
        self.labelVisibilityMode = labelVisibilityMode
        self.celestialRootNode = SCNNode()
        self.starsNode = SCNNode()
        self.faintStarsNode = SCNNode()
        self.linesNode = SCNNode()
        self.horizonNode = SCNNode(geometry: StarGeometryFactory.makeHorizon())
        self.dynamicRootNode = SCNNode()
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 70
        camera.projectionDirection = .vertical
        camera.zNear = 0.1
        camera.zFar = 500
        camera.wantsHDR = false
        camera.bloomIntensity = 0
        camera.bloomThreshold = 1
        camera.bloomBlurRadius = 0
        cameraNode.camera = camera
        self.cameraNode = cameraNode
        self.camera = camera
        self.selectionNode = StarGeometryFactory.makeSelectionNode()
        self.labelOverlayScene = SkyLabelOverlayScene(size: CGSize(width: 1, height: 1))
        self.labelPreparationComplete = labelVisibilityMode == .adaptive

        super.init()

        labelOverlayScene.configure(visibilityMode: labelVisibilityMode)

#if os(macOS)
        sceneView.backgroundColor = NSColor(red: 0.008, green: 0.024, blue: 0.055, alpha: 1)
#else
        sceneView.backgroundColor = UIColor(red: 0.008, green: 0.024, blue: 0.055, alpha: 1)
#endif
        sceneView.antialiasingMode = .multisampling2X
        sceneView.preferredFramesPerSecond = 60
        sceneView.rendersContinuously = true
        sceneView.autoenablesDefaultLighting = false
        sceneView.isPlaying = true

        let scene = SCNScene()
        scene.background.contents = CGColor(red: 0.008, green: 0.024, blue: 0.055, alpha: 1)
        sceneView.scene = scene

        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        celestialRootNode.name = "celestialRoot"
        starsNode.name = "starsNode"
        faintStarsNode.name = "faintStarsNode"
        linesNode.name = "linesNode"
        celestialRootNode.addChildNode(starsNode)
        celestialRootNode.addChildNode(faintStarsNode)
        celestialRootNode.addChildNode(linesNode)
        scene.rootNode.addChildNode(celestialRootNode)

        horizonNode.name = "horizonNode"
        scene.rootNode.addChildNode(horizonNode)

        dynamicRootNode.name = "dynamicRoot"
        scene.rootNode.addChildNode(dynamicRootNode)

        selectionNode.isHidden = true
        scene.rootNode.addChildNode(selectionNode)

        sceneView.overlaySKScene = labelOverlayScene
        sceneView.delegate = self
        updateCamera(SkyCameraState(), selectedObjectID: nil, notify: false)
        lastPublishedCameraState = currentCameraState
        startFrameConsumer()
    }

    deinit {
        frameConsumerTask?.cancel()
        staticGeometryTask?.cancel()
        frameMailbox.finish()
    }

    public func update(
        snapshot: SkySnapshot,
        showConstellations: Bool,
        starScale: CGFloat
    ) {
        wakeRendering()
        let targetChanged = !hasAppliedSceneTarget ||
            snapshot.moment != targetSnapshot.moment ||
            snapshot.observer != targetSnapshot.observer
        let scaleChanged = staticGeometryScale != starScale
        self.showConstellations = showConstellations
        self.starScale = starScale

        if let catalog {
            if !hasBuiltStaticGeometry || scaleChanged {
                scheduleStaticGeometryBuild(catalog: catalog, scale: starScale)
            } else if staticGeometryTask != nil {
                cancelStaticGeometryBuild()
            }
            starsNode.isHidden = !hasBuiltStaticGeometry
            updateFaintStarVisibility()
            linesNode.isHidden = !showConstellations
            horizonNode.isHidden = !showConstellations
        } else {
            let key = GeometryKey(
                moment: snapshot.moment.date,
                observer: snapshot.observer,
                showConstellations: showConstellations,
                starScale: starScale
            )
            if key != geometryKey {
                geometryKey = key
                starsNode.geometry = StarGeometryFactory.makeStars(snapshot.positions, scale: starScale)
                faintStarsNode.geometry = nil
                updateFaintStarVisibility()
                linesNode.geometry = showConstellations
                    ? StarGeometryFactory.makeConstellationLines(snapshot.constellationSegments)
                    : nil
                linesNode.isHidden = !showConstellations
                horizonNode.isHidden = !showConstellations
                metrics.recordGeometryRebuild()
                staticGeometryRebuildCount += 1
            }
        }

        if targetChanged {
            beginTransition(to: snapshot)
        } else {
            targetSnapshot = snapshot
            rebuildSnapshotVectors()
            ensureDynamicNodes(for: snapshot.dynamicPositions)
            updateLabelSourcesIfNeeded()
        }
        updateSelection()
        updateContinuousRenderingMode()
    }

    public func updateLabels(magnitudeLimit: Double, showCardinals: Bool) {
        let magnitudeChanged = abs(self.labelMagnitudeLimit - magnitudeLimit) > 0.000_1
        let cardinalChanged = self.showCardinals != showCardinals
        guard magnitudeChanged || cardinalChanged else { return }
        wakeRendering()
        self.labelMagnitudeLimit = magnitudeLimit
        self.showCardinals = showCardinals
        if magnitudeChanged {
            labelSourceKey = nil
        }
        updateLabelSourcesIfNeeded()
    }

    public func updateCamera(
        _ state: SkyCameraState,
        selectedObjectID: String?,
        notify: Bool = true,
        immediate: Bool = true
    ) {
        wakeRendering()
        self.selectedObjectID = selectedObjectID
        if immediate {
            cameraMotion.setImmediate(state)
            applyCameraMotionSnapshot(
                SkyCameraMotionSnapshot(
                    orientation: cameraMotion.orientation,
                    basis: cameraMotion.basis,
                    state: cameraMotion.state,
                    isMoving: false
                ),
                publishSettled: false
            )
        } else {
            cameraMotion.animate(to: state)
            updateContinuousRenderingMode()
        }
        updateLabelSourcesIfNeeded()
        if notify {
            lastPublishedCameraState = currentCameraState
            onCameraChange?(currentCameraState)
        }
    }

    public func synchronizeCamera(_ state: SkyCameraState, selectedObjectID: String?) {
        if self.selectedObjectID != selectedObjectID {
            self.selectedObjectID = selectedObjectID
            updateSelection()
            updateLabelSourcesIfNeeded()
            wakeRendering()
        }
        if isUserInteracting {
            return
        }
        if let lastPublishedCameraState,
           Self.cameraStatesAreApproximatelyEqual(state, lastPublishedCameraState) {
            return
        }
        wakeRendering()
        cameraMotion.animate(to: state)
        updateContinuousRenderingMode()
    }

    public func beginCameraInteraction() {
        isUserInteracting = true
        isInteractionPerformanceWindowActive = true
        cameraMotion.beginInteraction()
        refreshInteractionRenderProfile()
        updateContinuousRenderingMode()
    }

    public func endCameraInteraction(
        horizontalVelocity: Double,
        verticalVelocity: Double,
        rollVelocity: Double,
        viewportSize: CGSize
    ) {
        wakeRendering()
        let horizontalScale = currentCameraState.fieldOfView / max(Double(viewportSize.width), 1)
        let verticalScale = currentCameraState.fieldOfView / max(Double(viewportSize.height), 1)
        isUserInteracting = false
        cameraMotion.endInteraction(
            horizontalVelocity: horizontalVelocity * horizontalScale,
            verticalVelocity: verticalVelocity * verticalScale,
            rollVelocity: rollVelocity
        )
        if !cameraMotion.isMoving {
            finishInteractionPerformanceWindow()
            let state = currentCameraState
            lastPublishedCameraState = state
            onCameraSettled?(state)
            updateContinuousRenderingMode()
        }
    }

    public func pick(at point: CGPoint, in size: CGSize) -> String? {
        let projection = SkyProjection(
            camera: currentCameraState,
            basis: cameraMotion.basis,
            size: size
        )
        let objects = catalog?.objects ?? targetSnapshot.positions.map(\.object)
        return objects.compactMap { object -> (String, CGFloat)? in
            guard let direction = displayVector(for: object.id) else { return nil }
            guard let pointOnScreen = projection.screenPoint(for: direction) else { return nil }
            let distance = hypot(pointOnScreen.x - point.x, pointOnScreen.y - point.y)
            return distance <= 32 ? (object.id, distance) : nil
        }
        .min { $0.1 < $1.1 }?
        .0
    }

    public func orbit(
        horizontalDelta: Double,
        verticalDelta: Double,
        viewportSize: CGSize,
        notify: Bool = true
    ) {
        wakeRendering()
        let horizontalScale = currentCameraState.fieldOfView / max(Double(viewportSize.width), 1)
        let verticalScale = currentCameraState.fieldOfView / max(Double(viewportSize.height), 1)
        cameraMotion.rotate(
            horizontalDegrees: horizontalDelta * horizontalScale,
            verticalDegrees: verticalDelta * verticalScale,
            rollDegrees: 0
        )
        updateContinuousRenderingMode()
        if notify {
            onCameraChange?(currentCameraState)
        }
    }

    public func zoom(by scale: Double, notify: Bool = true) {
        wakeRendering()
        cameraMotion.zoom(by: scale)
        updateContinuousRenderingMode()
        if notify {
            onCameraChange?(currentCameraState)
        }
    }

    public func rotate(by degrees: Double, notify: Bool = true) {
        wakeRendering()
        cameraMotion.rotate(horizontalDegrees: 0, verticalDegrees: 0, rollDegrees: degrees)
        updateContinuousRenderingMode()
        if notify {
            onCameraChange?(currentCameraState)
        }
    }

    public func nudge(horizontal: Double = 0, vertical: Double = 0, zoom: Double = 0, notify: Bool = true) {
        wakeRendering()
        cameraMotion.rotate(
            horizontalDegrees: -horizontal,
            verticalDegrees: vertical,
            rollDegrees: 0
        )
        if zoom != 0 {
            cameraMotion.zoom(by: pow(1.08, -zoom / 5))
        }
        updateContinuousRenderingMode()
        if notify {
            onCameraChange?(currentCameraState)
        }
    }

    public func setMotionReading(_ reading: SkyMotionReading?) {
        let wasFollowingMotion = motionTarget != nil
        motionTarget = isApplicationActive && isViewVisible ? reading : nil
        guard wasFollowingMotion != (motionTarget != nil) else { return }
        updateContinuousRenderingMode()
    }

    public func resetMetrics() {
        metrics.reset()
    }

    public func setApplicationActive(_ active: Bool, isVisible: Bool) {
        let wasBlocked = !isApplicationActive || !isViewVisible
        isApplicationActive = active
        isViewVisible = isVisible
        if active && isVisible {
            if wasBlocked {
                wakeRendering()
                updateContinuousRenderingMode()
            }
        } else {
            suspendRendering()
        }
    }

    public func updateRenderEnvironment(_ environment: SkyRenderEnvironment) {
        let previousPressure = lastRenderEnvironment?.memoryPressure ?? .normal
        lastRenderEnvironment = environment
        if environment.memoryPressure != .normal,
           environment.memoryPressure != previousPressure {
            labelOverlayScene.trimIdleResources()
            labelProjectionKey = nil
            cachedObjectVisuals.removeAll(keepingCapacity: true)
            cachedCardinalVisuals.removeAll(keepingCapacity: true)
            requestSceneDisplay()
        }
        environmentRenderAdaptationProfile = SkyRenderAdaptationPolicy.profile(for: environment)
        applyEffectiveRenderAdaptationProfile()
    }

    public func shutdown() {
        onCameraChange = nil
        onCameraSettled = nil
        onDiagnosticsChange = nil
        onLabelReadinessChange = nil
        frameMailbox.setEnabled(false)
        frameMailbox.finish()
        frameConsumerTask?.cancel()
        frameConsumerTask = nil
        cancelStaticGeometryBuild()
        sceneView.delegate = nil
        sceneView.rendersContinuously = false
        sceneView.isPlaying = false
        sceneView.overlaySKScene = nil
    }

    private func applyRenderAdaptationProfile(_ profile: SkyRenderAdaptationProfile) {
        let changed = profile != renderAdaptationProfile
        renderAdaptationProfile = profile
        applyPreferredFramesPerSecond()
        switch profile.antialiasing {
        case .multisampling2X:
            sceneView.antialiasingMode = .multisampling2X
        case .disabled:
            sceneView.antialiasingMode = .none
        }
        updateFaintStarVisibility()
        if changed {
            labelProjectionKey = nil
            requestSceneDisplay()
        }
    }

    private func applyEffectiveRenderAdaptationProfile() {
        let profile: SkyRenderAdaptationProfile
        switch performanceGovernor.level {
        case .normal:
            profile = environmentRenderAdaptationProfile
        case .elevated:
            profile = SkyRenderAdaptationPolicy.mostConstrained(
                environmentRenderAdaptationProfile,
                .elevated
            )
        case .critical:
            profile = .critical
        }
        guard profile != renderAdaptationProfile else { return }
        applyRenderAdaptationProfile(profile)
    }

    private func applyPreferredFramesPerSecond() {
        sceneView.preferredFramesPerSecond = renderAdaptationProfile.preferredFramesPerSecond
    }

    var debugCelestialRootNode: SCNNode { celestialRootNode }
    var debugCurrentSceneMatrix: simd_float3x3 { currentSceneMatrix }
    var debugCurrentCameraBasis: SkyCameraBasis { cameraMotion.basis }
    var debugCurrentDynamicVectors: [String: Vector3D] { currentDynamicVectors }
    var debugTransitionStartTime: TimeInterval { transitionStartTime }
    var debugTransitionDuration: TimeInterval { transitionDuration }
    var debugRendersContinuously: Bool { sceneView.rendersContinuously }
    var debugSceneIsPlaying: Bool { sceneView.isPlaying }
    var debugRenderingEnabled: Bool { frameMailbox.isEnabled }
    var debugRenderPolicy: SkyRenderPolicy { renderPolicy }
    var debugLabelProjectionRecomputeCount: Int { labelProjectionRecomputeCount }
    var debugLabelSourceRevision: Int { labelSourceRevision }
    var debugLabelSourceObjectIDs: [String] { labelSources.map(\.object.id) }
    var debugLabelCapacity: Int {
        if labelVisibilityMode == .alwaysVisible {
            return labelSources.count
        }
        return min(
            labelCapacityPolicy.capacity,
            interactionRenderProfile.labelCapacityLimit ?? .max,
            renderAdaptationProfile.labelCapacityLimit ?? .max
        )
    }
    var debugLabelNodeCount: Int { labelOverlayScene.debugObjectNodeCount }
    var debugPendingLabelTextUpdateCount: Int { labelOverlayScene.pendingTextUpdateCount }
    var debugDisplayedObjectIDs: Set<String> { labelOverlayScene.displayedObjectIDs }
    var debugFaintStarsIsHidden: Bool { faintStarsNode.isHidden }
    var debugInteractionRenderProfile: SkyInteractionRenderProfile { interactionRenderProfile }
    var debugRenderAdaptationProfile: SkyRenderAdaptationProfile { renderAdaptationProfile }
    var debugHasPendingLabelTextUpdates: Bool { labelOverlayScene.hasPendingTextUpdates }

    func debugRefreshContinuousRenderingMode() {
        updateContinuousRenderingMode()
    }

    func debugAdvanceAnimation(to time: TimeInterval) {
        updateAnimation(at: time)
    }

    func debugSimulateFrame(at time: TimeInterval) {
        updateFrame(at: time)
    }

    func debugRefreshLabels() {
        updateOverlayLabels(force: true)
    }

    func debugWaitForStaticGeometry() async {
        await staticGeometryTask?.value
    }

    func debugOverlayPoint(
        for direction: Vector3D,
        renderer: any SCNSceneRenderer
    ) -> CGPoint? {
        overlayPoint(for: direction, size: sceneView.bounds.size, renderer: renderer)
    }


    public nonisolated func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        frameMailbox.submit(time: time)
    }

    private func startFrameConsumer() {
        frameConsumerTask?.cancel()
        frameConsumerTask = Task { @MainActor [weak self] in
            guard let mailbox = self?.frameMailbox else { return }
            for await time in mailbox.stream {
                guard !Task.isCancelled else { return }
                guard let self else {
                    mailbox.finish()
                    return
                }
                if self.isApplicationActive && self.isViewVisible {
                    self.updateFrame(at: time)
                    self.updateContinuousRenderingMode()
                }
                mailbox.completeFrame()
            }
        }
    }

    private func updateFrame(at time: TimeInterval) {
        let isActiveRenderingWindow = renderPolicy == .interactive ||
            renderPolicy == .animating ||
            needsLabelTextWarmup
        if isActiveRenderingWindow {
            metrics.recordFrame(at: time)
        } else {
            metrics.resetSampling()
        }
        if renderPolicy == .interactive || renderPolicy == .animating {
            let previousLevel = performanceGovernor.level
            let nextLevel = performanceGovernor.update(metrics: metrics, at: time)
            if nextLevel != previousLevel {
                metrics.resetSampling()
                applyEffectiveRenderAdaptationProfile()
            }
        }
        updateAnimation(at: time)
        updateOverlayLabels()
        publishDiagnosticsIfNeeded(at: time)
#if DEBUG
        debugFrameCounter += 1
        if debugFrameCounter % 120 == 0 || metrics.consecutiveSlowFrames >= 3 {
            SkyTraceDiagnostics.frames.debug(
                "FPS \(self.metrics.averageFPS, privacy: .public) p95 \(self.metrics.p95FrameInterval, privacy: .public) p99 \(self.metrics.p99FrameInterval, privacy: .public)"
            )
            SkyTraceDiagnostics.event("FrameMetricsReport")
        }
#endif
    }

    private func publishDiagnosticsIfNeeded(at time: TimeInterval) {
        let shouldPublish = onDiagnosticsChange != nil &&
            (lastDiagnosticsTime == 0 || time - lastDiagnosticsTime >= 1)
        let shouldLog = lastDiagnosticsLogTime == 0 || time - lastDiagnosticsLogTime >= 5
        guard shouldPublish || shouldLog else { return }

        let diagnostics = SkyRenderDiagnostics(
            renderQuality: renderAdaptationProfile.quality,
            renderActivity: currentRenderActivity,
            p95FrameInterval: metrics.p95FrameInterval,
            p99FrameInterval: metrics.p99FrameInterval,
            cumulativeP95FrameInterval: metrics.cumulativeP95FrameInterval,
            cumulativeP99FrameInterval: metrics.cumulativeP99FrameInterval,
            cumulativeFrameCount: metrics.cumulativeMeasuredFrameCount,
            longestFrameInterval: metrics.longestFrameInterval,
            mainThreadStallCount: metrics.mainThreadStallCount,
            labelNodeCount: labelOverlayScene.debugObjectNodeCount,
            pendingLabelTextUpdates: labelOverlayScene.pendingTextUpdateCount,
            geometryRebuildCount: metrics.geometryRebuildCount,
            labelSourceCount: labelSources.count,
            displayedLabelCount: labelOverlayScene.displayedObjectIDs.count,
            residentMemoryBytes: SkyProcessMemory.residentBytes()
        )
        if shouldPublish {
            lastDiagnosticsTime = time
            onDiagnosticsChange?(diagnostics)
        }
        if shouldLog {
            lastDiagnosticsLogTime = time
            SkyTraceDiagnostics.frames.info(
                "Render diagnostics quality=\(diagnostics.renderQuality.rawValue, privacy: .public) activity=\(diagnostics.renderActivity.rawValue, privacy: .public) p95=\(diagnostics.p95FrameInterval, privacy: .public) p99=\(diagnostics.p99FrameInterval, privacy: .public) labels=\(diagnostics.displayedLabelCount, privacy: .public) rss=\(diagnostics.residentMemoryBytes, privacy: .public)"
            )
        }
    }

    private var currentRenderActivity: SkyRenderActivity {
        if renderPolicy == .suspended { return .suspended }
        if renderPolicy == .interactive { return .interactive }
        if renderPolicy == .animating { return .animating }
        return needsLabelTextWarmup ? .warmup : .idle
    }

    private var needsLabelTextWarmup: Bool {
        sceneView.bounds.width > 0 &&
            sceneView.bounds.height > 0 &&
            labelOverlayScene.hasPendingTextUpdates
    }

    private func wakeRendering() {
        guard isApplicationActive && isViewVisible else { return }
        if renderingSuspended {
            metrics.resetSampling()
            renderingSuspended = false
        }
        frameMailbox.setEnabled(true)
        let shouldRenderContinuously = renderPolicy.usesContinuousRendering ||
            needsLabelTextWarmup
        sceneView.rendersContinuously = shouldRenderContinuously
        sceneView.isPlaying = true
        if !shouldRenderContinuously {
            requestSceneDisplay()
        }
    }

    private func suspendRendering() {
        renderingSuspended = true
        isUserInteracting = false
        resetInteractionPerformanceWindow()
        motionTarget = nil
        cameraMotion.suspend()
        performanceGovernor.reset()
        applyEffectiveRenderAdaptationProfile()
        metrics.resetSampling()
        renderPolicy = .suspended
        frameMailbox.setEnabled(false)
        sceneView.rendersContinuously = false
        sceneView.isPlaying = false
    }

    private func updateContinuousRenderingMode() {
        let previousPolicy = renderPolicy
        if !isApplicationActive || !isViewVisible {
            renderPolicy = .suspended
        } else if isUserInteracting {
            renderPolicy = .interactive
        } else if cameraMotion.isMoving || transitionDuration > 0 || motionTarget != nil {
            renderPolicy = .animating
        } else {
            renderPolicy = .idleWarm
        }

        switch renderPolicy {
        case .interactive, .animating:
            if previousPolicy == .idleWarm {
                metrics.resetSampling()
            }
            frameMailbox.setEnabled(true)
            sceneView.rendersContinuously = true
            sceneView.isPlaying = true
        case .idleWarm:
            if needsLabelTextWarmup {
                frameMailbox.setEnabled(true)
                sceneView.rendersContinuously = true
                sceneView.isPlaying = true
            } else {
                if previousPolicy != .idleWarm {
                    metrics.resetSampling()
                }
                frameMailbox.setEnabled(false)
                sceneView.rendersContinuously = false
                sceneView.isPlaying = false
            }
            requestSceneDisplay()
        case .suspended:
            suspendRendering()
        }
    }

    private func refreshInteractionRenderProfile() {
        let profile = interactionRenderPolicy.update(
            isInteractionActive: isInteractionPerformanceWindowActive,
            fieldOfView: currentCameraState.fieldOfView
        )
        guard profile != interactionRenderProfile else { return }
        interactionRenderProfile = profile
        updateFaintStarVisibility()
    }

    private func finishInteractionPerformanceWindow() {
        guard isInteractionPerformanceWindowActive else { return }
        isInteractionPerformanceWindowActive = false
        refreshInteractionRenderProfile()
    }

    private func resetInteractionPerformanceWindow() {
        isInteractionPerformanceWindowActive = false
        interactionRenderPolicy = SkyInteractionRenderPolicy()
        interactionRenderProfile = .full
        updateFaintStarVisibility()
    }

    private func updateFaintStarVisibility() {
        faintStarsNode.isHidden = interactionRenderProfile.hidesFaintStars ||
            renderAdaptationProfile.hidesFaintStars
    }

    private func requestSceneDisplay() {
#if os(macOS)
        sceneView.setNeedsDisplay(sceneView.bounds)
#else
        sceneView.setNeedsDisplay()
#endif
    }

    private func applyCameraMotionSnapshot(
        _ snapshot: SkyCameraMotionSnapshot,
        publishSettled: Bool
    ) {
        cameraNode.simdOrientation = snapshot.orientation
        camera.fieldOfView = CGFloat(snapshot.state.fieldOfView)

        if publishSettled, wasCameraMoving, !snapshot.isMoving {
            finishInteractionPerformanceWindow()
            lastPublishedCameraState = snapshot.state
            onCameraSettled?(snapshot.state)
        }
        wasCameraMoving = snapshot.isMoving
    }

    private func scheduleStaticGeometryBuild(catalog: SkySceneCatalog, scale: CGFloat) {
        if staticGeometryScaleInFlight == scale, staticGeometryTask != nil {
            return
        }
        cancelStaticGeometryBuild()
        let generation = staticGeometryGeneration
        staticGeometryScaleInFlight = scale

        staticGeometryTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                let objects = catalog.staticObjects
                let brightObjects = objects.filter { !SkyInteractionRenderPolicy.isFaintStar($0) }
                let faintObjects = objects.filter { SkyInteractionRenderPolicy.isFaintStar($0) }
                let bright = StarGeometryFactory.makeStarGeometryData(objects: brightObjects, scale: scale)
                let faint = StarGeometryFactory.makeStarGeometryData(objects: faintObjects, scale: scale)
                return (bright, faint)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            guard
                !Task.isCancelled,
                let self,
                generation == self.staticGeometryGeneration
            else { return }
            self.installStaticGeometry(
                brightData: result.0,
                faintData: result.1,
                catalog: catalog,
                scale: scale
            )
        }
    }

    private func cancelStaticGeometryBuild() {
        staticGeometryGeneration &+= 1
        staticGeometryTask?.cancel()
        staticGeometryTask = nil
        staticGeometryScaleInFlight = nil
    }

    private func installStaticGeometry(
        brightData: StarGeometryData,
        faintData: StarGeometryData,
        catalog: SkySceneCatalog,
        scale: CGFloat
    ) {
        starsNode.geometry = brightData.isEmpty
            ? nil
            : StarGeometryFactory.makeStars(data: brightData)
        faintStarsNode.geometry = faintData.isEmpty
            ? nil
            : StarGeometryFactory.makeStars(data: faintData)
        if linesNode.geometry == nil {
            linesNode.geometry = StarGeometryFactory.makeConstellationLinesFromJ2000(catalog.segments)
        }
        updateFaintStarVisibility()
        starsNode.isHidden = false
        staticGeometryScale = scale
        staticGeometryScaleInFlight = nil
        staticGeometryTask = nil
        hasBuiltStaticGeometry = true
        metrics.recordGeometryRebuild()
        staticGeometryRebuildCount += 1
        requestSceneDisplay()
    }

    private func beginTransition(
        to snapshot: SkySnapshot,
        sceneMatrix: simd_float3x3? = nil,
        transitionDuration requestedTransitionDuration: TimeInterval = 0.22
    ) {
        let now = CACurrentMediaTime()
        let shouldSnap = !hasAppliedSceneTarget
        previousSceneMatrix = currentSceneMatrix
        previousQuaternion = simd_quatf(previousSceneMatrix)
        previousDynamicVectors = currentDynamicVectors

        targetSnapshot = snapshot
        let dynamicPositions = snapshot.dynamicPositions
        targetDynamicVectors = Dictionary(
            uniqueKeysWithValues: dynamicPositions.map { ($0.id, $0.horizontalVector) }
        )
        currentSnapshotVectors = catalog == nil
            ? Dictionary(uniqueKeysWithValues: snapshot.positions.map { ($0.id, $0.horizontalVector) })
            : targetDynamicVectors
        targetSceneMatrix = sceneMatrix ?? astronomy.horizontalTransform(
            for: snapshot.moment,
            observer: snapshot.observer
        ).sceneMatrix
        targetQuaternion = simd_quatf(targetSceneMatrix)
        transitionStartTime = now
        ensureDynamicNodes(for: dynamicPositions)

        if shouldSnap {
            previousSceneMatrix = targetSceneMatrix
            previousQuaternion = targetQuaternion
            currentSceneMatrix = targetSceneMatrix
            previousDynamicVectors = targetDynamicVectors
            currentDynamicVectors = targetDynamicVectors
            celestialRootNode.simdOrientation = targetQuaternion
            updateDynamicNodePositions()
            transitionDuration = 0
        } else {
            transitionDuration = min(1, max(0, requestedTransitionDuration))
            if transitionDuration == 0 {
                previousQuaternion = targetQuaternion
                previousSceneMatrix = targetSceneMatrix
                previousDynamicVectors = targetDynamicVectors
                currentDynamicVectors = targetDynamicVectors
            }
        }
        hasAppliedSceneTarget = true
        rebuildSnapshotVectors()
        updateLabelSourcesIfNeeded()
    }

    private func updateAnimation(at time: TimeInterval) {
        if let motionTarget, !isUserInteracting {
            var target = currentCameraState
            target.azimuth = motionTarget.azimuth
            target.altitude = motionTarget.altitude
            target.roll = motionTarget.roll
            cameraMotion.animate(to: target)
        }

        let cameraSnapshot = cameraMotion.update(at: time)
        applyCameraMotionSnapshot(cameraSnapshot, publishSettled: true)
        refreshInteractionRenderProfile()

        let progress: Float
        if transitionDuration > 0 {
            let elapsed = max(0, time - transitionStartTime)
            progress = Float(min(1, elapsed / transitionDuration))
            if progress >= 1 {
                transitionDuration = 0
            }
        } else {
            progress = 1
        }

        let quaternion = progress >= 1
            ? targetQuaternion
            : simd_slerp(previousQuaternion, targetQuaternion, progress)
        celestialRootNode.simdOrientation = quaternion
        currentSceneMatrix = simd_float3x3(quaternion)
        updateDynamicVectors(progress: progress)
        updateDynamicNodePositions()
        updateSelection()
    }

    private func updateDynamicVectors(progress: Float) {
        if progress >= 1 {
            currentDynamicVectors = targetDynamicVectors
            return
        }

        for (id, target) in targetDynamicVectors {
            guard
                let previous = previousDynamicVectors[id],
                let current = slerp(previous, target, progress)
            else {
                currentDynamicVectors[id] = target
                continue
            }
            currentDynamicVectors[id] = current
        }

        for id in previousDynamicVectors.keys where targetDynamicVectors[id] == nil {
            currentDynamicVectors[id] = previousDynamicVectors[id]
        }
    }

    private func updateDynamicNodePositions() {
        var updated = 0
        for (id, node) in dynamicNodes {
            guard let direction = currentDynamicVectors[id] ?? targetDynamicVectors[id] else {
                node.isHidden = true
                continue
            }
            node.position = SCNVector3(
                Float(direction.x * StarGeometryFactory.skyRadius * 0.98),
                Float(direction.y * StarGeometryFactory.skyRadius * 0.98),
                Float(direction.z * StarGeometryFactory.skyRadius * 0.98)
            )
            node.isHidden = false
            updated += 1
        }
        if updated > 0 {
            metrics.recordDynamicNodeUpdate(count: updated)
        }
    }

    private func ensureDynamicNodes(for positions: [SkyPosition]) {
        for position in positions where dynamicNodes[position.id] == nil {
            let node = StarGeometryFactory.makeBodyNode(for: position.object)
            dynamicRootNode.addChildNode(node)
            dynamicNodes[position.id] = node
        }
    }

    private func rebuildSnapshotVectors() {
        targetDynamicVectors = Dictionary(
            uniqueKeysWithValues: targetSnapshot.dynamicPositions.map { ($0.id, $0.horizontalVector) }
        )
        currentSnapshotVectors = catalog == nil
            ? Dictionary(uniqueKeysWithValues: targetSnapshot.positions.map { ($0.id, $0.horizontalVector) })
            : targetDynamicVectors
    }

    private func updateSelection() {
        guard
            let selectedObjectID,
            let direction = displayVector(for: selectedObjectID)
        else {
            selectionNode.isHidden = true
            return
        }

        let point = direction * (StarGeometryFactory.skyRadius * 0.98)
        selectionNode.position = SCNVector3(Float(point.x), Float(point.y), Float(point.z))
        selectionNode.isHidden = false
        selectionNode.removeAction(forKey: "pulse")
        selectionNode.scale = SCNVector3(1, 1, 1)
    }

    private func displayVector(for objectID: String) -> Vector3D? {
        if let catalog, let direction = catalog.directionJ2000(for: objectID) {
            let world = currentSceneMatrix * SIMD3<Float>(
                Float(direction.x),
                Float(direction.y),
                Float(direction.z)
            )
            return Vector3D(x: Double(world.x), y: Double(world.y), z: Double(world.z)).normalized
        }
        if let current = currentDynamicVectors[objectID] {
            return current
        }
        return currentSnapshotVectors[objectID]
    }

    private func updateLabelSourcesIfNeeded() {
        let key = LabelSourceKey(
            selectedObjectID: selectedObjectID,
            magnitudeLimit: labelMagnitudeLimit,
            objectCount: catalog?.objects.count ?? targetSnapshot.positions.count
        )
        guard key != labelSourceKey else { return }
        labelSourceKey = key

        let objects: [CelestialObject]
        if let catalog {
            var candidates = catalog.solarSystemObjects + catalog.constellationObjects
            candidates.append(contentsOf: catalog.deepSkyByMagnitude.prefix { ($0.magnitude ?? 99) <= 5.0 })
            candidates.append(contentsOf: catalog.starsByMagnitude.prefix { ($0.magnitude ?? 99) <= labelMagnitudeLimit })
            if let selectedObjectID,
               !candidates.contains(where: { $0.id == selectedObjectID }),
               let selected = catalog.objects.first(where: { $0.id == selectedObjectID }) {
                candidates.append(selected)
            }
            objects = candidates
        } else {
            objects = targetSnapshot.positions.map(\.object)
        }

        labelSources = objects.compactMap { object in
            let selected = object.id == selectedObjectID
            guard selected || Self.shouldShowLabel(for: object, magnitudeLimit: labelMagnitudeLimit) else {
                return nil
            }
            let direction = catalog?.directionJ2000(for: object.id)
            return LabelSource(object: object, j2000Direction: direction)
        }
        .sorted { lhs, rhs in
            if lhs.object.id == selectedObjectID { return true }
            if rhs.object.id == selectedObjectID { return false }
            let lhsPriority = lhs.object.kind.labelPriority
            let rhsPriority = rhs.object.kind.labelPriority
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            let lhsMagnitude = lhs.object.magnitude ?? .infinity
            let rhsMagnitude = rhs.object.magnitude ?? .infinity
            if lhsMagnitude != rhsMagnitude { return lhsMagnitude < rhsMagnitude }
            return lhs.object.id < rhs.object.id
        }
        labelSourceRevision &+= 1
        prepareLabelResources()
    }

    private func prepareLabelResources() {
        if labelVisibilityMode == .alwaysVisible {
            labelPreparationComplete = false
            onLabelReadinessChange?(false)
            labelOverlayScene.prepareObjectLabels(
                labelSources.map {
                    SkyObjectLabelSeed(
                        id: $0.object.id,
                        text: $0.object.name,
                        kind: $0.object.kind
                    )
                }
            )
        } else {
            labelOverlayScene.queuePrewarm(
                texts: Array(labelSources.prefix(100).map(\.object.name))
            )
        }
        refreshLabelPreparationState()
    }

    private func refreshLabelPreparationState() {
        let complete = labelVisibilityMode == .adaptive ||
            (labelSourceKey != nil && !labelOverlayScene.hasPendingTextUpdates)
        guard complete != labelPreparationComplete else { return }
        labelPreparationComplete = complete
        onLabelReadinessChange?(complete)
    }

    private func updateOverlayLabels(force: Bool = false) {
        let now = CACurrentMediaTime()
        let size = sceneView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let start = now

        let visibleCapacity: Int
        if labelVisibilityMode == .alwaysVisible {
            visibleCapacity = labelSources.count
        } else {
            let baseCapacity = labelCapacityPolicy.update(
                fieldOfView: currentCameraState.fieldOfView
            )
            visibleCapacity = min(
                baseCapacity,
                interactionRenderProfile.labelCapacityLimit ?? .max,
                renderAdaptationProfile.labelCapacityLimit ?? .max
            )
        }
        let cacheKey = LabelProjectionKey(
            camera: currentCameraState,
            sceneMatrix: currentSceneMatrix.floatValues,
            size: size,
            selectedObjectID: selectedObjectID,
            showCardinals: showCardinals,
            labelSourceRevision: labelSourceRevision,
            labelCapacity: visibleCapacity
        )
        if cacheKey == labelProjectionKey {
            if labelOverlayScene.hasPendingTextUpdates {
                labelOverlayScene.apply(
                    visuals: cachedObjectVisuals,
                    cardinals: cachedCardinalVisuals
                )
                refreshLabelPreparationState()
            }
            metrics.recordLabelProjection(duration: CACurrentMediaTime() - start)
            return
        }

        labelProjectionRecomputeCount += 1
        labelOverlayScene.size = size
        var cardinalVisuals: [SkyLabelVisual] = []

        if showCardinals {
            let cardinals: [(String, Vector3D)] = [
                ("北", vector(azimuth: 0, altitude: 0)),
                ("东", vector(azimuth: 90, altitude: 0)),
                ("南", vector(azimuth: 180, altitude: 0)),
                ("西", vector(azimuth: 270, altitude: 0))
            ]
            for (text, direction) in cardinals {
                if let point = overlayPoint(for: direction, size: size) {
                    cardinalVisuals.append(
                        SkyLabelVisual(
                            id: "cardinal-\(text)",
                            text: text,
                            point: point,
                            kind: .constellation,
                            selected: false
                        )
                    )
                }
            }
        }

        var visibleVisuals: [SkyLabelVisual] = []
        visibleVisuals.reserveCapacity(labelSources.count)
        if labelVisibilityMode == .alwaysVisible {
            for source in labelSources {
                guard let direction = displayVector(for: source.object.id) else { continue }
                guard let point = overlayPoint(for: direction, size: size) else { continue }
                visibleVisuals.append(
                    SkyLabelVisual(
                        id: source.object.id,
                        text: source.object.name,
                        point: point,
                        kind: source.object.kind,
                        selected: source.object.id == selectedObjectID
                    )
                )
            }
        } else {
            let previousObjectIDs = Set(cachedObjectVisuals.map(\.id))
            let forward = cameraMotion.basis.forward
            var mandatory: [SkyLabelVisual] = []
            var resident: [SkyLabelVisual] = []
            var newcomers: [SkyLabelVisual] = []

            for source in labelSources {
                guard let direction = displayVector(for: source.object.id) else { continue }
                let wasIncluded = previousObjectIDs.contains(source.object.id)
                let depth = Vector3D.dot(direction, forward)
                guard SkyLabelEligibilityPolicy.isDepthEligible(depth, wasIncluded: wasIncluded) else { continue }
                guard let point = overlayPoint(
                    for: direction,
                    size: size,
                    wasIncluded: wasIncluded
                ) else { continue }
                let visual = SkyLabelVisual(
                    id: source.object.id,
                    text: source.object.name,
                    point: point,
                    kind: source.object.kind,
                    selected: source.object.id == selectedObjectID
                )
                if Self.isMandatoryLabel(visual, selectedObjectID: selectedObjectID) {
                    mandatory.append(visual)
                } else if wasIncluded {
                    resident.append(visual)
                } else {
                    newcomers.append(visual)
                }
            }

            visibleVisuals = SkyLabelCandidateAllocator.ordered(
                [mandatory, resident, newcomers],
                capacity: visibleCapacity
            )
        }

        cachedObjectVisuals = visibleVisuals
        cachedCardinalVisuals = cardinalVisuals
        labelProjectionKey = cacheKey
        labelOverlayScene.apply(
            visuals: cachedObjectVisuals,
            cardinals: cachedCardinalVisuals
        )
        refreshLabelPreparationState()
        metrics.recordLabelProjection(duration: CACurrentMediaTime() - start)
    }

    private func overlayPoint(
        for direction: Vector3D,
        size: CGSize,
        wasIncluded: Bool = false
    ) -> CGPoint? {
        overlayPoint(
            for: direction,
            size: size,
            renderer: sceneView,
            wasIncluded: wasIncluded
        )
    }

    private func overlayPoint(
        for direction: Vector3D,
        size: CGSize,
        renderer: any SCNSceneRenderer,
        wasIncluded: Bool = false
    ) -> CGPoint? {
        let point = renderer.projectPoint(
            SCNVector3(
                Float(direction.x * StarGeometryFactory.skyRadius),
                Float(direction.y * StarGeometryFactory.skyRadius),
                Float(direction.z * StarGeometryFactory.skyRadius)
            )
        )
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
        guard point.z >= -0.01, point.z <= 1.01 else { return nil }
#if os(macOS)
        let screenPoint = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
#else
        let screenPoint = CGPoint(x: CGFloat(point.x), y: size.height - CGFloat(point.y))
#endif
        guard SkyLabelEligibilityPolicy.isPointEligible(
            screenPoint,
            size: size,
            wasIncluded: wasIncluded
        ) else { return nil }
        return screenPoint
    }

    private func vector(azimuth: Double, altitude: Double) -> Vector3D {
        let az = azimuth * .pi / 180
        let alt = altitude * .pi / 180
        let horizontal = cos(alt)
        return Vector3D(
            x: horizontal * sin(az),
            y: sin(alt),
            z: -horizontal * cos(az)
        )
    }

    private static func isSolarSystem(_ kind: CelestialKind) -> Bool {
        kind == .sun || kind == .moon || kind == .planet
    }

    private static func isMandatoryLabel(
        _ visual: SkyLabelVisual,
        selectedObjectID: String?
    ) -> Bool {
        visual.id == selectedObjectID ||
            visual.kind == .sun ||
            visual.kind == .moon ||
            visual.kind == .planet ||
            visual.kind == .constellation
    }

    private static func shouldShowLabel(for object: CelestialObject, magnitudeLimit: Double) -> Bool {
        switch object.kind {
        case .star:
            return (object.magnitude ?? 99) <= magnitudeLimit
        case .deepSky:
            return (object.magnitude ?? 99) <= 5.0
        case .constellation, .sun, .moon, .planet:
            return true
        }
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }

    private static func cameraStatesAreApproximatelyEqual(
        _ lhs: SkyCameraState,
        _ rhs: SkyCameraState
    ) -> Bool {
        abs(shortestAngleDelta(from: lhs.azimuth, to: rhs.azimuth)) < 0.05 &&
            abs(lhs.altitude - rhs.altitude) < 0.05 &&
            abs(shortestAngleDelta(from: lhs.roll, to: rhs.roll)) < 0.05 &&
            abs(lhs.fieldOfView - rhs.fieldOfView) < 0.05
    }

    private static func shortestAngleDelta(from start: Double, to end: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return delta
    }
}

private struct LabelProjectionKey: Equatable {
    let camera: SkyCameraState
    let sceneMatrix: [Float]
    let size: CGSize
    let selectedObjectID: String?
    let showCardinals: Bool
    let labelSourceRevision: Int
    let labelCapacity: Int
}

private extension simd_float3x3 {
    var floatValues: [Float] {
        [
            columns.0.x, columns.0.y, columns.0.z,
            columns.1.x, columns.1.y, columns.1.z,
            columns.2.x, columns.2.y, columns.2.z
        ]
    }
}

private struct FrameUpdateMailboxState: Sendable {
    var isEnabled = true
    var isPending = false
    var pendingTime: TimeInterval?
}

private final class FrameUpdateMailbox: @unchecked Sendable {
    let stream: AsyncStream<TimeInterval>

    private let continuation: AsyncStream<TimeInterval>.Continuation
    private let lock = OSAllocatedUnfairLock(initialState: FrameUpdateMailboxState())

    init() {
        var continuation: AsyncStream<TimeInterval>.Continuation?
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
            continuation = $0
        }
        self.continuation = continuation!
    }

    var isEnabled: Bool {
        lock.withLock(\.isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        lock.withLock { state in
            state.isEnabled = enabled
            if !enabled {
                state.isPending = false
                state.pendingTime = nil
            }
        }
    }

    func submit(time: TimeInterval) {
        let shouldYield = lock.withLock { state -> Bool in
            guard state.isEnabled else { return false }
            if state.isPending {
                state.pendingTime = time
                return false
            }
            state.isPending = true
            return true
        }
        if shouldYield {
            continuation.yield(time)
        }
    }

    func completeFrame() {
        let nextTime = lock.withLock { state -> TimeInterval? in
            if let pendingTime = state.pendingTime {
                state.pendingTime = nil
                return pendingTime
            }
            state.isPending = false
            return nil
        }
        if let nextTime {
            continuation.yield(nextTime)
        }
    }

    func finish() {
        continuation.finish()
    }
}

private struct GeometryKey: Equatable {
    let moment: Date
    let observer: ObserverContext
    let showConstellations: Bool
    let starScale: CGFloat
}

private struct LabelSource {
    let object: CelestialObject
    let j2000Direction: Vector3D?
}

private struct LabelSourceKey: Equatable {
    let selectedObjectID: String?
    let magnitudeLimit: Double
    let objectCount: Int
}

private extension CelestialKind {
    var labelPriority: Int {
        switch self {
        case .sun: 0
        case .moon: 1
        case .planet: 2
        case .constellation: 3
        case .star: 4
        case .deepSky: 5
        }
    }
}

private func slerp(_ lhs: Vector3D, _ rhs: Vector3D, _ progress: Float) -> Vector3D? {
    let a = SIMD3<Float>(Float(lhs.x), Float(lhs.y), Float(lhs.z))
    let b = SIMD3<Float>(Float(rhs.x), Float(rhs.y), Float(rhs.z))
    let lengthA = simd_length(a)
    let lengthB = simd_length(b)
    guard lengthA > 0, lengthB > 0 else { return nil }
    let dotValue = max(-1, min(1, simd_dot(a / lengthA, b / lengthB)))
    if dotValue > 0.9995 {
        let linear = a / lengthA + (b / lengthB - a / lengthA) * progress
        guard simd_length(linear) > 0 else { return nil }
        let result = linear / simd_length(linear)
        return Vector3D(x: Double(result.x), y: Double(result.y), z: Double(result.z))
    }
    let theta = acos(dotValue)
    let sinTheta = sin(theta)
    let first = sin((1 - progress) * theta) / sinTheta
    let second = sin(progress * theta) / sinTheta
    let result = (a / lengthA) * first + (b / lengthB) * second
    return Vector3D(x: Double(result.x), y: Double(result.y), z: Double(result.z)).normalized
}
