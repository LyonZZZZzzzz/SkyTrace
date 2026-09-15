import XCTest

@MainActor
final class SkyTraceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchAndOpenSearch() {
        let app = launchApp()
        let searchButton = app.buttons["搜索天体"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 8))
        searchButton.tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("金星")
        XCTAssertTrue(app.staticTexts["金星"].waitForExistence(timeout: 3))
    }

    func testOpenObservationPlan() {
        let app = launchApp()
        let planButton = app.buttons["今晚观测计划"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 8))
        planButton.tap()
        XCTAssertTrue(app.staticTexts["今夜时间线"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["推荐目标"].exists)
    }

    func testOpenFavorites() {
        let app = launchApp()
        let favoritesButton = app.buttons["打开收藏"]
        XCTAssertTrue(favoritesButton.waitForExistence(timeout: 8))
        favoritesButton.tap()
        XCTAssertTrue(app.navigationBars["收藏"].waitForExistence(timeout: 4))
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        if app.buttons["稍后探索"].waitForExistence(timeout: 3) {
            app.buttons["稍后探索"].tap()
        }
        return app
    }
}
