import CoreGraphics
import SpriteKit

struct SkyLabelVisual {
    let id: String
    let text: String
    let point: CGPoint
    let kind: CelestialKind
    let selected: Bool
}

/// A fixed-size SpriteKit overlay. Text textures are created only when the
/// text of a slot changes; the render loop only changes positions, colors and
/// opacity.
@MainActor
final class SkyLabelOverlayScene: SKScene {
    private struct PreparedObjectLabel {
        let visual: SkyLabelVisual
        let nodeIndex: Int
        let textReady: Bool
    }

    private var objectNodes: [SKLabelNode] = []
    private var objectNodeSizes: [CGSize?] = []
    private var activeObjectNodes: [String: Int] = [:]
    private var idleObjectNodeIndices: [Int] = []
    private var cardinalNodes: [SKLabelNode] = []
    private var cardinalNodeSizes: [CGSize?] = Array(repeating: nil, count: 4)
    private var prewarmNode: SKLabelNode?
    private var prewarmTexts: [String] = []
    private var prewarmIndex = 0
    private(set) var lastTextUpdateCount = 0
    private(set) var textMeasurementCount = 0
    private(set) var displayedObjectIDs: Set<String> = []
    private(set) var displayedCardinalIDs: Set<String> = []
    private let maximumObjectNodes = 100
    private let maximumTextUpdatesPerFrame = 4
    private let horizontalPadding: CGFloat = 6
    private let verticalPadding: CGFloat = 4

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

    func queuePrewarm(texts: [String]) {
        var seen = Set<String>()
        prewarmTexts = texts.filter { !$0.isEmpty && seen.insert($0).inserted }
        prewarmIndex = 0
    }

    func apply(visuals: [SkyLabelVisual], cardinals: [SkyLabelVisual]) {
        var textUpdates = 0
        var assignedObjectIDs = Set<String>()
        var preparedLabels: [PreparedObjectLabel] = []
        preparedLabels.reserveCapacity(min(visuals.count, maximumObjectNodes))

        for visual in visuals.prefix(maximumObjectNodes) {
            guard let index = objectNodeIndex(for: visual.id) else { continue }
            assignedObjectIDs.insert(visual.id)
            let node = objectNodes[index]
            node.isHidden = true

            if node.text != visual.text {
                guard textUpdates < maximumTextUpdatesPerFrame else {
                    preparedLabels.append(
                        PreparedObjectLabel(visual: visual, nodeIndex: index, textReady: false)
                    )
                    continue
                }
                node.text = visual.text
                objectNodeSizes[index] = nil
                textUpdates += 1
            }

            let targetFontSize = visual.selected ? 12 : (visual.kind == .constellation ? 10.5 : 11)
            if abs(node.fontSize - targetFontSize) > 0.01 {
                node.fontSize = targetFontSize
                objectNodeSizes[index] = nil
            }
            node.fontColor = color(for: visual)
            node.alpha = visual.selected ? 1 : 0.86
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
        var occupiedFrames: [CGRect] = []
        occupiedFrames.reserveCapacity(preparedLabels.count + cardinals.count)

        for label in preparedLabels where label.textReady && label.visual.selected {
            placeObjectLabel(label, occupiedFrames: &occupiedFrames)
        }

        for (index, node) in cardinalNodes.enumerated() {
            guard index < cardinals.count else {
                node.isHidden = true
                continue
            }
            let visual = cardinals[index]
            node.position = visual.point
            if node.text != visual.text {
                guard textUpdates < maximumTextUpdatesPerFrame else {
                    node.isHidden = true
                    continue
                }
                node.text = visual.text
                cardinalNodeSizes[index] = nil
                textUpdates += 1
            }

            let collision = collisionFrame(
                for: node,
                cachedSize: cardinalNodeSizes[index],
                center: visual.point
            )
            guard !occupiedFrames.contains(where: { $0.intersects(collision.frame) }) else {
                node.isHidden = true
                continue
            }
            cardinalNodeSizes[index] = collision.size
            occupiedFrames.append(collision.frame)
            displayedCardinalIDs.insert(visual.id)
            node.isHidden = false
        }

        for label in preparedLabels where label.textReady && !label.visual.selected {
            placeObjectLabel(label, occupiedFrames: &occupiedFrames)
        }

        while textUpdates < maximumTextUpdatesPerFrame, prewarmIndex < prewarmTexts.count {
            prewarmNode?.text = prewarmTexts[prewarmIndex]
            prewarmIndex += 1
            textUpdates += 1
        }
        lastTextUpdateCount = textUpdates
    }

    private func placeObjectLabel(
        _ label: PreparedObjectLabel,
        occupiedFrames: inout [CGRect]
    ) {
        let node = objectNodes[label.nodeIndex]
        node.position = label.visual.point
        let collision = collisionFrame(
            for: node,
            cachedSize: objectNodeSizes[label.nodeIndex],
            center: label.visual.point
        )

        if !label.visual.selected {
            guard !occupiedFrames.contains(where: { $0.intersects(collision.frame) }) else {
                node.isHidden = true
                return
            }
        }

        objectNodeSizes[label.nodeIndex] = collision.size
        occupiedFrames.append(collision.frame)
        displayedObjectIDs.insert(label.visual.id)
        node.isHidden = false
    }

    private func collisionFrame(
        for node: SKLabelNode,
        cachedSize: CGSize?,
        center: CGPoint
    ) -> (frame: CGRect, size: CGSize) {
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
        let frame = CGRect(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
        .insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        return (frame, size)
    }

    private func objectNodeIndex(for objectID: String) -> Int? {
        if let index = activeObjectNodes[objectID] {
            return index
        }
        if let index = idleObjectNodeIndices.popLast() {
            activeObjectNodes[objectID] = index
            return index
        }
        guard objectNodes.count < maximumObjectNodes else { return nil }
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
        let index = objectNodes.count - 1
        activeObjectNodes[objectID] = index
        return index
    }

    private func color(for visual: SkyLabelVisual) -> SKColor {
        if visual.selected {
            return SKColor(red: 1, green: 0.60, blue: 0.22, alpha: 1)
        }
        switch visual.kind {
        case .constellation:
            return SKColor(red: 0.25, green: 0.82, blue: 0.98, alpha: 0.82)
        case .deepSky:
            return SKColor(red: 0.35, green: 0.92, blue: 0.76, alpha: 0.90)
        case .planet, .sun, .moon:
            return .white
        case .star:
            return SKColor(white: 1, alpha: 0.88)
        }
    }
}
