import AppKit
import XCTest

final class ClearMindUITests: XCTestCase {
    @MainActor
    func testOverviewShowsTwentyFourHourTimeWithoutDayProgressBar() throws {
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
        XCTAssertFalse(app.descendants(matching: .any)["dashboard-day-progress"].exists)
        let timeValue = try XCTUnwrap(displayedTime.value as? String)
        XCTAssertNotNil(
            timeValue.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression),
            "顶部时间的实际值：\(timeValue)"
        )
        XCTAssertTrue(app.staticTexts["时间表"].exists)
        XCTAssertFalse(app.staticTexts["一天的时间分配"].exists)
        XCTAssertFalse(app.staticTexts["都已经安顿好了"].exists)
        XCTAssertTrue(
            app.buttons["sidebar-item-overview"].exists,
            "全局导航侧栏应始终可用。"
        )
        XCTAssertFalse(app.buttons["打开"].exists, "安心总览不应显示收集箱区块的打开按钮。")
    }

    @MainActor
    func testScheduleHeaderFitsMinimumWindowInLightAppearance() throws {
        let app = launchApp(arguments: ["--uitesting-dashboard-time-fixture", "-AppleInterfaceStyle", "Dark"])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let resizeHandle = window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
        resizeHandle.press(forDuration: 0.2, thenDragTo: resizeHandle.withOffset(CGVector(dx: -300, dy: 0)))
        XCTAssertLessThanOrEqual(window.frame.width, 1010, "应能缩至项目设置的 980 pt 最小宽度")

        let title = app.staticTexts["时间表"]
        let edit = app.buttons["schedule-edit-toggle"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(edit.exists)
        XCTAssertLessThan(title.frame.maxX, edit.frame.minX)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard-day-progress"].exists)
        let captured = window.screenshot()
        let screenshot = XCTAttachment(screenshot: captured)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(captured.image.tiffRepresentation)))
        let background = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 4, y: bitmap.pixelsHigh / 5))
        XCTAssertGreaterThan(background.usingColorSpace(.deviceRGB)?.redComponent ?? 0, 0.9)
        screenshot.name = "dashboard-schedule-light-narrow"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testOverviewHighlightsOnlyTheCurrentScheduleRow() throws {
        let app = launchApp(arguments: ["--uitesting-dashboard-time-fixture"])

        let displayedTime = app.staticTexts["dashboard-time"]
        XCTAssertTrue(displayedTime.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedTime.value as? String, "14:30")
        XCTAssertFalse(app.staticTexts["dashboard-current-schedule"].exists)
        XCTAssertFalse(app.staticTexts["dashboard-next-schedule"].exists)

        XCTAssertEqual(app.buttons["schedule-inline-time-55555555-5555-5555-5555-555555555555"].label, "14:00 – 15:00")
        XCTAssertEqual(app.buttons["schedule-inline-time-66666666-6666-6666-6666-666666666666"].label, "15:30 – 16:00")
        XCTAssertFalse(app.descendants(matching: .any)["dashboard-day-progress"].exists)
        let currentRows = app.descendants(matching: .any).matching(identifier: "schedule-current-block")
        XCTAssertEqual(currentRows.count, 1)

        let editScheduleButton = app.buttons["schedule-edit-toggle"]
        editScheduleButton.click()
        let addRowButton = app.buttons["schedule-add-row"]
        XCTAssertTrue(addRowButton.waitForExistence(timeout: 2))
        let startFields = app.textFields.matching(identifier: "schedule-start-time")
        XCTAssertGreaterThan(startFields.count, 0)
        XCTAssertGreaterThan(addRowButton.frame.minY, startFields.element(boundBy: startFields.count - 1).frame.maxY)
        let previousRowCount = startFields.count
        addRowButton.click()
        XCTAssertEqual(startFields.count, previousRowCount + 1)
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "schedule-current-block").count,
            0,
            "编辑模式不应高亮尚未保存的安排"
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testScheduleScopeColorPickerSavesSelectedPaletteColor() throws {
        let app = launchApp(arguments: ["--uitesting-dashboard-time-fixture"])
        let colorButton = app.buttons["schedule-scope-color-55555555-5555-5555-5555-555555555555"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5))

        colorButton.click()
        XCTAssertEqual(app.buttons["schedule-scope-color-option-denim"].value as? String, "已选择")
        app.buttons["schedule-scope-color-option-plum"].click()

        colorButton.click()
        XCTAssertEqual(app.buttons["schedule-scope-color-option-plum"].value as? String, "已选择")
    }

    @MainActor
    func testInlineTimeEditSavesBothTimesAfterLeavingTheGroup() throws {
        let app = launchApp(arguments: ["--uitesting-dashboard-time-fixture"])
        app.buttons["schedule-inline-time-55555555-5555-5555-5555-555555555555"].click()
        let start = app.textFields["schedule-inline-start-55555555-5555-5555-5555-555555555555"]
        let end = app.textFields["schedule-inline-end-55555555-5555-5555-5555-555555555555"]
        XCTAssertTrue(start.exists)
        XCTAssertTrue(end.exists)

        end.click()
        XCTAssertTrue(start.exists, "开始与结束输入框属于同一次编辑")
        end.typeKey("a", modifierFlags: .command)
        end.typeText("15:20")
        app.staticTexts["dashboard-module-heading-goals"].click()

        let savedTime = app.buttons["schedule-inline-time-55555555-5555-5555-5555-555555555555"]
        XCTAssertTrue(savedTime.waitForExistence(timeout: 2))
        XCTAssertEqual(savedTime.label, "14:00 – 15:20")
        XCTAssertFalse(end.exists)
    }

    @MainActor
    func testInlineTimeConflictKeepsEditorUntilCancelled() throws {
        let app = launchApp(arguments: ["--uitesting-dashboard-time-fixture"])
        app.buttons["schedule-inline-time-55555555-5555-5555-5555-555555555555"].click()
        let end = app.textFields["schedule-inline-end-55555555-5555-5555-5555-555555555555"]
        end.click()
        end.typeKey("a", modifierFlags: .command)
        end.typeText("15:40")
        app.staticTexts["时间表"].click()

        XCTAssertTrue(end.exists)
        XCTAssertTrue(app.staticTexts["schedule-inline-error-55555555-5555-5555-5555-555555555555"].exists)
        end.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(app.buttons["schedule-inline-time-55555555-5555-5555-5555-555555555555"].label, "14:00 – 15:00")
    }

    @MainActor
    func testInlineScopeTaskAndEmptyTaskSaveOnBlur() throws {
        let app = launchApp(arguments: ["--uitesting-dashboard-time-fixture"])
        app.buttons["schedule-inline-scope-55555555-5555-5555-5555-555555555555"].click()
        let scope = app.textFields["schedule-inline-scope-input-55555555-5555-5555-5555-555555555555"]
        scope.typeKey("a", modifierFlags: .command)
        scope.typeText("写作")
        app.staticTexts["时间表"].click()
        XCTAssertEqual(app.buttons["schedule-inline-scope-55555555-5555-5555-5555-555555555555"].label, "写作")

        app.buttons["schedule-inline-task-准备材料"].click()
        let task = app.textFields["schedule-inline-task-input-准备材料"]
        task.typeKey("a", modifierFlags: .command)
        task.typeKey(.delete, modifierFlags: [])
        app.staticTexts["时间表"].click()
        XCTAssertFalse(app.buttons["schedule-inline-task-准备材料"].exists)

        app.buttons["schedule-inline-empty-task-66666666-6666-6666-6666-666666666666"].click()
        let newTask = app.textFields["schedule-inline-new-task-66666666-6666-6666-6666-666666666666"]
        newTask.typeText("散步计划")
        app.staticTexts["时间表"].click()
        XCTAssertTrue(app.buttons["schedule-inline-task-散步计划"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testGoalMonthCalendarAddsMilestoneAndShowsSummaryMarker() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])
        let goalCard = app.buttons["dashboard-goal-card-11111111-1111-1111-1111-111111111111"]
        XCTAssertTrue(goalCard.waitForExistence(timeout: 5))
        goalCard.click()

        let calendar = app.descendants(matching: .any)["goal-detail-month-calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 3))
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let dayKey = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        let dayButton = app.buttons["goal-month-day-\(dayKey)"]
        for _ in 0..<5 where !dayButton.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(dayButton.isHittable)
        dayButton.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.15)).click()

        let title = app.textFields["goal-milestone-quick-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(title.exists)
        dayButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).click()
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.click()
        title.typeText("月历测试里程碑")
        app.buttons["milestone-color-plum"].click()
        XCTAssertEqual(app.buttons["milestone-color-plum"].value as? String, "已选择")
        app.buttons["goal-milestone-quick-save"].click()
        XCTAssertTrue(app.buttons["goal-month-milestone-月历测试里程碑"].waitForExistence(timeout: 2))
        app.buttons["goal-month-milestone-月历测试里程碑"].click()
        XCTAssertTrue(app.staticTexts["里程碑是一个明确的日期节点，不占据时间区间。"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons["milestone-color-plum"].value as? String, "已选择")
        app.buttons["取消"].click()

        dayButton.click()
        let secondTitle = app.textFields["goal-milestone-quick-title"]
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 2))
        secondTitle.click()
        secondTitle.typeText("第二个测试里程碑")
        app.buttons["goal-milestone-quick-save"].click()

        navigate(to: "overview", in: app)
        let summaryCard = app.buttons["dashboard-goal-card-11111111-1111-1111-1111-111111111111"]
        XCTAssertTrue(summaryCard.waitForExistence(timeout: 3))
        XCTAssertTrue(summaryCard.label.contains("里程碑："), summaryCard.label)
        for _ in 0..<5 where summaryCard.frame.maxY > app.windows.firstMatch.frame.maxY - 20 {
            app.scrollViews.firstMatch.swipeUp()
        }
        summaryCard.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.05)).hover()
        let baseline = app.windows.firstMatch.screenshot()
        let dateCalendar = Calendar.current
        let firstOfMonth = try XCTUnwrap(dateCalendar.date(
            from: dateCalendar.dateComponents([.year, .month], from: Date.now)
        ))
        let leadingDays = (dateCalendar.component(.weekday, from: firstOfMonth) + 5) % 7
        let dayIndex = leadingDays + dateCalendar.component(.day, from: Date.now) - 1
        let column = dayIndex % 7
        let row = dayIndex / 7
        let cardWidth = summaryCard.frame.width
        let cellWidth = (cardWidth - 36 - 6 * 4) / 7
        let dayX = (18 + (CGFloat(column) + 0.5) * cellWidth + CGFloat(column) * 4) / cardWidth
        let dayY = 1 - (57 + CGFloat(5 - row) * 34) / summaryCard.frame.height
        summaryCard.coordinate(withNormalizedOffset: CGVector(dx: dayX, dy: dayY)).hover()
        let hovered = app.windows.firstMatch.screenshot()
        let calendarHoverScreenshot = XCTAttachment(screenshot: hovered)
        calendarHoverScreenshot.name = "summary-calendar-hover"
        calendarHoverScreenshot.lifetime = .keepAlways
        add(calendarHoverScreenshot)
        XCTAssertGreaterThan(
            changedPixelsInRightHalf(of: summaryCard.frame, window: app.windows.firstMatch.frame,
                                     before: baseline.image, after: hovered.image),
            700,
            "里程碑日期悬浮时，目标卡片内应出现明显的信息卡"
        )
        XCTAssertTrue(summaryCard.label.contains("第二个测试里程碑"))
        summaryCard.click()
        XCTAssertTrue(app.descendants(matching: .any)["goal-detail-month-calendar"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testGoalMonthCalendarDisablesDatesOutsideGoalPeriod() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])
        app.buttons["dashboard-goal-card-11111111-1111-1111-1111-111111111111"].click()
        let previous = app.buttons["goal-month-previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 3))
        for _ in 0..<5 where !previous.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(previous.isHittable)
        for _ in 0..<4 where previous.isEnabled {
            previous.click()
        }
        XCTAssertFalse(previous.isEnabled)

        let start = Calendar.current.date(byAdding: .day, value: -45, to: Calendar.current.startOfDay(for: .now))!
        let beforeStart = Calendar.current.date(byAdding: .day, value: -1, to: start)!
        if Calendar.current.isDate(beforeStart, equalTo: start, toGranularity: .month) {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: beforeStart)
            let key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            let day = app.buttons["goal-month-day-\(key)"]
            for _ in 0..<5 where !day.exists {
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(day.waitForExistence(timeout: 2))
            XCTAssertFalse(day.isEnabled)
        }
    }

    @MainActor
    func testSidebarOpensAllSectionsAndKeepsCurrentPage() throws {
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

            let currentItem = app.buttons["sidebar-item-\(destination.identifier)"]
            XCTAssertEqual(currentItem.value as? String, "已选择")
            if destination.identifier == "overview" {
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "global-navigation-sidebar"
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
    func testFiveThemesSwitchImmediatelyAndPersistAfterRelaunch() throws {
        let app = launchApp()
        let appearance = app.buttons["appearance-menu"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.click()

        for theme in ["mistyBlue", "sageGreen", "mutedLavender", "slateIndigo", "warmTerracotta"] {
            let option = app.buttons["theme-option-\(theme)"]
            XCTAssertTrue(option.waitForExistence(timeout: 2))
            option.click()
            XCTAssertEqual(option.value as? String, "已选择")
        }

        app.typeKey("2", modifierFlags: [.command, .option])
        XCTAssertEqual(app.buttons["theme-option-mistyBlue"].value as? String, "已选择")
        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--uitesting"]
        relaunched.launch()
        let restored = relaunched.buttons["appearance-menu"]
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.value as? String, "雾蓝灰")
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
    func testGlobalSearchQuickCaptureAndSidebarRemainAvailable() throws {
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

        XCTAssertTrue(app.buttons["sidebar-item-overview"].exists)
        XCTAssertTrue(app.buttons["appearance-menu"].exists)
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
    func testGoalArchiveConfirmationAndRestoreFromArchivedList() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])
        navigate(to: "goals", in: app)

        let goalCard = app.buttons["goal-card-11111111-1111-1111-1111-111111111111"]
        XCTAssertTrue(goalCard.waitForExistence(timeout: 3))
        goalCard.click()

        let editButton = app.buttons["goal-edit-button"]
        editButton.hover()
        XCTAssertTrue(app.staticTexts["goal-edit-button-hover"].waitForExistence(timeout: 2))

        let archiveButton = app.buttons["goal-archive-button"]
        archiveButton.hover()
        XCTAssertTrue(app.staticTexts["goal-archive-button-hover"].waitForExistence(timeout: 2))
        archiveButton.click()
        XCTAssertTrue(app.alerts["归档这个目标？"].waitForExistence(timeout: 2))
        app.alerts.buttons["取消"].click()
        XCTAssertTrue(archiveButton.exists)

        archiveButton.click()
        app.alerts.buttons["归档目标"].click()
        XCTAssertFalse(goalCard.exists)

        let archiveToggle = app.checkBoxes["查看已归档"]
        XCTAssertTrue(archiveToggle.waitForExistence(timeout: 2))
        archiveToggle.click()
        XCTAssertTrue(goalCard.waitForExistence(timeout: 2))
        goalCard.click()
        XCTAssertTrue(app.staticTexts["goal-archived-status"].waitForExistence(timeout: 2))
        app.buttons["goal-restore-button"].click()
        XCTAssertFalse(goalCard.exists)

        archiveToggle.click()
        XCTAssertTrue(goalCard.waitForExistence(timeout: 2))
    }

    @MainActor
    func testGoalMonthCalendarShowsWorkstreamBandsAndHoverDetails() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])
        navigate(to: "goals", in: app)
        app.buttons["goal-card-11111111-1111-1111-1111-111111111111"].click()

        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let dayKey = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        let dayButton = app.buttons["goal-month-day-\(dayKey)"]
        for _ in 0..<5 where !dayButton.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(dayButton.isHittable)
        let band = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "goal-month-workstream-band-22222222-2222-2222-2222-222222222222")
        ).firstMatch
        XCTAssertTrue(band.exists)
        dayButton.hover()
        let hover = app.descendants(matching: .any)["goal-month-workstreams-hover"]
        XCTAssertTrue(hover.waitForExistence(timeout: 2))
        XCTAssertTrue(hover.label.contains("UI 测试推进项"))
        XCTAssertTrue(app.staticTexts["goal-plan-start-date"].exists)
        XCTAssertTrue(app.staticTexts["goal-plan-end-date"].exists)
    }

    @MainActor
    func testWorkstreamColorSelectionPersistsInEditor() throws {
        let app = launchApp(arguments: ["--uitesting-goal-fixture"])
        navigate(to: "goals", in: app)
        app.buttons["goal-card-11111111-1111-1111-1111-111111111111"].click()

        let bar = app.buttons["goal-plan-workstream-22222222-2222-2222-2222-222222222222"]
        XCTAssertTrue(bar.waitForExistence(timeout: 2))
        bar.click()
        let plum = app.buttons["workstream-color-plum"]
        XCTAssertTrue(plum.waitForExistence(timeout: 2))
        plum.click()
        XCTAssertEqual(plum.value as? String, "已选择")
        app.buttons["保存"].click()

        bar.click()
        XCTAssertEqual(app.buttons["workstream-color-plum"].value as? String, "已选择")
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
        let item = app.buttons["sidebar-item-\(identifier)"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "缺少侧栏导航项：\(identifier)")
        item.click()
    }

    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--uitesting", "--uitesting-reset-theme"] + arguments
        app.launch()
        return app
    }

    private func compactChineseDate(_ date: Date) -> String {
        date.formatted(
            .dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))
        )
    }

    private func changedPixelsInRightHalf(
        of card: CGRect,
        window: CGRect,
        before: NSImage,
        after: NSImage
    ) -> Int {
        guard let beforeData = before.tiffRepresentation,
              let afterData = after.tiffRepresentation,
              let beforeBitmap = NSBitmapImageRep(data: beforeData),
              let afterBitmap = NSBitmapImageRep(data: afterData),
              beforeBitmap.pixelsWide == afterBitmap.pixelsWide,
              beforeBitmap.pixelsHigh == afterBitmap.pixelsHigh else { return 0 }
        let scale = CGFloat(beforeBitmap.pixelsWide) / window.width
        let minX = max(0, Int((card.midX - window.minX) * scale))
        let maxX = min(beforeBitmap.pixelsWide, Int((card.maxX - window.minX) * scale))
        let minY = max(0, Int((card.minY - window.minY) * scale))
        let maxY = min(beforeBitmap.pixelsHigh, Int((card.maxY - window.minY) * scale))
        var changed = 0
        for y in stride(from: minY, to: maxY, by: 4) {
            for x in stride(from: minX, to: maxX, by: 4) {
                if beforeBitmap.colorAt(x: x, y: y) != afterBitmap.colorAt(x: x, y: y) {
                    changed += 1
                }
            }
        }
        return changed
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
