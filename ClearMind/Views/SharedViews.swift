import SwiftUI

struct PageContainer<Content: View>: View {
    @Environment(\.cmPalette) private var palette
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .frame(maxWidth: CMTheme.pageMaxWidth, alignment: .leading)
                    .padding(.horizontal, geometry.size.width < 800 ? 24 : CMTheme.pagePadding)
                    .padding(.top, 40)
                    .padding(.bottom, 64)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(palette.canvas)
    }
}

struct PageHeader: View {
    @Environment(\.cmPalette) private var palette
    let eyebrow: String?
    let title: String

    init(_ title: String, eyebrow: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
            }

            Text(title)
                .font(.system(size: 30, weight: .medium, design: .serif))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.bottom, 8)
    }
}

struct SectionHeading: View {
    @Environment(\.cmPalette) private var palette
    let title: String
    let trailingText: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(_ title: String, trailingText: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.trailingText = trailingText
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))

            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }
}

struct BrushHighlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.34))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2),
            control1: CGPoint(x: rect.width * 0.24, y: rect.minY + rect.height * 0.06),
            control2: CGPoint(x: rect.width * 0.72, y: rect.minY + rect.height * 0.36)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.03, y: rect.maxY - rect.height * 0.18),
            control1: CGPoint(x: rect.maxX + rect.width * 0.02, y: rect.height * 0.44),
            control2: CGPoint(x: rect.maxX - rect.width * 0.01, y: rect.height * 0.7)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.maxY - rect.height * 0.04),
            control1: CGPoint(x: rect.width * 0.7, y: rect.maxY),
            control2: CGPoint(x: rect.width * 0.26, y: rect.maxY - rect.height * 0.13)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.34),
            control1: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.height * 0.78),
            control2: CGPoint(x: rect.minX + rect.width * 0.01, y: rect.height * 0.52)
        )
        path.closeSubpath()
        return path
    }
}

struct DashboardModuleHeading<Trailing: View>: View {
    let title: String
    let colorKey: String
    let accessibilityIdentifier: String
    @ViewBuilder let trailing: Trailing

    init(
        _ title: String,
        colorKey: String,
        accessibilityIdentifier: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.colorKey = colorKey
        self.accessibilityIdentifier = accessibilityIdentifier
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            DashboardModuleTitle(title, colorKey: colorKey, accessibilityIdentifier: accessibilityIdentifier)

            Spacer()
            trailing
        }
    }
}

struct DashboardModuleTitle: View {
    @Environment(\.cmPalette) private var palette
    let title: String
    let colorKey: String
    let accessibilityIdentifier: String

    init(_ title: String, colorKey: String, accessibilityIdentifier: String) {
        self.title = title
        self.colorKey = colorKey
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        Text(title)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                BrushHighlightShape()
                    .fill(palette.color(for: colorKey).opacity(0.16))
                    .padding(.horizontal, -7)
                    .padding(.vertical, -1)
                    .offset(y: 2)
            }
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct HoverIconButton: View {
    @Environment(\.cmPalette) private var palette
    @State private var isHovered = false

    let systemName: String
    let helpText: String
    let tint: Color
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isHovered ? tint : palette.textSecondary)
            .background(
                (isHovered ? tint.opacity(0.11) : Color.clear),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 0.7)
                }
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
            .accessibilityLabel(helpText)
            .accessibilityIdentifier(accessibilityIdentifier)

            if isHovered {
                Text(helpText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(palette.cardSurface, in: RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(palette.separator, lineWidth: 0.7)
                    }
                    .offset(y: 35)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("\(accessibilityIdentifier)-hover")
            }
        }
        .frame(width: 30, height: 30)
        .zIndex(isHovered ? 2 : 0)
    }
}

struct IslandSection<Content: View>: View {
    @Environment(\.cmPalette) private var palette
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.separator, lineWidth: 1)
            }
    }
}

struct DashboardIslandSection<Content: View>: View {
    @Environment(\.cmPalette) private var palette
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.separator, lineWidth: 1)
            }
    }
}

struct QuietDivider: View {
    @Environment(\.cmPalette) private var palette
    var body: some View {
        Rectangle()
            .fill(palette.separator)
            .frame(height: 1)
    }
}

