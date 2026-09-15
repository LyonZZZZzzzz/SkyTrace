import XCTest

@MainActor
final class SkyTraceMacUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchAndOpenSearch() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["今晚观测"].waitForExistence(timeout: 6))

        let planButton = app.buttons["今晚可见"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 5))
        planButton.click()
        XCTAssertTrue(app.staticTexts["今夜时间线"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["天空事件"].exists)
        app.buttons["关闭"].click()

        app.activate()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["搜索天空"].waitForExistence(timeout: 6))

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.click()
        field.typeText("M42")
        XCTAssertTrue(app.staticTexts["猎户座大星云"].waitForExistence(timeout: 5))
    }
}
