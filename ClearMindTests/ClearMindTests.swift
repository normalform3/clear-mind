import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import ClearMind

@MainActor
final class ClearMindTests: XCTestCase {
    func testScheduleRejectsInvalidAndOverlappingRanges() throws {
        let block = ScheduleBlock(startMinute: 9 * 60, endMinute: 10 * 60)

        XCTAssertThrowsError(
            try ScheduleValidator.validate(startMinute: 600, endMinute: 600, blocks: [])
        ) { error in
            XCTAssertEqual(error as? ScheduleValidationError, .invalidRange)
        }

        XCTAssertThrowsError(
            try ScheduleValidator.validate(startMinute: 570, endMinute: 630, blocks: [block])
        ) { error in
            XCTAssertEqual(error as? ScheduleValidationError, .overlaps)
        }

        XCTAssertNoThrow(
            try ScheduleValidator.validate(startMinute: 600, endMinute: 660, blocks: [block])
        )
    }

    func testScheduleTimeParserAcceptsEndOfDayOnlyForEndTime() throws {
        XCTAssertEqual(try ScheduleTimeParser.minutes(from: "9:05", allowsEndOfDay: false), 545)
        XCTAssertEqual(try ScheduleTimeParser.minutes(from: "24:00", allowsEndOfDay: true), 1440)
        XCTAssertThrowsError(try ScheduleTimeParser.minutes(from: "24:00", allowsEndOfDay: false))
        XCTAssertThrowsError(try ScheduleTimeParser.minutes(from: "24:01", allowsEndOfDay: true))
        XCTAssertThrowsError(try ScheduleTimeParser.minutes(from: "上午九点", allowsEndOfDay: false))
    }

    func testInvalidScheduleDraftDoesNotCreateBlock() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = ScheduleTemplate(name: "工作日")
        context.insert(template)
        try context.save()

        var draft = ScheduleBlockDraft()
        draft.startText = "10:00"
        draft.endText = "10:00"

