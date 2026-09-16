import Foundation
import SwiftData

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "这个备份来自不受支持的数据版本（\(version)）。"
        case .invalidData(let message): "备份内容无效：\(message)"
        }
    }
}

struct BackupEnvelope: Codable {
    static let currentVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let tags: [TagRecord]
    let goals: [GoalRecord]
    let nearTermItems: [NearTermRecord]
    let ideas: [IdeaRecord]
    let inboxEntries: [InboxRecord]
    let scheduleScopes: [ScopeRecord]
    let scheduleTemplates: [TemplateRecord]
}

struct TagRecord: Codable {
    let id: UUID
    let name: String
    let normalizedName: String
    let colorKey: String
    let createdAt: Date
}

struct GoalRecord: Codable {
    let id: UUID
    let title: String
    let details: String
    let startDate: Date
    let endDate: Date
    let statusRaw: String
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let tagIDs: [UUID]
    let workstreams: [WorkstreamRecord]
    let milestones: [MilestoneRecord]
}

struct WorkstreamRecord: Codable {
    let id: UUID
    let title: String
    let details: String
    let startDate: Date
    let endDate: Date
    let statusRaw: String
    let createdAt: Date
    let updatedAt: Date
}

struct MilestoneRecord: Codable {
    let id: UUID
    let title: String
    let details: String
    let date: Date
    let isCompleted: Bool
    let createdAt: Date
}

struct NearTermRecord: Codable {
    let id: UUID
    let title: String
    let details: String
    let reviewDate: Date
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let tagIDs: [UUID]
}

struct IdeaRecord: Codable {
    let id: UUID
    let title: String
    let details: String
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let tagIDs: [UUID]
}

struct InboxRecord: Codable {
    let id: UUID
    let text: String
    let createdAt: Date
}

struct ScopeRecord: Codable {
    let id: UUID
    let name: String
    let normalizedName: String
    let colorKey: String
    let createdAt: Date
}

struct TemplateRecord: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let blocks: [BlockRecord]
}

struct BlockRecord: Codable {
    let id: UUID
    let startMinute: Int
    let endMinute: Int
    let createdAt: Date
    let updatedAt: Date
    let scopeID: UUID?
    let checklistItems: [ChecklistRecord]
}

struct ChecklistRecord: Codable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let sortOrder: Int
    let createdAt: Date
}

