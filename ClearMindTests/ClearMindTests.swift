import SwiftData
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
        XCTAssertEqual(restoredGoal.workstreams.first?.status, .inProgress)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<ScheduleTemplate>()), 1)
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
