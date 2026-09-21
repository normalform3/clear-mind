import Foundation
import SwiftData

enum ScheduleValidationError: LocalizedError, Equatable {
    case invalidRange
    case overlaps

    var errorDescription: String? {
        switch self {
        case .invalidRange: "结束时间需要晚于开始时间。"
        case .overlaps: "这个时间段与时间表中的其他安排重叠。"
        }
    }
}

enum ScheduleValidator {
    static func validate(
        startMinute: Int,
        endMinute: Int,
        blocks: [ScheduleBlock],
        excluding excludedID: UUID? = nil
    ) throws {
        guard (0..<1440).contains(startMinute), (1...1440).contains(endMinute), startMinute < endMinute else {
            throw ScheduleValidationError.invalidRange
        }

        let hasOverlap = blocks.contains { block in
            block.id != excludedID && startMinute < block.endMinute && endMinute > block.startMinute
        }

        if hasOverlap {
            throw ScheduleValidationError.overlaps
        }
    }
}

enum ScheduleTimeInputError: LocalizedError, Equatable {
    case invalidFormat

    var errorDescription: String? {
        "请使用 HH:mm 格式填写时间。"
    }
}

enum ScheduleTimeParser {
    static func minutes(from value: String, allowsEndOfDay: Bool) throws -> Int {
        let parts = value.trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0...59).contains(minute),
            (0...23).contains(hour) || (allowsEndOfDay && hour == 24 && minute == 0)
        else {
            throw ScheduleTimeInputError.invalidFormat
        }

        return hour * 60 + minute
    }
}

struct ScheduleTaskDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool

    init(id: UUID = UUID(), title: String = "", isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

struct ScheduleBlockDraft: Identifiable, Equatable {
    let id: UUID
    let sourceBlockID: UUID?
    var startText: String
    var endText: String
    var scopeName: String
    var tasks: [ScheduleTaskDraft]

    init() {
        id = UUID()
        sourceBlockID = nil
        startText = ""
        endText = ""
        scopeName = ""
        tasks = [ScheduleTaskDraft()]
    }

    init(block: ScheduleBlock) {
        id = block.id
        sourceBlockID = block.id
        startText = block.startMinute.clockText
        endText = block.endMinute.clockText
        scopeName = block.scope?.name ?? ""
        tasks = block.checklistItems
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ScheduleTaskDraft(id: $0.id, title: $0.title, isCompleted: $0.isCompleted) }
        if tasks.isEmpty {
            tasks = [ScheduleTaskDraft()]
        }
    }

    var isBlankNewDraft: Bool {
        sourceBlockID == nil
            && startText.trimmed.isEmpty
            && endText.trimmed.isEmpty
            && scopeName.trimmed.isEmpty
            && tasks.allSatisfy { $0.title.trimmed.isEmpty }
    }
}

enum ScheduleTableValidationIssue: Equatable {
    case invalidTime
    case invalidRange
    case overlaps
    case missingSource

    var message: String {
        switch self {
        case .invalidTime: "请使用 HH:mm 格式填写时间。"
        case .invalidRange: "结束时间需要晚于开始时间。"
        case .overlaps: "这个时间段与其他安排重叠。"
        case .missingSource: "原时间块已不存在，请取消编辑后重试。"
        }
    }
}

struct ScheduleTableValidationFailure: LocalizedError, Equatable {
    let issues: [UUID: ScheduleTableValidationIssue]

    var errorDescription: String? {
        issues.values.first?.message ?? "时间表包含无法保存的内容。"
    }
}

@MainActor
enum ScheduleTableWriter {
    private struct ParsedDraft {
        let draft: ScheduleBlockDraft
        let startMinute: Int
        let endMinute: Int
    }

