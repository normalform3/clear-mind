import XCTest

final class ClearMindUITests: XCTestCase {
    @MainActor
    func testOverviewShowsOnlyDateAndNoInboxSection() throws {
        let app = launchApp()
        let expectedDate = Date.now.formatted(
            .dateTime.year().month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))
        )
        let dateLabel = app.staticTexts["dashboard-date"]

        XCTAssertTrue(dateLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(dateLabel.label.contains(expectedDate))
        XCTAssertFalse(app.staticTexts["都已经安顿好了"].exists)
        XCTAssertTrue(app.staticTexts["收集箱"].exists, "侧边栏收集箱入口应保留。")
        XCTAssertFalse(app.buttons["打开"].exists, "安心总览不应显示收集箱区块的打开按钮。")
    }

    @MainActor
    func testScheduleRowWithoutTasksShowsDash() throws {
        let app = launchApp()
        let editScheduleButton = app.buttons["schedule-edit-toggle"]
        XCTAssertTrue(editScheduleButton.waitForExistence(timeout: 5))
        editScheduleButton.click()

        let addRowButton = app.buttons["schedule-add-row"]
        XCTAssertTrue(addRowButton.waitForExistence(timeout: 2))
        addRowButton.click()

        let startTimeField = app.textFields["schedule-start-time"]
        let endTimeField = app.textFields["schedule-end-time"]
        XCTAssertTrue(startTimeField.waitForExistence(timeout: 2))
        startTimeField.click()
        startTimeField.typeText("09:00")
        endTimeField.click()
        endTimeField.typeText("10:00")
        editScheduleButton.click()

        let emptyTasksLabel = app.staticTexts["schedule-empty-tasks"]
        XCTAssertTrue(emptyTasksLabel.waitForExistence(timeout: 2))
        XCTAssertTrue(emptyTasksLabel.label.contains("-"))
        XCTAssertFalse(app.staticTexts["没有具体任务"].exists)
    }

    @MainActor
    func testCoreNavigationAndEditorsOpen() throws {
        let app = launchApp()

        let editScheduleButton = app.buttons["schedule-edit-toggle"]
        XCTAssertTrue(editScheduleButton.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["schedule-add-row"].exists)
        editScheduleButton.click()

        let addRowButton = app.buttons["schedule-add-row"]
        XCTAssertTrue(addRowButton.waitForExistence(timeout: 2))
        addRowButton.click()
        XCTAssertTrue(app.textFields["schedule-start-time"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["schedule-end-time"].exists)
        XCTAssertEqual(editScheduleButton.label, "完成")
        XCTAssertFalse(app.staticTexts["给时间一个清晰去处，但不必把每一分钟都填满。"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(editScheduleButton.label, "编辑")

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

    @MainActor
    func testOverviewShowsProgressCalendarAndRemainingDaysForCurrentWorkstream() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])

        let calendar = app.descendants(matching: .any)["goal-progress-calendar"]
        if !calendar.waitForExistence(timeout: 2) {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(calendar.waitForExistence(timeout: 3))
        XCTAssertTrue((calendar.value as? String)?.contains("处于1个推进项") == true)

        let workstream = app.descendants(matching: .any)[
            "current-workstream-22222222-2222-2222-2222-222222222222-summary"
        ]
        XCTAssertTrue(workstream.waitForExistence(timeout: 2))
        XCTAssertTrue(workstream.label.contains("还剩 10 天"))
    }

    @MainActor
    func testTimelineEndHandleDragChangesDateWithoutOpeningEditor() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])

        let sidebarGoals = app.staticTexts["长期目标"].firstMatch
        XCTAssertTrue(sidebarGoals.waitForExistence(timeout: 5))
        sidebarGoals.click()
        XCTAssertFalse(app.descendants(matching: .any)["goal-progress-calendar"].exists)

        let goal = app.staticTexts["UI 测试目标"].firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 2))
        goal.click()

        let handle = app.descendants(matching: .any)[
            "timeline-22222222-2222-2222-2222-222222222222-end-handle"
        ]
        XCTAssertTrue(handle.waitForExistence(timeout: 3))
        let originalValue = try XCTUnwrap(handle.value as? String)

        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let finish = start.withOffset(CGVector(dx: 0, dy: 16))
        start.press(forDuration: 0.35, thenDragTo: finish)

        let valueChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return (element.value as? String) != originalValue
            },
            object: handle
        )
        XCTAssertEqual(XCTWaiter.wait(for: [valueChanged], timeout: 2), .completed)
        XCTAssertFalse(
            app.staticTexts["并行的小目标会在时间图中各自占据一条泳道。"].exists,
            "拖动把手不应触发推进条的点击编辑。"
        )
    }

    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + arguments
        app.launch()
        return app
    }
}
