import SwiftData
import SwiftUI

struct ScheduleSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    @Query(sort: \ScheduleScope.name) private var scopes: [ScheduleScope]
    @AppStorage("selectedScheduleTemplateID") private var selectedTemplateID = ""

    @State private var showingNewTemplate = false
    @State private var renamingTemplate: ScheduleTemplate?
    @State private var templatePendingDeletion: ScheduleTemplate?
    @State private var blockPendingDeletion: ScheduleBlock?
    @State private var activeDraft: ScheduleBlockDraft?
    @State private var draftInsertionIndex: Int?
    @State private var rowErrorMessage: String?
    @State private var errorMessage: String?

    private var selectedTemplate: ScheduleTemplate? {
        templates.first(where: { $0.id.uuidString == selectedTemplateID }) ?? templates.first
    }

    var body: some View {
        IslandSection {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    Text("一天的时间分配")
                        .font(.system(size: 19, weight: .semibold))

                    Spacer()

                    if !templates.isEmpty {
                        Picker("模板", selection: templateSelection) {
                            ForEach(templates) { template in
                                Text(template.name).tag(template.id.uuidString)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 170)
                    }

                    templateMenu

                    Button {
                        guard let selectedTemplate else { return }
                        startNewRow(at: sortedBlocks(in: selectedTemplate).count)
                    } label: {
                        Label("新增一行", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedTemplate == nil)
                    .accessibilityIdentifier("schedule-add-row")
                }

                QuietDivider()

                if let selectedTemplate {
                    scheduleTable(for: selectedTemplate)
                } else {
                    EmptyState("正在准备默认模板", message: "模板会保存在这台 Mac 上。")
                }
            }
        }
        .onAppear { ensureSelection() }
        .onChange(of: templates.count) { _, _ in ensureSelection() }
        .onDisappear {
            if !finishEditing() {
                cancelEditing()
            }
        }
        .sheet(isPresented: $showingNewTemplate) {
            TemplateNameSheet(title: "新建模板", initialName: "") { name in
                let template = ScheduleTemplate(name: name)
                modelContext.insert(template)
                try modelContext.save()
                selectedTemplateID = template.id.uuidString
            }
        }
        .sheet(item: $renamingTemplate) { template in
            TemplateNameSheet(title: "重命名模板", initialName: template.name) { name in
                template.name = name
                template.updatedAt = .now
                try modelContext.save()
            }
        }
        .confirmationDialog(
            "删除“\(templatePendingDeletion?.name ?? "")”？",
            isPresented: Binding(
                get: { templatePendingDeletion != nil },
                set: { if !$0 { templatePendingDeletion = nil } }
            )
        ) {
            Button("删除模板", role: .destructive) {
                if let template = templatePendingDeletion { delete(template) }
            }
            Button("取消", role: .cancel) { templatePendingDeletion = nil }
        } message: {
            Text("这个模板中的时间块和清单也会被删除。")
        }
        .confirmationDialog(
            "删除这个时间块？",
            isPresented: Binding(
                get: { blockPendingDeletion != nil },
                set: { if !$0 { blockPendingDeletion = nil } }
            )
        ) {
            Button("删除时间块", role: .destructive) {
                if let block = blockPendingDeletion { delete(block) }
            }
            Button("取消", role: .cancel) { blockPendingDeletion = nil }
        } message: {
            Text("其中的具体任务也会一起删除。")
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

    private var templateSelection: Binding<String> {
        Binding(
            get: { selectedTemplate?.id.uuidString ?? "" },
            set: { newValue in
                guard finishEditing() else { return }
                selectedTemplateID = newValue
            }
        )
    }

    private var templateMenu: some View {
        Menu {
            Button("新建模板") {
                guard finishEditing() else { return }
                showingNewTemplate = true
            }
            if let selectedTemplate {
                Button("重命名") {
                    guard finishEditing() else { return }
                    renamingTemplate = selectedTemplate
                }
                Button("复制模板") {
                    guard finishEditing() else { return }
                    duplicate(selectedTemplate)
                }
                Divider()
                Button("删除模板", role: .destructive) {
                    guard finishEditing() else { return }
                    templatePendingDeletion = selectedTemplate
                }
                .disabled(templates.count <= 1)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("管理时间表模板")
    }

    @ViewBuilder
    private func scheduleTable(for template: ScheduleTemplate) -> some View {
        let blocks = sortedBlocks(in: template)

        VStack(alignment: .leading, spacing: 0) {
            ScheduleTableHeader()
            QuietDivider()

            if blocks.isEmpty && activeDraft == nil {
                EmptyState(
                    "还没有安排时间",
                    message: "只添加真正想长期保留的时间段，空白本身也是计划的一部分。",
                    actionTitle: "新增第一行"
                ) { startNewRow(at: 0) }
            } else {
                if activeDraft?.sourceBlockID == nil, draftInsertionIndex == 0 {
                    editableRow(anchorBlock: nil)
                    QuietDivider()
                }

                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    if activeDraft?.sourceBlockID == block.id {
                        editableRow(anchorBlock: block)
                    } else {
                        ScheduleBlockRow(
                            block: block,
                            edit: { startEditing(block) },
                            insertAbove: { insertRow(relativeTo: block.id, after: false) },
                            insertBelow: { insertRow(relativeTo: block.id, after: true) },
                            requestDelete: { blockPendingDeletion = block },
                            saveError: { errorMessage = $0 }
                        )
                    }
                    QuietDivider()

                    if activeDraft?.sourceBlockID == nil, draftInsertionIndex == index + 1 {
                        editableRow(anchorBlock: nil)
                        QuietDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editableRow(anchorBlock: ScheduleBlock?) -> some View {
        if activeDraft != nil {
            ScheduleEditingRow(
                draft: Binding(
                    get: { activeDraft ?? ScheduleBlockDraft() },
                    set: { activeDraft = $0 }
                ),
                scopes: scopes,
                errorMessage: rowErrorMessage,
                isNew: activeDraft?.sourceBlockID == nil,
                commit: { _ = finishEditing() },
                cancel: cancelEditing,
                insertAbove: anchorBlock.map { block in
                    { insertRow(relativeTo: block.id, after: false) }
                },
                insertBelow: anchorBlock.map { block in
                    { insertRow(relativeTo: block.id, after: true) }
                },
                requestDelete: anchorBlock.map { block in
                    { blockPendingDeletion = block }
                },
                toggleTask: { id, value in
                    persistTaskToggle(id: id, value: value, in: anchorBlock)
                }
            )
        }
    }

    private func sortedBlocks(in template: ScheduleTemplate) -> [ScheduleBlock] {
        template.blocks.sorted { lhs, rhs in
            lhs.startMinute == rhs.startMinute
                ? lhs.endMinute < rhs.endMinute
                : lhs.startMinute < rhs.startMinute
        }
    }

    private func startEditing(_ block: ScheduleBlock) {
        if activeDraft?.sourceBlockID == block.id { return }
        guard finishEditing() else { return }
        activeDraft = ScheduleBlockDraft(block: block)
        draftInsertionIndex = nil
        rowErrorMessage = nil
    }

    private func startNewRow(at index: Int) {
        guard finishEditing(), let selectedTemplate else { return }
        activeDraft = ScheduleBlockDraft()
        draftInsertionIndex = min(max(0, index), sortedBlocks(in: selectedTemplate).count)
        rowErrorMessage = nil
    }

    private func insertRow(relativeTo blockID: UUID, after: Bool) {
        guard finishEditing(), let selectedTemplate else { return }
        let blocks = sortedBlocks(in: selectedTemplate)
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        startNewRow(at: index + (after ? 1 : 0))
    }

    @discardableResult
    private func finishEditing() -> Bool {
        guard let draft = activeDraft else { return true }
        if draft.isBlankNewDraft {
            cancelEditing()
            return true
        }
        guard let template = selectedTemplate else { return false }

        let block = draft.sourceBlockID.flatMap { id in
            template.blocks.first(where: { $0.id == id })
        }

        do {
            try ScheduleBlockWriter.commit(draft, block: block, template: template, in: modelContext)
            activeDraft = nil
            draftInsertionIndex = nil
            rowErrorMessage = nil
            return true
        } catch {
            rowErrorMessage = error.localizedDescription
            return false
        }
    }

    private func cancelEditing() {
        activeDraft = nil
        draftInsertionIndex = nil
        rowErrorMessage = nil
    }

    private func persistTaskToggle(id: UUID, value: Bool, in block: ScheduleBlock?) {
        guard let item = block?.checklistItems.first(where: { $0.id == id }) else { return }
        item.isCompleted = value
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureSelection() {
        guard let selected = selectedTemplate else { return }
        if selectedTemplateID != selected.id.uuidString {
            selectedTemplateID = selected.id.uuidString
        }
    }

    private func duplicate(_ template: ScheduleTemplate) {
        do {
            let copy = ScheduleTemplate(name: "\(template.name) 副本")
            modelContext.insert(copy)
            for block in template.blocks {
                let blockCopy = ScheduleBlock(
                    startMinute: block.startMinute,
                    endMinute: block.endMinute,
                    scope: block.scope
                )
                copy.blocks.append(blockCopy)
                for item in block.checklistItems.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    blockCopy.checklistItems.append(ScheduleChecklistItem(
                        title: item.title,
                        isCompleted: item.isCompleted,
                        sortOrder: item.sortOrder
                    ))
                }
            }
            try modelContext.save()
            selectedTemplateID = copy.id.uuidString
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ template: ScheduleTemplate) {
        guard templates.count > 1 else { return }
        do {
            modelContext.delete(template)
            try modelContext.save()
            templatePendingDeletion = nil
            selectedTemplateID = templates.first(where: { $0.id != template.id })?.id.uuidString ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ block: ScheduleBlock) {
        do {
            if activeDraft?.sourceBlockID == block.id {
                cancelEditing()
            }
            modelContext.delete(block)
            try modelContext.save()
            blockPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
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
    var body: some View {
        Grid(horizontalSpacing: ScheduleTableMetrics.spacing) {
            GridRow {
                Text("时间")
                    .frame(width: ScheduleTableMetrics.timeWidth, alignment: .leading)
                Text("归属")
                    .frame(width: ScheduleTableMetrics.scopeWidth, alignment: .leading)
                Text("具体任务")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("操作")
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
    let edit: () -> Void
    let insertAbove: () -> Void
    let insertBelow: () -> Void
    let requestDelete: () -> Void
    let saveError: (String) -> Void

    var body: some View {
        Grid(horizontalSpacing: ScheduleTableMetrics.spacing) {
            GridRow(alignment: .top) {
                Button(action: edit) {
                    Text("\(block.startMinute.clockText) – \(block.endMinute.clockText)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(CMTheme.textPrimary)
                        .frame(width: ScheduleTableMetrics.timeWidth, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: edit) {
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
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 9) {
                    let items = block.checklistItems.sorted { $0.sortOrder < $1.sortOrder }
                    if items.isEmpty {
                        Button("添加具体任务", action: edit)
                            .buttonStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(CMTheme.textTertiary)
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

                                Button(action: edit) {
                                    Text(item.title)
                                        .font(.system(size: 13))
                                        .foregroundStyle(item.isCompleted ? CMTheme.textTertiary : CMTheme.textPrimary)
                                        .strikethrough(item.isCompleted, color: CMTheme.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button("编辑") { edit() }
                    Divider()
                    Button("在上方插入") { insertAbove() }
                    Button("在下方插入") { insertBelow() }
                    Divider()
                    Button("删除时间块", role: .destructive) { requestDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(CMTheme.textSecondary)
                        .frame(width: ScheduleTableMetrics.actionWidth, height: 24, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("时间块操作")
            }
        }
        .padding(.vertical, CMTheme.rowVerticalPadding)
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
    let isNew: Bool
    let commit: () -> Void
    let cancel: () -> Void
    let insertAbove: (() -> Void)?
    let insertBelow: (() -> Void)?
    let requestDelete: (() -> Void)?
    let toggleTask: (UUID, Bool) -> Void

    @FocusState private var focusedField: Field?
    @State private var suppressNextBlurCommit = false

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
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(CMTheme.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(CMTheme.separator, lineWidth: 0.7)
                            }
                            .focused($focusedField, equals: .scope)
                            .onSubmit(commit)
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
                                            Text(scope.name)
                                                .lineLimit(1)
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
                                    .onChange(of: task.isCompleted) { _, value in
                                        toggleTask(task.id, value)
                                    }

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

                    HStack(spacing: 6) {
                        Button(action: cancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(CMTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .help(isNew ? "取消新增（Esc）" : "取消编辑（Esc）")

                        Menu {
                            if let insertAbove {
                                Button("在上方插入", action: insertAbove)
                            }
                            if let insertBelow {
                                Button("在下方插入", action: insertBelow)
                            }
                            if insertAbove != nil || insertBelow != nil {
                                Divider()
                            }
                            Button(isNew ? "取消新增" : "取消编辑", action: cancel)
                            if let requestDelete {
                                Divider()
                                Button("删除时间块", role: .destructive, action: requestDelete)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(CMTheme.textSecondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .simultaneousGesture(TapGesture().onEnded {
                            suppressNextBlurCommit = true
                        })
                    }
                    .frame(width: ScheduleTableMetrics.actionWidth, height: 24, alignment: .trailing)
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
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focusedField = .start
            }
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if case .task(let id) = oldValue, oldValue != newValue {
                removeEmptyTaskIfNeeded(id)
            }
            guard oldValue != nil, newValue == nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                if suppressNextBlurCommit {
                    suppressNextBlurCommit = false
                    return
                }
                if focusedField == nil {
                    commit()
                }
            }
        }
        .onExitCommand(perform: cancel)
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
            .onSubmit(commit)
            .accessibilityIdentifier(identifier)
    }

    private func advanceTask(after id: UUID) {
        guard let index = draft.tasks.firstIndex(where: { $0.id == id }) else { return }
        if draft.tasks[index].title.trimmed.isEmpty {
            if draft.tasks.count > 1 {
                draft.tasks.remove(at: index)
            } else {
                commit()
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

    private func removeEmptyTaskIfNeeded(_ id: UUID) {
        guard
            draft.tasks.count > 1,
            let task = draft.tasks.first(where: { $0.id == id }),
            task.title.trimmed.isEmpty
        else { return }
        draft.tasks.removeAll { $0.id == id }
    }
}

private struct TemplateNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (String) throws -> Void
    @State private var name: String
    @State private var errorMessage: String?

    init(title: String, initialName: String, onSave: @escaping (String) throws -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: title, subtitle: "例如：工作日、休息日、专注日")
            TextField("模板名称", text: $name)
                .calmTextField()
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(CMTheme.color(for: "clay"))
            }
            SheetFooter(canSave: !name.trimmed.isEmpty, cancel: { dismiss() }) {
                do {
                    try onSave(name.trimmed)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(CMTheme.canvas)
    }
}
