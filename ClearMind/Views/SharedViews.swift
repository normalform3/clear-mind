import SwiftUI

struct PageContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: CMTheme.pageMaxWidth, alignment: .leading)
                .padding(.horizontal, CMTheme.pagePadding)
                .padding(.top, 42)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(CMTheme.canvas)
    }
}

struct PageHeader: View {
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
                    .foregroundStyle(CMTheme.textTertiary)
            }

            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .default))
                .foregroundStyle(CMTheme.textPrimary)
        }
        .padding(.bottom, 8)
    }
}

struct SectionHeading: View {
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
                    .foregroundStyle(CMTheme.textSecondary)
            }

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
                    .foregroundStyle(CMTheme.textSecondary)
            }
        }
    }
}

struct IslandSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CMTheme.islandSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CMTheme.separator, lineWidth: 0.7)
            }
    }
}

struct DashboardIslandSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CMTheme.quietFill)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CMTheme.separator, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.055), radius: 8, y: 3)
    }
}

struct QuietDivider: View {
    var body: some View {
        Rectangle()
            .fill(CMTheme.separator)
            .frame(height: 0.7)
    }
}

struct EmptyState: View {
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
                .foregroundStyle(CMTheme.textSecondary)
                .lineSpacing(3)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
                    .foregroundStyle(CMTheme.textPrimary)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TagPills: View {
    let tags: [Tag]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(tags.prefix(4)) { tag in
                    Text(tag.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CMTheme.color(for: tag.colorKey))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(CMTheme.color(for: tag.colorKey).opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct GoalProgressCalendar: View {
    let currentWorkstreams: [Workstream]
    var referenceDate: Date = .now

    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    private var days: [GoalCalendarDay] {
        GoalCalendarLogic.monthDays(
            containing: referenceDate,
            currentWorkstreams: currentWorkstreams
        )
    }

    private var monthTitle: String {
        referenceDate.formatted(
            .dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))
        )
    }

    private var accessibilitySummary: String {
        let today = referenceDate.formatted(
            .dateTime.month().day().locale(Locale(identifier: "zh_CN"))
        )
        if currentWorkstreams.isEmpty {
            return "今天是\(today)，当前没有推进项"
        }
        return "今天是\(today)，处于\(currentWorkstreams.count)个推进项"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                Text(monthTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CMTheme.textSecondary)

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
                        .foregroundStyle(CMTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(days) { day in
                    calendarCell(day)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(monthTitle)日历，\(accessibilitySummary)")
        .accessibilityIdentifier("goal-progress-calendar")
    }

    private var calendarLegend: some View {
        HStack(spacing: 9) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(CMTheme.color(for: "denim").opacity(0.16))
                    .frame(width: 12, height: 8)
                Text("推进期")
            }

            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(CMTheme.color(for: "clay"), lineWidth: 1)
                    .frame(width: 12, height: 8)
                Text("今天")
            }
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundStyle(CMTheme.textTertiary)
    }

    private func calendarCell(_ day: GoalCalendarDay) -> some View {
        let dayNumber = Calendar.current.component(.day, from: day.date)
        return VStack(spacing: 0) {
            Text("\(dayNumber)")
                .font(.system(size: 10, weight: day.isToday ? .semibold : .regular))
            if day.isToday {
                Text("今")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(CMTheme.color(for: "clay"))
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .foregroundStyle(day.isInDisplayedMonth ? CMTheme.textSecondary : CMTheme.textTertiary.opacity(0.42))
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(day.isCoveredByCurrentWorkstream ? CMTheme.color(for: "denim").opacity(0.15) : Color.clear)
        )
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(CMTheme.color(for: "clay"), lineWidth: 1.2)
            }
        }
    }
}

struct GoalSummaryCard: View {
    let goal: Goal
    var showsDetails = false
    var showsProgressCalendar = false

    private var currentWorkstreams: [Workstream] {
        WorkstreamTimelineLogic.current(in: goal.workstreams, on: .now)
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
                        .foregroundStyle(CMTheme.textPrimary)
                        .lineLimit(2)
                }

                Text("\(goal.startDate.compactChineseDate) – \(goal.endDate.compactChineseDate)")
                    .font(.system(size: 11))
                    .foregroundStyle(CMTheme.textSecondary)

                if showsDetails && !goal.details.trimmed.isEmpty {
                    Text(goal.details)
                        .font(.system(size: 13))
                        .foregroundStyle(CMTheme.textSecondary)
                        .lineLimit(2)
                        .lineSpacing(3)
                }

                TagPills(tags: goal.tags)
            }

            QuietDivider()

            VStack(alignment: .leading, spacing: 7) {
                Text("当前推进")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CMTheme.textTertiary)

                if currentWorkstreams.isEmpty {
                    Text("当前没有推进项")
                        .font(.system(size: 12))
                        .foregroundStyle(CMTheme.textTertiary)
                } else {
                    ForEach(currentWorkstreams) { workstream in
                        workstreamRow(workstream)
                    }
                }
            }

            if showsProgressCalendar {
                QuietDivider()
                GoalProgressCalendar(currentWorkstreams: currentWorkstreams)
            }

            if let nextMilestone {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(CMTheme.color(for: "ochre"))
                    Text(nextMilestone.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(nextMilestone.date.compactChineseDate)
                        .font(.system(size: 10))
                        .foregroundStyle(CMTheme.textSecondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(CMTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(CMTheme.separator, lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    @ViewBuilder
    private func workstreamRow(_ workstream: Workstream) -> some View {
        if showsProgressCalendar {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(CMTheme.color(for: "denim"))
                        .frame(width: 6, height: 6)
                    Text(workstream.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(remainingText(for: workstream))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CMTheme.color(for: "denim"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(CMTheme.color(for: "denim").opacity(0.09))
                        .clipShape(Capsule())
                        .fixedSize()
                }
                Text("\(workstream.startDate.compactChineseDate) – \(workstream.endDate.compactChineseDate)")
                    .font(.system(size: 10))
                    .foregroundStyle(CMTheme.textSecondary)
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
                    .fill(CMTheme.color(for: "denim"))
                    .frame(width: 6, height: 6)
                Text(workstream.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(workstream.startDate.compactChineseDate) – \(workstream.endDate.compactChineseDate)")
                    .font(.system(size: 10))
                    .foregroundStyle(CMTheme.textSecondary)
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
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(CMTheme.textSecondary)
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
    let placeholder: String
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(CMTheme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(7)
                .background(Color.clear)
        }
        .background(CMTheme.quietFill.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(CMTheme.separator, lineWidth: 0.7)
        }
    }
}

extension Date {
    var compactChineseDate: String {
        formatted(.dateTime.year().month(.abbreviated).day().locale(Locale(identifier: "zh_CN")))
    }
}
