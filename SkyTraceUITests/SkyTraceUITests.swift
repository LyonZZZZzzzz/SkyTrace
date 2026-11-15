import XCTest

@MainActor
final class SkyTraceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launch()
            XCTAssertTrue(app.buttons["搜索天体"].waitForExistence(timeout: 8))
            app.terminate()
        }
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

    func testStarMapPanSmoke() {
        let app = launchApp()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))

        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
        let upward = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        start.press(forDuration: 0.1, thenDragTo: upward)

        let downward = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        upward.press(forDuration: 0.1, thenDragTo: downward)

        XCTAssertTrue(app.buttons["搜索天体"].exists)
    }

    func testBackgroundForegroundThenPan() {
        let app = launchApp()
        let searchButton = app.buttons["搜索天体"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 8))

        let motionButton = app.buttons["开启姿态跟随"]
        XCTAssertTrue(motionButton.waitForExistence(timeout: 3))
        motionButton.tap()
        XCTAssertTrue(app.buttons["关闭姿态跟随"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["time.select"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["播放时间"].exists)

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(searchButton.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["关闭姿态跟随"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["time.now"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["time.select"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["播放时间"].exists)

        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(searchButton.exists)
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


    func testManualTimeSelectionControls() {
        let app = launchApp()
        let nowButton = app.buttons["time.now"]
        XCTAssertTrue(nowButton.waitForExistence(timeout: 8))

        let selectButton = app.buttons["time.select"]
        XCTAssertTrue(selectButton.waitForExistence(timeout: 3))
        selectButton.tap()
        XCTAssertTrue(app.navigationBars["选择时间"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["播放时间"].exists)
    }

    func testMaximumZoomPanSmoke() {
        let app = launchApp()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))

        for _ in 0..<3 {
            window.pinch(withScale: 0.5, velocity: -2)
            window.pinch(withScale: 2, velocity: 2)
        }
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(app.buttons["搜索天体"].waitForExistence(timeout: 4))
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
