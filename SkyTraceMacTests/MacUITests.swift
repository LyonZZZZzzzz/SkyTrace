import XCTest
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
}
