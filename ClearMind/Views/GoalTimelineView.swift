import SwiftUI

struct GoalTimelineView: View {
    let goal: Goal
    let workstreams: [Workstream]
    let milestones: [Milestone]
    let onSelectWorkstream: (Workstream) -> Void
    let onSelectMilestone: (Milestone) -> Void
    let onUpdateWorkstreamRange: (Workstream, Date, Date) -> Void

    private let axisWidth: CGFloat = 88
    private let laneWidth: CGFloat = 112
    private let headerHeight: CGFloat = 44
    private let pointsPerDay: CGFloat = 3.2
    private let bottomPadding: CGFloat = 40

    private var dayCount: Int {
        TimelineMath.inclusiveDayCount(from: goal.startDate, to: goal.endDate)
    }

    private var timelineHeight: CGFloat {
        TimelineMath.contentHeight(
            dayCount: dayCount,
            headerHeight: headerHeight,
            pointsPerDay: pointsPerDay,
            bottomPadding: bottomPadding
        )
    }

    private var viewportHeight: CGFloat {
        TimelineMath.viewportHeight(for: timelineHeight)
    }

    private var todayY: CGFloat? {
        todayOffset.map { headerHeight + CGFloat($0) * pointsPerDay }
    }

    private var scrollContentHeight: CGFloat {
        TimelineMath.scrollContentHeight(
            chartHeight: timelineHeight,
            viewportHeight: viewportHeight,
            todayY: todayY
        )
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
                        pointsPerDay: pointsPerDay,
                        headerHeight: headerHeight,
                        height: timelineHeight,
                        anchorOffset: todayOffset
                    )
                    .frame(width: axisWidth, height: timelineHeight, alignment: .topLeading)

                    Rectangle()
                        .fill(CMTheme.separator)
                        .frame(width: 0.7, height: timelineHeight)

                    ScrollView(.horizontal) {
                        TimelineLanes(
                            goal: goal,
                            workstreams: workstreams,
                            milestones: milestones,
                            pointsPerDay: pointsPerDay,
                            laneWidth: laneWidth,
                            headerHeight: headerHeight,
                            height: timelineHeight,
                            onSelectWorkstream: onSelectWorkstream,
                            onSelectMilestone: onSelectMilestone,
                            onUpdateWorkstreamRange: onUpdateWorkstreamRange
                        )
                        .frame(
                            width: max(540, CGFloat(max(1, workstreams.count)) * laneWidth),
                            height: timelineHeight,
                            alignment: .topLeading
                        )
                    }
                    .scrollIndicators(.visible)
                }
                .frame(height: scrollContentHeight, alignment: .top)
            }
            .frame(height: viewportHeight)
            .scrollIndicators(.visible)
            .background(CMTheme.quietFill.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CMTheme.separator, lineWidth: 0.7)
            }
            .onAppear { alignTodayToTop(using: proxy) }
        }
    }

    private func alignTodayToTop(using proxy: ScrollViewProxy) {
        if todayOffset != nil && timelineHeight > viewportHeight {
            proxy.scrollTo("timeline-today", anchor: .top)
        }
    }
}

private struct WorkstreamResizePreview {
    let session: WorkstreamResizeSession
    let range: WorkstreamDateRange

    var workstreamID: UUID { session.workstreamID }
    var edge: TimelineResizeEdge { session.edge }
}

private struct TimelineAxis: View {
    let startDate: Date
    let endDate: Date
    let pointsPerDay: CGFloat
    let headerHeight: CGFloat
    let height: CGFloat
    let anchorOffset: Int?

    private var ticks: [Date] {
        TimelineMath.monthLabelTicks(from: startDate, to: endDate)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("月份")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CMTheme.textTertiary)
                .padding(.leading, 12)
                .offset(y: 15)

