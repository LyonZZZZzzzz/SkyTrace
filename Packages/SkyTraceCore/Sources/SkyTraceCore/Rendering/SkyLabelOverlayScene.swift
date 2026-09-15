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
    private var cardinalNodes: [SKLabelNode] = []

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

        objectNodes = (0..<100).map { _ in
            let node = SKLabelNode()
            node.fontName = "PingFangSC-Regular"
            node.fontSize = 11
            node.horizontalAlignmentMode = .center
            node.verticalAlignmentMode = .center
            node.isHidden = true
            node.zPosition = 2
            addChild(node)
            return node
        }

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

    func apply(visuals: [SkyLabelVisual], cardinals: [SkyLabelVisual]) {
        for (index, node) in objectNodes.enumerated() {
            guard index < visuals.count else {
                node.isHidden = true
                continue
            }
            let visual = visuals[index]
            if node.text != visual.text {
                node.text = visual.text
            }
            node.position = visual.point
            node.fontSize = visual.selected ? 12 : (visual.kind == .constellation ? 10.5 : 11)
            node.fontColor = color(for: visual)
            node.alpha = visual.selected ? 1 : 0.86
            node.isHidden = false
        }

        for (index, node) in cardinalNodes.enumerated() {
            guard index < cardinals.count else {
                node.isHidden = true
                continue
            }
            let visual = cardinals[index]
            if node.text != visual.text {
                node.text = visual.text
            }
            node.position = visual.point
            node.isHidden = false
        }
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
