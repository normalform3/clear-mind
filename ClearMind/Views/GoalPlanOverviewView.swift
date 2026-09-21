import SwiftUI

struct GoalPlanOverviewView: View {
    @State private var displayedDay = Date.now.startOfDay
    @State private var isTimeProgressHovered = false
    @State private var hoveredWorkstreamID: UUID?

    let goal: Goal
    let workstreams: [Workstream]
    let milestones: [Milestone]
    let onSelectWorkstream: (Workstream) -> Void
    let onSelectMilestone: (Milestone) -> Void

    private let labelWidth: CGFloat = 218
    private let columnSpacing: CGFloat = 12
    private let axisHeight: CGFloat = 36
    private let workstreamHeight: CGFloat = 62
    private let milestoneHeight: CGFloat = 40
    private let emptyHeight: CGFloat = 56

    private var today: Date { displayedDay }

    private var focus: GoalPlanFocus {
        GoalPlanOverviewLogic.focus(
            workstreams: workstreams,
            goalStart: goal.startDate,
            goalEnd: goal.endDate,
            on: today
        )
    }

    private var totalDays: Int {
        TimelineMath.inclusiveDayCount(from: goal.startDate, to: goal.endDate)
    }

    private var elapsedFraction: Double {
        GoalPlanOverviewLogic.elapsedFraction(
            goalStart: goal.startDate,
            goalEnd: goal.endDate,
            on: today
        )
    }

