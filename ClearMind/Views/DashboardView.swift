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
            VStack(alignment: .leading, spacing: 38) {
                TimelineView(.everyMinute) { context in
                    DashboardTimeHeader(
                        date: UITestFixtureSeeder.dashboardReferenceDate ?? context.date
                    )
                }

                ScheduleSection()

                DashboardIslandSection { dashboardGoals }
                DashboardIslandSection { nearTermSection }
            }
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

    private var timeContext: DashboardTimeContext {
        DashboardTimeContext.resolve(at: date, blocks: [])
    }

    private var dateText: String {
        date.formatted(
            .dateTime.year().month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))
        )
    }

    private var clockText: String {
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        let period = hour < 12 ? "上午" : "下午"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%@ %d:%02d", period, hour12, minute)
    }

    private var accessibilitySummary: String {
        "今天是\(dateText)，现在是\(clockText)"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ZStack(alignment: .leading) {
                daylightArc
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(x: -56)

                dateAndTime
            }
            .frame(minWidth: 600, minHeight: 64)

            VStack(alignment: .leading, spacing: 16) {
                dateAndTime

                daylightArc
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard-date-time")
    }

    private var daylightArc: some View {
        DashboardDaylightArc(progress: timeContext.dayProgress)
            .frame(width: 220, height: 54)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("一日进度，今天已过去约 \(Int((timeContext.dayProgress * 100).rounded()))%")
            .accessibilityIdentifier("dashboard-daylight-arc")
    }

    private var dateAndTime: some View {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }
}

private struct DashboardDaylightArc: View {
    let progress: Double

    private let tickPositions = [0.0, 0.25, 0.5, 0.75, 1.0]
    private let horizontalInset: CGFloat = 8
    private let horizonY: CGFloat = 37
    private let controlY: CGFloat = -4

    var body: some View {
        GeometryReader { proxy in
            let currentPosition = point(at: progress, in: proxy.size)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: horizontalInset, y: horizonY))
                    path.addLine(to: CGPoint(x: proxy.size.width - horizontalInset, y: horizonY))
                }
                .stroke(CMTheme.daylightHorizon, lineWidth: 0.8)

                DashboardDaylightArcShape()
                    .stroke(
                        CMTheme.daylightArcTrack,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )

                DashboardDaylightArcShape()
                    .trim(from: 0, to: progress)
                    .stroke(
                        CMTheme.daylightArcAccent,
                        style: StrokeStyle(lineWidth: 2.25, lineCap: .round)
                    )

                ForEach(tickPositions, id: \.self) { position in
                    let tickPosition = point(at: position, in: proxy.size)
                    Path { path in
                        path.move(to: CGPoint(x: tickPosition.x, y: tickPosition.y - 2.5))
                        path.addLine(to: CGPoint(x: tickPosition.x, y: tickPosition.y + 2.5))
                    }
                    .stroke(
                        CMTheme.daylightArcScale,
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                        .accessibilityHidden(true)
                }

                Circle()
                    .fill(CMTheme.daylightSunHalo)
                    .frame(width: 17, height: 17)
                    .position(currentPosition)
                    .accessibilityHidden(true)

                Circle()
                    .fill(CMTheme.canvas)
                    .overlay {
                        Circle()
                            .stroke(CMTheme.daylightArcAccent, lineWidth: 1.5)
                    }
                    .frame(width: 7, height: 7)
                    .position(currentPosition)
                    .accessibilityHidden(true)

                scaleLabel("0", x: horizontalInset)
                scaleLabel("12", x: proxy.size.width / 2)
                scaleLabel("24", x: proxy.size.width - horizontalInset)
            }
        }
    }

    private func scaleLabel(_ value: String, x: CGFloat) -> some View {
        Text(value)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(CMTheme.daylightArcScale)
            .frame(width: 22)
            .position(x: x, y: 49)
            .accessibilityHidden(true)
    }

    private func point(at progress: Double, in size: CGSize) -> CGPoint {
        let t = min(max(progress, 0), 1)
        let inverse = 1 - t
        let start = CGPoint(x: horizontalInset, y: horizonY)
        let control = CGPoint(x: size.width / 2, y: controlY)
        let end = CGPoint(x: size.width - horizontalInset, y: horizonY)

        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }
}

private struct DashboardDaylightArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 8, y: 37))
        path.addQuadCurve(
            to: CGPoint(x: rect.width - 8, y: 37),
            control: CGPoint(x: rect.midX, y: -4)
        )
        return path
    }
}
