import CoreGraphics
import SpriteKit

struct SkyLabelVisual {
    let id: String
    let text: String
    let point: CGPoint
    let kind: CelestialKind
    let selected: Bool
}

struct SkyObjectLabelSeed {
    let id: String
    let text: String
    let kind: CelestialKind
}

/// A fixed-size SpriteKit overlay. Text textures are created only when the
/// text of a slot changes; the render loop only changes positions, colors and
/// opacity.
@MainActor
final class SkyLabelOverlayScene: SKScene {
    private enum LabelStyle: Equatable {
        case selected
        case constellation
        case deepSky
        case solarSystem
        case star
    }

    private struct PreparedObjectLabel {
        let visual: SkyLabelVisual
        let nodeIndex: Int
        let textReady: Bool
    }

    private var objectNodes: [SKLabelNode] = []
    private var objectNodeSizes: [CGSize?] = []
    private var objectNodeHasPosition: [Bool] = []
    private var objectNodeStyles: [LabelStyle?] = []
    private var activeObjectNodes: [String: Int] = [:]
    private var idleObjectNodeIndices: [Int] = []
    private var cardinalNodes: [SKLabelNode] = []
    private var cardinalNodeSizes: [CGSize?] = Array(repeating: nil, count: 4)
    private var cardinalNodeHasPosition = Array(repeating: false, count: 4)
    private var prewarmNode: SKLabelNode?
    private var prewarmTexts: [String] = []
    private var prewarmIndex = 0
    private(set) var lastTextUpdateCount = 0
    private(set) var textMeasurementCount = 0
    private(set) var styleMutationCount = 0
    private(set) var displayedObjectIDs: Set<String> = []
    private(set) var displayedCardinalIDs: Set<String> = []
    private var pendingVisibleTextIDs: Set<String> = []

    private var visibilityMode: SkyLabelVisibilityMode = .adaptive
    private var objectNodeLimit = 100
    private var stableObjectNodeIndices: [String: Int] = [:]
    private var stableObjectSeeds: [String: SkyObjectLabelSeed] = [:]
    private var pendingStableObjectSeeds: [SkyObjectLabelSeed] = []
    private var pendingStableSeedIndex = 0
    private var nodeVisibilityGeneration: [UInt64] = []
    private var activeVisibilityGeneration: UInt64 = 0
    private var previousVisibleNodeIndices: [Int] = []
    private var reusableVisibleNodeIndices: [Int] = []

    private let maximumAdaptiveObjectNodes = 100
    private let maximumTextUpdatesPerFrame = 4
    private let alwaysVisibleTextUpdatesPerFrame = 8
    private let showHorizontalPadding: CGFloat = 6
    private let showVerticalPadding: CGFloat = 4
    private let stickyHorizontalInset: CGFloat = 2
    private let stickyVerticalInset: CGFloat = 1
    private let positionQuantum: CGFloat = 0.25

    var hasPendingTextUpdates: Bool {
        pendingStableSeedIndex < pendingStableObjectSeeds.count ||
            !pendingVisibleTextIDs.isEmpty ||
            prewarmIndex < prewarmTexts.count
    }

    var pendingTextUpdateCount: Int {
        max(0, pendingStableObjectSeeds.count - pendingStableSeedIndex) +
            pendingVisibleTextIDs.count +
            max(0, prewarmTexts.count - prewarmIndex)
    }

    var debugObjectNodeCount: Int { objectNodes.count }
    var debugStableObjectNodeCount: Int { stableObjectNodeIndices.count }

