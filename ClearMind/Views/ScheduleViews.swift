import SwiftData
import SwiftUI

struct ScheduleInlineHitRegion: Equatable {
    let blockID: UUID
    let field: ScheduleInlineField
    let frame: CGRect
}

struct ScheduleOutsideTap: Equatable {
    let blockID: UUID
    let field: ScheduleInlineField
    let sequence: Int
}

struct ScheduleInlineHitRegionKey: PreferenceKey {
    static let defaultValue: [ScheduleInlineHitRegion] = []

    static func reduce(value: inout [ScheduleInlineHitRegion], nextValue: () -> [ScheduleInlineHitRegion]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ScheduleInlineHitRegionModifier: ViewModifier {
    let blockID: UUID
    let field: ScheduleInlineField

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ScheduleInlineHitRegionKey.self,
                    value: [ScheduleInlineHitRegion(
                        blockID: blockID,
                        field: field,
                        frame: geometry.frame(in: .named("dashboard"))
                    )]
                )
            }
        }
    }
}

struct ScheduleSection: View {
    let outsideTap: ScheduleOutsideTap?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    @Query(sort: \ScheduleScope.name) private var scopes: [ScheduleScope]
    @AppStorage("selectedScheduleTemplateID") private var selectedTemplateID = ""

    @State private var isEditing = false
    @State private var drafts: [ScheduleBlockDraft] = []
    @State private var rowIssues: [UUID: ScheduleTableValidationIssue] = [:]
    @State private var errorMessage: String?
    @State private var inlineEdit: ScheduleInlineEdit?

    private var selectedTemplate: ScheduleTemplate? {
        ScheduleTemplateResolver.canonical(from: templates, selectedID: selectedTemplateID)
    }

