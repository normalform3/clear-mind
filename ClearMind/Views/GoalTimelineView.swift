import SwiftUI

struct GoalTimelineView: View {
    let goal: Goal
    let workstreams: [Workstream]
    let milestones: [Milestone]
    let zoom: TimelineZoom
    let onSelectWorkstream: (Workstream) -> Void
    let onSelectMilestone: (Milestone) -> Void

    private let axisWidth: CGFloat = 98
    private let laneWidth: CGFloat = 178
    private let headerHeight: CGFloat = 48

    private var dayCount: Int {
        TimelineMath.inclusiveDayCount(from: goal.startDate, to: goal.endDate)
    }

    private var timelineHeight: CGFloat {
        max(430, headerHeight + CGFloat(dayCount) * zoom.pointsPerDay + 24)
    }

    private var todayOffset: Int? {
        let today = Date.now.startOfDay
        guard today >= goal.startDate, today <= goal.endDate else { return nil }
        return TimelineMath.dayOffset(from: goal.startDate, to: today)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    TimelineAxis(
                        startDate: goal.startDate,
                        endDate: goal.endDate,
                        zoom: zoom,
                        headerHeight: headerHeight,
                        height: timelineHeight,
                        anchorOffset: todayOffset
                    )
                    .frame(width: axisWidth, height: timelineHeight)

                    Rectangle()
                        .fill(CMTheme.separator)
                        .frame(width: 0.7, height: timelineHeight)

                    ScrollView(.horizontal) {
                        TimelineLanes(
                            goal: goal,
                            workstreams: workstreams,
                            milestones: milestones,
                            zoom: zoom,
                            laneWidth: laneWidth,
                            headerHeight: headerHeight,
                            height: timelineHeight,
                            onSelectWorkstream: onSelectWorkstream,
                            onSelectMilestone: onSelectMilestone
                        )
                        .frame(
                            width: max(540, CGFloat(max(1, workstreams.count)) * laneWidth),
                            height: timelineHeight,
                            alignment: .topLeading
                        )
                    }
                    .scrollIndicators(.visible)
                }
            }
            .scrollIndicators(.visible)
            .background(CMTheme.quietFill.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CMTheme.separator, lineWidth: 0.7)
            }
            .onAppear { centerToday(using: proxy) }
            .onChange(of: zoom) { _, _ in
                Task { @MainActor in centerToday(using: proxy) }
            }
        }
    }

    private func centerToday(using proxy: ScrollViewProxy) {
        if todayOffset != nil {
            proxy.scrollTo("timeline-today", anchor: .center)
        }
    }
}

private struct TimelineAxis: View {
    let startDate: Date
    let endDate: Date
    let zoom: TimelineZoom
    let headerHeight: CGFloat
    let height: CGFloat
    let anchorOffset: Int?

    private var ticks: [Date] {
        let calendar = Calendar.current
        switch zoom {
        case .day:
            return strideDates(every: 1, component: .day)
        case .week:
            return strideDates(every: 7, component: .day)
        case .month:
            var dates: [Date] = [startDate]
            var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate)) ?? startDate
            if cursor < startDate {
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? endDate
            }
            while cursor <= endDate {
                dates.append(cursor)
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? endDate.addingTimeInterval(1)
            }
            return Array(Set(dates.map { $0.startOfDay })).sorted()
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("日期")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CMTheme.textTertiary)
                .padding(.leading, 14)
                .offset(y: 17)

            ForEach(ticks, id: \.self) { date in
                Text(label(for: date))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CMTheme.textSecondary)
                    .padding(.leading, 14)
                    .offset(y: headerHeight + CGFloat(TimelineMath.dayOffset(from: startDate, to: date)) * zoom.pointsPerDay - 6)
            }

            if let anchorOffset {
                Color.clear
                    .frame(width: 1, height: 1)
                    .offset(y: headerHeight + CGFloat(anchorOffset) * zoom.pointsPerDay)
                    .id("timeline-today")
            }
        }
    }

    private func strideDates(every value: Int, component: Calendar.Component) -> [Date] {
        var result: [Date] = []
        var cursor = startDate.startOfDay
        while cursor <= endDate.startOfDay {
            result.append(cursor)
            cursor = Calendar.current.date(byAdding: component, value: value, to: cursor) ?? endDate.addingTimeInterval(1)
        }
        return result
    }

    private func label(for date: Date) -> String {
        switch zoom {
        case .day:
            date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "zh_CN")))
        case .week:
            date.formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "zh_CN")))
        case .month:
            date.formatted(.dateTime.year().month(.abbreviated).locale(Locale(identifier: "zh_CN")))
        }
    }
}

private struct TimelineLanes: View {
    let goal: Goal
    let workstreams: [Workstream]
    let milestones: [Milestone]
    let zoom: TimelineZoom
    let laneWidth: CGFloat
    let headerHeight: CGFloat
    let height: CGFloat
    let onSelectWorkstream: (Workstream) -> Void
    let onSelectMilestone: (Milestone) -> Void