@MainActor
enum BackupService {
    static func exportData(from context: ModelContext) throws -> Data {
        let envelope = try makeEnvelope(from: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    static func summary(of data: Data) throws -> String {
        let envelope = try decode(data)
        return "\(envelope.goals.count) 个长期目标、\(envelope.nearTermItems.count) 个近期事项、\(envelope.ideas.count) 条想法、\(envelope.scheduleTemplates.count) 个时间表模板"
    }

    static func importData(_ data: Data, into context: ModelContext) throws {
        let envelope = try decode(data)
        try validate(envelope)
        try saveSafetySnapshot(from: context)

        do {
            try clearAll(in: context)
            try restore(envelope, into: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func makeEnvelope(from context: ModelContext) throws -> BackupEnvelope {
        let tags = try context.fetch(FetchDescriptor<Tag>())
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let nearTerm = try context.fetch(FetchDescriptor<NearTermItem>())
        let ideas = try context.fetch(FetchDescriptor<Idea>())
        let inbox = try context.fetch(FetchDescriptor<InboxEntry>())
        let scopes = try context.fetch(FetchDescriptor<ScheduleScope>())
        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>())

        return BackupEnvelope(
            schemaVersion: BackupEnvelope.currentVersion,
            exportedAt: .now,
            tags: tags.map { TagRecord(id: $0.id, name: $0.name, normalizedName: $0.normalizedName, colorKey: $0.colorKey, createdAt: $0.createdAt) },
            goals: goals.map { goal in
                GoalRecord(
                    id: goal.id,
                    title: goal.title,
                    details: goal.details,
                    startDate: goal.startDate,
                    endDate: goal.endDate,
                    statusRaw: goal.statusRaw,
                    isArchived: goal.isArchived,
                    createdAt: goal.createdAt,
                    updatedAt: goal.updatedAt,
                    tagIDs: goal.tags.map(\.id),
                    workstreams: goal.workstreams.map {
                        WorkstreamRecord(id: $0.id, title: $0.title, details: $0.details, startDate: $0.startDate, endDate: $0.endDate, statusRaw: $0.statusRaw, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
                    },
                    milestones: goal.milestones.map {
                        MilestoneRecord(id: $0.id, title: $0.title, details: $0.details, date: $0.date, isCompleted: $0.isCompleted, createdAt: $0.createdAt)
                    }
                )
            },
            nearTermItems: nearTerm.map {
                NearTermRecord(id: $0.id, title: $0.title, details: $0.details, reviewDate: $0.reviewDate, isArchived: $0.isArchived, createdAt: $0.createdAt, updatedAt: $0.updatedAt, tagIDs: $0.tags.map(\.id))
            },
            ideas: ideas.map {
                IdeaRecord(id: $0.id, title: $0.title, details: $0.details, isArchived: $0.isArchived, createdAt: $0.createdAt, updatedAt: $0.updatedAt, tagIDs: $0.tags.map(\.id))
            },
            inboxEntries: inbox.map { InboxRecord(id: $0.id, text: $0.text, createdAt: $0.createdAt) },
            scheduleScopes: scopes.map { ScopeRecord(id: $0.id, name: $0.name, normalizedName: $0.normalizedName, colorKey: $0.colorKey, createdAt: $0.createdAt) },
            scheduleTemplates: templates.map { template in
                TemplateRecord(
                    id: template.id,
                    name: template.name,
                    createdAt: template.createdAt,
                    updatedAt: template.updatedAt,
                    blocks: template.blocks.map { block in
                        BlockRecord(
                            id: block.id,
                            startMinute: block.startMinute,
                            endMinute: block.endMinute,
                            createdAt: block.createdAt,
                            updatedAt: block.updatedAt,
                            scopeID: block.scope?.id,
                            checklistItems: block.checklistItems.map {
                                ChecklistRecord(id: $0.id, title: $0.title, isCompleted: $0.isCompleted, sortOrder: $0.sortOrder, createdAt: $0.createdAt)
                            }
                        )
                    }
                )
            }
        )
    }

    private static func decode(_ data: Data) throws -> BackupEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
        guard envelope.schemaVersion == BackupEnvelope.currentVersion else {
            throw BackupError.unsupportedVersion(envelope.schemaVersion)
        }
        return envelope
    }

    private static func validate(_ envelope: BackupEnvelope) throws {
        guard !envelope.scheduleTemplates.isEmpty else {
            throw BackupError.invalidData("至少需要一个时间表模板。")
        }

        let tagIDs = Set(envelope.tags.map(\.id))
        let scopeIDs = Set(envelope.scheduleScopes.map(\.id))

        for goal in envelope.goals {
            guard !goal.title.trimmed.isEmpty, goal.startDate <= goal.endDate else {
                throw BackupError.invalidData("长期目标标题或日期范围不正确。")
            }
            guard Set(goal.tagIDs).isSubset(of: tagIDs) else {
                throw BackupError.invalidData("长期目标引用了不存在的标签。")
            }
            guard goal.workstreams.allSatisfy({ $0.startDate <= $0.endDate && $0.startDate >= goal.startDate && $0.endDate <= goal.endDate }) else {
                throw BackupError.invalidData("推进项超出了长期目标周期。")
            }
        }

        for template in envelope.scheduleTemplates {
            let sorted = template.blocks.sorted { $0.startMinute < $1.startMinute }
            for (index, block) in sorted.enumerated() {
                guard block.startMinute >= 0, block.endMinute <= 1440, block.startMinute < block.endMinute else {
                    throw BackupError.invalidData("时间表中存在无效时间段。")
                }
                if let scopeID = block.scopeID, !scopeIDs.contains(scopeID) {
                    throw BackupError.invalidData("时间块引用了不存在的归属。")
                }
                if index > 0, sorted[index - 1].endMinute > block.startMinute {
                    throw BackupError.invalidData("同一模板中存在重叠时间段。")
                }
            }
        }
    }

    private static func clearAll(in context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<Goal>()) { context.delete(model) }
        for model in try context.fetch(FetchDescriptor<NearTermItem>()) { context.delete(model) }
        for model in try context.fetch(FetchDescriptor<Idea>()) { context.delete(model) }
        for model in try context.fetch(FetchDescriptor<InboxEntry>()) { context.delete(model) }
        for model in try context.fetch(FetchDescriptor<ScheduleTemplate>()) { context.delete(model) }
        for model in try context.fetch(FetchDescriptor<Tag>()) { context.delete(model) }
        for model in try context.fetch(FetchDescriptor<ScheduleScope>()) { context.delete(model) }
    }

    private static func restore(_ envelope: BackupEnvelope, into context: ModelContext) throws {
        var tagMap: [UUID: Tag] = [:]
        for record in envelope.tags {
            let tag = Tag(id: record.id, name: record.name, normalizedName: record.normalizedName, colorKey: record.colorKey, createdAt: record.createdAt)
            context.insert(tag)
            tagMap[record.id] = tag
        }

        var scopeMap: [UUID: ScheduleScope] = [:]
        for record in envelope.scheduleScopes {
            let scope = ScheduleScope(id: record.id, name: record.name, normalizedName: record.normalizedName, colorKey: record.colorKey, createdAt: record.createdAt)
            context.insert(scope)
            scopeMap[record.id] = scope
        }

        for record in envelope.goals {
            let goal = Goal(
                id: record.id,
                title: record.title,
                details: record.details,
                startDate: record.startDate,
                endDate: record.endDate,
                status: GoalStatus(rawValue: record.statusRaw) ?? .active,
                isArchived: record.isArchived,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                tags: record.tagIDs.compactMap { tagMap[$0] }
            )
            context.insert(goal)
            for item in record.workstreams {
                goal.workstreams.append(Workstream(
                    id: item.id,
                    title: item.title,
                    details: item.details,
                    startDate: item.startDate,
                    endDate: item.endDate,
                    status: WorkstreamStatus(rawValue: item.statusRaw) ?? .planned,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                ))
            }
            for item in record.milestones {
                goal.milestones.append(Milestone(id: item.id, title: item.title, details: item.details, date: item.date, isCompleted: item.isCompleted, createdAt: item.createdAt))
            }
        }

        for record in envelope.nearTermItems {
            context.insert(NearTermItem(
                id: record.id,
                title: record.title,
                details: record.details,
                reviewDate: record.reviewDate,
                isArchived: record.isArchived,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                tags: record.tagIDs.compactMap { tagMap[$0] }
            ))
        }

        for record in envelope.ideas {
            context.insert(Idea(
                id: record.id,
                title: record.title,
                details: record.details,
                isArchived: record.isArchived,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                tags: record.tagIDs.compactMap { tagMap[$0] }
            ))
        }

        for record in envelope.inboxEntries {
            context.insert(InboxEntry(id: record.id, text: record.text, createdAt: record.createdAt))
        }

        for record in envelope.scheduleTemplates {
            let template = ScheduleTemplate(id: record.id, name: record.name, createdAt: record.createdAt, updatedAt: record.updatedAt)
            context.insert(template)
            for item in record.blocks {
                let block = ScheduleBlock(
                    id: item.id,
                    startMinute: item.startMinute,
                    endMinute: item.endMinute,
                    scope: item.scopeID.flatMap { scopeMap[$0] },
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
                template.blocks.append(block)
                for checklistItem in item.checklistItems {
                    block.checklistItems.append(ScheduleChecklistItem(
                        id: checklistItem.id,
                        title: checklistItem.title,
                        isCompleted: checklistItem.isCompleted,
                        sortOrder: checklistItem.sortOrder,
                        createdAt: checklistItem.createdAt
                    ))
                }
            }
        }
    }

    private static func saveSafetySnapshot(from context: ModelContext) throws {
        let data = try exportData(from: context)
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("ClearMind", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        try data.write(to: directory.appendingPathComponent("before-import-\(stamp).clearmindbackup"), options: .atomic)
    }
}
