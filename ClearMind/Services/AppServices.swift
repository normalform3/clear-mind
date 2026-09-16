import Foundation
import SwiftData

enum ScheduleValidationError: LocalizedError, Equatable {
    case invalidRange
    case overlaps

    var errorDescription: String? {
        switch self {
        case .invalidRange: "结束时间需要晚于开始时间。"
        case .overlaps: "这个时间段与模板中的其他安排重叠。"
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

enum TimelineMath {
    static func dayOffset(from startDate: Date, to date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: startDate.startOfDay, to: date.startOfDay).day ?? 0
    }

    static func inclusiveDayCount(from startDate: Date, to endDate: Date, calendar: Calendar = .current) -> Int {
        max(1, dayOffset(from: startDate, to: endDate, calendar: calendar) + 1)
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
