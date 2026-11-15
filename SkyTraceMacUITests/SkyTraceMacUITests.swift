import XCTest

@MainActor
final class SkyTraceMacUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    func testOptionalForegroundSoak() throws {
        let environmentValue = ProcessInfo.processInfo.environment["SKYTRACE_SOAK_SECONDS"]
        let fileValue = try? String(contentsOfFile: "/tmp/skytrace-soak-seconds", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let seconds = (environmentValue ?? fileValue).flatMap(TimeInterval.init) ?? 0
        guard seconds > 0 else {
            throw XCTSkip("Set SKYTRACE_SOAK_SECONDS to run the foreground GPU soak")
        }

        let app = XCUIApplication()
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        let deadline = Date().addingTimeInterval(seconds)
        var upward = true
        while Date() < deadline {
            let startY = upward ? 0.62 : 0.35
            let endY = upward ? 0.35 : 0.62
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end)
            upward.toggle()
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertTrue(app.buttons["今晚可见"].exists)
        XCTAssertTrue(app.buttons["time.now"].exists)
    }

    func testStarMapDragSmoke() {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
        let upward = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        start.press(forDuration: 0.1, thenDragTo: upward)

        let downward = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
        upward.press(forDuration: 0.1, thenDragTo: downward)

        XCTAssertTrue(app.buttons["今晚可见"].exists)
        XCTAssertTrue(app.buttons["time.now"].exists)
        XCTAssertTrue(app.datePickers["time.datePicker"].exists)
        XCTAssertFalse(app.buttons["播放"].exists)
        XCTAssertFalse(app.buttons["暂停"].exists)
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
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        window.click()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["搜索天空"].waitForExistence(timeout: 6))

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.click()
        field.typeText("M42")
        XCTAssertTrue(app.staticTexts["猎户座大星云"].waitForExistence(timeout: 5))
    }
}