    var body: some View {
        DashboardIslandSection {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    DashboardModuleTitle(
                        "时间表",
                        colorKey: "sage",
                        accessibilityIdentifier: "dashboard-module-heading-schedule"
                    )
                    .onTapGesture { _ = saveInlineEdit() }

                    Spacer(minLength: 24)

                    HStack(spacing: 8) {
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
        .onChange(of: outsideTap) { _, tap in
            guard let tap,
                  inlineEdit?.blockID == tap.blockID,
                  inlineEdit?.field == tap.field else { return }
            _ = saveInlineEdit()
        }
        .onDisappear {
            if isEditing { cancelEditing() }
            _ = saveInlineEdit()
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
                .onTapGesture { _ = saveInlineEdit() }
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
                Button {
                    drafts.append(ScheduleBlockDraft())
                    rowIssues = [:]
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel("新增一行")
                .accessibilityIdentifier("schedule-add-row")
                .padding(.top, 8)
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
                        inlineEdit: $inlineEdit,
                        beginEdit: { field in beginInlineEdit(block: block, field: field) },
                        commitEdit: { _ = saveInlineEdit() },
                        cancelEdit: { inlineEdit = nil },
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
        guard saveInlineEdit() else { return }
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

    private func beginInlineEdit(block: ScheduleBlock, field: ScheduleInlineField) {
        if inlineEdit?.blockID == block.id && inlineEdit?.field == field { return }
        guard saveInlineEdit() else { return }
        inlineEdit = ScheduleInlineEdit(block: block, field: field)
    }

    @discardableResult
    private func saveInlineEdit() -> Bool {
        guard var edit = inlineEdit else { return true }
        guard let selectedTemplate,
              let block = selectedTemplate.blocks.first(where: { $0.id == edit.blockID }) else {
            edit.errorMessage = ScheduleTableValidationIssue.missingSource.message
            inlineEdit = edit
            return false
        }
        do {
            try edit.save(block: block, template: selectedTemplate, in: modelContext)
            inlineEdit = nil
            return true
        } catch {
            edit.errorMessage = error.localizedDescription
            inlineEdit = edit
            return false
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
    @Environment(\.cmPalette) private var palette
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
            .foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 7)
    }
}

private struct ScheduleBlockRow: View {
    @Environment(\.cmPalette) private var palette
    private enum FocusedField: Hashable {
        case start
        case end
        case scope
        case task(UUID)
        case newTask
    }

    @Environment(\.modelContext) private var modelContext
    @State private var isColorPickerPresented = false
    @FocusState private var focusedField: FocusedField?
    let block: ScheduleBlock
    let isCurrent: Bool
    @Binding var inlineEdit: ScheduleInlineEdit?
    let beginEdit: (ScheduleInlineField) -> Void
    let commitEdit: () -> Void
    let cancelEdit: () -> Void
    let saveError: (String) -> Void

    private var activeField: ScheduleInlineField? {
        inlineEdit?.blockID == block.id ? inlineEdit?.field : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Grid(horizontalSpacing: ScheduleTableMetrics.spacing) {
                GridRow(alignment: .top) {
                    Group {
                        if activeField == .time {
                            HStack(spacing: 4) {
                                timeInput("开始", keyPath: \.startText, focus: .start,
                                          identifier: "schedule-inline-start-\(block.id.uuidString)")
                                Text("–").foregroundStyle(palette.textTertiary)
                                timeInput("结束", keyPath: \.endText, focus: .end,
                                          identifier: "schedule-inline-end-\(block.id.uuidString)")
                            }
                        } else {
                            Button {
                                beginEdit(.time)
                                focusAfterAppearance(.start)
                            } label: {
                                Text("\(block.startMinute.clockText) – \(block.endMinute.clockText)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.textPrimary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("schedule-inline-time-\(block.id.uuidString)")
                        }
                    }
                    .frame(width: ScheduleTableMetrics.timeWidth, alignment: .leading)

                    Group {
                        if let scope = block.scope {
                            HStack(spacing: 7) {
                                Button {
                                    isColorPickerPresented = true
                                } label: {
                                    Circle()
                                        .fill(palette.color(for: scope.colorKey))
                                        .frame(width: 7, height: 7)
                                        .frame(width: 20, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("选择\(scope.name)的颜色")
                                .accessibilityLabel("选择\(scope.name)的颜色")
                                .accessibilityIdentifier("schedule-scope-color-\(block.id.uuidString)")
                                .popover(isPresented: $isColorPickerPresented) {
                                    colorPicker(for: scope)
                                }
                                scopeContent(scope.name)
                            }
                        } else {
                            scopeContent("未填写")
                        }
                    }
                    .font(.system(size: 13))
                    .frame(width: ScheduleTableMetrics.scopeWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: 9) {
                        let items = block.checklistItems.sorted { $0.sortOrder < $1.sortOrder }
                        if items.isEmpty {
                            if activeField == .newTask {
                                TextField("增加一项具体任务", text: taskTextBinding(taskID: nil))
                                    .scheduleInputStyle()
                                    .focused($focusedField, equals: .newTask)
                                    .onSubmit(commitEdit)
                                    .onExitCommand(perform: cancelEdit)
                                    .modifier(ScheduleInlineHitRegionModifier(blockID: block.id, field: .newTask))
                                    .accessibilityIdentifier("schedule-inline-new-task-\(block.id.uuidString)")
                            } else {
                                Button {
                                    beginEdit(.newTask)
                                    focusAfterAppearance(.newTask)
                                } label: {
                                    Text("-")
                                        .font(.system(size: 13))
                                        .foregroundStyle(palette.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("schedule-inline-empty-task-\(block.id.uuidString)")
                            }
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

                                    if activeField == .task(item.id) {
                                        TextField("具体任务", text: taskTextBinding(taskID: item.id))
                                            .scheduleInputStyle()
                                            .focused($focusedField, equals: .task(item.id))
                                            .onSubmit(commitEdit)
                                            .onExitCommand(perform: cancelEdit)
                                            .modifier(ScheduleInlineHitRegionModifier(blockID: block.id, field: .task(item.id)))
                                            .accessibilityIdentifier("schedule-inline-task-input-\(item.title)")
                                    } else {
                                        Button {
                                            beginEdit(.task(item.id))
                                            focusAfterAppearance(.task(item.id))
                                        } label: {
                                            Text(item.title)
                                                .font(.system(size: 13))
                                                .foregroundStyle(item.isCompleted ? palette.textTertiary : palette.textPrimary)
                                                .strikethrough(item.isCompleted, color: palette.textTertiary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("schedule-inline-task-\(item.title)")
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear
                        .frame(width: ScheduleTableMetrics.actionWidth, height: 1)
                }
            }
            if let message = inlineEdit?.blockID == block.id ? inlineEdit?.errorMessage : nil {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.contentTextColor(for: "clay"))
                    .accessibilityIdentifier("schedule-inline-error-\(block.id.uuidString)")
            }
        }
        .padding(.vertical, CMTheme.rowVerticalPadding)
        .background(isCurrent ? palette.currentScheduleHighlight : Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            isCurrent ? "schedule-current-block" : "schedule-block-\(block.id.uuidString)"
        )
        .accessibilityValue(isCurrent ? "当前安排" : "")
        .onChange(of: focusedField) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else { return }
            DispatchQueue.main.async {
                if focusedField == nil, let oldValue, focusMatchesActive(oldValue) {
                    commitEdit()
                    if activeField != nil { focusedField = oldValue }
                }
            }
        }
    }

    @ViewBuilder
    private func scopeContent(_ title: String) -> some View {
        if activeField == .scope {
            TextField("例如：工作", text: inlineTextBinding(\.scopeName))
                .scheduleInputStyle()
                .focused($focusedField, equals: .scope)
                .onSubmit(commitEdit)
                .onExitCommand(perform: cancelEdit)
                .modifier(ScheduleInlineHitRegionModifier(blockID: block.id, field: .scope))
                .accessibilityIdentifier("schedule-inline-scope-input-\(block.id.uuidString)")
        } else {
            Button {
                beginEdit(.scope)
                focusAfterAppearance(.scope)
            } label: {
                Text(title)
                    .lineLimit(2)
                    .foregroundStyle(block.scope == nil ? palette.textTertiary : palette.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("schedule-inline-scope-\(block.id.uuidString)")
        }
    }

    private func timeInput(
        _ label: String,
        keyPath: WritableKeyPath<ScheduleBlockDraft, String>,
        focus: FocusedField,
        identifier: String
    ) -> some View {
        TextField(label, text: inlineTextBinding(keyPath))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .multilineTextAlignment(.center)
            .padding(.vertical, 7)
            .frame(width: 64)
            .background(palette.cardSurface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.separator, lineWidth: 0.7))
            .focused($focusedField, equals: focus)
            .onSubmit(commitEdit)
            .onExitCommand(perform: cancelEdit)
            .modifier(ScheduleInlineHitRegionModifier(blockID: block.id, field: .time))
            .accessibilityIdentifier(identifier)
    }

    private func inlineTextBinding(_ keyPath: WritableKeyPath<ScheduleBlockDraft, String>) -> Binding<String> {
        Binding(
            get: { inlineEdit?.draft[keyPath: keyPath] ?? "" },
            set: { value in
                guard inlineEdit?.blockID == block.id else { return }
                inlineEdit?.draft[keyPath: keyPath] = value
                inlineEdit?.errorMessage = nil
            }
        )
    }

    private func taskTextBinding(taskID: UUID?) -> Binding<String> {
        Binding(
            get: {
                let tasks = inlineEdit?.draft.tasks ?? []
                return taskID.flatMap { id in tasks.first(where: { $0.id == id })?.title }
                    ?? (taskID == nil ? tasks.first?.title ?? "" : "")
            },
            set: { value in
                guard inlineEdit?.blockID == block.id else { return }
                let index = taskID.flatMap { id in inlineEdit?.draft.tasks.firstIndex(where: { $0.id == id }) }
                    ?? (taskID == nil ? 0 : nil)
                guard let index, inlineEdit?.draft.tasks.indices.contains(index) == true else { return }
                inlineEdit?.draft.tasks[index].title = value
                inlineEdit?.errorMessage = nil
            }
        )
    }

    private func focusAfterAppearance(_ field: FocusedField) {
        DispatchQueue.main.async {
            if activeField != nil { focusedField = field }
        }
    }

    private func focusMatchesActive(_ focus: FocusedField) -> Bool {
        switch (focus, activeField) {
        case (.start, .time), (.end, .time), (.scope, .scope), (.newTask, .newTask): true
        case let (.task(id), .task(activeID)): id == activeID
        default: false
        }
    }

    private func colorPicker(for scope: ScheduleScope) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(scope.name)的颜色")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 7) {
                ForEach(CMTheme.paletteKeys, id: \.self) { key in
                    Button {
                        do {
                            try ScopeService.updateColor(of: scope, to: key, in: modelContext)
                            isColorPickerPresented = false
                        } catch {
                            saveError(error.localizedDescription)
                        }
                    } label: {
                        Circle()
                            .fill(palette.color(for: key))
                            .frame(width: 19, height: 19)
                            .overlay {
                                if scope.colorKey == key {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(palette.contentOnColor(for: key))
                                }
                            }
                            .padding(3)
                            .overlay {
                                Circle()
                                    .strokeBorder(scope.colorKey == key ? palette.textPrimary : .clear, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(colorName(for: key))
                    .accessibilityLabel(colorName(for: key))
                    .accessibilityValue(scope.colorKey == key ? "已选择" : "未选择")
                    .accessibilityIdentifier("schedule-scope-color-option-\(key)")
                }
            }
        }
        .padding(12)
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

private struct ScheduleEditingRow: View {
    @Environment(\.cmPalette) private var palette
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
                            .foregroundStyle(palette.textTertiary)
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
                                                .fill(palette.color(for: scope.colorKey))
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
                                        .foregroundStyle(palette.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .help("删除这项任务")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(palette.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(palette.separator, lineWidth: 0.7)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(role: .destructive, action: requestDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(palette.textTertiary)
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
                .foregroundStyle(palette.contentTextColor(for: "clay"))
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
            .background(palette.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(palette.separator, lineWidth: 0.7)
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
        modifier(ScheduleInputStyle())
    }
}

private struct ScheduleInputStyle: ViewModifier {
    @Environment(\.cmPalette) private var palette

    func body(content: Content) -> some View {
        content.textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(palette.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(palette.separator, lineWidth: 0.7)
            }
    }
}
