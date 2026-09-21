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
        let displayedDate = try XCTUnwrap(dateLabel.value as? String)
        XCTAssertEqual(
            displayedDate.filter { !$0.isWhitespace },
            expectedDate.filter { !$0.isWhitespace }
        )
        let displayedTime = app.staticTexts["dashboard-time"]
        XCTAssertTrue(displayedTime.exists)
        let timeValue = try XCTUnwrap(displayedTime.value as? String)
        XCTAssertNotNil(
            timeValue.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression),
            "顶部时间的实际值：\(timeValue)"
        )
        XCTAssertTrue(app.staticTexts["时间表"].exists)
        XCTAssertFalse(app.staticTexts["一天的时间分配"].exists)
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
        let workstream = app.descendants(matching: .any)[
            "current-workstream-22222222-2222-2222-2222-222222222222-summary"
        ]
        XCTAssertTrue(workstream.waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "dashboard-overview"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let calendar = app.descendants(matching: .any)["goal-progress-calendar"]
        if !calendar.waitForExistence(timeout: 2) {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(calendar.waitForExistence(timeout: 3))
        XCTAssertTrue(calendar.label.contains("处于1个推进项"))

        XCTAssertTrue(workstream.label.contains("还剩 10 天"))
        XCTAssertLessThan(workstream.frame.minY, calendar.frame.minY, "当前推进应显示在月历上方。")
    }

    @MainActor
    func testTimelineEditingModeControlsHandlesAndBarStillOpensEditor() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])

        let sidebarGoals = app.staticTexts["长期目标"].firstMatch
        XCTAssertTrue(sidebarGoals.waitForExistence(timeout: 5))
        sidebarGoals.click()
        XCTAssertFalse(app.descendants(matching: .any)["goal-progress-calendar"].exists)

        let goal = app.buttons["goal-card-11111111-1111-1111-1111-111111111111"]
        XCTAssertTrue(goal.waitForExistence(timeout: 2))
        goal.click()

        let overview = app.descendants(matching: .any)["goal-plan-overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["时间进度"].exists)
        let timeProgress = app.descendants(matching: .any)["goal-plan-time-progress"]
        XCTAssertTrue(timeProgress.exists)
        XCTAssertTrue(timeProgress.label.contains("今天"))
        XCTAssertFalse(app.staticTexts["仅表示计划时间，不代表完成情况"].exists)
        XCTAssertTrue(app.staticTexts["goal-plan-current-22222222-2222-2222-2222-222222222222"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["goal-plan-today"].exists)
        XCTAssertTrue(app.buttons["goal-plan-workstream-33333333-3333-3333-3333-333333333333"].exists)
        XCTAssertTrue(app.buttons["goal-plan-workstream-44444444-4444-4444-4444-444444444444"].exists)

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "goal-plan-overview"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let milestone = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "里程碑：首版完成")).firstMatch
        XCTAssertTrue(milestone.exists)
        milestone.click()
        XCTAssertTrue(app.staticTexts["里程碑是一个明确的日期节点，不占据时间区间。"].waitForExistence(timeout: 2))
        app.buttons["取消"].click()

        let overviewBar = app.buttons["goal-plan-workstream-22222222-2222-2222-2222-222222222222"]
        XCTAssertTrue(overviewBar.exists)
        overviewBar.click()
        XCTAssertTrue(app.staticTexts["并行的小目标会在时间图中各自占据一条泳道。"].waitForExistence(timeout: 2))
        app.buttons["取消"].click()

        let handle = app.descendants(matching: .any)[
            "timeline-22222222-2222-2222-2222-222222222222-end-handle"
        ]
        XCTAssertFalse(handle.exists, "时间图默认应为只读状态。")

        let editTimelineButton = app.buttons["timeline-edit-toggle"]
        XCTAssertTrue(editTimelineButton.waitForExistence(timeout: 2))
        XCTAssertEqual(editTimelineButton.label, "编辑时间")
        editTimelineButton.click()

        XCTAssertTrue(handle.waitForExistence(timeout: 3))
        XCTAssertNotNil(handle.value as? String)
        XCTAssertFalse(overview.exists)

        editTimelineButton.click()
        XCTAssertFalse(handle.exists, "退出时间编辑后应再次隐藏拖拽把手。")
        XCTAssertTrue(overview.waitForExistence(timeout: 2))

        XCTAssertTrue(overviewBar.waitForExistence(timeout: 2))
        overviewBar.click()
        XCTAssertTrue(
            app.staticTexts["并行的小目标会在时间图中各自占据一条泳道。"].waitForExistence(timeout: 2),
            "总览模式下点击推进条仍应打开精确编辑表单。"
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
