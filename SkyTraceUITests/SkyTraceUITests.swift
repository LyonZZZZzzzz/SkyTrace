import XCTest

@MainActor
final class SkyTraceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchAndOpenSearch() {
        let app = XCUIApplication()
        app.launch()

        if app.buttons["稍后探索"].waitForExistence(timeout: 3) {
            app.buttons["稍后探索"].tap()
        }

        let searchButton = app.buttons["搜索天体"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 8))
        searchButton.tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("金星")
        XCTAssertTrue(app.staticTexts["金星"].waitForExistence(timeout: 3))
    }
}
