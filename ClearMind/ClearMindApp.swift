import SwiftData
import SwiftUI

extension Notification.Name {
    static let showQuickCapture = Notification.Name("ClearMind.showQuickCapture")
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