    private var totalWidth: CGFloat {
        max(540, CGFloat(max(1, workstreams.count)) * laneWidth)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            timelineGrid

            if workstreams.isEmpty {
                Text("添加推进项后，它们会在这里按日期并排出现。")
                    .font(.system(size: 13))
                    .foregroundStyle(CMTheme.textTertiary)
                    .padding(.leading, 24)
                    .offset(y: headerHeight + 30)
            }

            ForEach(Array(workstreams.enumerated()), id: \.element.id) { index, item in
                laneHeader(item, index: index)
                workstreamBar(item, index: index)
            }

            ForEach(milestones.sorted(by: { $0.date < $1.date })) { milestone in
                milestoneMarker(milestone)
            }

            todayLine
        }
        .frame(width: totalWidth, height: height, alignment: .topLeading)
        .clipped()
    }

    private var timelineGrid: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(CMTheme.separator)
                .frame(width: totalWidth, height: 0.7)
                .offset(y: headerHeight)

            ForEach(Array(workstreams.indices), id: \.self) { index in
                Rectangle()
                    .fill(CMTheme.separator.opacity(0.48))
                    .frame(width: 0.7, height: height)
                    .offset(x: CGFloat(index + 1) * laneWidth)
            }

            ForEach(gridDates, id: \.self) { date in
                Rectangle()
                    .fill(CMTheme.separator.opacity(0.45))
                    .frame(width: totalWidth, height: 0.5)
                    .offset(y: yPosition(for: date))
            }
        }
    }

    private var gridDates: [Date] {
        let step: Int = switch zoom {
        case .day: 1
        case .week: 7
        case .month: 30
        }
        var values: [Date] = []
        var date = goal.startDate
        while date <= goal.endDate {
            values.append(date)
            date = Calendar.current.date(byAdding: .day, value: step, to: date) ?? goal.endDate.addingTimeInterval(1)
        }
        return values
    }

    private func laneHeader(_ item: Workstream, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            WorkstreamStatusLabel(status: item.status)
        }
        .padding(.horizontal, 12)
        .frame(width: laneWidth, height: headerHeight, alignment: .leading)
        .offset(x: CGFloat(index) * laneWidth)
    }

    private func workstreamBar(_ item: Workstream, index: Int) -> some View {
        let startOffset = TimelineMath.dayOffset(from: goal.startDate, to: item.startDate)
        let duration = TimelineMath.inclusiveDayCount(from: item.startDate, to: item.endDate)
        let barHeight = max(36, CGFloat(duration) * zoom.pointsPerDay - 5)
        let color = CMTheme.statusColor(item.status)

        return Button {
            onSelectWorkstream(item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CMTheme.textPrimary)
                    .lineLimit(2)
                if barHeight > 58 {
                    Text("\(item.startDate.compactChineseDate) – \(item.endDate.compactChineseDate)")
                        .font(.system(size: 9))
                        .foregroundStyle(CMTheme.textSecondary)
                }
            }
            .padding(10)
            .frame(width: laneWidth - 14, height: barHeight, alignment: .topLeading)
            .background(color.opacity(0.11))
            .overlay(alignment: .leading) {
                Rectangle().fill(color).frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .offset(
            x: CGFloat(index) * laneWidth + 7,
            y: headerHeight + CGFloat(startOffset) * zoom.pointsPerDay + 3
        )
    }

    private func milestoneMarker(_ milestone: Milestone) -> some View {
        let y = yPosition(for: milestone.date)
        return Button {
            onSelectMilestone(milestone)
        } label: {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(CMTheme.color(for: "ochre").opacity(0.65))
                    .frame(width: totalWidth, height: 1)
                HStack(spacing: 7) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                    Text(milestone.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .padding(.trailing, 7)
                }
                .foregroundStyle(CMTheme.color(for: "ochre"))
                .padding(.vertical, 4)
                .padding(.leading, 8)
                .background(CMTheme.canvas.opacity(0.92))
            }
        }
        .buttonStyle(.plain)
        .offset(y: y - 11)
    }

    @ViewBuilder
    private var todayLine: some View {
        if Date.now.startOfDay >= goal.startDate, Date.now.startOfDay <= goal.endDate {
            let y = yPosition(for: Date.now)
            HStack(spacing: 6) {
                Circle()
                    .fill(CMTheme.color(for: "clay"))
                    .frame(width: 7, height: 7)
                Rectangle()
                    .fill(CMTheme.color(for: "clay").opacity(0.72))
                    .frame(width: totalWidth, height: 1)
            }
            .offset(x: -3, y: y - 3)
            .allowsHitTesting(false)
        }
    }

    private func yPosition(for date: Date) -> CGFloat {
        headerHeight + CGFloat(TimelineMath.dayOffset(from: goal.startDate, to: date)) * zoom.pointsPerDay
    }
}