    static func commit(
        _ drafts: [ScheduleBlockDraft],
        template: ScheduleTemplate,
        in context: ModelContext
    ) throws {
        let activeDrafts = drafts.filter { !$0.isBlankNewDraft }
        var parsedDrafts: [ParsedDraft] = []
        var issues: [UUID: ScheduleTableValidationIssue] = [:]

        for draft in activeDrafts {
            do {
                let startMinute = try ScheduleTimeParser.minutes(from: draft.startText, allowsEndOfDay: false)
                let endMinute = try ScheduleTimeParser.minutes(from: draft.endText, allowsEndOfDay: true)
                guard startMinute < endMinute else {
                    issues[draft.id] = .invalidRange
                    continue
                }
                if let sourceID = draft.sourceBlockID,
                   !template.blocks.contains(where: { $0.id == sourceID }) {
                    issues[draft.id] = .missingSource
                    continue
                }
                parsedDrafts.append(ParsedDraft(
                    draft: draft,
                    startMinute: startMinute,
                    endMinute: endMinute
                ))
            } catch {
                issues[draft.id] = .invalidTime
            }
        }

        for firstIndex in parsedDrafts.indices {
            for secondIndex in parsedDrafts.indices where secondIndex > firstIndex {
                let first = parsedDrafts[firstIndex]
                let second = parsedDrafts[secondIndex]
                if first.startMinute < second.endMinute && first.endMinute > second.startMinute {
                    issues[first.draft.id] = .overlaps
                    issues[second.draft.id] = .overlaps
                }
            }
        }

        guard issues.isEmpty else {
            throw ScheduleTableValidationFailure(issues: issues)
        }

        let retainedIDs = Set(parsedDrafts.compactMap(\.draft.sourceBlockID))
        let removedBlocks = template.blocks.filter { !retainedIDs.contains($0.id) }
        template.blocks.removeAll { !retainedIDs.contains($0.id) }
        for block in removedBlocks {
            context.delete(block)
        }

        do {
            for parsed in parsedDrafts {
                let draft = parsed.draft
                let target: ScheduleBlock
                if let sourceID = draft.sourceBlockID,
                   let existing = template.blocks.first(where: { $0.id == sourceID }) {
                    target = existing
                } else {
                    target = ScheduleBlock(startMinute: parsed.startMinute, endMinute: parsed.endMinute)
                    template.blocks.append(target)
                }

                target.startMinute = parsed.startMinute
                target.endMinute = parsed.endMinute
                target.scope = try ScopeService.resolve(name: draft.scopeName, in: context)
                target.updatedAt = .now

                let savedTasks = draft.tasks.filter { !$0.title.trimmed.isEmpty }
                let savedTaskIDs = Set(savedTasks.map(\.id))
                let removedTasks = target.checklistItems.filter { !savedTaskIDs.contains($0.id) }
                target.checklistItems.removeAll { !savedTaskIDs.contains($0.id) }
                for task in removedTasks {
                    context.delete(task)
                }

                for (index, task) in savedTasks.enumerated() {
                    if let existing = target.checklistItems.first(where: { $0.id == task.id }) {
                        existing.title = task.title.trimmed
                        existing.isCompleted = task.isCompleted
                        existing.sortOrder = index
                    } else {
                        target.checklistItems.append(ScheduleChecklistItem(
                            id: task.id,
                            title: task.title.trimmed,
                            isCompleted: task.isCompleted,
                            sortOrder: index
                        ))
                    }
                }
            }

            template.updatedAt = .now
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

@MainActor
enum ScheduleBlockWriter {
    @discardableResult
    static func commit(
        _ draft: ScheduleBlockDraft,
        block: ScheduleBlock?,
        template: ScheduleTemplate,
        in context: ModelContext
    ) throws -> ScheduleBlock {
        let startMinute = try ScheduleTimeParser.minutes(from: draft.startText, allowsEndOfDay: false)
        let endMinute = try ScheduleTimeParser.minutes(from: draft.endText, allowsEndOfDay: true)

        try ScheduleValidator.validate(
            startMinute: startMinute,
            endMinute: endMinute,
            blocks: template.blocks,
            excluding: block?.id
        )

        let scope = try ScopeService.resolve(name: draft.scopeName, in: context)
        let target = block ?? ScheduleBlock(startMinute: startMinute, endMinute: endMinute)
        target.startMinute = startMinute
        target.endMinute = endMinute
        target.scope = scope
        target.updatedAt = .now

        if block == nil {
            template.blocks.append(target)
        }

        let savedTasks = draft.tasks.filter { !$0.title.trimmed.isEmpty }
        let savedIDs = Set(savedTasks.map(\.id))
        for existing in target.checklistItems where !savedIDs.contains(existing.id) {
            context.delete(existing)
        }
        target.checklistItems.removeAll { !savedIDs.contains($0.id) }

        for (index, task) in savedTasks.enumerated() {
            if let existing = target.checklistItems.first(where: { $0.id == task.id }) {
                existing.title = task.title.trimmed
                existing.isCompleted = task.isCompleted
                existing.sortOrder = index
            } else {
                target.checklistItems.append(ScheduleChecklistItem(
                    id: task.id,
                    title: task.title.trimmed,
                    isCompleted: task.isCompleted,
                    sortOrder: index
                ))
            }
        }

        template.updatedAt = .now
        try context.save()
        return target
    }
}

enum GoalValidator {
    static func hasValidRange(startDate: Date, endDate: Date) -> Bool {
        startDate.startOfDay <= endDate.startOfDay
    }

    static func isWithinGoal(startDate: Date, endDate: Date, goal: Goal) -> Bool {
        startDate.startOfDay >= goal.startDate.startOfDay && endDate.startOfDay <= goal.endDate.startOfDay
    }
}

enum GoalOrderLogic {
    static func ordered(_ goals: [Goal]) -> [Goal] {
        goals.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    @discardableResult
    static func normalizeIfNeeded(_ goals: [Goal]) -> Bool {
        let currentOrder = ordered(goals)
        let hasDuplicateOrder = Set(goals.map(\.sortOrder)).count != goals.count
        var hasSeenArchivedGoal = false
        let hasActiveGoalAfterArchivedGoal = currentOrder.contains { goal in
            if goal.isArchived {
                hasSeenArchivedGoal = true
                return false
            }
            return hasSeenArchivedGoal
        }
        guard hasDuplicateOrder || hasActiveGoalAfterArchivedGoal else { return false }

        let active = ordered(goals.filter { !$0.isArchived })
        let archived = ordered(goals.filter(\.isArchived))
        for (index, goal) in (active + archived).enumerated() {
            goal.sortOrder = index
        }
        return true
    }

    static func placeAtFront(_ goal: Goal, among goals: [Goal]) {
        let existingActive = ordered(goals.filter { $0.id != goal.id && !$0.isArchived })
        let archived = ordered(goals.filter { $0.id != goal.id && $0.isArchived })
        goal.sortOrder = 0
        for (index, item) in (existingActive + archived).enumerated() {
            item.sortOrder = index + 1
        }
    }

    static func moving(_ draggedID: UUID, on targetID: UUID, in ids: [UUID]) -> [UUID] {
        guard draggedID != targetID,
              let source = ids.firstIndex(of: draggedID),
              let target = ids.firstIndex(of: targetID) else { return ids }
        var result = ids
        result.remove(at: source)
        guard let adjustedTarget = result.firstIndex(of: targetID) else { return ids }
        let destination = source < target ? adjustedTarget + 1 : adjustedTarget
        result.insert(draggedID, at: min(destination, result.count))
        return result
    }

    @discardableResult
    static func applyActiveDraft(_ activeIDs: [UUID], to goals: [Goal]) -> Bool {
        let active = goals.filter { !$0.isArchived }
        guard activeIDs.count == active.count,
              Set(activeIDs).count == activeIDs.count,
              Set(activeIDs) == Set(active.map(\.id)) else { return false }

        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let orderedActive = activeIDs.compactMap { byID[$0] }
        let archived = ordered(goals.filter(\.isArchived))
        for (index, goal) in (orderedActive + archived).enumerated() {
            goal.sortOrder = index
        }
        return true
    }
}

enum GoalOrderError: LocalizedError {
    case invalidDraft

    var errorDescription: String? {
        switch self {
        case .invalidDraft: "目标列表已经发生变化，请取消排序后重试。"
        }
    }
}

@MainActor
enum GoalOrderService {
    static func normalizeIfNeeded(in context: ModelContext) throws {
        let goals = try context.fetch(FetchDescriptor<Goal>())
        if GoalOrderLogic.normalizeIfNeeded(goals) {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    static func insertAtFront(_ goal: Goal, in context: ModelContext) throws {
        let goals = try context.fetch(FetchDescriptor<Goal>())
        GoalOrderLogic.placeAtFront(goal, among: goals)
        context.insert(goal)
    }

    static func commitActiveDraft(_ activeIDs: [UUID], in context: ModelContext) throws {
        let goals = try context.fetch(FetchDescriptor<Goal>())
        guard GoalOrderLogic.applyActiveDraft(activeIDs, to: goals) else {
            throw GoalOrderError.invalidDraft
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func archive(_ goal: Goal, in context: ModelContext) throws {
        let goals = try context.fetch(FetchDescriptor<Goal>())
        guard let target = goals.first(where: { $0.id == goal.id }) else {
            throw GoalOrderError.invalidDraft
        }
        target.isArchived = true
        let activeIDs = GoalOrderLogic.ordered(goals.filter { !$0.isArchived }).map(\.id)
        guard GoalOrderLogic.applyActiveDraft(activeIDs, to: goals) else {
            throw GoalOrderError.invalidDraft
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

enum TimelineResizeEdge: Equatable {
    case start
    case end
}

struct WorkstreamDateRange: Equatable {
    let startDate: Date
    let endDate: Date
}

struct WorkstreamResizeSession: Equatable {
    let workstreamID: UUID
    let edge: TimelineResizeEdge
    let originalRange: WorkstreamDateRange
    let startPointerY: CGFloat

    func previewRange(
        pointerY: CGFloat,
        pointsPerDay: CGFloat,
        goalStartDate: Date,
        goalEndDate: Date,
        calendar: Calendar = .current
    ) -> WorkstreamDateRange {
        WorkstreamTimelineLogic.resizedRange(
            startDate: originalRange.startDate,
            endDate: originalRange.endDate,
            edge: edge,
            verticalTranslation: pointerY - startPointerY,
            pointsPerDay: pointsPerDay,
            goalStartDate: goalStartDate,
            goalEndDate: goalEndDate,
            calendar: calendar
        )
    }
}

enum WorkstreamTimelineLogic {
    static func current(
        in workstreams: [Workstream],
        on date: Date,
        calendar: Calendar = .current
    ) -> [Workstream] {
        let day = calendar.startOfDay(for: date)
        return workstreams
            .filter {
                calendar.startOfDay(for: $0.startDate) <= day
                    && calendar.startOfDay(for: $0.endDate) >= day
            }
            .sorted { lhs, rhs in
                let lhsStart = calendar.startOfDay(for: lhs.startDate)
                let rhsStart = calendar.startOfDay(for: rhs.startDate)
                if lhsStart == rhsStart {
                    return calendar.startOfDay(for: lhs.endDate) < calendar.startOfDay(for: rhs.endDate)
                }
                return lhsStart < rhsStart
            }
    }

    static func resizedRange(
        startDate: Date,
        endDate: Date,
        edge: TimelineResizeEdge,
        verticalTranslation: CGFloat,
        pointsPerDay: CGFloat,
        goalStartDate: Date,
        goalEndDate: Date,
        calendar: Calendar = .current
    ) -> WorkstreamDateRange {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard pointsPerDay > 0 else {
            return WorkstreamDateRange(startDate: start, endDate: end)
        }

        let dayDelta = Int((verticalTranslation / pointsPerDay).rounded())
        let movedDate = calendar.date(
            byAdding: .day,
            value: dayDelta,
            to: edge == .start ? start : end
        ) ?? (edge == .start ? start : end)
        let goalStart = calendar.startOfDay(for: goalStartDate)
        let goalEnd = calendar.startOfDay(for: goalEndDate)

        switch edge {
        case .start:
            return WorkstreamDateRange(
                startDate: max(goalStart, min(movedDate, end)),
                endDate: end
            )
        case .end:
            return WorkstreamDateRange(
                startDate: start,
                endDate: min(goalEnd, max(movedDate, start))
            )
        }
    }
}

struct GoalCalendarDay: Equatable, Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isCoveredByCurrentWorkstream: Bool

    var id: Date { date }
}

enum GoalCalendarLogic {
    static func remainingDays(
        until endDate: Date,
        from date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: endDate)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    static func monthDays(
        containing date: Date,
        currentWorkstreams: [Workstream],
        calendar: Calendar = .current
    ) -> [GoalCalendarDay] {
        let day = calendar.startOfDay(for: date)
        let monthComponents = calendar.dateComponents([.year, .month], from: day)
        guard let firstOfMonth = calendar.date(from: monthComponents) else { return [] }

        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let daysSinceMonday = (weekday + 5) % 7
        guard let gridStart = calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: firstOfMonth
        ) else { return [] }

        return (0..<42).compactMap { offset in
            guard let gridDate = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let normalizedGridDate = calendar.startOfDay(for: gridDate)
            let isInDisplayedMonth = calendar.isDate(
                normalizedGridDate,
                equalTo: firstOfMonth,
                toGranularity: .month
            )
            return GoalCalendarDay(
                date: normalizedGridDate,
                isInDisplayedMonth: isInDisplayedMonth,
                isToday: calendar.isDate(normalizedGridDate, inSameDayAs: day),
                isCoveredByCurrentWorkstream: isInDisplayedMonth && currentWorkstreams.contains { workstream in
                    let start = calendar.startOfDay(for: workstream.startDate)
                    let end = calendar.startOfDay(for: workstream.endDate)
                    return start <= normalizedGridDate && normalizedGridDate <= end
                }
            )
        }
    }
}

struct GoalPlanSpan: Equatable {
    let start: Double
    let width: Double
}

struct GoalPlanFocus {
    enum State: Equatable {
        case empty
        case upcoming
        case current
        case gap
        case ended
    }

    let state: State
    let current: [Workstream]
    let next: Workstream?
}

enum GoalPlanOverviewLogic {
    static let monthLabelWidth: CGFloat = 64

    static func span(
        from startDate: Date,
        to endDate: Date,
        goalStart: Date,
        goalEnd: Date,
        calendar: Calendar = .current
    ) -> GoalPlanSpan {
        let totalDays = Double(TimelineMath.inclusiveDayCount(from: goalStart, to: goalEnd, calendar: calendar))
        let startDay = Double(TimelineMath.dayOffset(from: goalStart, to: startDate, calendar: calendar))
        let endDay = Double(TimelineMath.dayOffset(from: goalStart, to: endDate, calendar: calendar) + 1)
        let start = min(1, max(0, startDay / totalDays))
        let end = min(1, max(start, endDay / totalDays))
        return GoalPlanSpan(start: start, width: end - start)
    }

    static func elapsedFraction(
        goalStart: Date,
        goalEnd: Date,
        on date: Date,
        calendar: Calendar = .current
    ) -> Double {
        let totalDays = Double(TimelineMath.inclusiveDayCount(from: goalStart, to: goalEnd, calendar: calendar))
        let elapsedDays = Double(TimelineMath.dayOffset(from: goalStart, to: date, calendar: calendar)) + 0.5
        return min(1, max(0, elapsedDays / totalDays))
    }

    static func progressText(
        goalStart: Date,
        goalEnd: Date,
        on date: Date,
        calendar: Calendar = .current
    ) -> String {
        let day = calendar.startOfDay(for: date)
        if day < calendar.startOfDay(for: goalStart) {
            let days = TimelineMath.dayOffset(from: day, to: goalStart, calendar: calendar)
            return "距开始 " + String(days) + " 天"
        }
        if day > calendar.startOfDay(for: goalEnd) { return "计划周期已结束" }

        let totalDays = TimelineMath.inclusiveDayCount(from: goalStart, to: goalEnd, calendar: calendar)
        let currentDay = TimelineMath.dayOffset(from: goalStart, to: day, calendar: calendar) + 1
        let percent = Int((elapsedFraction(
            goalStart: goalStart, goalEnd: goalEnd, on: day, calendar: calendar
        ) * 100).rounded())
        return "第 " + String(currentDay) + " / " + String(totalDays)
            + " 天 · 周期位置 " + String(percent) + "%"
    }

    static func focus(
        workstreams: [Workstream],
        goalStart: Date,
        goalEnd: Date,
        on date: Date,
        calendar: Calendar = .current
    ) -> GoalPlanFocus {
        guard !workstreams.isEmpty else {
            return GoalPlanFocus(state: .empty, current: [], next: nil)
        }

        let day = calendar.startOfDay(for: date)
        let next = workstreams
            .filter { calendar.startOfDay(for: $0.startDate) > day }
            .min { lhs, rhs in
                lhs.startDate == rhs.startDate ? lhs.endDate < rhs.endDate : lhs.startDate < rhs.startDate
            }
        if day < calendar.startOfDay(for: goalStart) {
            return GoalPlanFocus(state: .upcoming, current: [], next: next)
        }
        if day > calendar.startOfDay(for: goalEnd) {
            return GoalPlanFocus(state: .ended, current: [], next: nil)
        }

        let current = WorkstreamTimelineLogic.current(in: workstreams, on: day, calendar: calendar)
        if !current.isEmpty {
            return GoalPlanFocus(state: .current, current: current, next: next)
        }
        return GoalPlanFocus(state: .gap, current: [], next: next)
    }

    static func monthTicks(
        goalStart: Date,
        goalEnd: Date,
        width: CGFloat,
        minimumSpacing: CGFloat = 70,
        calendar: Calendar = .current
    ) -> [Date] {
        let ticks = TimelineMath.monthTicks(from: goalStart, to: goalEnd, calendar: calendar)
        let totalDays = CGFloat(TimelineMath.inclusiveDayCount(from: goalStart, to: goalEnd, calendar: calendar))
        var lastPosition = -CGFloat.infinity
        return ticks.filter { tick in
            let position = CGFloat(TimelineMath.dayOffset(from: goalStart, to: tick, calendar: calendar)) / totalDays * width
            guard position + monthLabelWidth <= width else { return false }
            guard position - lastPosition >= minimumSpacing else { return false }
            lastPosition = position
            return true
        }
    }

    static func monthLabel(for date: Date, calendar: Calendar = .current) -> String {
        "\(calendar.component(.year, from: date))/\(calendar.component(.month, from: date))"
    }
}

enum TimelineMath {
    static func dayOffset(from startDate: Date, to date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: startDate.startOfDay, to: date.startOfDay).day ?? 0
    }

    static func inclusiveDayCount(from startDate: Date, to endDate: Date, calendar: Calendar = .current) -> Int {
        max(1, dayOffset(from: startDate, to: endDate, calendar: calendar) + 1)
    }

    static func monthTicks(from startDate: Date, to endDate: Date, calendar: Calendar = .current) -> [Date] {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        guard normalizedStart <= normalizedEnd else { return [] }

        var ticks = [normalizedStart]
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: normalizedStart))
            ?? normalizedStart
        if cursor <= normalizedStart {
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? normalizedEnd.addingTimeInterval(1)
        }
        while cursor <= normalizedEnd {
            ticks.append(cursor)
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? normalizedEnd.addingTimeInterval(1)
        }
        return ticks
    }

    static func monthLabelTicks(
        from startDate: Date,
        to endDate: Date,
        minimumSpacingDays: Int = 12,
        calendar: Calendar = .current
    ) -> [Date] {
        monthTicks(from: startDate, to: endDate, calendar: calendar).reduce(into: []) { labels, tick in
            guard let previous = labels.last else {
                labels.append(tick)
                return
            }
            if dayOffset(from: previous, to: tick, calendar: calendar) >= minimumSpacingDays {
                labels.append(tick)
            }
        }
    }

    static func workstreamBarHeight(
        durationDays: Int,
        availableHeight: CGFloat,
        pointsPerDay: CGFloat
    ) -> CGFloat {
        guard availableHeight > 0 else { return 0 }
        let preferredHeight = max(36, CGFloat(max(1, durationDays)) * pointsPerDay - 5)
        return min(preferredHeight, availableHeight)
    }

    static func contentHeight(
        dayCount: Int,
        headerHeight: CGFloat,
        pointsPerDay: CGFloat,
        bottomPadding: CGFloat
    ) -> CGFloat {
        headerHeight + CGFloat(max(1, dayCount)) * pointsPerDay + bottomPadding
    }

    static func viewportHeight(
        for contentHeight: CGFloat,
        minimum: CGFloat = 140,
        maximum: CGFloat = 480
    ) -> CGFloat {
        min(maximum, max(minimum, contentHeight))
    }

    static func scrollContentHeight(
        chartHeight: CGFloat,
        viewportHeight: CGFloat,
        todayY: CGFloat?
    ) -> CGFloat {
        guard chartHeight > viewportHeight, let todayY else { return chartHeight }
        return max(chartHeight, todayY + viewportHeight)
    }
}

enum ScheduleTemplateResolver {
    static func canonical(from templates: [ScheduleTemplate], selectedID: String) -> ScheduleTemplate? {
        templates.first(where: { $0.id.uuidString == selectedID })
            ?? templates.min(by: { $0.createdAt < $1.createdAt })
    }
}

@MainActor
enum AppBootstrapper {
    static func ensureDefaultTemplate(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<ScheduleTemplate>()
        guard try context.fetchCount(descriptor) == 0 else { return }
        context.insert(ScheduleTemplate(name: "默认日"))
        try context.save()
    }
}

@MainActor
enum ScopeService {
    static func resolve(name: String, in context: ModelContext) throws -> ScheduleScope? {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.normalizedKey
        let scopes = try context.fetch(FetchDescriptor<ScheduleScope>())
        if let existing = scopes.first(where: { $0.normalizedName == normalized }) {
            return existing
        }

        let colorKey = CMTheme.paletteKeys[scopes.count % CMTheme.paletteKeys.count]
        let scope = ScheduleScope(name: trimmed, normalizedName: normalized, colorKey: colorKey)
        context.insert(scope)
        return scope
    }
}

@MainActor
enum TagService {
    static func resolve(commaSeparatedNames value: String, in context: ModelContext) throws -> [Tag] {
        let requestedNames = value
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }

        let existing = try context.fetch(FetchDescriptor<Tag>())
        var result: [Tag] = []

        for name in requestedNames {
            let key = name.normalizedKey
            if let tag = existing.first(where: { $0.normalizedName == key }) ?? result.first(where: { $0.normalizedName == key }) {
                result.append(tag)
            } else {
                let colorKey = CMTheme.paletteKeys[(existing.count + result.count) % CMTheme.paletteKeys.count]
                let tag = Tag(name: name, normalizedName: key, colorKey: colorKey)
                context.insert(tag)
                result.append(tag)
            }
        }

        return Array(Dictionary(grouping: result, by: \Tag.normalizedName).compactMap(\.value.first))
    }
}

enum TextParser {
    static func titleAndDetails(from text: String) -> (title: String, details: String) {
        let lines = text.split(whereSeparator: \Character.isNewline).map(String.init)
        let title = lines.first?.trimmed.isEmpty == false ? lines[0].trimmed : "未命名内容"
        let details = lines.dropFirst().joined(separator: "\n").trimmed
        return (title, details)
    }
}

extension Int {
    var clockText: String {
        guard self == 1440 else {
            return String(format: "%02d:%02d", self / 60, self % 60)
        }
        return "24:00"
    }
}
