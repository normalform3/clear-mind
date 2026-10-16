import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query private var goals: [Goal]
    @Query(sort: \NearTermItem.updatedAt, order: .reverse) private var nearTermItems: [NearTermItem]
    @State private var inlineHitRegions: [ScheduleInlineHitRegion] = []
    @State private var outsideTap: ScheduleOutsideTap?
    @State private var tapSequence = 0

    let onNavigate: (SidebarSection) -> Void

    private var activeGoals: [Goal] {
        GoalOrderLogic.ordered(goals.filter { !$0.isArchived })
    }

    private var recentItems: [NearTermItem] {
        nearTermItems.filter { !$0.isArchived }
    }

    var body: some View {
        PageContainer {
            VStack(alignment: .leading, spacing: 38) {
                TimelineView(.everyMinute) { context in
                    DashboardTimeHeader(
                        date: UITestFixtureSeeder.dashboardReferenceDate ?? context.date
                    )
                }

                ScheduleSection(outsideTap: outsideTap)

                DashboardIslandSection { dashboardGoals }
                DashboardIslandSection { nearTermSection }
            }
            .coordinateSpace(name: "dashboard")
            .onPreferenceChange(ScheduleInlineHitRegionKey.self) { inlineHitRegions = $0 }
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named("dashboard")).onEnded { tap in
                guard let region = inlineHitRegions.first,
                      !inlineHitRegions.contains(where: { $0.frame.contains(tap.location) }) else { return }
                tapSequence += 1
                outsideTap = ScheduleOutsideTap(
                    blockID: region.blockID,
                    field: region.field,
                    sequence: tapSequence
                )
            })
        }
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
                        NavigationLink(value: AppNavigationRoute.goal(goal.id)) {
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

private struct DashboardTimeHeader: View {
    let date: Date

    private var dateText: String {
        date.formatted(
            .dateTime.year().month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))
        )
    }

    private var clockText: String {
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(dateText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CMTheme.textSecondary)
                .accessibilityIdentifier("dashboard-date")

            Text(clockText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CMTheme.textSecondary)
                .accessibilityIdentifier("dashboard-time")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard-date-time")
    }
}
