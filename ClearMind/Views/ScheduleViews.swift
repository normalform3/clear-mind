import SwiftData
import SwiftUI

struct ScheduleSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    @Query(sort: \ScheduleScope.name) private var scopes: [ScheduleScope]
    @AppStorage("selectedScheduleTemplateID") private var selectedTemplateID = ""

    @State private var isEditing = false
    @State private var drafts: [ScheduleBlockDraft] = []
    @State private var rowIssues: [UUID: ScheduleTableValidationIssue] = [:]
    @State private var errorMessage: String?

    private var selectedTemplate: ScheduleTemplate? {
        ScheduleTemplateResolver.canonical(from: templates, selectedID: selectedTemplateID)
    }

    var body: some View {
        DashboardIslandSection {
            VStack(alignment: .leading, spacing: 18) {
                DashboardModuleHeading(
                    "时间表",
                    colorKey: "sage",
                    accessibilityIdentifier: "dashboard-module-heading-schedule"
                ) {
                    HStack(spacing: 8) {
                        if isEditing {
                            Button {
                                drafts.append(ScheduleBlockDraft())
                                rowIssues = [:]
                            } label: {
                                Label("新增一行", systemImage: "plus")
                            }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("schedule-add-row")
                        }

                        if isEditing {
                            Button("取消", action: cancelEditing)
                                .buttonStyle(QuietButtonStyle())
                                .keyboardShortcut(.cancelAction)

                            Button("完成", action: finishEditing)
                                .buttonStyle(PrimaryButtonStyle())
                                .accessibilityIdentifier("schedule-edit-toggle")
                        } else {
                            Button("编辑", action: startEditing)
                                .buttonStyle(QuietButtonStyle())
                                .disabled(selectedTemplate == nil)
                                .accessibilityIdentifier("schedule-edit-toggle")
                        }
                    }
                }

                QuietDivider()

                if let selectedTemplate {
                    if isEditing {
                        scheduleTable(for: selectedTemplate, at: .now)
                    } else {
                        TimelineView(.everyMinute) { context in
                            scheduleTable(
                                for: selectedTemplate,
                                at: UITestFixtureSeeder.dashboardReferenceDate ?? context.date
                            )
                        }
                    }
                } else {
                    EmptyState("正在准备时间表", message: "时间表会保存在这台 Mac 上。")
                }
            }
        }
        .onAppear { ensureSelection() }
        .onChange(of: templates.count) { _, _ in ensureSelection() }
        .onDisappear {
            if isEditing { cancelEditing() }
        }
        .alert("无法完成操作", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    @ViewBuilder
    private func scheduleTable(for template: ScheduleTemplate, at referenceDate: Date) -> some View {
        let blocks = sortedBlocks(in: template)
        let currentBlockID = isEditing
            ? nil
            : DashboardTimeContext.resolve(at: referenceDate, blocks: blocks).currentBlock?.id

        VStack(alignment: .leading, spacing: 0) {
            ScheduleTableHeader(isEditing: isEditing)
            QuietDivider()

            if isEditing {
                if drafts.isEmpty {
                    EmptyState(
                        "还没有安排时间",
                        message: "添加真正想长期保留的时间段，空白本身也可以是计划的一部分。",
                        actionTitle: "新增第一行"
                    ) {
                        drafts.append(ScheduleBlockDraft())
                    }
                } else {
                    ForEach($drafts) { $draft in
                        ScheduleEditingRow(
                            draft: $draft,
                            scopes: scopes,
                            errorMessage: rowIssues[draft.id]?.message,
                            requestDelete: { removeDraft(draft.id) }
                        )
                        QuietDivider()
                    }
                }
            } else if blocks.isEmpty {
                EmptyState(
                    "还没有安排时间",
                    message: "只添加真正想长期保留的时间段，空白本身也是计划的一部分。",
                    actionTitle: "开始编辑"
                ) { startEditing() }
            } else {
                ForEach(blocks) { block in
                    ScheduleBlockRow(
                        block: block,
                        isCurrent: block.id == currentBlockID,
                        saveError: { errorMessage = $0 }
                    )
                    QuietDivider()
                }
            }
        }
    }

    private func sortedBlocks(in template: ScheduleTemplate) -> [ScheduleBlock] {
        template.blocks.sorted { lhs, rhs in
            lhs.startMinute == rhs.startMinute
                ? lhs.endMinute < rhs.endMinute
                : lhs.startMinute < rhs.startMinute
        }
    }

    private func startEditing() {
        guard let selectedTemplate else { return }
        drafts = sortedBlocks(in: selectedTemplate).map(ScheduleBlockDraft.init(block:))
        rowIssues = [:]
        isEditing = true
    }

    private func finishEditing() {
        guard let selectedTemplate else { return }
        do {
            try ScheduleTableWriter.commit(drafts, template: selectedTemplate, in: modelContext)
            drafts = []
            rowIssues = [:]
            isEditing = false
        } catch let failure as ScheduleTableValidationFailure {
            rowIssues = failure.issues
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelEditing() {
        drafts = []
        rowIssues = [:]
        isEditing = false
    }

    private func removeDraft(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        rowIssues[id] = nil
    }

    private func ensureSelection() {
        guard let selectedTemplate else { return }
        if selectedTemplateID != selectedTemplate.id.uuidString {
            selectedTemplateID = selectedTemplate.id.uuidString
        }
    }
}

private enum ScheduleTableMetrics {
    static let timeWidth: CGFloat = 150
    static let scopeWidth: CGFloat = 170
    static let actionWidth: CGFloat = 58
    static let spacing: CGFloat = 20
}

private struct ScheduleTableHeader: View {
    let isEditing: Bool

    var body: some View {
        Grid(horizontalSpacing: ScheduleTableMetrics.spacing) {
            GridRow {
                Text("时间")
                    .frame(width: ScheduleTableMetrics.timeWidth, alignment: .leading)
                Text("归属")
                    .frame(width: ScheduleTableMetrics.scopeWidth, alignment: .leading)
                Text("具体任务")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isEditing ? "操作" : "")
                    .frame(width: ScheduleTableMetrics.actionWidth, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CMTheme.textTertiary)
        }
        .padding(.vertical, 7)
    }
}

private struct ScheduleBlockRow: View {
    @Environment(\.modelContext) private var modelContext
    let block: ScheduleBlock
    let isCurrent: Bool
    let saveError: (String) -> Void

    var body: some View {
        Grid(horizontalSpacing: ScheduleTableMetrics.spacing) {
            GridRow(alignment: .top) {
                Text("\(block.startMinute.clockText) – \(block.endMinute.clockText)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(CMTheme.textPrimary)
                    .frame(width: ScheduleTableMetrics.timeWidth, alignment: .leading)

                Group {
                    if let scope = block.scope {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(CMTheme.color(for: scope.colorKey))
                                .frame(width: 7, height: 7)
                            Text(scope.name).lineLimit(2)
                        }
                    } else {
                        Text("未填写")
                            .foregroundStyle(CMTheme.textTertiary)
                    }
                }
                .font(.system(size: 13))
                .frame(width: ScheduleTableMetrics.scopeWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 9) {
                    let items = block.checklistItems.sorted { $0.sortOrder < $1.sortOrder }
                    if items.isEmpty {
                        Text("-")
                            .font(.system(size: 13))
                            .foregroundStyle(CMTheme.textTertiary)
                            .accessibilityIdentifier("schedule-empty-tasks")
                    } else {
                        ForEach(items) { item in
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { item.isCompleted },
                                    set: { value in
                                        item.isCompleted = value
                                        do {
                                            try modelContext.save()
                                        } catch {
                                            saveError(error.localizedDescription)
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.checkbox)

                                Text(item.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(item.isCompleted ? CMTheme.textTertiary : CMTheme.textPrimary)
                                    .strikethrough(item.isCompleted, color: CMTheme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: ScheduleTableMetrics.actionWidth, height: 1)
            }
        }
        .padding(.vertical, CMTheme.rowVerticalPadding)
        .background(isCurrent ? CMTheme.currentScheduleHighlight : Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            isCurrent ? "schedule-current-block" : "schedule-block-\(block.id.uuidString)"
        )
        .accessibilityValue(isCurrent ? "当前安排" : "")
    }
}

private struct ScheduleEditingRow: View {
    private enum Field: Hashable {
        case start
        case end
        case scope
        case task(UUID)
    }

    @Binding var draft: ScheduleBlockDraft
    let scopes: [ScheduleScope]
    let errorMessage: String?
    let requestDelete: () -> Void

    @FocusState private var focusedField: Field?

    private var suggestions: [ScheduleScope] {
        let key = draft.scopeName.normalizedKey
        guard !key.isEmpty else { return [] }
        return Array(scopes.filter { $0.normalizedName.contains(key) }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(horizontalSpacing: ScheduleTableMetrics.spacing) {
                GridRow(alignment: .top) {
                    HStack(spacing: 6) {
                        inlineTextField("09:00", text: $draft.startText, field: .start, identifier: "schedule-start-time")
                        Text("–")
                            .foregroundStyle(CMTheme.textTertiary)
                        inlineTextField("10:00", text: $draft.endText, field: .end, identifier: "schedule-end-time")
                    }
                    .frame(width: ScheduleTableMetrics.timeWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("例如：工作", text: $draft.scopeName)
                            .scheduleInputStyle()
                            .focused($focusedField, equals: .scope)
                            .accessibilityLabel("归属")

                        if focusedField == .scope && !suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(suggestions) { scope in
                                    Button {
                                        draft.scopeName = scope.name
                                        focusedField = nil
                                    } label: {
                                        HStack(spacing: 7) {
                                            Circle()
                                                .fill(CMTheme.color(for: scope.colorKey))
                                                .frame(width: 6, height: 6)
                                            Text(scope.name).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(QuietButtonStyle())
                                }
                            }
                        }
                    }
                    .frame(width: ScheduleTableMetrics.scopeWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach($draft.tasks) { $task in
                            HStack(spacing: 8) {
                                Toggle("", isOn: $task.isCompleted)
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)

                                TextField("增加一项具体任务", text: $task.title)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .focused($focusedField, equals: .task(task.id))
                                    .onSubmit { advanceTask(after: task.id) }
                                    .accessibilityLabel("具体任务")

                                Button {
                                    removeTask(task.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(CMTheme.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .help("删除这项任务")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(CMTheme.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(CMTheme.separator, lineWidth: 0.7)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(role: .destructive, action: requestDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(CMTheme.textTertiary)
                            .frame(width: ScheduleTableMetrics.actionWidth, height: 24, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .help("删除这行")
                }
            }

            if let errorMessage {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle")
                    Text(errorMessage)
                }
                .font(.system(size: 11))
                .foregroundStyle(CMTheme.color(for: "clay"))
                .padding(.leading, 2)
                .accessibilityLabel("时间块错误：\(errorMessage)")
            }
        }
        .padding(.vertical, 12)
    }

    private func inlineTextField(
        _ placeholder: String,
        text: Binding<String>,
        field: Field,
        identifier: String
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .frame(width: 64)
            .background(CMTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(CMTheme.separator, lineWidth: 0.7)
            }
            .focused($focusedField, equals: field)
            .accessibilityIdentifier(identifier)
    }

    private func advanceTask(after id: UUID) {
        guard let index = draft.tasks.firstIndex(where: { $0.id == id }) else { return }
        if draft.tasks[index].title.trimmed.isEmpty {
            if draft.tasks.count > 1 {
                draft.tasks.remove(at: index)
            }
            return
        }

        if index == draft.tasks.count - 1 {
            let newTask = ScheduleTaskDraft()
            draft.tasks.append(newTask)
            focusedField = .task(newTask.id)
        } else {
            focusedField = .task(draft.tasks[index + 1].id)
        }
    }

    private func removeTask(_ id: UUID) {
        draft.tasks.removeAll { $0.id == id }
        if draft.tasks.isEmpty {
            draft.tasks = [ScheduleTaskDraft()]
        }
    }
}

private extension View {
    func scheduleInputStyle() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(CMTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(CMTheme.separator, lineWidth: 0.7)
            }
    }
}
