import AppKit
import XCTest

final class ClearMindUITests: XCTestCase {
    @MainActor
    func testOverviewShowsDaylightArcAndTwelveHourTime() throws {
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
        XCTAssertTrue(app.descendants(matching: .any)["dashboard-date-time"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard-daylight-arc"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard-day-dial"].exists)
        let timeValue = try XCTUnwrap(displayedTime.value as? String)
        XCTAssertNotNil(
            timeValue.range(of: #"^(上午|下午) \d{1,2}:\d{2}$"#, options: .regularExpression),
            "顶部时间的实际值：\(timeValue)"
        )
        XCTAssertTrue(app.staticTexts["时间表"].exists)
        XCTAssertFalse(app.staticTexts["一天的时间分配"].exists)
        XCTAssertFalse(app.staticTexts["都已经安顿好了"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["global-navigation-menu"].exists,
            "全局导航菜单应始终可用。"
        )
        XCTAssertFalse(app.buttons["打开"].exists, "安心总览不应显示收集箱区块的打开按钮。")
    }

    @MainActor
    func testOverviewHighlightsOnlyTheCurrentScheduleRow() throws {
        let app = launchApp(arguments: ["--uitesting-dashboard-time-fixture"])

        let displayedTime = app.staticTexts["dashboard-time"]
        XCTAssertTrue(displayedTime.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedTime.value as? String, "下午 2:30")
        XCTAssertFalse(app.staticTexts["dashboard-current-schedule"].exists)
        XCTAssertFalse(app.staticTexts["dashboard-next-schedule"].exists)

        XCTAssertTrue(app.staticTexts["14:00 – 15:00"].exists)
        XCTAssertTrue(app.staticTexts["15:30 – 16:00"].exists)
        let currentRows = app.descendants(matching: .any).matching(identifier: "schedule-current-block")
        XCTAssertEqual(currentRows.count, 1)

        let editScheduleButton = app.buttons["schedule-edit-toggle"]
        editScheduleButton.click()
        XCTAssertTrue(app.buttons["schedule-add-row"].waitForExistence(timeout: 2))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "schedule-current-block").count,
            0,
            "编辑模式不应高亮尚未保存的安排"
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testGlobalNavigationMenuOpensAllSectionsAndKeepsCurrentPage() throws {
        let app = launchApp()

        let destinations = [
            (identifier: "overview", title: "安心总览"),
            (identifier: "goals", title: "长期目标"),
            (identifier: "nearTerm", title: "近期事项"),
            (identifier: "ideas", title: "想法库"),
            (identifier: "inbox", title: "收集箱"),
        ]

        for destination in destinations {
            navigate(to: destination.identifier, in: app)
            XCTAssertTrue(
                app.staticTexts[destination.title].waitForExistence(timeout: 2),
                "导航后未显示页面：\(destination.identifier)"
            )

            app.descendants(matching: .any)["global-navigation-menu"].click()
            let currentItem = app.menuItems["global-navigation-item-\(destination.identifier)"]
            XCTAssertTrue(currentItem.waitForExistence(timeout: 2))
            if destination.identifier == "overview" {
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "global-navigation-menu"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            currentItem.click()
            XCTAssertTrue(
                app.staticTexts[destination.title].waitForExistence(timeout: 2),
                "再次选择当前菜单项后不应离开页面：\(destination.identifier)"
            )
        }
    }

    @MainActor
    func testTopLevelNavigationClearsExistingDetailPath() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])
        let goalCard = app.buttons["dashboard-goal-card-11111111-1111-1111-1111-111111111111"]
        XCTAssertTrue(goalCard.waitForExistence(timeout: 5))
        goalCard.click()
        XCTAssertTrue(app.descendants(matching: .any)["goal-detail-summary"].waitForExistence(timeout: 2))

        navigate(to: "inbox", in: app)

        XCTAssertTrue(app.staticTexts["收集箱"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["goal-detail-summary"].exists)
        let backButton = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["返回", "后退", "Back"])
        ).firstMatch
        XCTAssertFalse(backButton.exists)
    }

    @MainActor
    func testGlobalSearchQuickCaptureAndNavigationMenuRemainAvailable() throws {
        let app = launchApp()

        let searchButton = app.buttons["global-search-toggle"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.click()
        let searchField = app.textFields["global-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("test")
        XCTAssertTrue(app.descendants(matching: .any)["global-search-results"].waitForExistence(timeout: 2))
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(searchField.exists)
        XCTAssertEqual(searchField.value as? String, "test")
        searchButton.click()
        XCTAssertFalse(searchField.waitForExistence(timeout: 1))

        let quickCapture = app.buttons["global-quick-capture"]
        XCTAssertTrue(quickCapture.exists)
        quickCapture.click()
        XCTAssertTrue(app.staticTexts["先放下这件事"].waitForExistence(timeout: 2))
        app.buttons["取消"].click()

        XCTAssertTrue(app.descendants(matching: .any)["global-navigation-menu"].exists)
        XCTAssertFalse(app.buttons["隐藏边栏"].exists)
        XCTAssertFalse(app.buttons["显示边栏"].exists)
        XCTAssertFalse(app.buttons["sidebar-item-overview"].exists)
    }

    @MainActor
    func testScheduleRowWithoutTasksShowsDash() throws {
        let app = launchApp()
        let editScheduleButton = app.buttons["schedule-edit-toggle"]
        XCTAssertTrue(editScheduleButton.waitForExistence(timeout: 5))
        editScheduleButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let addRowButton = app.buttons["schedule-add-row"]
        XCTAssertTrue(addRowButton.waitForExistence(timeout: 2))
        addRowButton.click()

        let startTimeField = app.textFields["schedule-start-time"]
        let endTimeField = app.textFields["schedule-end-time"]
        XCTAssertTrue(startTimeField.waitForExistence(timeout: 2))
        typeTime(hour: "09", minute: "00", into: startTimeField)
        typeTime(hour: "10", minute: "00", into: endTimeField)
        editScheduleButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let emptyTasksLabel = app.staticTexts["schedule-empty-tasks"]
        XCTAssertTrue(emptyTasksLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(emptyTasksLabel.value as? String, "-")
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
            navigate(to: "goals", in: app)
        }
        XCTAssertTrue(app.buttons["新建目标"].waitForExistence(timeout: 2))
        app.buttons["新建目标"].click()
        XCTAssertTrue(app.staticTexts["只写下真正值得持续投入的方向。"].waitForExistence(timeout: 2))
        app.buttons["取消"].click()
    }

    @MainActor
    func testOverviewShowsProgressCalendarAndRemainingDaysForCurrentWorkstream() throws {
        let app = launchApp(arguments: [
            "--uitesting-goal-fixture",
            "--uitesting-dashboard-time-fixture",
        ])
        let goalCard = app.buttons["dashboard-goal-card-11111111-1111-1111-1111-111111111111"]
        XCTAssertTrue(goalCard.waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "dashboard-overview"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(goalCard.label.contains("当前推进"))
        XCTAssertTrue(goalCard.label.contains("UI 测试推进项"))
        XCTAssertTrue(goalCard.label.contains("还剩 10 天"))
        XCTAssertTrue(goalCard.label.contains("处于1个推进项"))
    }

    @MainActor
    func testDashboardUsesDedicatedModuleHeadings() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])

        XCTAssertTrue(app.staticTexts["dashboard-module-heading-schedule"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["dashboard-module-heading-goals"].exists)

        let nearTermHeading = app.staticTexts["dashboard-module-heading-near-term"]
        if !nearTermHeading.waitForExistence(timeout: 1) {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(nearTermHeading.waitForExistence(timeout: 2))
    }

    @MainActor
    func testGoalDetailProvidesDirectIconActions() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])
        let goalCard = app.buttons["dashboard-goal-card-11111111-1111-1111-1111-111111111111"]
        XCTAssertTrue(goalCard.waitForExistence(timeout: 5))
        goalCard.click()

        let editButton = app.buttons["goal-edit-button"]
        let archiveButton = app.buttons["goal-archive-button"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 2))
        XCTAssertEqual(editButton.label, "编辑目标")
        XCTAssertTrue(archiveButton.exists)
        XCTAssertEqual(archiveButton.label, "归档目标")

        editButton.click()
        XCTAssertTrue(app.staticTexts["只写下真正值得持续投入的方向。"].waitForExistence(timeout: 2))
        app.buttons["取消"].click()
    }

    @MainActor
    func testOverviewGoalCardShowsNextStageAndOpensStreamlinedDetail() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])
        XCTAssertTrue(app.staticTexts["目标"].waitForExistence(timeout: 5))

        let goalCard = app.buttons["dashboard-goal-card-11111111-1111-1111-1111-111111111111"]
        if !goalCard.waitForExistence(timeout: 2) {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(goalCard.waitForExistence(timeout: 3))
        XCTAssertTrue(goalCard.label.contains("下一阶段"))
        XCTAssertTrue(goalCard.label.contains("交付收尾"))
        goalCard.click()

        XCTAssertTrue(app.descendants(matching: .any)["goal-detail-summary"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["goal-detail-period-summary"].exists)
        XCTAssertFalse(app.staticTexts["推进项"].exists, "详情页不应再显示重复的推进项列表标题。")

        let overviewBar = app.buttons["goal-plan-workstream-22222222-2222-2222-2222-222222222222"]
        XCTAssertTrue(overviewBar.waitForExistence(timeout: 2))
        overviewBar.click()
        XCTAssertTrue(
            app.staticTexts["并行的小目标会在时间图中各自占据一条泳道。"].waitForExistence(timeout: 2)
        )
        app.buttons["取消"].click()

        let backButton = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["返回", "后退", "Back"])
        ).firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.click()
        XCTAssertTrue(app.staticTexts["dashboard-date"].waitForExistence(timeout: 2))
        XCTAssertTrue(goalCard.waitForExistence(timeout: 2))
    }

    @MainActor
    func testTimelineEditingModeControlsHandlesAndBarStillOpensEditor() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])

        navigate(to: "goals", in: app)
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
    func testPlanOverviewHoverRevealsBoundedCalendarDetails() throws {
        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: .now)
        let expectedStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -45, to: referenceDay))
        let expectedEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 45, to: referenceDay))
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])
        navigate(to: "goals", in: app)

        let goal = app.buttons["goal-card-11111111-1111-1111-1111-111111111111"]
        XCTAssertTrue(goal.waitForExistence(timeout: 3))
        goal.click()

        let timeProgress = app.descendants(matching: .any)["goal-plan-time-progress"]
        XCTAssertTrue(timeProgress.waitForExistence(timeout: 2))
        let progressTrack = app.descendants(matching: .any)["goal-plan-progress-track"]
        XCTAssertTrue(progressTrack.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(
            progressTrack.frame.width,
            app.windows.firstMatch.frame.width * 0.6,
            "目标周期进度条应覆盖详情内容区，而不是随标签内容收缩。"
        )
        let startDate = app.staticTexts["goal-plan-progress-start-date"]
        let endDate = app.staticTexts["goal-plan-progress-end-date"]
        let monthLabels = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "goal-plan-progress-month-")
        )
        XCTAssertFalse(startDate.exists)
        XCTAssertFalse(endDate.exists)
        XCTAssertEqual(monthLabels.count, 0)

        timeProgress.hover()
        let timeHover = app.descendants(matching: .any)["goal-plan-time-hover"]
        XCTAssertTrue(timeHover.waitForExistence(timeout: 2))
        XCTAssertTrue(timeHover.label.contains("今天"), "Unexpected time tooltip: \(timeHover.label)")
        XCTAssertLessThanOrEqual(timeHover.frame.maxY, timeProgress.frame.midY)
        XCTAssertTrue(startDate.waitForExistence(timeout: 2))
        XCTAssertEqual(startDate.value as? String, compactChineseDate(expectedStart))
        XCTAssertTrue(endDate.exists)
        XCTAssertEqual(endDate.value as? String, compactChineseDate(expectedEnd))
        XCTAssertGreaterThanOrEqual(monthLabels.count, 1)
        XCTAssertEqual(startDate.frame.minX, progressTrack.frame.minX, accuracy: 3)
        XCTAssertEqual(endDate.frame.maxX, progressTrack.frame.maxX, accuracy: 3)

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "goal-plan-overview"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let workstream = app.buttons["goal-plan-workstream-22222222-2222-2222-2222-222222222222"]
        XCTAssertTrue(workstream.exists)
        workstream.hover()
        let workstreamHover = app.descendants(matching: .any)["goal-plan-workstream-hover"]
        XCTAssertTrue(workstreamHover.waitForExistence(timeout: 2))
        XCTAssertTrue(workstreamHover.label.contains("–"), "Unexpected workstream tooltip: \(workstreamHover.label)")
        XCTAssertFalse(workstreamHover.label.contains("UI 测试推进项"))
    }

    @MainActor
    private func navigate(to identifier: String, in app: XCUIApplication) {
        let menu = app.descendants(matching: .any)["global-navigation-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()

        let item = app.menuItems["global-navigation-item-\(identifier)"]
        XCTAssertTrue(item.waitForExistence(timeout: 2), "缺少导航菜单项：\(identifier)")
        item.click()
    }

    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--uitesting"] + arguments
        app.launch()
        return app
    }

    private func compactChineseDate(_ date: Date) -> String {
        date.formatted(
            .dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))
        )
    }

    @MainActor
    private func typeTime(hour: String, minute: String, into field: XCUIElement) {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        defer {
            pasteboard.clearContents()
            if let previousItems, !previousItems.isEmpty {
                pasteboard.writeObjects(previousItems)
            }
        }

        pasteboard.clearContents()
        pasteboard.setString("\(hour):\(minute)", forType: .string)

        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey("v", modifierFlags: .command)
    }

}
