import SwiftData
import SwiftUI

extension Notification.Name {
    static let showQuickCapture = Notification.Name("ClearMind.showQuickCapture")
}

@MainActor
enum UITestFixtureSeeder {
    static let goalID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let workstreamID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    static func seedIfRequested(in context: ModelContext) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"),
              arguments.contains("--uitesting-goal-fixture") else { return }
        try seedGoalTimeline(in: context, referenceDate: .now)
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
        goal.workstreams.append(workstream)
        context.insert(goal)
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
        }

        Settings {
            SettingsView()
                .modelContainer(modelContainer)
                .frame(width: 560, height: 420)
        }
    }
}