struct EmptyState: View {
    @Environment(\.cmPalette) private var palette
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(_ title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TagPills: View {
    @Environment(\.cmPalette) private var palette
    let tags: [Tag]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(tags.prefix(4)) { tag in
                    Text(tag.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.contentTextColor(for: tag.colorKey))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(palette.color(for: tag.colorKey).opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct GoalProgressCalendar: View {
    @Environment(\.cmPalette) private var palette
    let currentWorkstreams: [Workstream]
    let milestones: [Milestone]
    var referenceDate: Date = .now

    @State private var hoveredDayKey: String?

    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    private var days: [GoalCalendarDay] {
        GoalCalendarLogic.monthDays(
            containing: referenceDate,
            currentWorkstreams: currentWorkstreams,
            milestones: milestones
        )
    }

    private var monthTitle: String {
        referenceDate.formatted(
            .dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))
        )
    }

    private var hoveredDay: GoalCalendarDay? {
        days.first { GoalCalendarLogic.dayKey(for: $0.date) == hoveredDayKey && !$0.milestones.isEmpty }
    }

    private var accessibilitySummary: String {
        let today = referenceDate.formatted(
            .dateTime.month().day().locale(Locale(identifier: "zh_CN"))
        )
        let progress = currentWorkstreams.isEmpty
            ? "今天是\(today)，当前没有推进项"
            : "今天是\(today)，处于\(currentWorkstreams.count)个推进项"
        let visibleMilestones = milestones.filter {
            Calendar.current.isDate($0.date, equalTo: referenceDate, toGranularity: .month)
        }
        guard !visibleMilestones.isEmpty else { return progress }
        let entries = visibleMilestones.sorted { $0.date < $1.date }
            .map { "\($0.date.compactChineseDate) \($0.title)" }
            .joined(separator: "、")
        return "\(progress)，里程碑：\(entries)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                Text(monthTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)

                Spacer(minLength: 8)

                calendarLegend
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(days) { day in
                    calendarCell(day)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let hoveredDay {
                milestoneHoverCard(for: hoveredDay)
                    .frame(maxWidth: 210, alignment: .leading)
                    .offset(y: 30)
                    .allowsHitTesting(false)
                    .zIndex(2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(monthTitle)日历，\(accessibilitySummary)")
        .accessibilityIdentifier("goal-progress-calendar")
    }

    private var calendarLegend: some View {
        HStack(spacing: 9) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(palette.color(for: "denim").opacity(0.16))
                    .frame(width: 12, height: 8)
                Text("推进期")
            }

            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(palette.color(for: "clay"), lineWidth: 1)
                    .frame(width: 12, height: 8)
                Text("今天")
            }
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundStyle(palette.textTertiary)
    }

    private func calendarCell(_ day: GoalCalendarDay) -> some View {
        let dayNumber = Calendar.current.component(.day, from: day.date)
        return VStack(spacing: 1) {
            Text("\(dayNumber)")
                .font(.system(size: 10, weight: day.isToday ? .semibold : (day.isInDisplayedMonth ? .medium : .regular)))
            HStack(spacing: 2) {
                if day.isToday {
                    Text("今")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(palette.contentTextColor(for: "clay"))
                }
                ForEach(day.milestones.prefix(3)) { milestone in
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(palette.contentTextColor(for: milestone.colorKey))
                }
            }
            .frame(height: 8)
        }
        .foregroundStyle(palette.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(day.isCoveredByCurrentWorkstream ? palette.color(for: "denim").opacity(0.15) : Color.clear)
        )
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(palette.color(for: "clay"), lineWidth: 1.2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            let key = GoalCalendarLogic.dayKey(for: day.date)
            if hovering && !day.milestones.isEmpty {
                hoveredDayKey = key
            } else if hoveredDayKey == key {
                hoveredDayKey = nil
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(day.date.compactChineseDate)\(day.isToday ? "，今天" : "")\(day.milestones.isEmpty ? "" : "，里程碑：" + day.milestones.map(\.title).joined(separator: "、"))"
        )
        .accessibilityIdentifier(
            day.milestones.isEmpty
                ? "goal-summary-day-\(GoalCalendarLogic.dayKey(for: day.date))"
                : "goal-summary-milestone-\(GoalCalendarLogic.dayKey(for: day.date))"
        )
    }

    private func milestoneHoverCard(for day: GoalCalendarDay) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.date.compactChineseDate)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            ForEach(day.milestones) { milestone in
                HStack(spacing: 6) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(palette.contentTextColor(for: milestone.colorKey))
                    Text(milestone.title)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardSurface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.separator, lineWidth: 0.7))
        .shadow(color: palette.textPrimary.opacity(0.05), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.date.compactChineseDate)，里程碑：\(day.milestones.map(\.title).joined(separator: "、"))")
        .accessibilityIdentifier("goal-summary-milestone-hover")
    }
}

struct GoalSummaryCard: View {
    @Environment(\.cmPalette) private var palette
    let goal: Goal
    var showsDetails = false
    var showsProgressCalendar = false

    private var currentWorkstreams: [Workstream] {
        WorkstreamTimelineLogic.current(in: goal.workstreams, on: .now)
    }

    private var nextWorkstream: Workstream? {
        WorkstreamTimelineLogic.next(in: goal.workstreams, on: .now)
    }

    private var nextMilestone: Milestone? {
        goal.milestones
            .filter { !$0.isCompleted && $0.date >= Date.now.startOfDay }
            .min { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(goal.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                }

                Text("\(goal.startDate.compactChineseDate) – \(goal.endDate.compactChineseDate)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)

                if showsDetails && !goal.details.trimmed.isEmpty {
                    Text(goal.details)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                        .lineSpacing(3)
                }

                TagPills(tags: goal.tags)
            }

            QuietDivider()

            VStack(alignment: .leading, spacing: 7) {
                Text("当前推进")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)

                if currentWorkstreams.isEmpty {
                    Text("当前没有推进项")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textTertiary)
                } else {
                    ForEach(currentWorkstreams) { workstream in
                        workstreamRow(workstream)
                    }
                }
            }

            if showsProgressCalendar, let nextWorkstream {
                VStack(alignment: .leading, spacing: 7) {
                    Text("下一阶段")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)

                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(palette.color(for: "denim").opacity(0.32))
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(nextWorkstream.title)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                            Text("\(nextWorkstream.startDate.compactChineseDate) – \(nextWorkstream.endDate.compactChineseDate)")
                                .font(.system(size: 10))
                                .foregroundStyle(palette.textTertiary)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "下一阶段，\(nextWorkstream.title)，\(nextWorkstream.startDate.compactChineseDate) 至 \(nextWorkstream.endDate.compactChineseDate)"
                    )
                    .accessibilityIdentifier("next-workstream-\(nextWorkstream.id.uuidString)-summary")
                }
            }

