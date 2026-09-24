import SwiftData
import SwiftUI

extension Notification.Name {
    static let showQuickCapture = Notification.Name("ClearMind.showQuickCapture")
    static let focusGlobalSearch = Notification.Name("ClearMind.focusGlobalSearch")
}

@MainActor
enum UITestFixtureSeeder {
    static let goalID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let workstreamID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let earlierWorkstreamID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let laterWorkstreamID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let currentScheduleBlockID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    static let nextScheduleBlockID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

    static var dashboardReferenceDate: Date? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting-dashboard-time-fixture") else { return nil }
        return Calendar.current.date(
            bySettingHour: 14,
            minute: 30,
            second: 0,
            of: .now
        )
    }

    static func seedIfRequested(in context: ModelContext) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting") else { return }

        if arguments.contains("--uitesting-goal-fixture") {
            try seedGoalTimeline(in: context, referenceDate: .now)
        }
        if arguments.contains("--uitesting-dashboard-time-fixture") {
            try seedDashboardSchedule(in: context)
        }
    }

    static func seedGoalTimeline(
        in context: ModelContext,
        referenceDate: Date
    ) throws {
        let goals = try context.fetch(FetchDescriptor<Goal>())
        guard !goals.contains(where: { $0.id == goalID }) else { return }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: referenceDate)
        let goal = Goal(
            id: goalID,
            title: "UI 测试目标",
            startDate: calendar.date(byAdding: .day, value: -45, to: day) ?? day,
            endDate: calendar.date(byAdding: .day, value: 45, to: day) ?? day
        )
        let workstream = Workstream(
            id: workstreamID,
            title: "UI 测试推进项",
            startDate: calendar.date(byAdding: .day, value: -5, to: day) ?? day,
            endDate: calendar.date(byAdding: .day, value: 10, to: day) ?? day
        )
        let earlier = Workstream(
            id: earlierWorkstreamID,
            title: "前期梳理",
            startDate: calendar.date(byAdding: .day, value: -35, to: day) ?? day,
            endDate: calendar.date(byAdding: .day, value: -12, to: day) ?? day
        )
        let later = Workstream(
            id: laterWorkstreamID,
            title: "交付收尾",
            startDate: calendar.date(byAdding: .day, value: 8, to: day) ?? day,
            endDate: calendar.date(byAdding: .day, value: 35, to: day) ?? day
        )
        let milestone = Milestone(
            title: "首版完成",
            date: calendar.date(byAdding: .day, value: 15, to: day) ?? day
        )
        goal.workstreams.append(contentsOf: [earlier, workstream, later])
        goal.milestones.append(milestone)
        context.insert(goal)
        try context.save()
    }

    static func seedDashboardSchedule(in context: ModelContext) throws {
        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>())
        guard let template = templates.min(by: { $0.createdAt < $1.createdAt }) else { return }
        guard !template.blocks.contains(where: { $0.id == currentScheduleBlockID }) else { return }

        let focusScope = ScheduleScope(name: "深度工作", colorKey: "denim")
        let walkScope = ScheduleScope(name: "散步", colorKey: "sage")
        let current = ScheduleBlock(
            id: currentScheduleBlockID,
            startMinute: 14 * 60,
            endMinute: 15 * 60,
            scope: focusScope
        )
        let next = ScheduleBlock(
            id: nextScheduleBlockID,
            startMinute: 15 * 60 + 30,
            endMinute: 16 * 60,
            scope: walkScope
        )

        context.insert(focusScope)
        context.insert(walkScope)
        template.blocks.append(contentsOf: [current, next])
        try context.save()
    }
}

@main
struct ClearMindApp: App {
    private let modelContainer: ModelContainer = {
        do {
            let configuration = ModelConfiguration(
                isStoredInMemoryOnly: ProcessInfo.processInfo.arguments.contains("--uitesting")
            )
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
        } catch {
            fatalError("无法建立本地数据库：\(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup("Clear Mind") {
            RootView()
                .modelContainer(modelContainer)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("记到收集箱…") {
                    NotificationCenter.default.post(name: .showQuickCapture, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("搜索所有内容") {
                    NotificationCenter.default.post(name: .focusGlobalSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .modelContainer(modelContainer)
                .frame(width: 560, height: 420)
        }
    }
}
