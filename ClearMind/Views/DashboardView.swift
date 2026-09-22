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
        NavigationStack {
            PageContainer {
                VStack(alignment: .leading, spacing: 46) {
                    TimelineView(.everyMinute) { context in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(context.date.formatted(
                                .dateTime.year().month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))
                            ))
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(CMTheme.textTertiary)
                            .accessibilityIdentifier("dashboard-date")

                            Circle()
                                .fill(CMTheme.separator)
                                .frame(width: 3, height: 3)
                                .accessibilityHidden(true)

                            Text(clockText(for: context.date))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CMTheme.textSecondary)
                                .monospacedDigit()
                                .accessibilityIdentifier("dashboard-time")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("dashboard-date-time")
                        .padding(.bottom, 8)
                    }

                    ScheduleSection()

                    DashboardIslandSection { dashboardGoals }
                    DashboardIslandSection { nearTermSection }
                }
            }
        }
    }

    private func clockText(for date: Date) -> String {
        let calendar = Calendar.current
        return String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
    }

    private var dashboardGoals: some View {
        VStack(alignment: .leading, spacing: 18) {
            DashboardModuleHeading(
                "目标",
                colorKey: "denim",
                accessibilityIdentifier: "dashboard-module-heading-goals"
            ) {
                Button("查看全部") { onNavigate(.goals) }
                    .buttonStyle(QuietButtonStyle())
                    .foregroundStyle(CMTheme.textSecondary)
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
                        NavigationLink {
                            GoalDetailView(goal: goal)
                        } label: {
                            GoalSummaryCard(goal: goal, showsProgressCalendar: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dashboard-goal-card-\(goal.id.uuidString)")
                    }
                }
            }
        }
    }

    private var nearTermSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardModuleHeading(
                "近期事项",
                colorKey: "ochre",
                accessibilityIdentifier: "dashboard-module-heading-near-term"
            ) {
                HStack(spacing: 8) {
                    if !recentItems.isEmpty {
                        Text("\(recentItems.count) 条")
                            .font(.system(size: 12))
                            .foregroundStyle(CMTheme.textSecondary)
                    }
                    Button("查看全部") { onNavigate(.nearTerm) }
                        .buttonStyle(QuietButtonStyle())
                        .foregroundStyle(CMTheme.textSecondary)
                }
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
