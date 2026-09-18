import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query private var goals: [Goal]
    @Query(sort: \NearTermItem.updatedAt, order: .reverse) private var nearTermItems: [NearTermItem]

    let onNavigate: (SidebarSection) -> Void

    private var activeGoals: [Goal] {
        GoalOrderLogic.ordered(goals.filter { !$0.isArchived })
    }

    private var recentItems: [NearTermItem] {
        nearTermItems.filter { !$0.isArchived }
    }

    var body: some View {
        PageContainer {
            VStack(alignment: .leading, spacing: 46) {
                Text(Date.now.formatted(
                    .dateTime.year().month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))
                ))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(CMTheme.textTertiary)
                .padding(.bottom, 8)
                .accessibilityIdentifier("dashboard-date")

                ScheduleSection()

                DashboardIslandSection { dashboardGoals }
                DashboardIslandSection { nearTermSection }
            }
        }
    }

    private var dashboardGoals: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading("正在追求的方向", actionTitle: "查看全部") {
                onNavigate(.goals)
            }

            if activeGoals.isEmpty {
                EmptyState("还没有长期目标", message: "建立一个真正值得投入几个月的方向。", actionTitle: "前往长期目标") {
                    onNavigate(.goals)
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 340, maximum: 460), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(activeGoals.prefix(3)) { goal in
                        GoalSummaryCard(goal: goal, showsProgressCalendar: true)
                    }
                }
            }
        }
    }

    private var nearTermSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("近期事项", trailingText: recentItems.isEmpty ? nil : "\(recentItems.count) 条", actionTitle: "查看全部") {
                onNavigate(.nearTerm)
            }
            QuietDivider()

            if recentItems.isEmpty {
                EmptyState("近期没有需要托管的事情", message: "那些不能立刻处理的事情仍然可以安全地待在原处。")
            } else {
                ForEach(recentItems.prefix(4)) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "tray.full")
                            .foregroundStyle(CMTheme.textTertiary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .medium))
                            if !item.details.trimmed.isEmpty {
                                Text(item.details)
                                    .font(.system(size: 12))
                                    .foregroundStyle(CMTheme.textSecondary)
                                    .lineLimit(2)
                            }
                            TagPills(tags: item.tags)
                        }
                        Spacer()
                    }
                    .padding(.vertical, CMTheme.rowVerticalPadding)
                    QuietDivider()
                }
            }
        }
    }

}
