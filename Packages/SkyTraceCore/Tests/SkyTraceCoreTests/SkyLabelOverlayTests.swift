import CoreGraphics
import XCTest
@testable import SkyTraceCore

@MainActor
final class SkyLabelOverlayTests: XCTestCase {
    func testTextTextureUpdatesAreLimitedPerFrame() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let visuals = (0..<20).map {
            SkyLabelVisual(
                id: "object-\($0)",
                text: "Label \($0)",
                point: CGPoint(x: $0 * 10, y: $0 * 10),
                kind: .star,
                selected: false
            )
        }

        scene.apply(visuals: visuals, cardinals: [])
        XCTAssertLessThanOrEqual(scene.lastTextUpdateCount, 4)
        XCTAssertGreaterThan(scene.lastTextUpdateCount, 0)

        scene.apply(visuals: visuals, cardinals: [])
        XCTAssertLessThanOrEqual(scene.lastTextUpdateCount, 4)
    }

    func testReorderedVisualsReuseNodesByObjectID() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let visuals = (0..<4).map {
            SkyLabelVisual(
                id: "object-\($0)",
                text: "Label \($0)",
                point: CGPoint(x: $0 * 10, y: $0 * 10),
                kind: .star,
                selected: false
            )
        }

        scene.apply(visuals: visuals, cardinals: [])
        scene.apply(visuals: Array(visuals.reversed()), cardinals: [])

        XCTAssertEqual(scene.lastTextUpdateCount, 0)
    }

    func testPrewarmQueueProcessesAtMostFourTextsPerFrame() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        scene.queuePrewarm(texts: ["一", "二", "三", "四", "五", "六"])

        scene.apply(visuals: [], cardinals: [])
        XCTAssertEqual(scene.lastTextUpdateCount, 4)
        scene.apply(visuals: [], cardinals: [])
        XCTAssertLessThanOrEqual(scene.lastTextUpdateCount, 2)
    }
}