            ForEach(ticks, id: \.self) { date in
                Text(date.formatted(.dateTime.year().month(.abbreviated).locale(Locale(identifier: "zh_CN"))))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CMTheme.textSecondary)
                    .padding(.leading, 12)
                    .offset(y: headerHeight + CGFloat(TimelineMath.dayOffset(from: startDate, to: date)) * pointsPerDay - 6)
            }

            if let anchorOffset {
                Color.clear
                    .frame(width: 1, height: 1)
                    .offset(y: headerHeight + CGFloat(anchorOffset) * pointsPerDay)
                    .id("timeline-today")
            }
        }
    }
}

private struct TimelineLanes: View {
    private static let coordinateSpaceName = "goal-timeline-lanes"

    let goal: Goal
    let workstreams: [Workstream]
    let milestones: [Milestone]
    let pointsPerDay: CGFloat
    let laneWidth: CGFloat
    let headerHeight: CGFloat
    let height: CGFloat
    let onSelectWorkstream: (Workstream) -> Void
    let onSelectMilestone: (Milestone) -> Void
    let onUpdateWorkstreamRange: (Workstream, Date, Date) -> Void

    @GestureState private var resizePreview: WorkstreamResizePreview?

    private var totalWidth: CGFloat {
        max(540, CGFloat(max(1, workstreams.count)) * laneWidth)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            timelineGrid

            if workstreams.isEmpty {
                Text("添加推进项后，它们会在这里按月份并排出现。")
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
        .coordinateSpace(name: Self.coordinateSpaceName)
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

            ForEach(TimelineMath.monthTicks(from: goal.startDate, to: goal.endDate), id: \.self) { date in
                Rectangle()
                    .fill(CMTheme.separator.opacity(0.45))
                    .frame(width: totalWidth, height: 0.5)
                    .offset(y: yPosition(for: date))
            }
        }
    }

    private func laneHeader(_ item: Workstream, index: Int) -> some View {
        Text(item.title)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(2)
            .padding(.horizontal, 10)
            .frame(width: laneWidth, height: headerHeight, alignment: .leading)
            .offset(x: CGFloat(index) * laneWidth)
    }