    override init(size: CGSize) {
        super.init(size: size)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        scaleMode = .resizeFill
        backgroundColor = .clear
        isUserInteractionEnabled = false
        anchorPoint = .zero

        prewarmNode = SKLabelNode()
        prewarmNode?.fontName = "PingFangSC-Regular"
        prewarmNode?.fontSize = 11
        prewarmNode?.alpha = 0
        prewarmNode?.position = CGPoint(x: -10_000, y: -10_000)
        if let prewarmNode { addChild(prewarmNode) }

        cardinalNodes = (0..<4).map { _ in
            let node = SKLabelNode()
            node.fontName = "PingFangSC-Semibold"
            node.fontSize = 12
            node.fontColor = SKColor(red: 0.62, green: 0.92, blue: 1, alpha: 0.9)
            node.horizontalAlignmentMode = .center
            node.verticalAlignmentMode = .center
            node.isHidden = true
            node.zPosition = 3
            addChild(node)
            return node
        }
    }

    func configure(visibilityMode: SkyLabelVisibilityMode) {
        self.visibilityMode = visibilityMode
        objectNodeLimit = visibilityMode == .adaptive
            ? maximumAdaptiveObjectNodes
            : max(stableObjectNodeIndices.count, objectNodes.count)
        if visibilityMode == .alwaysVisible, !stableObjectSeeds.isEmpty {
            prepareObjectLabels(Array(stableObjectSeeds.values))
        }
    }

    func queuePrewarm(texts: [String]) {
        guard visibilityMode == .adaptive else { return }
        var seen = Set<String>()
        prewarmTexts = texts.filter { !$0.isEmpty && seen.insert($0).inserted }
        prewarmIndex = 0
    }

    /// Binds stable object IDs to reusable nodes. In always-visible mode the
    /// complete label source set is materialized once so manual time changes
    /// never need to allocate or evict nodes.
    func prepareObjectLabels(_ seeds: [SkyObjectLabelSeed]) {
        guard visibilityMode == .alwaysVisible else {
            queuePrewarm(texts: seeds.prefix(maximumAdaptiveObjectNodes).map(\.text))
            return
        }

        stableObjectSeeds = Dictionary(
            uniqueKeysWithValues: seeds.map { ($0.id, $0) }
        )
        ensureStableObjectNodes(for: seeds)
        pendingStableObjectSeeds = seeds.filter { seed in
            guard let index = stableObjectNodeIndices[seed.id] else { return true }
            return objectNodes[index].text != seed.text
        }
        pendingStableSeedIndex = 0
        objectNodeLimit = max(objectNodeLimit, stableObjectNodeIndices.count)
    }

    func trimIdleResources() {
        if visibilityMode == .alwaysVisible {
            trimOffscreenLabels()
            return
        }
        prewarmTexts.removeAll(keepingCapacity: false)
        prewarmIndex = 0
        prewarmNode?.text = ""
        pendingVisibleTextIDs.removeAll()

        for index in idleObjectNodeIndices {
            guard objectNodes.indices.contains(index) else { continue }
            objectNodes[index].text = ""
            objectNodeStyles[index] = nil
            objectNodeSizes[index] = nil
            objectNodes[index].isHidden = true
        }
        cardinalNodeSizes = Array(repeating: nil, count: cardinalNodes.count)
    }

    private func trimOffscreenLabels() {
        let visibleIndices = Set(displayedObjectIDs.compactMap { stableObjectNodeIndices[$0] })
        pendingStableObjectSeeds.removeAll(keepingCapacity: true)
        pendingStableSeedIndex = 0

        for index in objectNodes.indices where !visibleIndices.contains(index) {
            objectNodes[index].text = ""
            objectNodes[index].isHidden = true
            objectNodeSizes[index] = nil
            objectNodeStyles[index] = nil
        }
        cardinalNodeSizes = Array(repeating: nil, count: cardinalNodes.count)
    }

    func apply(visuals: [SkyLabelVisual], cardinals: [SkyLabelVisual]) {
        let textBudget = visibilityMode == .alwaysVisible
            ? alwaysVisibleTextUpdatesPerFrame
            : maximumTextUpdatesPerFrame
        var textUpdates = processPendingStableObjectSeeds(limit: textBudget)

        if visibilityMode == .alwaysVisible {
            applyAlwaysVisible(
                visuals: visuals,
                cardinals: cardinals,
                textUpdates: &textUpdates,
                textBudget: textBudget
            )
        } else {
            applyAdaptive(
                visuals: visuals,
                cardinals: cardinals,
                textUpdates: &textUpdates
            )
        }

        lastTextUpdateCount = textUpdates
    }

