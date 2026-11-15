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

    func testLongLabelIsClampedInsideViewport() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 320, height: 240))
        let labels = [
            visual(
                id: "edge",
                text: "这是一个非常靠左且很长很长的恒星名称",
                point: CGPoint(x: 1, y: 120),
                kind: .star
            )
        ]

        scene.apply(visuals: labels, cardinals: [])

        let frame = try? XCTUnwrap(scene.debugObjectFrame(for: "edge"))
        XCTAssertGreaterThanOrEqual(frame?.minX ?? -1, 0)
        XCTAssertLessThanOrEqual(frame?.maxX ?? .infinity, scene.size.width)
    }

    func testAlwaysVisibleTrimKeepsOnscreenTextAndClearsOffscreenText() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        scene.configure(visibilityMode: .alwaysVisible)
        let seeds = (0..<20).map {
            SkyObjectLabelSeed(id: "object-\($0)", text: "名称\($0)", kind: .star)
        }
        scene.prepareObjectLabels(seeds)
        let allVisuals = seeds.map {
            visual(
                id: $0.id,
                text: $0.text,
                point: CGPoint(x: 100, y: 100),
                kind: .star
            )
        }
        for _ in 0..<4 {
            scene.apply(visuals: allVisuals, cardinals: [])
        }
        XCTAssertTrue(scene.debugObjectHasText("object-19"))

        scene.apply(visuals: [allVisuals[0]], cardinals: [])
        scene.trimIdleResources()

        XCTAssertTrue(scene.debugObjectHasText("object-0"))
        XCTAssertFalse(scene.debugObjectHasText("object-19"))
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

    func testSubPixelPointChangesDoNotMoveStableLabel() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let first = visual(id: "star", text: "测试", point: CGPoint(x: 200, y: 200), kind: .star)
        let tinyChange = visual(id: "star", text: "测试", point: CGPoint(x: 200.1, y: 200.05), kind: .star)
        let visibleChange = visual(id: "star", text: "测试", point: CGPoint(x: 200.5, y: 200), kind: .star)

        scene.apply(visuals: [first], cardinals: [])
        let initialPoint = scene.debugObjectPoint(for: "star")

        scene.apply(visuals: [tinyChange], cardinals: [])
        XCTAssertEqual(scene.debugObjectPoint(for: "star"), initialPoint)

        scene.apply(visuals: [visibleChange], cardinals: [])
        XCTAssertNotEqual(scene.debugObjectPoint(for: "star"), initialPoint)
    }

    func testVisibilityHysteresisPreventsBoundaryFlicker() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let first = visual(id: "a", text: "测试", point: CGPoint(x: 300, y: 300), kind: .star)

        scene.apply(visuals: [first, visual(id: "b", text: "测试", point: CGPoint(x: 300, y: 340), kind: .star)], cardinals: [])
        XCTAssertEqual(scene.displayedObjectIDs, Set(["a", "b"]))

        scene.apply(visuals: [first, visual(id: "b", text: "测试", point: CGPoint(x: 300, y: 318), kind: .star)], cardinals: [])
        XCTAssertEqual(scene.displayedObjectIDs, Set(["a", "b"]))

        scene.apply(visuals: [first, visual(id: "b", text: "测试", point: CGPoint(x: 300, y: 308), kind: .star)], cardinals: [])
        XCTAssertEqual(scene.displayedObjectIDs, Set(["a"]))

        scene.apply(visuals: [first, visual(id: "b", text: "测试", point: CGPoint(x: 300, y: 318), kind: .star)], cardinals: [])
        XCTAssertEqual(scene.displayedObjectIDs, Set(["a"]))

        scene.apply(visuals: [first, visual(id: "b", text: "测试", point: CGPoint(x: 300, y: 340), kind: .star)], cardinals: [])
        XCTAssertEqual(scene.displayedObjectIDs, Set(["a", "b"]))
    }

    func testRepeatedApplyDoesNotMutateLabelStyles() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let visuals = [
            visual(id: "star", text: "恒星", point: CGPoint(x: 200, y: 200), kind: .star),
            visual(id: "constellation", text: "星座", point: CGPoint(x: 400, y: 200), kind: .constellation),
            visual(id: "deep-sky", text: "星云", point: CGPoint(x: 600, y: 200), kind: .deepSky),
            visual(id: "planet", text: "行星", point: CGPoint(x: 400, y: 400), kind: .planet)
        ]

        scene.apply(visuals: visuals, cardinals: [])
        let styleMutationCount = scene.styleMutationCount
        scene.apply(visuals: visuals, cardinals: [])
        scene.apply(visuals: Array(visuals.reversed()), cardinals: [])

        XCTAssertGreaterThan(styleMutationCount, 0)
        XCTAssertEqual(scene.styleMutationCount, styleMutationCount)
    }

    func testSelectedStyleChangeMutatesOnlySelectedNode() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let star = visual(id: "star", text: "恒星", point: CGPoint(x: 200, y: 200), kind: .star)
        let planet = visual(id: "planet", text: "行星", point: CGPoint(x: 500, y: 200), kind: .planet)

        scene.apply(visuals: [star, planet], cardinals: [])
        let styleMutationCount = scene.styleMutationCount

        scene.apply(
            visuals: [
                visual(id: "star", text: "恒星", point: CGPoint(x: 200, y: 200), kind: .star, selected: true),
                planet
            ],
            cardinals: []
        )

        XCTAssertEqual(scene.styleMutationCount, styleMutationCount + 1)
    }

    func testPositionOnlyUpdatesDoNotMutateStyles() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 2000, height: 2000))
        let visuals = (0..<100).map { index in
            visual(
                id: "object-\(index)",
                text: "测试",
                point: CGPoint(x: CGFloat(index % 10) * 150 + 100, y: CGFloat(index / 10) * 150 + 100),
                kind: .star
            )
        }

        for _ in 0..<25 {
            scene.apply(visuals: visuals, cardinals: [])
        }
        let styleMutationCount = scene.styleMutationCount
        XCTAssertEqual(styleMutationCount, 100)

        let moved = visuals.map { item in
            visual(
                id: item.id,
                text: item.text,
                point: CGPoint(x: item.point.x + 0.5, y: item.point.y + 0.5),
                kind: item.kind,
                selected: item.selected
            )
        }
        scene.apply(visuals: moved, cardinals: [])

        XCTAssertEqual(scene.styleMutationCount, styleMutationCount)
    }

    func testEligibilityPolicyUsesRelaxedBoundsForRetainedLabels() {
        let size = CGSize(width: 800, height: 600)
        let edgePoint = CGPoint(x: 850, y: 300)

        XCTAssertFalse(
            SkyLabelEligibilityPolicy.isPointEligible(edgePoint, size: size, wasIncluded: false)
        )
        XCTAssertTrue(
            SkyLabelEligibilityPolicy.isPointEligible(edgePoint, size: size, wasIncluded: true)
        )
        XCTAssertFalse(SkyLabelEligibilityPolicy.isDepthEligible(0, wasIncluded: false))
        XCTAssertTrue(SkyLabelEligibilityPolicy.isDepthEligible(0, wasIncluded: true))
        XCTAssertFalse(SkyLabelEligibilityPolicy.isDepthEligible(-0.1, wasIncluded: true))
    }

    func testPendingTextUpdatesClearAfterAllTexturesAreReady() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        let visuals = (0..<10).map {
            visual(
                id: "object-\($0)",
                text: "名称\($0)",
                point: CGPoint(x: $0 * 50 + 50, y: 300),
                kind: .star
            )
        }

        scene.apply(visuals: visuals, cardinals: [])
        XCTAssertTrue(scene.hasPendingTextUpdates)

        scene.apply(visuals: visuals, cardinals: [])
        XCTAssertTrue(scene.hasPendingTextUpdates)

        scene.apply(visuals: visuals, cardinals: [])
        XCTAssertFalse(scene.hasPendingTextUpdates)
    }

    func testAlwaysVisibleModeKeepsOverlappingLabelsAndCardinals() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        scene.configure(visibilityMode: .alwaysVisible)
        let point = CGPoint(x: 300, y: 240)
        let visuals = [
            visual(id: "selected", text: "选中目标", point: point, kind: .star, selected: true),
            visual(id: "other", text: "其他星体", point: point, kind: .star),
            visual(id: "constellation", text: "测试座", point: point, kind: .constellation)
        ]
        scene.prepareObjectLabels(
            visuals.map { SkyObjectLabelSeed(id: $0.id, text: $0.text, kind: $0.kind) }
        )

        scene.apply(
            visuals: visuals,
            cardinals: [visual(id: "cardinal-北", text: "北", point: point, kind: .constellation)]
        )

        XCTAssertEqual(scene.displayedObjectIDs, Set(["selected", "other", "constellation"]))
        XCTAssertEqual(scene.displayedCardinalIDs, Set(["cardinal-北"]))
        XCTAssertFalse(scene.hasPendingTextUpdates)
    }

    func testAlwaysVisibleModeKeepsFixedNodeCountAcrossCameraChurn() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        scene.configure(visibilityMode: .alwaysVisible)
        let seeds = (0..<200).map {
            SkyObjectLabelSeed(id: "object-\($0)", text: "名称\($0)", kind: .star)
        }
        scene.prepareObjectLabels(seeds)

        for _ in 0..<25 {
            scene.apply(visuals: [], cardinals: [])
        }
        XCTAssertEqual(scene.debugObjectNodeCount, 200)
        XCTAssertFalse(scene.hasPendingTextUpdates)

        for iteration in 0..<1_000 {
            let offset = iteration % seeds.count
            let visuals = (0..<40).map { index in
                let seed = seeds[(index + offset) % seeds.count]
                return visual(
                    id: seed.id,
                    text: seed.text,
                    point: CGPoint(x: index * 15, y: 300),
                    kind: seed.kind
                )
            }
            scene.apply(visuals: visuals, cardinals: [])
        }

        XCTAssertEqual(scene.debugObjectNodeCount, 200)
        XCTAssertFalse(scene.hasPendingTextUpdates)
    }

    func testCapacityPolicyChangesWithFOVHysteresis() {
        var policy = SkyLabelCapacityPolicy()

        XCTAssertEqual(policy.update(fieldOfView: 20), 100)
        XCTAssertEqual(policy.update(fieldOfView: 75), 100)
        XCTAssertEqual(policy.update(fieldOfView: 76), 90)
        XCTAssertEqual(policy.update(fieldOfView: 90), 90)
        XCTAssertEqual(policy.update(fieldOfView: 91), 80)
        XCTAssertEqual(policy.update(fieldOfView: 86), 80)
        XCTAssertEqual(policy.update(fieldOfView: 84), 90)
        XCTAssertEqual(policy.update(fieldOfView: 71), 90)
        XCTAssertEqual(policy.update(fieldOfView: 69), 100)
    }

    func testCandidateAllocatorPrioritizesMandatoryThenResidentLabels() {
        let result = SkyLabelCandidateAllocator.ordered(
            [["selected", "sun"], ["resident-a", "resident-b"], ["new-a"]],
            capacity: 4
        )

        XCTAssertEqual(result, ["selected", "sun", "resident-a", "resident-b"])
    }

    func testCandidateAllocatorDoesNotExceedCapacity() {
        let result = SkyLabelCandidateAllocator.ordered(
            [[1, 2], [3, 4], [5, 6]],
            capacity: 3
        )

        XCTAssertEqual(result, [1, 2, 3])
    }

    func testPrewarmQueueProcessesAtMostFourTextsPerFrame() {
        let scene = SkyLabelOverlayScene(size: CGSize(width: 800, height: 600))
        scene.queuePrewarm(texts: ["一", "二", "三", "四", "五", "六"])

        XCTAssertTrue(scene.hasPendingTextUpdates)
        scene.apply(visuals: [], cardinals: [])
        XCTAssertEqual(scene.lastTextUpdateCount, 4)
        XCTAssertTrue(scene.hasPendingTextUpdates)
        scene.apply(visuals: [], cardinals: [])
        XCTAssertLessThanOrEqual(scene.lastTextUpdateCount, 2)
        XCTAssertFalse(scene.hasPendingTextUpdates)
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
