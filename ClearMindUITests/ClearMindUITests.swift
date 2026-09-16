import XCTest

final class ClearMindUITests: XCTestCase {
    @MainActor
    func testCoreNavigationAndEditorsOpen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        XCTAssertTrue(app.staticTexts["都已经安顿好了"].waitForExistence(timeout: 5))

        let addRowButton = app.buttons["schedule-add-row"]
        XCTAssertTrue(addRowButton.waitForExistence(timeout: 2))
        addRowButton.click()
        XCTAssertTrue(app.textFields["schedule-start-time"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["schedule-end-time"].exists)
        XCTAssertFalse(app.staticTexts["给时间一个清晰去处，但不必把每一分钟都填满。"].exists)
        app.typeKey(.escape, modifierFlags: [])

        let goalsButton = app.buttons["前往长期目标"]
        if goalsButton.waitForExistence(timeout: 1) {
            goalsButton.click()
        } else {
            let sidebarGoals = app.staticTexts["长期目标"].firstMatch
            XCTAssertTrue(sidebarGoals.waitForExistence(timeout: 2))
            sidebarGoals.click()
        }
        XCTAssertTrue(app.buttons["新建目标"].waitForExistence(timeout: 2))
        app.buttons["新建目标"].click()
        XCTAssertTrue(app.staticTexts["只写下真正值得持续投入的方向。"].waitForExistence(timeout: 2))
        app.buttons["取消"].click()
    }
}