    private func processPendingStableObjectSeeds(limit: Int) -> Int {
        var updates = 0
        while updates < limit, pendingStableSeedIndex < pendingStableObjectSeeds.count {
            let seed = pendingStableObjectSeeds[pendingStableSeedIndex]
            pendingStableSeedIndex += 1
            guard let index = stableObjectNodeIndices[seed.id] else { continue }
            let node = objectNodes[index]
            if node.text != seed.text {
                node.text = seed.text
                objectNodeSizes[index] = nil
                updates += 1
            }
            applyStyleIfNeeded(Self.style(for: seed.kind, selected: false), to: index)
        }
        if pendingStableSeedIndex == pendingStableObjectSeeds.count {
            pendingStableObjectSeeds.removeAll(keepingCapacity: true)
            pendingStableSeedIndex = 0
        }
        return updates
    }

    private func ensureStableObjectNodes(for seeds: [SkyObjectLabelSeed]) {
        for seed in seeds where stableObjectNodeIndices[seed.id] == nil {
            let node = SKLabelNode()
            node.fontName = "PingFangSC-Regular"
            node.fontSize = 11
            node.horizontalAlignmentMode = .center
            node.verticalAlignmentMode = .center
            node.isHidden = true
            node.zPosition = 2
            addChild(node)

            let index = objectNodes.count
            objectNodes.append(node)
            objectNodeSizes.append(nil)
            objectNodeHasPosition.append(false)
            objectNodeStyles.append(nil)
            nodeVisibilityGeneration.append(0)
            stableObjectNodeIndices[seed.id] = index
        }
    }

    private func applyAlwaysVisible(
        visuals: [SkyLabelVisual],
        cardinals: [SkyLabelVisual],
        textUpdates: inout Int,
        textBudget: Int
    ) {
        activeVisibilityGeneration &+= 1
        reusableVisibleNodeIndices.removeAll(keepingCapacity: true)
        displayedObjectIDs.removeAll(keepingCapacity: true)

        for visual in visuals {
            guard
                let index = stableObjectNodeIndices[visual.id],
                objectNodes.indices.contains(index)
            else { continue }

            let node = objectNodes[index]
            node.position = stabilizedPoint(
                visual.point,
                current: node.position,
                hasPosition: objectNodeHasPosition[index]
            )
            objectNodeHasPosition[index] = true

            if node.text != visual.text {
                guard textUpdates < textBudget else {
                    node.isHidden = true
                    continue
                }
                node.text = visual.text
                objectNodeSizes[index] = nil
                textUpdates += 1
            }

            applyStyleIfNeeded(
                Self.style(for: visual.kind, selected: visual.selected),
                to: index
            )
            let placement = visibleLabelPlacement(
                for: node,
                cachedSize: objectNodeSizes[index],
                center: node.position
            )
            node.position = placement.center
            objectNodeSizes[index] = placement.size
            node.isHidden = false
            node.zPosition = visual.selected ? 4 : 2
            nodeVisibilityGeneration[index] = activeVisibilityGeneration
            reusableVisibleNodeIndices.append(index)
            displayedObjectIDs.insert(visual.id)
        }

        for index in previousVisibleNodeIndices
        where nodeVisibilityGeneration.indices.contains(index) &&
            nodeVisibilityGeneration[index] != activeVisibilityGeneration {
            objectNodes[index].isHidden = true
        }
        swap(&previousVisibleNodeIndices, &reusableVisibleNodeIndices)

        displayedCardinalIDs.removeAll(keepingCapacity: true)
        for (index, node) in cardinalNodes.enumerated() {
            guard index < cardinals.count else {
                node.isHidden = true
                continue
            }
            let visual = cardinals[index]
            node.position = stabilizedPoint(
                visual.point,
                current: node.position,
                hasPosition: cardinalNodeHasPosition[index]
            )
            cardinalNodeHasPosition[index] = true
            if node.text != visual.text {
                node.text = visual.text
                cardinalNodeSizes[index] = nil
            }
            let placement = visibleLabelPlacement(
                for: node,
                cachedSize: cardinalNodeSizes[index],
                center: node.position
            )
            node.position = placement.center
            cardinalNodeSizes[index] = placement.size
            node.isHidden = false
            displayedCardinalIDs.insert(visual.id)
        }
    }

