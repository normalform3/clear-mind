import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \Goal.updatedAt, order: .reverse) private var goals: [Goal]
    @Query(sort: \NearTermItem.reviewDate) private var nearTermItems: [NearTermItem]
    @Query(sort: \InboxEntry.createdAt, order: .reverse) private var inboxEntries: [InboxEntry]

    let onNavigate: (SidebarSection) -> Void

    private var activeGoals: [Goal] {
        goals.filter { !$0.isArchived && $0.status == .active }
    }

    private var reviewItems: [NearTermItem] {
        nearTermItems.filter { !$0.isArchived && $0.reviewDate.startOfDay <= Date.now.startOfDay }
    }

    var body: some View {
        PageContainer {
            VStack(alignment: .leading, spacing: CMTheme.sectionSpacing) {
                PageHeader(
                    "都已经安顿好了",
                    eyebrow: Date.now.formatted(.dateTime.year().month().day().weekday(.wide).locale(Locale(identifier: "zh_CN")))
                )

                ScheduleSection()

                IslandSection { dashboardGoals }
                IslandSection { reviewSection }
                IslandSection { inboxSection }
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
                        GoalSummaryCard(goal: goal)
                    }
                }
            }
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("该重新看看了", trailingText: reviewItems.isEmpty ? nil : "\(reviewItems.count) 条", actionTitle: "查看全部") {
                onNavigate(.nearTerm)
            }
            QuietDivider()

            if reviewItems.isEmpty {
                EmptyState("暂时没有需要回看的事", message: "那些不能立刻处理的事情仍然安全地待在原处。")
            } else {
                ForEach(reviewItems.prefix(4)) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(CMTheme.textTertiary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .medium))
                            Text("原定 \(item.reviewDate.compactChineseDate) 回看")
                                .font(.system(size: 11))
                                .foregroundStyle(CMTheme.textSecondary)
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

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("收集箱", trailingText: "\(inboxEntries.count) 条", actionTitle: "打开") {
                onNavigate(.inbox)
            }
            QuietDivider()

            if inboxEntries.isEmpty {
                EmptyState("收集箱是空的", message: "没有悬而未决的念头需要分类。")
            } else {
                ForEach(inboxEntries.prefix(3)) { entry in
                    Text(entry.text)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .padding(.vertical, CMTheme.rowVerticalPadding)
                    QuietDivider()
                }
            }
        }
    }
}
