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
    private var objectNodes: [SKLabelNode] = []
    private var activeObjectNodes: [String: Int] = [:]
    private var idleObjectNodeIndices: [Int] = []
    private var cardinalNodes: [SKLabelNode] = []
    private var prewarmNode: SKLabelNode?
    private var prewarmTexts: [String] = []
    private var prewarmIndex = 0
    private(set) var lastTextUpdateCount = 0
    private let maximumObjectNodes = 100
    private let maximumTextUpdatesPerFrame = 4

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
        var visibleObjectIDs = Set<String>()

        for visual in visuals.prefix(maximumObjectNodes) {
            guard let index = objectNodeIndex(for: visual.id) else { continue }
            let node = objectNodes[index]
            visibleObjectIDs.insert(visual.id)

            if node.text != visual.text {
                guard textUpdates < maximumTextUpdatesPerFrame else {
                    node.isHidden = true
                    continue
                }
                node.text = visual.text
                textUpdates += 1
            }

            node.position = visual.point
            let targetFontSize = visual.selected ? 12 : (visual.kind == .constellation ? 10.5 : 11)
            if abs(node.fontSize - targetFontSize) > 0.01 {
                node.fontSize = targetFontSize
            }
            node.fontColor = color(for: visual)
            node.alpha = visual.selected ? 1 : 0.86
            node.isHidden = false
        }

        let inactiveIDs = activeObjectNodes.keys.filter { !visibleObjectIDs.contains($0) }
        for id in inactiveIDs {
            guard let index = activeObjectNodes.removeValue(forKey: id) else { continue }
            objectNodes[index].isHidden = true
            idleObjectNodeIndices.append(index)
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
                textUpdates += 1
            }
            node.isHidden = false
        }

        while textUpdates < maximumTextUpdatesPerFrame, prewarmIndex < prewarmTexts.count {
            prewarmNode?.text = prewarmTexts[prewarmIndex]
            prewarmIndex += 1
            textUpdates += 1
        }
        lastTextUpdateCount = textUpdates
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