    private func applyAdaptive(
        visuals: [SkyLabelVisual],
        cardinals: [SkyLabelVisual],
        textUpdates: inout Int
    ) {
        let previouslyDisplayedObjectIDs = displayedObjectIDs
        let previouslyDisplayedCardinalIDs = displayedCardinalIDs
        var assignedObjectIDs = Set<String>()
        var nextPendingVisibleTextIDs = Set<String>()
        var preparedLabels: [PreparedObjectLabel] = []
        preparedLabels.reserveCapacity(min(visuals.count, objectNodeLimit))

        for visual in visuals.prefix(objectNodeLimit) {
            guard let index = objectNodeIndex(for: visual.id) else { continue }
            assignedObjectIDs.insert(visual.id)
            let node = objectNodes[index]
            node.isHidden = true

            if node.text != visual.text {
                guard textUpdates < maximumTextUpdatesPerFrame else {
                    nextPendingVisibleTextIDs.insert(visual.id)
                    preparedLabels.append(
                        PreparedObjectLabel(visual: visual, nodeIndex: index, textReady: false)
                    )
                    continue
                }
                node.text = visual.text
                objectNodeSizes[index] = nil
                textUpdates += 1
            }

            applyStyleIfNeeded(Self.style(for: visual), to: index)
            preparedLabels.append(
                PreparedObjectLabel(
                    visual: visual,
                    nodeIndex: index,
                    textReady: node.text == visual.text
                )
            )
        }

        let inactiveIDs = activeObjectNodes.keys.filter { !assignedObjectIDs.contains($0) }
        for id in inactiveIDs {
            guard let index = activeObjectNodes.removeValue(forKey: id) else { continue }
            objectNodes[index].isHidden = true
            idleObjectNodeIndices.append(index)
        }

        displayedObjectIDs.removeAll(keepingCapacity: true)
        displayedCardinalIDs.removeAll(keepingCapacity: true)
        var occupiedShowFrames: [CGRect] = []
        var occupiedStickyFrames: [CGRect] = []
        occupiedShowFrames.reserveCapacity(preparedLabels.count + cardinals.count)
        occupiedStickyFrames.reserveCapacity(preparedLabels.count + cardinals.count)

        for label in preparedLabels where label.textReady && label.visual.selected {
            placeObjectLabel(
                label,
                wasVisible: previouslyDisplayedObjectIDs.contains(label.visual.id),
                occupiedShowFrames: &occupiedShowFrames,
                occupiedStickyFrames: &occupiedStickyFrames
            )
        }

        for (index, node) in cardinalNodes.enumerated() {
            guard index < cardinals.count else {
                node.isHidden = true
                continue
            }
            let visual = cardinals[index]
            node.position = stabilizedPoint(
                visual.point,
                current: node.position,
                hasPosition: cardinalNodeHasPosition[index]
            )
            cardinalNodeHasPosition[index] = true
            if node.text != visual.text {
                guard textUpdates < maximumTextUpdatesPerFrame else {
                    node.isHidden = true
                    continue
                }
                node.text = visual.text
                cardinalNodeSizes[index] = nil
                textUpdates += 1
            }

            let placement = visibleLabelPlacement(
                for: node,
                cachedSize: cardinalNodeSizes[index],
                center: node.position
            )
            node.position = placement.center
            cardinalNodeSizes[index] = placement.size
            let wasVisible = previouslyDisplayedCardinalIDs.contains(visual.id)
            let collision = collisionFrames(
                size: placement.size,
                center: node.position
            )
            let candidateFrame = wasVisible ? collision.sticky : collision.show
            let occupiedFrames = wasVisible ? occupiedStickyFrames : occupiedShowFrames
            guard !occupiedFrames.contains(where: { $0.intersects(candidateFrame) }) else {
                node.isHidden = true
                continue
            }
            occupiedShowFrames.append(collision.show)
            occupiedStickyFrames.append(collision.sticky)
            displayedCardinalIDs.insert(visual.id)
            node.isHidden = false
        }

        for label in preparedLabels where label.textReady && !label.visual.selected {
            placeObjectLabel(
                label,
                wasVisible: previouslyDisplayedObjectIDs.contains(label.visual.id),
                occupiedShowFrames: &occupiedShowFrames,
                occupiedStickyFrames: &occupiedStickyFrames
            )
        }

        while textUpdates < maximumTextUpdatesPerFrame, prewarmIndex < prewarmTexts.count {
            prewarmNode?.text = prewarmTexts[prewarmIndex]
            prewarmIndex += 1
            textUpdates += 1
        }
        pendingVisibleTextIDs = nextPendingVisibleTextIDs
    }

