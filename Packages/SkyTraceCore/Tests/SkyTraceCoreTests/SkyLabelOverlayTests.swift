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

    func testOverlappingLabelsKeepHigherPriorityVisual() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let visuals = [
            visual(id: "constellation", text: "测试座", point: CGPoint(x: 200, y: 200), kind: .constellation),
            visual(id: "star", text: "测试星", point: CGPoint(x: 200, y: 200), kind: .star)
        ]

        scene.apply(visuals: visuals, cardinals: [])

        XCTAssertEqual(scene.displayedObjectIDs, Set(["constellation"]))
    }

    func testSelectedLabelWinsOverCardinalAndOtherLabels() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let point = CGPoint(x: 300, y: 240)
        let visuals = [
            visual(id: "selected", text: "选中目标", point: point, kind: .star, selected: true),
            visual(id: "other", text: "其他星体", point: point, kind: .star)
        ]
        let cardinals = [visual(id: "cardinal-北", text: "北", point: point, kind: .constellation)]

        scene.apply(visuals: visuals, cardinals: cardinals)

        XCTAssertEqual(scene.displayedObjectIDs, Set(["selected"]))
        XCTAssertTrue(scene.displayedCardinalIDs.isEmpty)
    }

    func testLabelMeasurementIsCachedAcrossPositionChanges() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let first = [visual(id: "star", text: "测试星", point: CGPoint(x: 200, y: 200), kind: .star)]
        let second = [visual(id: "star", text: "测试星", point: CGPoint(x: 300, y: 240), kind: .star)]

        scene.apply(visuals: first, cardinals: [])
        let measurementCount = scene.textMeasurementCount
        scene.apply(visuals: second, cardinals: [])

        XCTAssertEqual(scene.textMeasurementCount, measurementCount)
        XCTAssertTrue(scene.displayedObjectIDs.contains("star"))
    }

    func testHiddenLabelReturnsWhenSpaceOpens() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let constellation = visual(
            id: "constellation",
            text: "测试座",
            point: CGPoint(x: 240, y: 220),
            kind: .constellation
        )
        var star = visual(
            id: "star",
            text: "测试星",
            point: CGPoint(x: 240, y: 220),
            kind: .star
        )

        scene.apply(visuals: [constellation, star], cardinals: [])
        XCTAssertFalse(scene.displayedObjectIDs.contains("star"))

        star = visual(id: "star", text: "测试星", point: CGPoint(x: 500, y: 220), kind: .star)
        scene.apply(visuals: [constellation, star], cardinals: [])

        XCTAssertEqual(scene.displayedObjectIDs, Set(["constellation", "star"]))
    }

    func testPrewarmQueueProcessesAtMostFourTextsPerFrame() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        scene.queuePrewarm(texts: ["一", "二", "三", "四", "五", "六"])

        scene.apply(visuals: [], cardinals: [])
        XCTAssertEqual(scene.lastTextUpdateCount, 4)
        scene.apply(visuals: [], cardinals: [])
        XCTAssertLessThanOrEqual(scene.lastTextUpdateCount, 2)
    }

    private func visual(
        id: String,
        text: String,
        point: CGPoint,
        kind: CelestialKind,
        selected: Bool = false
    ) -> SkyLabelVisual {
        SkyLabelVisual(id: id, text: text, point: point, kind: kind, selected: selected)
    }
}
