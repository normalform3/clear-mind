import SwiftData
import SwiftUI

struct GoalsView: View {
    @Environment(\.cmPalette) private var palette
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [Goal]
    @State private var showingNewGoal = false
    @State private var showArchived = false
    @State private var isReordering = false
    @State private var reorderDraft: [UUID] = []
    @State private var reorderErrorMessage: String?

    private var visibleGoals: [Goal] {
        GoalOrderLogic.ordered(goals.filter { !$0.isArchived })
    }

    private var archivedGoals: [Goal] {
        GoalOrderLogic.ordered(goals.filter(\.isArchived))
    }

    private var displayedGoals: [Goal] {
        if showArchived { return archivedGoals }
        guard isReordering else { return visibleGoals }
        let byID = Dictionary(uniqueKeysWithValues: visibleGoals.map { ($0.id, $0) })
        return reorderDraft.compactMap { byID[$0] }
    }

    var body: some View {
        PageContainer {
            VStack(alignment: .leading, spacing: CMTheme.sectionSpacing) {
                HStack(alignment: .bottom) {
                    PageHeader("长期目标")
                    Spacer()
                    if isReordering {
                        Button("取消", action: cancelReordering)
                            .buttonStyle(QuietButtonStyle())
                        Button("完成", action: finishReordering)
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("goal-reorder-finish")
                    } else {
                        if !showArchived && !visibleGoals.isEmpty {
                            Button("排序", action: beginReordering)
                                .buttonStyle(QuietButtonStyle())
                                .accessibilityIdentifier("goal-reorder-start")
                        }
                        Button {
                            showArchived = false
                            showingNewGoal = true
                        } label: {
                            Label("新建目标", systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }

                Toggle("查看已归档", isOn: $showArchived)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .disabled(isReordering)
                    .accessibilityIdentifier("goal-archive-toggle")

                if displayedGoals.isEmpty {
                    IslandSection {
                        EmptyState(
                            showArchived ? "还没有已归档目标" : "还没有进行中的长期目标",
                            message: showArchived
                                ? "归档的长期目标会显示在这里。"
                                : archivedGoals.isEmpty
                                    ? "一个明确的方向就足够开始，不需要一次规划完所有事情。"
                                    : "已归档的目标仍保留在这里，可以随时查看并恢复。",
                            actionTitle: showArchived ? nil : archivedGoals.isEmpty ? "建立第一个目标" : "查看已归档"
                        ) {
                            if archivedGoals.isEmpty { showingNewGoal = true } else { showArchived = true }
                        }
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 380, maximum: 500), spacing: 18)],
                        alignment: .leading,
                        spacing: 18
                    ) {
                        ForEach(displayedGoals) { goal in
                            if isReordering {
                                reorderCard(goal)
                            } else {
                                NavigationLink(value: AppNavigationRoute.goal(goal.id)) {
                                    GoalSummaryCard(goal: goal, showsDetails: true)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("goal-card-\(goal.id.uuidString)")
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewGoal) {
            GoalEditor()
        }
        .alert("无法保存目标顺序", isPresented: Binding(
            get: { reorderErrorMessage != nil },
            set: { if !$0 { reorderErrorMessage = nil } }
        )) {
            Button("好") { reorderErrorMessage = nil }
        } message: {
            Text(reorderErrorMessage ?? "请稍后重试。")
        }
    }

    private func beginReordering() {
        reorderDraft = visibleGoals.map(\.id)
        isReordering = true
    }

    private func cancelReordering() {
        reorderDraft = []
        isReordering = false
    }

    private func finishReordering() {
        do {
            try GoalOrderService.commitActiveDraft(reorderDraft, in: modelContext)
            reorderDraft = []
            isReordering = false
        } catch {
            reorderErrorMessage = error.localizedDescription
        }
    }

    private func moveGoal(_ id: UUID, by offset: Int) {
        guard let source = reorderDraft.firstIndex(of: id) else { return }
        let destination = source + offset
        guard reorderDraft.indices.contains(destination) else { return }
        reorderDraft.swapAt(source, destination)
    }

    private func dropGoal(_ draggedID: UUID, on targetID: UUID) -> Bool {
        let moved = GoalOrderLogic.moving(draggedID, on: targetID, in: reorderDraft)
        guard moved != reorderDraft else { return false }
        reorderDraft = moved
        return true
    }

    private func reorderCard(_ goal: Goal) -> some View {
        let index = reorderDraft.firstIndex(of: goal.id) ?? 0
        return ZStack(alignment: .topTrailing) {
            GoalSummaryCard(goal: goal, showsDetails: true)
            HStack(spacing: 2) {
                Button { moveGoal(goal.id, by: -1) } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(index == 0)
                .help("前移")
                .accessibilityLabel("前移\(goal.title)")

                Button { moveGoal(goal.id, by: 1) } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(index >= reorderDraft.count - 1)
                .help("后移")
                .accessibilityLabel("后移\(goal.title)")

                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(palette.textSecondary)
                    .padding(7)
                    .accessibilityHidden(true)
            }
            .buttonStyle(QuietButtonStyle())
            .padding(8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .draggable(goal.id.uuidString)
        .dropDestination(for: String.self) { values, _ in
            guard let rawID = values.first, let draggedID = UUID(uuidString: rawID) else { return false }
            return dropGoal(draggedID, on: goal.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(goal.title)，排序位置第 \(index + 1) 位")
    }
}

struct GoalDetailView: View {
    @Environment(\.cmPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var goal: Goal
    @State private var showCompletedMilestones = false
    @State private var editingGoal = false
    @State private var showingNewWorkstream = false
    @State private var showingNewMilestone = false
    @State private var editingWorkstream: Workstream?
    @State private var editingMilestone: Milestone?
    @State private var timelineErrorMessage: String?
    @State private var goalActionErrorMessage: String?
    @State private var showingArchiveConfirmation = false
    @State private var isEditingTimeline = false

    private var displayedWorkstreams: [Workstream] {
        goal.workstreams
            .sorted { lhs, rhs in
                lhs.startDate == rhs.startDate ? lhs.endDate < rhs.endDate : lhs.startDate < rhs.startDate
            }
    }

    private var goalDuration: Int {
        TimelineMath.inclusiveDayCount(from: goal.startDate, to: goal.endDate)
    }

    var body: some View {
        PageContainer {
            VStack(alignment: .leading, spacing: 30) {
                goalSummary
                VStack(alignment: .leading, spacing: 12) {
                    planningToolbar
                    QuietDivider()
                    if isEditingTimeline {
                        GoalTimelineView(
                            goal: goal,
                            workstreams: displayedWorkstreams,
                            milestones: goal.milestones.filter { showCompletedMilestones || !$0.isCompleted },
                            allowsRangeEditing: true,
                            onSelectWorkstream: { editingWorkstream = $0 },
                            onSelectMilestone: { editingMilestone = $0 },
                            onUpdateWorkstreamRange: updateWorkstreamRange
                        )
                    } else {
                        GoalPlanOverviewView(
                            goal: goal,
                            workstreams: displayedWorkstreams,
                            milestones: goal.milestones.filter { showCompletedMilestones || !$0.isCompleted },
                            onSelectWorkstream: { editingWorkstream = $0 },
                            onSelectMilestone: { editingMilestone = $0 }
                        )
                    }
                }

                GoalDetailMonthCalendar(
                    goal: goal,
                    milestones: goal.milestones.filter { showCompletedMilestones || !$0.isCompleted },
                    onCreateMilestone: createMilestone,
                    onSelectMilestone: { editingMilestone = $0 }
                )
            }
        }
        .navigationTitle("")
        .sheet(isPresented: $editingGoal) { GoalEditor(goal: goal) }
        .sheet(isPresented: $showingNewWorkstream) { WorkstreamEditor(goal: goal) }
        .sheet(isPresented: $showingNewMilestone) { MilestoneEditor(goal: goal) }
        .sheet(item: $editingWorkstream) { WorkstreamEditor(goal: goal, workstream: $0) }
        .sheet(item: $editingMilestone) { MilestoneEditor(goal: goal, milestone: $0) }
        .alert("归档这个目标？", isPresented: $showingArchiveConfirmation) {
            Button("取消", role: .cancel) {}
            Button("归档目标", role: .destructive, action: archiveGoal)
        } message: {
            Text("归档后可在长期目标页的“查看已归档”中找到并恢复。")
        }
        .alert("无法调整推进时间", isPresented: Binding(
            get: { timelineErrorMessage != nil },
            set: { if !$0 { timelineErrorMessage = nil } }
        )) {
            Button("好") { timelineErrorMessage = nil }
        } message: {
            Text(timelineErrorMessage ?? "请稍后重试，或打开推进项编辑器修改日期。")
        }
        .alert("无法更新目标", isPresented: Binding(
            get: { goalActionErrorMessage != nil },
            set: { if !$0 { goalActionErrorMessage = nil } }
        )) {
            Button("好") { goalActionErrorMessage = nil }
        } message: {
            Text(goalActionErrorMessage ?? "请稍后重试。")
        }
    }

    private var goalSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 24) {
                Text(goal.title)
                    .font(.system(size: 29, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    HoverIconButton(
                        systemName: "pencil",
                        helpText: "编辑目标",
                        tint: palette.color(for: "denim"),
                        accessibilityIdentifier: "goal-edit-button"
                    ) {
                        editingGoal = true
                    }
                    if goal.isArchived {
                        HoverIconButton(
                            systemName: "arrow.uturn.backward",
                            helpText: "恢复目标",
                            tint: palette.color(for: "sage"),
                            accessibilityIdentifier: "goal-restore-button",
                            action: restoreGoal
                        )
                    } else {
                        HoverIconButton(
                            systemName: "archivebox",
                            helpText: "归档目标",
                            tint: palette.color(for: "clay"),
                            accessibilityIdentifier: "goal-archive-button"
                        ) {
                            showingArchiveConfirmation = true
                        }
                    }
                }
            }
            .zIndex(1)

            if goal.isArchived {
                Text("已归档")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityIdentifier("goal-archived-status")
            }

            Text("\(goal.startDate.compactChineseDate) – \(goal.endDate.compactChineseDate) · \(goalDuration) 天")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
                .accessibilityIdentifier("goal-detail-period-summary")

            if !goal.details.trimmed.isEmpty {
                Text(goal.details)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(4)
                    .frame(maxWidth: 650, alignment: .leading)
            }

            TagPills(tags: goal.tags)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goal-detail-summary")
    }

    private var planningToolbar: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("推进计划")
                .font(.system(size: 17, weight: .semibold))

            Button {
                showingNewWorkstream = true
            } label: {
                Label("添加推进项", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                showingNewMilestone = true
            } label: {
                Label("添加里程碑", systemImage: "diamond")
            }
            .buttonStyle(QuietButtonStyle())

            Spacer(minLength: 12)

            Toggle("显示已完成里程碑", isOn: $showCompletedMilestones)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Button(isEditingTimeline ? "完成" : "编辑时间") {
                isEditingTimeline.toggle()
            }
            .buttonStyle(QuietButtonStyle())
            .foregroundStyle(palette.textSecondary)
            .accessibilityIdentifier("timeline-edit-toggle")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goal-plan-toolbar")
    }

    private func archiveGoal() {
        do {
            try GoalOrderService.archive(goal, in: modelContext)
            dismiss()
        } catch {
            goalActionErrorMessage = error.localizedDescription
        }
    }

    private func restoreGoal() {
        do {
            try GoalOrderService.restore(goal, in: modelContext)
            dismiss()
        } catch {
            goalActionErrorMessage = error.localizedDescription
        }
    }

    private func updateWorkstreamRange(_ item: Workstream, startDate: Date, endDate: Date) {
        item.startDate = startDate.startOfDay
        item.endDate = endDate.startOfDay
        item.updatedAt = .now
        goal.updatedAt = .now

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            timelineErrorMessage = "日期没有保存：\(error.localizedDescription)"
        }
    }

    private func createMilestone(on date: Date, title: String, colorKey: String) -> String? {
        do {
            try GoalMilestoneService.create(title: title, on: date, colorKey: colorKey, for: goal, in: modelContext)
            return nil
        } catch {
            return "里程碑没有保存：\(error.localizedDescription)"
        }
    }

}

private struct GoalDetailMonthCalendar: View {
    @Environment(\.cmPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    let goal: Goal
    let milestones: [Milestone]
    let onCreateMilestone: (Date, String, String) -> String?
    let onSelectMilestone: (Milestone) -> Void

    @State private var displayedMonth: Date
    @State private var quickDate: Date?
    @State private var quickTitle = ""
    @State private var quickColorKey = "ochre"
    @State private var quickError: String?
    @State private var hoveredDayKey: String?
    @FocusState private var isQuickTitleFocused: Bool

    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    init(
        goal: Goal,
        milestones: [Milestone],
        onCreateMilestone: @escaping (Date, String, String) -> String?,
        onSelectMilestone: @escaping (Milestone) -> Void
    ) {
        self.goal = goal
        self.milestones = milestones
        self.onCreateMilestone = onCreateMilestone
        self.onSelectMilestone = onSelectMilestone
        _displayedMonth = State(initialValue: GoalCalendarLogic.clampedMonth(
            containing: .now,
            goalStart: goal.startDate,
            goalEnd: goal.endDate
        ))
    }

    private var days: [GoalCalendarDay] {
        GoalCalendarLogic.monthDays(
            containing: displayedMonth,
            currentWorkstreams: goal.workstreams,
            milestones: milestones,
            today: .now
        )
    }

    private var monthTitle: String {
        displayedMonth.formatted(
            .dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))
        )
    }

    var body: some View {
        let monthDays = days
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("月历")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                monthButton(offset: -1, symbol: "chevron.left", label: "上个月")
                Text(monthTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(minWidth: 92)
                    .monospacedDigit()
                monthButton(offset: 1, symbol: "chevron.right", label: "下个月")
            }
            QuietDivider()

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<6, id: \.self) { weekIndex in
                    weekRow(Array(monthDays[(weekIndex * 7)..<((weekIndex + 1) * 7)]))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goal-detail-month-calendar")
        .onChange(of: goal.startDate) { _, _ in clampDisplayedMonth() }
        .onChange(of: goal.endDate) { _, _ in clampDisplayedMonth() }
    }

    private func monthButton(offset: Int, symbol: String, label: String) -> some View {
        let destination = GoalCalendarLogic.movedMonth(
            from: displayedMonth,
            offset: offset,
            goalStart: goal.startDate,
            goalEnd: goal.endDate
        )
        return Button {
            if let destination {
                displayedMonth = destination
                quickDate = nil
            }
        } label: {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(destination == nil ? palette.textTertiary : palette.textSecondary)
        .disabled(destination == nil)
        .accessibilityLabel(label)
        .accessibilityIdentifier(offset < 0 ? "goal-month-previous" : "goal-month-next")
    }

    private func weekRow(_ weekDays: [GoalCalendarDay]) -> some View {
        let bands = GoalCalendarLogic.weekBands(for: weekDays)
        return HStack(spacing: 6) {
            ForEach(Array(weekDays.enumerated()), id: \.element.id) { index, day in
                dayCell(day, overflowCount: bands.overflowCounts[index])
            }
        }
        .frame(height: 94)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                let cellWidth = (geometry.size.width - 36) / 7
                let step = cellWidth + 6
                ForEach(bands.segments) { band in
                    let leadingInset: CGFloat = band.roundedStart ? 7 : 0
                    let trailingInset: CGFloat = band.roundedEnd ? 7 : 0
                    let x = CGFloat(band.startDayIndex) * step + leadingInset
                    let right = CGFloat(band.endDayIndex) * step + cellWidth - trailingInset
                    let startRadius: CGFloat = band.roundedStart ? 4 : 0
                    let endRadius: CGFloat = band.roundedEnd ? 4 : 0
                    UnevenRoundedRectangle(
                        topLeadingRadius: startRadius,
                        bottomLeadingRadius: startRadius,
                        bottomTrailingRadius: endRadius,
                        topTrailingRadius: endRadius
                    )
                    .fill(palette.color(for: band.colorKey).opacity(colorScheme == .dark ? 0.62 : 0.42))
                    .frame(width: max(1, right - x), height: 7)
                    .offset(x: x, y: 66 + CGFloat(band.lane) * 10)
                    .accessibilityElement()
                    .accessibilityLabel(band.title)
                    .accessibilityIdentifier("goal-month-workstream-band-\(band.workstreamID.uuidString)-\(GoalCalendarLogic.dayKey(for: weekDays[0].date))")
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func dayCell(_ day: GoalCalendarDay, overflowCount: Int) -> some View {
        let dayKey = GoalCalendarLogic.dayKey(for: day.date)
        let available = day.isInDisplayedMonth && GoalCalendarLogic.isDateAvailable(
            day.date, goalStart: goal.startDate, goalEnd: goal.endDate
        )
        return ZStack(alignment: .topLeading) {
            Button {
                quickDate = day.date
                quickTitle = ""
                quickColorKey = "ochre"
                quickError = nil
            } label: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.quietFill.opacity(0.35))
                    .overlay {
                        if day.isToday {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(palette.color(for: "clay"), lineWidth: 1)
                        }
                    }
                    .frame(height: 94)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topLeading) {
                        Text("\(Calendar.current.component(.day, from: day.date))")
                            .font(.system(size: 12, weight: day.isToday ? .semibold : .regular))
                            .foregroundStyle(available ? palette.textPrimary : palette.textTertiary.opacity(0.5))
                            .padding(7)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!available)
            .accessibilityLabel(
                "\(day.date.compactChineseDate)"
                    + (day.workstreams.isEmpty ? "" : "，推进项：" + day.workstreams.map(\.title).joined(separator: "、"))
                    + "，添加里程碑"
            )
            .accessibilityIdentifier("goal-month-day-\(dayKey)")
            .popover(isPresented: Binding(
                get: { quickDate == day.date },
                set: { if !$0 { quickDate = nil } }
            ), arrowEdge: .top) {
                quickEntry(for: day.date)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(day.milestones.prefix(2)) { marker in
                    if let milestone = milestones.first(where: { $0.id == marker.id }) {
                        Button {
                            onSelectMilestone(milestone)
                        } label: {
                            Label(marker.title, systemImage: "diamond.fill")
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .foregroundStyle(palette.contentTextColor(for: marker.colorKey))
                                .strikethrough(marker.isCompleted)
                        }
                        .buttonStyle(.plain)
                        .help(marker.title)
                        .accessibilityIdentifier("goal-month-milestone-\(marker.title)")
                    }
                }

                if day.milestones.count > 2 {
                    Menu("+\(day.milestones.count - 2)") {
                        ForEach(Array(day.milestones.dropFirst(2))) { marker in
                            if let milestone = milestones.first(where: { $0.id == marker.id }) {
                                Button(marker.title) { onSelectMilestone(milestone) }
                            }
                        }
                    }
                    .font(.system(size: 10))
                    .menuStyle(.borderlessButton)
                }
            }
            .padding(.horizontal, 7)
            .padding(.top, 27)

            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 7)
                    .accessibilityIdentifier("goal-month-workstream-overflow-\(dayKey)")
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading)
        .onHover { hovering in
            if hovering && !day.workstreams.isEmpty {
                hoveredDayKey = dayKey
            } else if hoveredDayKey == dayKey {
                hoveredDayKey = nil
            }
        }
        .overlay(alignment: .bottom) {
            if hoveredDayKey == dayKey && !day.workstreams.isEmpty {
                workstreamHoverCard(for: day)
                    .frame(width: 210)
                    .offset(y: -90)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(hoveredDayKey == dayKey ? 2 : 0)
    }

    private func workstreamColor(_ workstream: GoalCalendarWorkstream) -> Color {
        palette.color(for: workstream.colorKey)
    }

    private func workstreamHoverCard(for day: GoalCalendarDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.date.compactChineseDate)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            ForEach(day.workstreams) { workstream in
                HStack(alignment: .top, spacing: 7) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(workstreamColor(workstream))
                        .frame(width: 12, height: 5)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workstream.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                        Text("\(workstream.startDate.compactChineseDate) – \(workstream.endDate.compactChineseDate)")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardSurface, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.separator, lineWidth: 0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(day.date.compactChineseDate)，推进项："
                + day.workstreams.map {
                    "\($0.title)，\($0.startDate.compactChineseDate)至\($0.endDate.compactChineseDate)"
                }.joined(separator: "；")
        )
        .accessibilityIdentifier("goal-month-workstreams-hover")
    }

    private func quickEntry(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(date.compactChineseDate) · 新增里程碑")
                .font(.system(size: 13, weight: .semibold))
            TextField("里程碑名称", text: $quickTitle)
                .textFieldStyle(.roundedBorder)
                .focused($isQuickTitleFocused)
                .onSubmit { saveQuickEntry(on: date) }
                .accessibilityIdentifier("goal-milestone-quick-title")
            PaletteColorSelector(selection: $quickColorKey, title: "图标颜色", identifierPrefix: "milestone-color")
            if let quickError {
                Text(quickError)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.contentTextColor(for: "clay"))
            }
            HStack {
                Spacer()
                Button("取消") { quickDate = nil }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { saveQuickEntry(on: date) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(quickTitle.trimmed.isEmpty)
                    .accessibilityIdentifier("goal-milestone-quick-save")
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { isQuickTitleFocused = true }
    }

    private func saveQuickEntry(on date: Date) {
        guard !quickTitle.trimmed.isEmpty else { return }
        if let error = onCreateMilestone(date, quickTitle.trimmed, quickColorKey) {
            quickError = error
        } else {
            quickDate = nil
            quickTitle = ""
            quickError = nil
        }
    }

    private func clampDisplayedMonth() {
        displayedMonth = GoalCalendarLogic.clampedMonth(
            containing: displayedMonth,
            goalStart: goal.startDate,
            goalEnd: goal.endDate
        )
    }
}

struct GoalEditor: View {
    @Environment(\.cmPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let goal: Goal?

    @State private var title: String
    @State private var details: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var tagNames: String
    @State private var errorMessage: String?

    init(goal: Goal? = nil) {
        self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _details = State(initialValue: goal?.details ?? "")
        _startDate = State(initialValue: goal?.startDate ?? .now)
        _endDate = State(initialValue: goal?.endDate ?? Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now)
        _tagNames = State(initialValue: goal?.tags.map(\.name).joined(separator: ", ") ?? "")
    }

    private var keepsExistingItemsInsideRange: Bool {
        guard let goal else { return true }
        let normalizedStart = startDate.startOfDay
        let normalizedEnd = endDate.startOfDay
        return goal.workstreams.allSatisfy { $0.startDate >= normalizedStart && $0.endDate <= normalizedEnd }
            && goal.milestones.allSatisfy { $0.date >= normalizedStart && $0.date <= normalizedEnd }
    }

    private var canSave: Bool {
        !title.trimmed.isEmpty
            && GoalValidator.hasValidRange(startDate: startDate, endDate: endDate)
            && keepsExistingItemsInsideRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: goal == nil ? "新建长期目标" : "编辑长期目标", subtitle: "只写下真正值得持续投入的方向。")
            TextField("目标名称", text: $title)
                .font(.system(size: 17, weight: .medium))
                .calmTextField()
            MultilineEditor(placeholder: "为什么这件事重要？", text: $details)
                .frame(height: 110)
            HStack(spacing: 18) {
                DatePicker("开始", selection: $startDate, displayedComponents: .date)
                DatePicker("结束", selection: $endDate, displayedComponents: .date)
                Spacer()
            }
            TextField("标签，用逗号分隔", text: $tagNames)
                .calmTextField()
            if !GoalValidator.hasValidRange(startDate: startDate, endDate: endDate) {
                Text("结束日期需要晚于或等于开始日期。")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.contentTextColor(for: "clay"))
            }
            if !keepsExistingItemsInsideRange {
                Text("新的目标周期会把已有推进项或里程碑留在范围之外。请先调整这些内容的日期。")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.contentTextColor(for: "clay"))
            }
            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(palette.contentTextColor(for: "clay"))
            }
            SheetFooter(canSave: canSave, cancel: { dismiss() }, save: save)
        }
        .padding(28)
        .frame(width: 620)
        .background(palette.canvas)
    }

    private func save() {
        do {
            let tags = try TagService.resolve(commaSeparatedNames: tagNames, in: modelContext)
            let target = goal ?? Goal(title: title.trimmed, startDate: startDate, endDate: endDate)
            target.title = title.trimmed
            target.details = details.trimmed
            target.startDate = startDate.startOfDay
            target.endDate = endDate.startOfDay
            target.tags = tags
            target.updatedAt = .now
            if goal == nil { try GoalOrderService.insertAtFront(target, in: modelContext) }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

struct WorkstreamEditor: View {
    @Environment(\.cmPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let goal: Goal
    let workstream: Workstream?

    @State private var title: String
    @State private var details: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var colorKey: String
    @State private var extendGoal = false
    @State private var errorMessage: String?

    init(goal: Goal, workstream: Workstream? = nil) {
        self.goal = goal
        self.workstream = workstream
        _title = State(initialValue: workstream?.title ?? "")
        _details = State(initialValue: workstream?.details ?? "")
        _startDate = State(initialValue: workstream?.startDate ?? max(goal.startDate, .now.startOfDay))
        _endDate = State(initialValue: workstream?.endDate ?? min(goal.endDate, Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? goal.endDate))
        _colorKey = State(initialValue: workstream.map {
            WorkstreamColorLogic.resolvedKey(for: $0, among: goal.workstreams)
        } ?? CMTheme.paletteKeys[goal.workstreams.count % CMTheme.paletteKeys.count])
    }

    private var validRange: Bool { GoalValidator.hasValidRange(startDate: startDate, endDate: endDate) }
    private var withinGoal: Bool { GoalValidator.isWithinGoal(startDate: startDate, endDate: endDate, goal: goal) }
    private var canSave: Bool { !title.trimmed.isEmpty && validRange && (withinGoal || extendGoal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: workstream == nil ? "添加推进项" : "编辑推进项", subtitle: "并行的小目标会在时间图中各自占据一条泳道。")
            TextField("推进项名称", text: $title)
                .calmTextField()
            MultilineEditor(placeholder: "补充说明（可选）", text: $details)
                .frame(height: 90)
            HStack(spacing: 18) {
                DatePicker("开始", selection: $startDate, displayedComponents: .date)
                DatePicker("结束", selection: $endDate, displayedComponents: .date)
                Spacer()
            }
            PaletteColorSelector(selection: $colorKey, title: "推进项颜色", identifierPrefix: "workstream-color")
            if validRange && !withinGoal {
                VStack(alignment: .leading, spacing: 8) {
                    Text("这段日期超出了目标周期（\(goal.startDate.compactChineseDate) – \(goal.endDate.compactChineseDate)）。")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.contentTextColor(for: "clay"))
                    Toggle("保存时扩展长期目标的周期", isOn: $extendGoal)
                        .toggleStyle(.checkbox)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(palette.contentTextColor(for: "clay"))
            }

            HStack {
                if let workstream {
                    Button("删除推进项", role: .destructive) {
                        modelContext.delete(workstream)
                        try? modelContext.save()
                        dismiss()
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                Spacer()
                SheetFooter(canSave: canSave, cancel: { dismiss() }, save: save)
            }
        }
        .padding(28)
        .frame(width: 600)
        .background(palette.canvas)
    }

    private func save() {
        do {
            if extendGoal {
                goal.startDate = min(goal.startDate, startDate.startOfDay)
                goal.endDate = max(goal.endDate, endDate.startOfDay)
            }
            let target = workstream ?? Workstream(title: title.trimmed, startDate: startDate, endDate: endDate)
            target.title = title.trimmed
            target.details = details.trimmed
            target.startDate = startDate.startOfDay
            target.endDate = endDate.startOfDay
            target.colorKey = colorKey
            target.updatedAt = .now
            if workstream == nil { goal.workstreams.append(target) }
            goal.updatedAt = .now
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MilestoneEditor: View {
    @Environment(\.cmPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let goal: Goal
    let milestone: Milestone?

    @State private var title: String
    @State private var details: String
    @State private var date: Date
    @State private var isCompleted: Bool
    @State private var colorKey: String

    init(goal: Goal, milestone: Milestone? = nil) {
        self.goal = goal
        self.milestone = milestone
        _title = State(initialValue: milestone?.title ?? "")
        _details = State(initialValue: milestone?.details ?? "")
        _date = State(initialValue: milestone?.date ?? min(goal.endDate, max(goal.startDate, .now.startOfDay)))
        _isCompleted = State(initialValue: milestone?.isCompleted ?? false)
        _colorKey = State(initialValue: milestone?.colorKey ?? "ochre")
    }

    private var canSave: Bool {
        !title.trimmed.isEmpty && date.startOfDay >= goal.startDate && date.startOfDay <= goal.endDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: milestone == nil ? "添加里程碑" : "编辑里程碑", subtitle: "里程碑是一个明确的日期节点，不占据时间区间。")
            TextField("里程碑名称", text: $title).calmTextField()
            MultilineEditor(placeholder: "补充说明（可选）", text: $details).frame(height: 90)
            PaletteColorSelector(selection: $colorKey, title: "图标颜色", identifierPrefix: "milestone-color")
            HStack {
                DatePicker("日期", selection: $date, in: goal.startDate...goal.endDate, displayedComponents: .date)
                Toggle("已完成", isOn: $isCompleted).toggleStyle(.checkbox)
                Spacer()
            }
            HStack {
                if let milestone {
                    Button("删除里程碑", role: .destructive) {
                        modelContext.delete(milestone)
                        try? modelContext.save()
                        dismiss()
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                Spacer()
                SheetFooter(canSave: canSave, cancel: { dismiss() }, save: save)
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(palette.canvas)
    }

    private func save() {
        let target = milestone ?? Milestone(title: title.trimmed, date: date)
        target.title = title.trimmed
        target.details = details.trimmed
        target.date = date.startOfDay
        target.isCompleted = isCompleted
        target.colorKey = colorKey
        if milestone == nil { goal.milestones.append(target) }
        goal.updatedAt = .now
        try? modelContext.save()
        dismiss()
    }
}

private struct PaletteColorSelector: View {
    @Environment(\.cmPalette) private var palette
    @Binding var selection: String
    let title: String
    let identifierPrefix: String

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            ForEach(CMTheme.paletteKeys, id: \.self) { key in
                Button {
                    selection = key
                } label: {
                    Circle()
                        .fill(palette.color(for: key))
                        .frame(width: 19, height: 19)
                        .overlay {
                            if selection == key {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(palette.contentOnColor(for: key))
                            }
                        }
                        .padding(3)
                        .overlay {
                            Circle()
                                .strokeBorder(selection == key ? palette.textPrimary : .clear, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help(colorName(for: key))
                .accessibilityLabel(colorName(for: key))
                .accessibilityValue(selection == key ? "已选择" : "未选择")
                .accessibilityIdentifier("\(identifierPrefix)-\(key)")
            }
        }
    }

    private func colorName(for key: String) -> String {
        switch key {
        case "sage": "鼠尾草绿"
        case "clay": "陶土红"
        case "denim": "牛仔蓝"
        case "ochre": "赭黄"
        case "plum": "梅紫"
        default: "岩灰"
        }
    }
}