        XCTAssertThrowsError(
            try ScheduleBlockWriter.commit(draft, block: nil, template: template, in: context)
        )
        XCTAssertTrue(template.blocks.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleBlock>()), 0)
    }

    func testScheduleDraftCommitReusesScopeAndPersistsTasks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = ScheduleTemplate(name: "工作日")
        context.insert(template)

        var firstDraft = ScheduleBlockDraft()
        firstDraft.startText = "09:00"
        firstDraft.endText = "10:00"
        firstDraft.scopeName = "深度工作"
        firstDraft.tasks = [
            ScheduleTaskDraft(title: "完成提纲"),
            ScheduleTaskDraft(title: "整理资料", isCompleted: true),
            ScheduleTaskDraft(title: "")
        ]
        let firstBlock = try ScheduleBlockWriter.commit(
            firstDraft,
            block: nil,
            template: template,
            in: context
        )

        var secondDraft = ScheduleBlockDraft()
        secondDraft.startText = "10:00"
        secondDraft.endText = "11:00"
        secondDraft.scopeName = "  深度工作  "
        let secondBlock = try ScheduleBlockWriter.commit(
            secondDraft,
            block: nil,
            template: template,
            in: context
        )

        XCTAssertEqual(firstBlock.scope?.id, secondBlock.scope?.id)
        XCTAssertEqual(firstBlock.checklistItems.count, 2)
        XCTAssertEqual(firstBlock.checklistItems.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.title), ["完成提纲", "整理资料"])
        XCTAssertTrue(firstBlock.checklistItems.contains(where: { $0.title == "整理资料" && $0.isCompleted }))
    }

    func testOverlappingEditKeepsPreviouslySavedBlockUnchanged() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = ScheduleTemplate(name: "工作日")
        let firstBlock = ScheduleBlock(startMinute: 540, endMinute: 600)
        let secondBlock = ScheduleBlock(startMinute: 600, endMinute: 660)
        context.insert(template)
        template.blocks.append(firstBlock)
        template.blocks.append(secondBlock)
        try context.save()

        var draft = ScheduleBlockDraft(block: firstBlock)
        draft.startText = "09:30"
        draft.endText = "10:30"

        XCTAssertThrowsError(
            try ScheduleBlockWriter.commit(draft, block: firstBlock, template: template, in: context)
        ) { error in
            XCTAssertEqual(error as? ScheduleValidationError, .overlaps)
        }
        XCTAssertEqual(firstBlock.startMinute, 540)
        XCTAssertEqual(firstBlock.endMinute, 600)
    }

    func testScheduleTableCommitSupportsSimultaneousRangeChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = ScheduleTemplate(name: "默认日")
        let firstBlock = ScheduleBlock(startMinute: 540, endMinute: 600)
        let secondBlock = ScheduleBlock(startMinute: 600, endMinute: 660)
        context.insert(template)
        template.blocks.append(firstBlock)
        template.blocks.append(secondBlock)
        try context.save()

        var firstDraft = ScheduleBlockDraft(block: firstBlock)
        firstDraft.startText = "10:00"
        firstDraft.endText = "11:00"
        var secondDraft = ScheduleBlockDraft(block: secondBlock)
        secondDraft.startText = "09:00"
        secondDraft.endText = "10:00"

        try ScheduleTableWriter.commit(
            [firstDraft, secondDraft],
            template: template,
            in: context
        )

        XCTAssertEqual(firstBlock.startMinute, 600)
        XCTAssertEqual(firstBlock.endMinute, 660)
        XCTAssertEqual(secondBlock.startMinute, 540)
        XCTAssertEqual(secondBlock.endMinute, 600)
    }

    func testInvalidScheduleTableCommitLeavesSavedBlocksUnchanged() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = ScheduleTemplate(name: "默认日")
        let firstBlock = ScheduleBlock(startMinute: 540, endMinute: 600)
        let secondBlock = ScheduleBlock(startMinute: 600, endMinute: 660)
        context.insert(template)
        template.blocks.append(firstBlock)
        template.blocks.append(secondBlock)
        try context.save()

        var firstDraft = ScheduleBlockDraft(block: firstBlock)
        firstDraft.startText = "09:30"
        firstDraft.endText = "10:30"
        let secondDraft = ScheduleBlockDraft(block: secondBlock)

        XCTAssertThrowsError(
            try ScheduleTableWriter.commit(
                [firstDraft, secondDraft],
                template: template,
                in: context
            )
        ) { error in
            let failure = error as? ScheduleTableValidationFailure
            XCTAssertEqual(failure?.issues[firstDraft.id], .overlaps)
            XCTAssertEqual(failure?.issues[secondDraft.id], .overlaps)
        }
        XCTAssertEqual(firstBlock.startMinute, 540)
        XCTAssertEqual(firstBlock.endMinute, 600)
        XCTAssertEqual(secondBlock.startMinute, 600)
        XCTAssertEqual(secondBlock.endMinute, 660)
    }

    func testScheduleTableCommitDeletesRemovedRowsAndIgnoresBlankNewRows() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = ScheduleTemplate(name: "默认日")
        let keptBlock = ScheduleBlock(startMinute: 540, endMinute: 600)
        let removedBlock = ScheduleBlock(startMinute: 600, endMinute: 660)
        context.insert(template)
        template.blocks.append(keptBlock)
        template.blocks.append(removedBlock)
        try context.save()

        try ScheduleTableWriter.commit(
            [ScheduleBlockDraft(block: keptBlock), ScheduleBlockDraft()],
            template: template,
            in: context
        )

        XCTAssertEqual(template.blocks.map(\.id), [keptBlock.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleBlock>()), 1)
    }

    func testScheduleTableCommitReusesNewScopeAcrossRowsAndPersistsTasks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = ScheduleTemplate(name: "默认日")
        context.insert(template)

        var morning = ScheduleBlockDraft()
        morning.startText = "09:00"
        morning.endText = "10:00"
        morning.scopeName = "深度工作"
        morning.tasks = [ScheduleTaskDraft(title: "完成提纲")]

        var afternoon = ScheduleBlockDraft()
        afternoon.startText = "14:00"
        afternoon.endText = "15:00"
        afternoon.scopeName = " 深度工作 "
        afternoon.tasks = [ScheduleTaskDraft(title: "整理资料", isCompleted: true)]

        try ScheduleTableWriter.commit([morning, afternoon], template: template, in: context)

        let blocks = template.blocks.sorted { $0.startMinute < $1.startMinute }
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].scope?.id, blocks[1].scope?.id)
        XCTAssertEqual(blocks[0].checklistItems.map(\.title), ["完成提纲"])
        XCTAssertEqual(blocks[1].checklistItems.map(\.title), ["整理资料"])
        XCTAssertTrue(blocks[1].checklistItems[0].isCompleted)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleScope>()), 1)
    }

    func testCanonicalScheduleUsesSelectionThenFallsBackToEarliestTemplate() {
        let early = ScheduleTemplate(
            name: "早期",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let selected = ScheduleTemplate(
            name: "当前",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(
            ScheduleTemplateResolver.canonical(
                from: [early, selected],
                selectedID: selected.id.uuidString
            )?.id,
            selected.id
        )
        XCTAssertEqual(
            ScheduleTemplateResolver.canonical(from: [selected, early], selectedID: "missing")?.id,
            early.id
        )
    }

    func testGoalBoundaryValidation() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31))!
        let goal = Goal(title: "测试目标", startDate: start, endDate: end)

        XCTAssertTrue(GoalValidator.isWithinGoal(startDate: start, endDate: end, goal: goal))
        XCTAssertFalse(GoalValidator.isWithinGoal(
            startDate: calendar.date(byAdding: .day, value: -1, to: start)!,
            endDate: end,
            goal: goal
        ))
        XCTAssertEqual(TimelineMath.inclusiveDayCount(from: start, to: end, calendar: calendar), 90)
    }

    func testCurrentWorkstreamsIncludeStartAndEndDateBoundaries() {
        let calendar = Calendar.current
        let today = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let startingToday = Workstream(title: "今天开始", startDate: today, endDate: calendar.date(byAdding: .day, value: 4, to: today)!)
        let endingToday = Workstream(title: "今天结束", startDate: calendar.date(byAdding: .day, value: -4, to: today)!, endDate: today)

        let result = WorkstreamTimelineLogic.current(
            in: [startingToday, endingToday],
            on: today,
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.title), ["今天结束", "今天开始"])
    }

    func testCurrentWorkstreamsExcludeOtherDatesAndSortByRange() {
        let calendar = Calendar.current
        let today = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let earlierEnd = Workstream(
            title: "同日起步，较早结束",
            startDate: calendar.date(byAdding: .day, value: -2, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 1, to: today)!
        )
        let laterEnd = Workstream(
            title: "同日起步，较晚结束",
            startDate: earlierEnd.startDate,
            endDate: calendar.date(byAdding: .day, value: 3, to: today)!
        )
        let earliestStart = Workstream(
            title: "更早开始",
            startDate: calendar.date(byAdding: .day, value: -5, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 2, to: today)!
        )
        let past = Workstream(
            title: "已经结束",
            startDate: calendar.date(byAdding: .day, value: -8, to: today)!,
            endDate: calendar.date(byAdding: .day, value: -1, to: today)!
        )
        let future = Workstream(
            title: "尚未开始",
            startDate: calendar.date(byAdding: .day, value: 1, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 8, to: today)!
        )

        let result = WorkstreamTimelineLogic.current(
            in: [laterEnd, future, earlierEnd, past, earliestStart],
            on: today,
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.title), ["更早开始", "同日起步，较早结束", "同日起步，较晚结束"])
    }

    func testGoalCalendarBuildsSixMondayFirstWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17))!

        let days = GoalCalendarLogic.monthDays(
            containing: today,
            currentWorkstreams: [],
            calendar: calendar
        )

        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first?.date, calendar.date(from: DateComponents(year: 2026, month: 8, day: 31)))
        XCTAssertEqual(days.last?.date, calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        XCTAssertEqual(days.first?.isInDisplayedMonth, false)
        XCTAssertEqual(days[1].isInDisplayedMonth, true)
        XCTAssertFalse(days.contains(where: \.isCoveredByCurrentWorkstream))
    }

    func testGoalCalendarMarksTodayInsideVisibleCurrentWorkstreamUnion() throws {
        let calendar = Calendar.current
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17))!
        let first = Workstream(
            title: "第一项",
            startDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!,
            endDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        )
        let second = Workstream(
            title: "第二项",
            startDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!,
            endDate: calendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!
        )

        let days = GoalCalendarLogic.monthDays(
            containing: today,
            currentWorkstreams: [first, second],
            calendar: calendar
        )
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        let september9 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9))!
        let september17 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17))!
        let september21 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21))!
        let september30 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let october1 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!

        XCTAssertEqual(days.filter(\.isToday).count, 1)
        XCTAssertEqual(try XCTUnwrap(byDate[september9]).isCoveredByCurrentWorkstream, false)
        XCTAssertEqual(try XCTUnwrap(byDate[september17]).isToday, true)
        XCTAssertEqual(try XCTUnwrap(byDate[september17]).isCoveredByCurrentWorkstream, true)
        XCTAssertEqual(try XCTUnwrap(byDate[september21]).isCoveredByCurrentWorkstream, true)
        XCTAssertEqual(try XCTUnwrap(byDate[september30]).isCoveredByCurrentWorkstream, true)
        XCTAssertEqual(try XCTUnwrap(byDate[october1]).isInDisplayedMonth, false)
        XCTAssertEqual(try XCTUnwrap(byDate[october1]).isCoveredByCurrentWorkstream, false)
    }

    func testGoalCalendarRemainingDaysUsesCalendarDaysExcludingToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let beforeDST = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
        let sameDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let afterDST = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let monthEnd = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 12))!
        let nextMonth = calendar.date(from: DateComponents(year: 2026, month: 4, day: 2, hour: 12))!

        XCTAssertEqual(GoalCalendarLogic.remainingDays(until: sameDay, from: beforeDST, calendar: calendar), 0)
        XCTAssertEqual(GoalCalendarLogic.remainingDays(until: tomorrow, from: beforeDST, calendar: calendar), 1)
        XCTAssertEqual(GoalCalendarLogic.remainingDays(until: afterDST, from: beforeDST, calendar: calendar), 2)
        XCTAssertEqual(GoalCalendarLogic.remainingDays(until: nextMonth, from: monthEnd, calendar: calendar), 2)
    }

    func testUITestGoalFixtureSeedsOneCurrentWorkstreamIdempotently() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17))!

        try UITestFixtureSeeder.seedGoalTimeline(in: context, referenceDate: referenceDate)
        try UITestFixtureSeeder.seedGoalTimeline(in: context, referenceDate: referenceDate)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        let goal = try XCTUnwrap(goals.first)
        let workstream = try XCTUnwrap(goal.workstreams.first)
        XCTAssertEqual(goals.count, 1)
        XCTAssertEqual(goal.id, UITestFixtureSeeder.goalID)
        XCTAssertEqual(goal.workstreams.count, 1)
        XCTAssertEqual(workstream.id, UITestFixtureSeeder.workstreamID)
        XCTAssertEqual(
            workstream.startDate,
            calendar.date(byAdding: .day, value: -5, to: referenceDate)?.startOfDay
        )
        XCTAssertEqual(
            workstream.endDate,
            calendar.date(byAdding: .day, value: 10, to: referenceDate)?.startOfDay
        )
    }

    func testTimelineResizeRoundsVerticalTranslationToWholeDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let goalStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let goalEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 20))!

        let result = WorkstreamTimelineLogic.resizedRange(
            startDate: start,
            endDate: end,
            edge: .start,
            verticalTranslation: 6.5,
            pointsPerDay: 3.2,
            goalStartDate: goalStart,
            goalEndDate: goalEnd,
            calendar: calendar
        )

        XCTAssertEqual(result.startDate, calendar.date(from: DateComponents(year: 2026, month: 1, day: 12)))
        XCTAssertEqual(result.endDate, end)
    }

    func testTimelineResizeSessionUsesFixedPointerOriginForEveryPreview() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let goalStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let goalEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 20))!
        let session = WorkstreamResizeSession(
            workstreamID: UUID(),
            edge: .start,
            originalRange: WorkstreamDateRange(startDate: start, endDate: end),
            startPointerY: 100
        )

        let firstPreview = session.previewRange(
            pointerY: 103.2,
            pointsPerDay: 3.2,
            goalStartDate: goalStart,
            goalEndDate: goalEnd,
            calendar: calendar
        )
        let secondPreview = session.previewRange(
            pointerY: 106.4,
            pointsPerDay: 3.2,
            goalStartDate: goalStart,
            goalEndDate: goalEnd,
            calendar: calendar
        )
        let reversePreview = session.previewRange(
            pointerY: 96.8,
            pointsPerDay: 3.2,
            goalStartDate: goalStart,
            goalEndDate: goalEnd,
            calendar: calendar
        )

        XCTAssertEqual(firstPreview.startDate, calendar.date(from: DateComponents(year: 2026, month: 1, day: 11)))
        XCTAssertEqual(secondPreview.startDate, calendar.date(from: DateComponents(year: 2026, month: 1, day: 12)))
        XCTAssertEqual(reversePreview.startDate, calendar.date(from: DateComponents(year: 2026, month: 1, day: 9)))
        XCTAssertEqual(firstPreview.endDate, end)
        XCTAssertEqual(secondPreview.endDate, end)
        XCTAssertEqual(reversePreview.endDate, end)
    }

    func testTimelineResizeClampsStartToGoalAndExistingEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let goalStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let goalEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 20))!

        let beforeGoal = WorkstreamTimelineLogic.resizedRange(
            startDate: start,
            endDate: end,
            edge: .start,
            verticalTranslation: -1_000,
            pointsPerDay: 3.2,
            goalStartDate: goalStart,
            goalEndDate: goalEnd,
            calendar: calendar
        )
        let afterEnd = WorkstreamTimelineLogic.resizedRange(
            startDate: start,
            endDate: end,
            edge: .start,
            verticalTranslation: 1_000,
            pointsPerDay: 3.2,
            goalStartDate: goalStart,
            goalEndDate: goalEnd,
            calendar: calendar
        )

        XCTAssertEqual(beforeGoal.startDate, goalStart)
        XCTAssertEqual(afterEnd.startDate, end)
    }

    func testTimelineResizeClampsEndToExistingStartAndGoal() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let goalStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let goalEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 20))!

        let beforeStart = WorkstreamTimelineLogic.resizedRange(
            startDate: start,
            endDate: end,
            edge: .end,
            verticalTranslation: -1_000,
            pointsPerDay: 3.2,
            goalStartDate: goalStart,
            goalEndDate: goalEnd,
            calendar: calendar
        )
        let afterGoal = WorkstreamTimelineLogic.resizedRange(
            startDate: start,
            endDate: end,
            edge: .end,
            verticalTranslation: 1_000,
            pointsPerDay: 3.2,
            goalStartDate: goalStart,
            goalEndDate: goalEnd,
            calendar: calendar
        )

        XCTAssertEqual(beforeStart.endDate, start)
        XCTAssertEqual(afterGoal.endDate, goalEnd)
    }

    func testTimelineResizeDoesNotCrossSingleDayRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let goalStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let goalEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let onlyDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        let movedStart = WorkstreamTimelineLogic.resizedRange(
            startDate: onlyDay,
            endDate: onlyDay,
            edge: .start,
            verticalTranslation: 32,
            pointsPerDay: 3.2,
            goalStartDate: goalStart,
            goalEndDate: goalEnd,
            calendar: calendar
        )
        let movedEnd = WorkstreamTimelineLogic.resizedRange(
            startDate: onlyDay,
            endDate: onlyDay,
            edge: .end,
            verticalTranslation: -32,
            pointsPerDay: 3.2,
            goalStartDate: goalStart,
            goalEndDate: goalEnd,
            calendar: calendar
        )

        XCTAssertEqual(movedStart.startDate, onlyDay)
        XCTAssertEqual(movedEnd.endDate, onlyDay)
    }

    func testMonthlyTimelineUsesCalendarMonthTicksAndContentSizedHeight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!

        let ticks = TimelineMath.monthTicks(from: start, to: end, calendar: calendar)

        XCTAssertEqual(ticks, [
            start,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!,
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        ])

        let contentHeight = TimelineMath.contentHeight(
            dayCount: 31,
            headerHeight: 44,
            pointsPerDay: 3.2,
            bottomPadding: 16
        )
        XCTAssertEqual(contentHeight, 159.2, accuracy: 0.001)
        XCTAssertEqual(TimelineMath.viewportHeight(for: contentHeight), contentHeight, accuracy: 0.001)
        XCTAssertEqual(TimelineMath.viewportHeight(for: 80), 140, accuracy: 0.001)
        XCTAssertEqual(TimelineMath.viewportHeight(for: 900), 480, accuracy: 0.001)
    }

    func testMonthlyTimelineKeepsNearEndBarsInsideContentAndSeparatesLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 29))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!

        XCTAssertEqual(
            TimelineMath.monthLabelTicks(from: start, to: end, minimumSpacingDays: 12, calendar: calendar),
            [
                start,
                calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
            ]
        )

        let contentHeight = TimelineMath.contentHeight(
            dayCount: 41,
            headerHeight: 44,
            pointsPerDay: 3.2,
            bottomPadding: 16
        )
        let finalDayY = 44 + CGFloat(40) * 3.2 + 3
        let availableHeight = contentHeight - finalDayY
        let barHeight = TimelineMath.workstreamBarHeight(
            durationDays: 1,
            availableHeight: availableHeight,
            pointsPerDay: 3.2
        )

        XCTAssertGreaterThan(barHeight, 0)
        XCTAssertLessThanOrEqual(barHeight, availableHeight)
    }

    func testTimelineScrollHeightLetsTodayReachViewportTopNearGoalEnd() {
        XCTAssertEqual(
            TimelineMath.scrollContentHeight(
                chartHeight: 1_200,
                viewportHeight: 480,
                todayY: 1_000
            ),
            1_480,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TimelineMath.scrollContentHeight(
                chartHeight: 1_200,
                viewportHeight: 480,
                todayY: 300
            ),
            1_200,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TimelineMath.scrollContentHeight(
                chartHeight: 1_200,
                viewportHeight: 480,
                todayY: nil
            ),
            1_200,
            accuracy: 0.001
        )
    }

    func testTimelineAxisBeginsAtTopOfLongGoalInsteadOfBeingVerticallyCentered() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let goal = Goal(
            title: "全年目标",
            startDate: calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!,
            endDate: calendar.date(from: DateComponents(year: 2024, month: 12, day: 31))!
        )
        let hostingView = NSHostingView(rootView:
            GoalTimelineView(
                goal: goal,
                workstreams: [],
                milestones: [],
                onSelectWorkstream: { _ in },
                onSelectMilestone: { _ in },
                onUpdateWorkstreamRange: { _, _, _ in }
            )
            .environment(\.colorScheme, .light)
            .frame(width: 680, height: 480, alignment: .topLeading)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 680, height: 480)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let background = try XCTUnwrap(bitmap.colorAt(x: 80, y: 240)?.usingColorSpace(.deviceRGB))
        var contrastingPixels = 0

        for x in 12..<76 {
            for y in (bitmap.pixelsHigh - 100)..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let difference = abs(color.redComponent - background.redComponent)
                    + abs(color.greenComponent - background.greenComponent)
                    + abs(color.blueComponent - background.blueComponent)
                if difference > 0.12 {
                    contrastingPixels += 1
                }
            }
        }

        XCTAssertGreaterThan(
            contrastingPixels,
            200,
            "长目标的左侧月份轴应从可视区域顶部开始绘制，而不是先留出大段空白。实际差异像素：\(contrastingPixels)"
        )
    }

    func testChecklistStatePersistsWithoutAutomaticReset() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = ScheduleTemplate(name: "工作日")
        let block = ScheduleBlock(startMinute: 540, endMinute: 600)
        let item = ScheduleChecklistItem(title: "推进重要工作", isCompleted: true)
        context.insert(template)
        template.blocks.append(block)
        block.checklistItems.append(item)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduleChecklistItem>()).first)
        XCTAssertTrue(fetched.isCompleted)
    }

    func testBackupRoundTripPreservesRelationships() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let tag = Tag(name: "学习", colorKey: "denim")
        let goal = Goal(
            title: "完成研究计划",
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .month, value: 2, to: .now)!,
            status: .paused,
            tags: [tag]
        )
        let workstream = Workstream(
            title: "阅读资料",
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .day, value: 14, to: .now)!,
            status: .inProgress
        )
        goal.workstreams.append(workstream)
        sourceContext.insert(goal)
        sourceContext.insert(ScheduleTemplate(name: "默认日"))
        sourceContext.insert(ScheduleTemplate(name: "旧休息日"))
        let legacyReviewDate = Calendar.current.date(byAdding: .day, value: 21, to: .now)!.startOfDay
        sourceContext.insert(NearTermItem(title: "旧近期事项", reviewDate: legacyReviewDate))
        try sourceContext.save()

        let data = try BackupService.exportData(from: sourceContext)

        let destination = try makeContainer()
        destination.mainContext.insert(Goal(
            title: "会被替换的旧目标",
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        ))
        destination.mainContext.insert(ScheduleTemplate(name: "旧模板"))
        try destination.mainContext.save()
        try BackupService.importData(data, into: destination.mainContext)

        let restoredGoal = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<Goal>()).first)
        XCTAssertEqual(restoredGoal.title, "完成研究计划")
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<Goal>()), 1)
        XCTAssertEqual(restoredGoal.tags.first?.name, "学习")
        XCTAssertEqual(restoredGoal.status, .paused)
        XCTAssertEqual(restoredGoal.workstreams.first?.status, .inProgress)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<ScheduleTemplate>()), 2)
        let restoredNearTerm = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<NearTermItem>()).first)
        XCTAssertEqual(restoredNearTerm.reviewDate, legacyReviewDate)
    }

    func testBackupSummaryCallsLegacyTemplatesScheduleData() throws {
        let container = try makeContainer()
        container.mainContext.insert(ScheduleTemplate(name: "默认日"))
        try container.mainContext.save()

        let summary = try BackupService.summary(of: BackupService.exportData(from: container.mainContext))

        XCTAssertTrue(summary.contains("1 份时间表数据"))
        XCTAssertFalse(summary.contains("时间表模板"))
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Tag.self,
            Goal.self,
            Workstream.self,
            Milestone.self,
            NearTermItem.self,
            Idea.self,
            InboxEntry.self,
            ScheduleScope.self,
            ScheduleTemplate.self,
            ScheduleBlock.self,
            ScheduleChecklistItem.self,
            configurations: configuration
        )
    }
}