    private func placeObjectLabel(
        _ label: PreparedObjectLabel,
        wasVisible: Bool,
        occupiedShowFrames: inout [CGRect],
        occupiedStickyFrames: inout [CGRect]
    ) {
        let node = objectNodes[label.nodeIndex]
        node.position = stabilizedPoint(
            label.visual.point,
            current: node.position,
            hasPosition: objectNodeHasPosition[label.nodeIndex]
        )
        objectNodeHasPosition[label.nodeIndex] = true
        let placement = visibleLabelPlacement(
            for: node,
            cachedSize: objectNodeSizes[label.nodeIndex],
            center: node.position
        )
        node.position = placement.center
        objectNodeSizes[label.nodeIndex] = placement.size
        let collision = collisionFrames(size: placement.size, center: node.position)

        if !label.visual.selected {
            let candidateFrame = wasVisible ? collision.sticky : collision.show
            let occupiedFrames = wasVisible ? occupiedStickyFrames : occupiedShowFrames
            guard !occupiedFrames.contains(where: { $0.intersects(candidateFrame) }) else {
                node.isHidden = true
                return
            }
        }

        occupiedShowFrames.append(collision.show)
        occupiedStickyFrames.append(collision.sticky)
        displayedObjectIDs.insert(label.visual.id)
        node.isHidden = false
    }

    private func applyStyleIfNeeded(_ style: LabelStyle, to index: Int) {
        guard objectNodeStyles[index] != style else { return }
        let node = objectNodes[index]
        switch style {
        case .selected:
            node.fontSize = 12
            node.fontColor = SKColor(red: 1, green: 0.60, blue: 0.22, alpha: 1)
            node.alpha = 1
        case .constellation:
            node.fontSize = 10.5
            node.fontColor = SKColor(red: 0.25, green: 0.82, blue: 0.98, alpha: 0.82)
            node.alpha = 0.86
        case .deepSky:
            node.fontSize = 11
            node.fontColor = SKColor(red: 0.35, green: 0.92, blue: 0.76, alpha: 0.90)
            node.alpha = 0.86
        case .solarSystem:
            node.fontSize = 11
            node.fontColor = .white
            node.alpha = 0.86
        case .star:
            node.fontSize = 11
            node.fontColor = SKColor(white: 1, alpha: 0.88)
            node.alpha = 0.86
        }
        objectNodeStyles[index] = style
        objectNodeSizes[index] = nil
        styleMutationCount += 1
    }

    private static func style(for visual: SkyLabelVisual) -> LabelStyle {
        style(for: visual.kind, selected: visual.selected)
    }

    private static func style(for kind: CelestialKind, selected: Bool) -> LabelStyle {
        if selected { return .selected }
        switch kind {
        case .constellation:
            return .constellation
        case .deepSky:
            return .deepSky
        case .sun, .moon, .planet:
            return .solarSystem
        case .star:
            return .star
        }
    }

