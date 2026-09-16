import SwiftData
import SwiftUI

struct GoalsView: View {
    @Query(sort: \Goal.updatedAt, order: .reverse) private var goals: [Goal]
    @State private var showingNewGoal = false
    @State private var statusFilter: GoalStatus? = .active

    private var visibleGoals: [Goal] {
        goals.filter { goal in
            !goal.isArchived && (statusFilter == nil || goal.status == statusFilter)
        }
    }

    var body: some View {
        NavigationStack {
            PageContainer {
                VStack(alignment: .leading, spacing: CMTheme.sectionSpacing) {
                    HStack(alignment: .bottom) {
                        PageHeader("长期目标")
                        Spacer()
                        Button {
                            showingNewGoal = true
                        } label: {
                            Label("新建目标", systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    Picker("状态", selection: $statusFilter) {
                        Text("进行中").tag(GoalStatus?.some(.active))
                        Text("已暂停").tag(GoalStatus?.some(.paused))
                        Text("已完成").tag(GoalStatus?.some(.completed))
                        Text("全部").tag(GoalStatus?.none)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                    if visibleGoals.isEmpty {
                        IslandSection {
                            EmptyState(
                                statusFilter == .active ? "还没有正在追求的长期目标" : "这里暂时没有内容",
                                message: "一个明确的方向就足够开始，不需要一次规划完所有事情。",
                                actionTitle: statusFilter == .active ? "建立第一个目标" : nil
                            ) { showingNewGoal = true }
                        }
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 380, maximum: 500), spacing: 18)],
                            alignment: .leading,
                            spacing: 18
                        ) {
                            ForEach(visibleGoals) { goal in
                                NavigationLink {
                                    GoalDetailView(goal: goal)
                                } label: {
                                    GoalSummaryCard(goal: goal, showsDetails: true, showsStatus: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("长期目标")
        }
        .sheet(isPresented: $showingNewGoal) {
            GoalEditor()
        }
    }
}

struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var goal: Goal
    @State private var showCompleted = false
    @State private var zoom: TimelineZoom = .week
    @State private var editingGoal = false
    @State private var showingNewWorkstream = false
    @State private var showingNewMilestone = false
    @State private var editingWorkstream: Workstream?
    @State private var editingMilestone: Milestone?

    private var displayedWorkstreams: [Workstream] {
        goal.workstreams
            .filter { showCompleted || $0.status != .completed }
            .sorted { lhs, rhs in
                lhs.startDate == rhs.startDate ? lhs.endDate < rhs.endDate : lhs.startDate < rhs.startDate
            }
    }

    var body: some View {
        PageContainer {
            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(goal.status.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(CMTheme.textTertiary)
                        Text(goal.title)
                            .font(.system(size: 29, weight: .semibold))
                        if !goal.details.trimmed.isEmpty {
                            Text(goal.details)
                                .font(.system(size: 14))
                                .foregroundStyle(CMTheme.textSecondary)
                                .lineSpacing(4)
                                .frame(maxWidth: 650, alignment: .leading)
                        }
                        TagPills(tags: goal.tags)
                    }
                    Spacer()
                    Menu {
                        Button("编辑目标") { editingGoal = true }
                        Button("归档目标") {
                            goal.isArchived = true
                            try? modelContext.save()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 28, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

                HStack(spacing: 12) {
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

                    Spacer()

                    Toggle("显示已完成", isOn: $showCompleted)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))

                    Picker("精度", selection: $zoom) {
                        ForEach(TimelineZoom.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading("推进时间图", trailingText: "\(goal.startDate.compactChineseDate) – \(goal.endDate.compactChineseDate)")
                    QuietDivider()
                    GoalTimelineView(
                        goal: goal,
                        workstreams: displayedWorkstreams,
                        milestones: goal.milestones.filter { showCompleted || !$0.isCompleted },
                        zoom: zoom,
                        onSelectWorkstream: { editingWorkstream = $0 },
                        onSelectMilestone: { editingMilestone = $0 }
                    )
                    .frame(minHeight: 480)
                }

                goalItemsList
            }
        }
        .navigationTitle(goal.title)
        .sheet(isPresented: $editingGoal) { GoalEditor(goal: goal) }
        .sheet(isPresented: $showingNewWorkstream) { WorkstreamEditor(goal: goal) }
        .sheet(isPresented: $showingNewMilestone) { MilestoneEditor(goal: goal) }
        .sheet(item: $editingWorkstream) { WorkstreamEditor(goal: goal, workstream: $0) }
        .sheet(item: $editingMilestone) { MilestoneEditor(goal: goal, milestone: $0) }
    }

    private var goalItemsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("推进项")
            QuietDivider()
            if displayedWorkstreams.isEmpty {
                EmptyState("还没有推进项", message: "把可以并行推进的小目标放进时间图。", actionTitle: "添加推进项") {
                    showingNewWorkstream = true
                }
            } else {
                ForEach(displayedWorkstreams) { item in
                    Button { editingWorkstream = item } label: {
                        HStack(spacing: 18) {
                            WorkstreamStatusLabel(status: item.status)
                                .frame(width: 78, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .medium))
                                if !item.details.trimmed.isEmpty {
                                    Text(item.details)
                                        .font(.system(size: 12))
                                        .foregroundStyle(CMTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(item.startDate.compactChineseDate) – \(item.endDate.compactChineseDate)")
                                .font(.system(size: 11))
                                .foregroundStyle(CMTheme.textSecondary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    QuietDivider()
                }
            }
        }
    }
}

struct GoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let goal: Goal?

    @State private var title: String
    @State private var details: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var status: GoalStatus
    @State private var tagNames: String
    @State private var errorMessage: String?

    init(goal: Goal? = nil) {
        self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _details = State(initialValue: goal?.details ?? "")
        _startDate = State(initialValue: goal?.startDate ?? .now)
        _endDate = State(initialValue: goal?.endDate ?? Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now)
        _status = State(initialValue: goal?.status ?? .active)
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
            HStack(spacing: 18) {
                Picker("状态", selection: $status) {
                    ForEach(GoalStatus.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 190)
                TextField("标签，用逗号分隔", text: $tagNames)
                    .calmTextField()
            }
            if !GoalValidator.hasValidRange(startDate: startDate, endDate: endDate) {
                Text("结束日期需要晚于或等于开始日期。")
                    .font(.system(size: 12))
                    .foregroundStyle(CMTheme.color(for: "clay"))
            }
            if !keepsExistingItemsInsideRange {
                Text("新的目标周期会把已有推进项或里程碑留在范围之外。请先调整这些内容的日期。")
                    .font(.system(size: 12))
                    .foregroundStyle(CMTheme.color(for: "clay"))
            }
            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(CMTheme.color(for: "clay"))
            }
            SheetFooter(canSave: canSave, cancel: { dismiss() }, save: save)
        }
        .padding(28)
        .frame(width: 620)
        .background(CMTheme.canvas)
    }

    private func save() {
        do {
            let tags = try TagService.resolve(commaSeparatedNames: tagNames, in: modelContext)
            let target = goal ?? Goal(title: title.trimmed, startDate: startDate, endDate: endDate)
            target.title = title.trimmed
            target.details = details.trimmed
            target.startDate = startDate.startOfDay
            target.endDate = endDate.startOfDay
            target.status = status
            target.tags = tags
            target.updatedAt = .now
            if goal == nil { modelContext.insert(target) }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WorkstreamEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let goal: Goal
    let workstream: Workstream?

    @State private var title: String
    @State private var details: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var status: WorkstreamStatus
    @State private var extendGoal = false
    @State private var errorMessage: String?

    init(goal: Goal, workstream: Workstream? = nil) {
        self.goal = goal
        self.workstream = workstream
        _title = State(initialValue: workstream?.title ?? "")
        _details = State(initialValue: workstream?.details ?? "")
        _startDate = State(initialValue: workstream?.startDate ?? max(goal.startDate, .now.startOfDay))
        _endDate = State(initialValue: workstream?.endDate ?? min(goal.endDate, Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? goal.endDate))
        _status = State(initialValue: workstream?.status ?? .planned)
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
            Picker("状态", selection: $status) {
                ForEach(WorkstreamStatus.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 220)

            if validRange && !withinGoal {
                VStack(alignment: .leading, spacing: 8) {
                    Text("这段日期超出了目标周期（\(goal.startDate.compactChineseDate) – \(goal.endDate.compactChineseDate)）。")
                        .font(.system(size: 12))
                        .foregroundStyle(CMTheme.color(for: "clay"))
                    Toggle("保存时扩展长期目标的周期", isOn: $extendGoal)
                        .toggleStyle(.checkbox)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(CMTheme.color(for: "clay"))
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
        .background(CMTheme.canvas)
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
            target.status = status
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let goal: Goal
    let milestone: Milestone?

    @State private var title: String
    @State private var details: String
    @State private var date: Date
    @State private var isCompleted: Bool

    init(goal: Goal, milestone: Milestone? = nil) {
        self.goal = goal
        self.milestone = milestone
        _title = State(initialValue: milestone?.title ?? "")
        _details = State(initialValue: milestone?.details ?? "")
        _date = State(initialValue: milestone?.date ?? min(goal.endDate, max(goal.startDate, .now.startOfDay)))
        _isCompleted = State(initialValue: milestone?.isCompleted ?? false)
    }

    private var canSave: Bool {
        !title.trimmed.isEmpty && date.startOfDay >= goal.startDate && date.startOfDay <= goal.endDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: milestone == nil ? "添加里程碑" : "编辑里程碑", subtitle: "里程碑是一个明确的日期节点，不占据时间区间。")
            TextField("里程碑名称", text: $title).calmTextField()
            MultilineEditor(placeholder: "补充说明（可选）", text: $details).frame(height: 90)
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
        .background(CMTheme.canvas)
    }

    private func save() {
        let target = milestone ?? Milestone(title: title.trimmed, date: date)
        target.title = title.trimmed
        target.details = details.trimmed
        target.date = date.startOfDay
        target.isCompleted = isCompleted
        if milestone == nil { goal.milestones.append(target) }
        goal.updatedAt = .now
        try? modelContext.save()
        dismiss()
    }
}