            if showsProgressCalendar {
                QuietDivider()
                GoalProgressCalendar(currentWorkstreams: currentWorkstreams, milestones: goal.milestones)
            }

            if let nextMilestone {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(palette.contentTextColor(for: nextMilestone.colorKey))
                    Text(nextMilestone.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(nextMilestone.date.compactChineseDate)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(palette.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(palette.separator, lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    @ViewBuilder
    private func workstreamRow(_ workstream: Workstream) -> some View {
        if showsProgressCalendar {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(palette.color(for: "denim"))
                        .frame(width: 6, height: 6)
                    Text(workstream.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(remainingText(for: workstream))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.contentTextColor(for: "denim"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(palette.color(for: "denim").opacity(0.09))
                        .clipShape(Capsule())
                        .fixedSize()
                }
                Text("\(workstream.startDate.compactChineseDate) – \(workstream.endDate.compactChineseDate)")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.leading, 14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(workstream.title)，\(workstream.startDate.compactChineseDate) 至 \(workstream.endDate.compactChineseDate)，\(remainingText(for: workstream))"
            )
            .accessibilityIdentifier("current-workstream-\(workstream.id.uuidString)-summary")
        } else {
            HStack(spacing: 8) {
                Circle()
                    .fill(palette.color(for: "denim"))
                    .frame(width: 6, height: 6)
                Text(workstream.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(workstream.startDate.compactChineseDate) – \(workstream.endDate.compactChineseDate)")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize()
            }
        }
    }

    private func remainingText(for workstream: Workstream) -> String {
        let days = GoalCalendarLogic.remainingDays(until: workstream.endDate, from: .now)
        return days == 0 ? "今天结束" : "还剩 \(days) 天"
    }
}

struct SheetHeader: View {
    @Environment(\.cmPalette) private var palette
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .medium, design: .serif))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SheetFooter: View {
    let canSave: Bool
    let saveTitle: String
    let cancel: () -> Void
    let save: () -> Void

    init(canSave: Bool, saveTitle: String = "保存", cancel: @escaping () -> Void, save: @escaping () -> Void) {
        self.canSave = canSave
        self.saveTitle = saveTitle
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        HStack {
            Spacer()
            Button("取消", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button(saveTitle, action: save)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.top, 8)
    }
}

struct MultilineEditor: View {
    @Environment(\.cmPalette) private var palette
    @FocusState private var isFocused: Bool
    let placeholder: String
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(7)
                .background(Color.clear)
        }
        .background(palette.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isFocused ? palette.focus : palette.separator, lineWidth: isFocused ? 1.5 : 1)
        }
    }
}

extension Date {
    var compactChineseDate: String {
        formatted(.dateTime.year().month(.abbreviated).day().locale(Locale(identifier: "zh_CN")))
    }
}
