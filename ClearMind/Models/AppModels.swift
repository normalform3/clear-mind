import Foundation
import SwiftData

enum GoalStatus: String, CaseIterable, Codable, Identifiable {
    case active
    case paused
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "进行中"
        case .paused: "已暂停"
        case .completed: "已完成"
        }
    }
}

enum WorkstreamStatus: String, CaseIterable, Codable, Identifiable {
    case planned
    case inProgress
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planned: "未开始"
        case .inProgress: "进行中"
        case .completed: "已完成"
        }
    }
}

enum TimelineZoom: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        }
    }

    var pointsPerDay: CGFloat {
        switch self {
        case .day: 28
        case .week: 10
        case .month: 3.2
        }
    }
}

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var normalizedName: String
    var colorKey: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        normalizedName: String? = nil,
        colorKey: String = "sage",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName ?? name.normalizedKey
        self.colorKey = colorKey
        self.createdAt = createdAt
    }
}

@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var startDate: Date
    var endDate: Date
    var statusRaw: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var tags: [Tag]

    @Relationship(deleteRule: .cascade, inverse: \Workstream.goal)
    var workstreams: [Workstream]

    @Relationship(deleteRule: .cascade, inverse: \Milestone.goal)
    var milestones: [Milestone]

    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .active }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        startDate: Date,
        endDate: Date,
        status: GoalStatus = .active,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tags: [Tag] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.startDate = startDate.startOfDay
        self.endDate = endDate.startOfDay
        self.statusRaw = status.rawValue
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.workstreams = []
        self.milestones = []
    }
}

@Model
final class Workstream {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var startDate: Date
    var endDate: Date
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var goal: Goal?

    var status: WorkstreamStatus {
        get { WorkstreamStatus(rawValue: statusRaw) ?? .planned }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        startDate: Date,
        endDate: Date,
        status: WorkstreamStatus = .planned,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.startDate = startDate.startOfDay
        self.endDate = endDate.startOfDay
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Milestone {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var date: Date
    var isCompleted: Bool
    var createdAt: Date
    var goal: Goal?

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        date: Date,
        isCompleted: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.date = date.startOfDay
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}

@Model
final class NearTermItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var reviewDate: Date
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var tags: [Tag]

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        reviewDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tags: [Tag] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.reviewDate = reviewDate.startOfDay
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
    }
}

@Model
final class Idea {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var tags: [Tag]

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tags: [Tag] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
    }
}

@Model
final class InboxEntry {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

@Model
final class ScheduleScope {
    @Attribute(.unique) var id: UUID
    var name: String
    var normalizedName: String
    var colorKey: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        normalizedName: String? = nil,
        colorKey: String = "sage",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName ?? name.normalizedKey
        self.colorKey = colorKey
        self.createdAt = createdAt
    }
}

@Model
final class ScheduleTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ScheduleBlock.template)
    var blocks: [ScheduleBlock]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.blocks = []
    }
}

@Model
final class ScheduleBlock {
    @Attribute(.unique) var id: UUID
    var startMinute: Int
    var endMinute: Int
    var createdAt: Date
    var updatedAt: Date
    var template: ScheduleTemplate?
    var scope: ScheduleScope?

    @Relationship(deleteRule: .cascade, inverse: \ScheduleChecklistItem.block)
    var checklistItems: [ScheduleChecklistItem]

    init(
        id: UUID = UUID(),
        startMinute: Int,
        endMinute: Int,
        scope: ScheduleScope? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.scope = scope
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.checklistItems = []
    }
}

@Model
final class ScheduleChecklistItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: Date
    var block: ScheduleBlock?

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

extension String {
    var normalizedKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}