    private func visibleLabelPlacement(
        for node: SKLabelNode,
        cachedSize: CGSize?,
        center: CGPoint
    ) -> (center: CGPoint, size: CGSize) {
        let size: CGSize
        if let cachedSize {
            size = cachedSize
        } else {
            textMeasurementCount += 1
            let measured = node.calculateAccumulatedFrame()
            size = CGSize(
                width: max(measured.width, node.fontSize),
                height: max(measured.height, node.fontSize)
            )
        }
        let halfWidth = min(size.width * 0.5, self.size.width * 0.5)
        let halfHeight = min(size.height * 0.5, self.size.height * 0.5)
        let clamped = CGPoint(
            x: min(max(center.x, halfWidth), max(halfWidth, self.size.width - halfWidth)),
            y: min(max(center.y, halfHeight), max(halfHeight, self.size.height - halfHeight))
        )
        return (clamped, size)
    }

    private func collisionFrames(
        size: CGSize,
        center: CGPoint
    ) -> (show: CGRect, sticky: CGRect) {
        let baseFrame = CGRect(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
        let showFrame = baseFrame.insetBy(dx: -showHorizontalPadding, dy: -showVerticalPadding)
        let stickyFrame = baseFrame.insetBy(dx: stickyHorizontalInset, dy: stickyVerticalInset)
        return (showFrame, stickyFrame)
    }

    private func stabilizedPoint(
        _ point: CGPoint,
        current: CGPoint,
        hasPosition: Bool
    ) -> CGPoint {
        let quantized = CGPoint(
            x: (point.x / positionQuantum).rounded() * positionQuantum,
            y: (point.y / positionQuantum).rounded() * positionQuantum
        )
        guard hasPosition else { return quantized }
        let distance = hypot(quantized.x - current.x, quantized.y - current.y)
        return distance < positionQuantum ? current : quantized
    }

    func debugObjectPoint(for objectID: String) -> CGPoint? {
        if visibilityMode == .alwaysVisible,
           let index = stableObjectNodeIndices[objectID] {
            return objectNodes[index].position
        }
        guard let index = activeObjectNodes[objectID] else { return nil }
        return objectNodes[index].position
    }

    func debugObjectFrame(for objectID: String) -> CGRect? {
        let index: Int?
        if visibilityMode == .alwaysVisible {
            index = stableObjectNodeIndices[objectID]
        } else {
            index = activeObjectNodes[objectID]
        }
        guard let index, objectNodes.indices.contains(index) else { return nil }
        return objectNodes[index].calculateAccumulatedFrame()
    }

    func debugObjectHasText(_ objectID: String) -> Bool {
        let index = stableObjectNodeIndices[objectID] ?? activeObjectNodes[objectID]
        guard let index, objectNodes.indices.contains(index) else { return false }
        return !(objectNodes[index].text ?? "").isEmpty
    }

    private func objectNodeIndex(for objectID: String) -> Int? {
        if let index = activeObjectNodes[objectID] {
            return index
        }
        if let index = idleObjectNodeIndices.popLast() {
            activeObjectNodes[objectID] = index
            return index
        }
        guard objectNodes.count < objectNodeLimit else { return nil }
        let node = SKLabelNode()
        node.fontName = "PingFangSC-Regular"
        node.fontSize = 11
        node.horizontalAlignmentMode = .center
        node.verticalAlignmentMode = .center
        node.isHidden = true
        node.zPosition = 2
        addChild(node)
        objectNodes.append(node)
        objectNodeSizes.append(nil)
        objectNodeHasPosition.append(false)
        objectNodeStyles.append(nil)
        nodeVisibilityGeneration.append(0)
        let index = objectNodes.count - 1
        activeObjectNodes[objectID] = index
        return index
    }

    func debugStyleMutationCount() -> Int {
        styleMutationCount
    }
}