    private var chartHeight: CGFloat {
        axisHeight
            + (workstreams.isEmpty ? emptyHeight : CGFloat(workstreams.count) * workstreamHeight)
            + CGFloat(milestones.count) * milestoneHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            timeProgress
            currentFocus
            chart
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goal-plan-overview")
        .onAppear { displayedDay = Date.now.startOfDay }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            let day = date.startOfDay
            if day != displayedDay { displayedDay = day }
        }
    }

    private var timeProgress: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("时间进度")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(GoalPlanOverviewLogic.progressText(
                    goalStart: goal.startDate,
                    goalEnd: goal.endDate,
                    on: today
                ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CMTheme.textSecondary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CMTheme.color(for: "denim").opacity(0.14))
                        .frame(height: 8)
                    Capsule()
                        .fill(CMTheme.color(for: "denim"))
                        .frame(width: geometry.size.width * elapsedFraction, height: 8)
                    if today >= goal.startDate && today <= goal.endDate {
                        Circle()
                            .fill(CMTheme.color(for: "clay"))
                            .frame(width: 10, height: 10)
                            .offset(x: max(0, min(geometry.size.width - 10, geometry.size.width * todayPosition - 5)))
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .onHover { isTimeProgressHovered = $0 }
                }
                .frame(height: 20)
                .overlay(alignment: .topLeading) {
                    if isTimeProgressHovered {
                        hoverLabel("今天：\(today.compactChineseDate)")
                            .offset(x: max(0, min(geometry.size.width - 160, geometry.size.width * todayPosition - 80)), y: 24)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 20)
            .zIndex(isTimeProgressHovered ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今天：\(today.compactChineseDate)")
            .accessibilityIdentifier("goal-plan-time-progress")

            HStack {
                Text(goal.startDate.compactChineseDate)
                Spacer()
                Text(goal.endDate.compactChineseDate)
            }
            .font(.system(size: 10))
            .foregroundStyle(CMTheme.textSecondary)
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private var currentFocus: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("当前推进")
                .font(.system(size: 12, weight: .semibold))

            switch focus.state {
            case .empty:
                Text("还没有推进项。添加一个小目标，就能看到它在整个计划中的位置。")
                    .foregroundStyle(CMTheme.textSecondary)
            case .upcoming:
                Text("目标尚未开始")
                    .foregroundStyle(CMTheme.textSecondary)
                nextItemText
            case .current:
                ForEach(focus.current) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(CMTheme.color(for: "denim"))
                            .frame(width: 6, height: 6)
                        Text(item.title)
                            .fontWeight(.medium)
                            .accessibilityIdentifier("goal-plan-current-\(item.id.uuidString)")
                        Spacer(minLength: 8)
                        Text("至 \(shortDate(item.endDate))")
                            .foregroundStyle(CMTheme.textSecondary)
                    }
                }
            case .gap:
                Text("今天没有安排推进项")
                    .foregroundStyle(CMTheme.textSecondary)
                nextItemText
            case .ended:
                Text("计划周期已结束，可以回看各推进项的时间安排。")
                    .foregroundStyle(CMTheme.textSecondary)
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var nextItemText: some View {
        if let next = focus.next {
            Text("接下来：\(next.title) · \(next.startDate.compactChineseDate)")
                .foregroundStyle(CMTheme.textSecondary)
        } else {
            Text("暂未安排后续推进项")
                .foregroundStyle(CMTheme.textTertiary)
        }
    }

    private var chart: some View {
        GeometryReader { geometry in
            let plotWidth = max(1, geometry.size.width - labelWidth - columnSpacing)
            let ticks = GoalPlanOverviewLogic.monthTicks(
                goalStart: goal.startDate,
                goalEnd: goal.endDate,
                width: plotWidth
            )
            VStack(spacing: 0) {
                axis(plotWidth: plotWidth, ticks: ticks)

                if workstreams.isEmpty {
                    Text("添加推进项后，这里会显示各项在目标周期中的位置。")
                        .font(.system(size: 12))
                        .foregroundStyle(CMTheme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: emptyHeight, alignment: .leading)
                } else {
                    ForEach(workstreams) { item in
                        workstreamRow(item, plotWidth: plotWidth)
                    }
                }

                ForEach(milestones.sorted(by: { $0.date < $1.date })) { milestone in
                    milestoneRow(milestone, plotWidth: plotWidth)
                }
            }
            .frame(width: geometry.size.width, height: chartHeight, alignment: .topLeading)
            .background(alignment: .topLeading) {
                Path { path in
                    for tick in ticks.dropFirst() {
                        let x = labelWidth + columnSpacing + plotWidth * dayPosition(tick)
                        path.move(to: CGPoint(x: x, y: axisHeight))
                        path.addLine(to: CGPoint(x: x, y: chartHeight))
                    }
                }
                .stroke(CMTheme.separator.opacity(0.75), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
                .frame(width: geometry.size.width, height: chartHeight)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if today >= goal.startDate && today <= goal.endDate {
                    Rectangle()
                        .fill(CMTheme.color(for: "clay").opacity(0.75))
                        .frame(width: 1.5, height: chartHeight - axisHeight)
                        .offset(x: labelWidth + columnSpacing + plotWidth * todayPosition, y: axisHeight)
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel("今天")
                        .accessibilityIdentifier("goal-plan-today")
                }
            }
            .overlay(alignment: .topLeading) {
                if let hoveredWorkstreamID,
                   let row = workstreams.firstIndex(where: { $0.id == hoveredWorkstreamID }) {
                    let item = workstreams[row]
                    let span = GoalPlanOverviewLogic.span(
                        from: item.startDate,
                        to: item.endDate,
                        goalStart: goal.startDate,
                        goalEnd: goal.endDate
                    )
                    let tooltipWidth = min(plotWidth, 320)
                    let centerX = plotWidth * (span.start + span.width / 2)
                    let tooltipX = max(0, min(plotWidth - tooltipWidth, centerX - tooltipWidth / 2))

                    hoverLabel("\(item.title)：\(item.startDate.compactChineseDate) – \(item.endDate.compactChineseDate)")
                        .frame(width: tooltipWidth, alignment: .leading)
                        .offset(
                            x: labelWidth + columnSpacing + tooltipX,
                            y: axisHeight + CGFloat(row) * workstreamHeight - 8
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: chartHeight)
        .padding(16)
        .background(CMTheme.quietFill.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CMTheme.separator, lineWidth: 0.7)
        }
    }

    private func axis(plotWidth: CGFloat, ticks: [Date]) -> some View {
        HStack(spacing: columnSpacing) {
            Text("推进项 / 里程碑")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CMTheme.textTertiary)
                .frame(width: labelWidth, alignment: .leading)

            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { date in
                    let x = dayPosition(date) * plotWidth
                    Text(verbatim: GoalPlanOverviewLogic.monthLabel(for: date))
                        .font(.system(size: 10))
                        .foregroundStyle(CMTheme.textSecondary)
                        .monospacedDigit()
                        .frame(width: GoalPlanOverviewLogic.monthLabelWidth, alignment: .leading)
                        .offset(x: x)
                }
            }
            .frame(width: plotWidth, height: axisHeight, alignment: .topLeading)
        }
        .frame(height: axisHeight)
    }

    private func workstreamRow(_ item: Workstream, plotWidth: CGFloat) -> some View {
        let span = GoalPlanOverviewLogic.span(
            from: item.startDate,
            to: item.endDate,
            goalStart: goal.startDate,
            goalEnd: goal.endDate
        )
        let barX = plotWidth * span.start
        let barWidth = max(1, plotWidth * span.width)
        let hitWidth = min(plotWidth, max(28, barWidth))
        let hitX = max(0, min(plotWidth - hitWidth, barX - (hitWidth - barWidth) / 2))
        let isCurrent = focus.current.contains { $0.id == item.id }
        let days = TimelineMath.inclusiveDayCount(from: item.startDate, to: item.endDate)

        return HStack(spacing: columnSpacing) {
            Button { onSelectWorkstream(item) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(CMTheme.textPrimary)
                        .lineLimit(1)
                    Text("\(shortDate(item.startDate)) – \(shortDate(item.endDate)) · \(days) 天")
                        .font(.system(size: 10))
                        .foregroundStyle(CMTheme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(width: labelWidth, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CMTheme.separator.opacity(0.65))
                    .frame(width: plotWidth, height: 4)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(CMTheme.color(for: "denim").opacity(isCurrent ? 0.9 : 0.6))
                    .frame(width: barWidth, height: 14)
                    .offset(x: barX)
                Button { onSelectWorkstream(item) } label: {
                    Color.clear
                        .frame(width: hitWidth, height: workstreamHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: hitX)
                .accessibilityLabel("\(item.title)，\(item.startDate.compactChineseDate) 至 \(item.endDate.compactChineseDate)，\(days) 天")
                .accessibilityIdentifier("goal-plan-workstream-\(item.id.uuidString)")
                .onHover { isHovered in
                    if isHovered {
                        hoveredWorkstreamID = item.id
                    } else if hoveredWorkstreamID == item.id {
                        hoveredWorkstreamID = nil
                    }
                }
            }
            .frame(width: plotWidth, height: workstreamHeight)
        }
        .frame(height: workstreamHeight)
        .background(isCurrent ? CMTheme.color(for: "denim").opacity(0.055) : Color.clear)
        .overlay(alignment: .bottom) { QuietDivider() }
    }

    private func milestoneRow(_ milestone: Milestone, plotWidth: CGFloat) -> some View {
        let x = plotWidth * dayPosition(milestone.date)
        let hitWidth: CGFloat = min(plotWidth, 28)
        let hitX = max(0, min(plotWidth - hitWidth, x - hitWidth / 2))

        return HStack(spacing: columnSpacing) {
            Button { onSelectMilestone(milestone) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(CMTheme.color(for: "ochre"))
                    Text(milestone.title)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(shortDate(milestone.date))
                        .foregroundStyle(CMTheme.textSecondary)
                }
                .font(.system(size: 10))
                .frame(width: labelWidth, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CMTheme.separator.opacity(0.45))
                    .frame(width: plotWidth, height: 2)
                Image(systemName: "diamond.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(CMTheme.color(for: "ochre"))
                    .offset(x: x - 5)
                Button { onSelectMilestone(milestone) } label: {
                    Color.clear
                        .frame(width: hitWidth, height: milestoneHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: hitX)
                .accessibilityLabel("里程碑：\(milestone.title)，\(milestone.date.compactChineseDate)")
                .help("编辑里程碑：\(milestone.title)")
            }
            .frame(width: plotWidth, height: milestoneHeight)
        }
        .frame(height: milestoneHeight)
        .overlay(alignment: .bottom) { QuietDivider() }
    }

    private var todayPosition: CGFloat {
        CGFloat(elapsedFraction)
    }

    private func dayPosition(_ date: Date) -> CGFloat {
        CGFloat(GoalPlanOverviewLogic.span(
            from: date,
            to: date,
            goalStart: goal.startDate,
            goalEnd: goal.endDate
        ).start)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
    }

    private func hoverLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(CMTheme.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(CMTheme.cardSurface, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CMTheme.separator, lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
    }
}