    private func workstreamBar(_ item: Workstream, index: Int) -> some View {
        let range = displayedRange(for: item)
        let startOffset = TimelineMath.dayOffset(from: goal.startDate, to: range.startDate)
        let duration = TimelineMath.inclusiveDayCount(from: range.startDate, to: range.endDate)
        let barY = headerHeight + CGFloat(startOffset) * pointsPerDay + 3
        let barHeight = TimelineMath.workstreamBarHeight(
            durationDays: duration,
            availableHeight: height - barY,
            pointsPerDay: pointsPerDay
        )
        let color = CMTheme.color(for: "denim")

        return ZStack {
            Button {
                onSelectWorkstream(item)
            } label: {
                Group {
                    if barHeight >= 30 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CMTheme.textPrimary)
                                .lineLimit(2)
                            if barHeight > 58 {
                                Text("\(range.startDate.compactChineseDate) – \(range.endDate.compactChineseDate)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(CMTheme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(9)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: laneWidth - 12, height: barHeight, alignment: .topLeading)
                .background(color.opacity(0.11))
                .overlay(alignment: .leading) {
                    Rectangle().fill(color).frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.title)，\(range.startDate.compactChineseDate) 至 \(range.endDate.compactChineseDate)")

            VStack(spacing: 0) {
                resizeHandle(item, edge: .start, date: range.startDate, color: color)
                Spacer(minLength: 0)
                resizeHandle(item, edge: .end, date: range.endDate, color: color)
            }
            .frame(width: laneWidth - 12, height: barHeight)

            if let resizePreview, resizePreview.workstreamID == item.id {
                let date = resizePreview.edge == .start
                    ? resizePreview.range.startDate
                    : resizePreview.range.endDate
                Text(date.compactChineseDate)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CMTheme.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(CMTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(CMTheme.separator, lineWidth: 0.7)
                    }
                    .allowsHitTesting(false)
            }
        }
        .frame(width: laneWidth - 12, height: barHeight)
        .offset(
            x: CGFloat(index) * laneWidth + 6,
            y: barY
        )
        .zIndex(2)
    }

    private func displayedRange(for item: Workstream) -> WorkstreamDateRange {
        if let resizePreview, resizePreview.workstreamID == item.id {
            return resizePreview.range
        }
        return WorkstreamDateRange(startDate: item.startDate, endDate: item.endDate)
    }

    private func resizeHandle(
        _ item: Workstream,
        edge: TimelineResizeEdge,
        date: Date,
        color: Color
    ) -> some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(color.opacity(0.92))
                .frame(width: 28, height: 3)
        }
        .frame(height: 14)
        .contentShape(Rectangle())
        .highPriorityGesture(resizeGesture(for: item, edge: edge))
        .accessibilityElement()
        .accessibilityLabel(edge == .start ? "调整开始日期" : "调整结束日期")
        .accessibilityValue(date.compactChineseDate)
        .accessibilityHint("上下拖动，或使用辅助功能增减一天")
        .accessibilityAdjustableAction { direction in
            let translation: CGFloat
            switch direction {
            case .increment: translation = pointsPerDay
            case .decrement: translation = -pointsPerDay
            @unknown default: return
            }
            commitResize(
                item,
                range: resizedRange(for: item, edge: edge, verticalTranslation: translation)
            )
        }
        .accessibilityIdentifier("timeline-\(item.id.uuidString)-\(edge == .start ? "start" : "end")-handle")
        .help(edge == .start ? "拖动调整开始日期" : "拖动调整结束日期")
    }

    private func resizeGesture(for item: Workstream, edge: TimelineResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpaceName))
            .updating($resizePreview) { value, preview, transaction in
                let session = preview?.session ?? WorkstreamResizeSession(
                    workstreamID: item.id,
                    edge: edge,
                    originalRange: WorkstreamDateRange(
                        startDate: item.startDate,
                        endDate: item.endDate
                    ),
                    startPointerY: value.startLocation.y
                )
                transaction.disablesAnimations = true
                preview = WorkstreamResizePreview(
                    session: session,
                    range: previewRange(for: session, pointerY: value.location.y)
                )
            }
            .onEnded { value in
                let session = WorkstreamResizeSession(
                    workstreamID: item.id,
                    edge: edge,
                    originalRange: WorkstreamDateRange(
                        startDate: item.startDate,
                        endDate: item.endDate
                    ),
                    startPointerY: value.startLocation.y
                )
                commitResize(item, range: previewRange(for: session, pointerY: value.location.y))
            }
    }

    private func previewRange(
        for session: WorkstreamResizeSession,
        pointerY: CGFloat
    ) -> WorkstreamDateRange {
        session.previewRange(
            pointerY: pointerY,
            pointsPerDay: pointsPerDay,
            goalStartDate: goal.startDate,
            goalEndDate: goal.endDate
        )
    }

    private func resizedRange(
        for item: Workstream,
        edge: TimelineResizeEdge,
        verticalTranslation: CGFloat
    ) -> WorkstreamDateRange {
        WorkstreamTimelineLogic.resizedRange(
            startDate: item.startDate,
            endDate: item.endDate,
            edge: edge,
            verticalTranslation: verticalTranslation,
            pointsPerDay: pointsPerDay,
            goalStartDate: goal.startDate,
            goalEndDate: goal.endDate
        )
    }

    private func commitResize(_ item: Workstream, range: WorkstreamDateRange) {
        guard range.startDate != item.startDate || range.endDate != item.endDate else { return }
        onUpdateWorkstreamRange(item, range.startDate, range.endDate)
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
        headerHeight + CGFloat(TimelineMath.dayOffset(from: goal.startDate, to: date)) * pointsPerDay
    }
}
