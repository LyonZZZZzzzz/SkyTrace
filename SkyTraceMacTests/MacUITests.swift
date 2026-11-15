import AppKit
import SceneKit
import QuartzCore
import XCTest
import SkyTraceCore
@testable import SkyTrace

@MainActor
final class MacUITests: XCTestCase {
    func testDefaultStateAndInspectorToggle() {
        let state = MacUIState()
        XCTAssertEqual(state.columnVisibility, .all)

        state.toggleInspector()
        XCTAssertEqual(state.columnVisibility, .doubleColumn)

        state.toggleInspector()
        XCTAssertEqual(state.columnVisibility, .all)
    }

    func testResetDisplaySettings() {
        let state = MacUIState()
        state.showConstellations = false
        state.showCardinals = false
        state.starScale = 0.6
        state.labelDensity = .compact

        state.resetDisplaySettings()

        XCTAssertTrue(state.showConstellations)
        XCTAssertTrue(state.showCardinals)
        XCTAssertEqual(state.starScale, 1, accuracy: 0.001)
        XCTAssertEqual(state.labelDensity, .standard)
    }

    func testStarMapClickUsesTopLeftCoordinatesAndDoubleClickOnlyResets() throws {
        let frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let view = MacInteractiveSceneView(frame: frame)
        window.contentView = view
        let click = CGPoint(x: 40, y: 55)
        let location = view.convert(click, to: nil)

        var selections: [CGPoint] = []
        var resets = 0
        view.onSelect = { selections.append($0) }
        view.onReset = { resets += 1 }

        for clickCount in [1, 2] {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type,
                    location: location,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: clickCount,
                    pressure: 0
                ))
                if type == .leftMouseDown {
                    view.mouseDown(with: event)
                } else {
                    view.mouseUp(with: event)
                }
            }
        }

        let expectedY = view.isFlipped ? click.y : frame.height - click.y
        XCTAssertEqual(selections, [CGPoint(x: click.x, y: expectedY)])
        XCTAssertEqual(resets, 1)
    }

    func testRendererControllerDeallocatesAcrossRepeatedLifecycles() {
        for iteration in 0..<20 {
            weak var releasedController: SkySceneController?
            weak var releasedView: SCNView?
            let start = CACurrentMediaTime()
            var viewCreated = start
            var controllerCreated = start
            var stopped = start
            var referencesReleased = start
            autoreleasepool {
                do {
                    let view = SCNView(frame: .zero)
                    releasedView = view
                    viewCreated = CACurrentMediaTime()
                    let controller = SkySceneController(sceneView: view)
                    releasedController = controller
                    controllerCreated = CACurrentMediaTime()
                    controller.shutdown()
                    stopped = CACurrentMediaTime()
                }
                referencesReleased = CACurrentMediaTime()
            }
            let drained = CACurrentMediaTime()
            XCTAssertNil(releasedController)
            XCTAssertNil(releasedView)
            print("LIFECYCLE iteration=\(iteration) view=\(viewCreated-start) controller=\(controllerCreated-viewCreated) shutdown=\(stopped-controllerCreated) release=\(referencesReleased-stopped) drain=\(drained-referencesReleased) total=\(drained-start)")
        }
    }
}
