import SwiftData
import SwiftUI

struct NearTermView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NearTermItem.updatedAt, order: .reverse) private var allItems: [NearTermItem]
    @State private var showingNewItem = false
    @State private var editingItem: NearTermItem?
    @State private var showArchived = false

    private var items: [NearTermItem] {
        allItems.filter { showArchived ? $0.isArchived : !$0.isArchived }
    }

    var body: some View {
        PageContainer {
            VStack(alignment: .leading, spacing: CMTheme.sectionSpacing) {
                HStack(alignment: .bottom) {
                    PageHeader("近期事项")
                    Spacer()
                    Button {
                        showingNewItem = true
                    } label: {
                        Label("新建事项", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                Toggle("查看已归档", isOn: $showArchived)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                if items.isEmpty {
                    QuietDivider()
                    EmptyState(
                        showArchived ? "没有归档内容" : "近期没有需要托管的事情",
                        message: "当一件事不能今天完成、又不想忘记时，再把它放到这里。",
                        actionTitle: showArchived ? nil : "添加近期事项"
                    ) { showingNewItem = true }
                } else {
                    itemSection(showArchived ? "已归档" : "近期事项", items: items)
                }
            }
        }
        .sheet(isPresented: $showingNewItem) { NearTermEditor() }
        .sheet(item: $editingItem) { NearTermEditor(item: $0) }
    }

    @ViewBuilder
    private func itemSection(_ title: String, items: [NearTermItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title)
            QuietDivider()
            ForEach(items) { item in
                Button { editingItem = item } label: {
                    ContentListRow(
                        title: item.title,
                        details: item.details,
                        metadata: showArchived ? "已归档" : nil,
                        tags: item.tags
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if item.isArchived {
                        Button("恢复") { item.isArchived = false; try? modelContext.save() }
                    } else {
                        Button("转为想法") { convertToIdea(item) }
                        Button("转为长期目标") { convertToGoal(item) }
                        Divider()
                        Button("归档") { item.isArchived = true; try? modelContext.save() }
                    }
                }
                QuietDivider()
            }
        }
    }

    private func convertToIdea(_ item: NearTermItem) {
        modelContext.insert(Idea(title: item.title, details: item.details, tags: item.tags))
        item.isArchived = true
        try? modelContext.save()
    }

    private func convertToGoal(_ item: NearTermItem) {
        let end = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
        modelContext.insert(Goal(title: item.title, details: item.details, startDate: .now, endDate: end, tags: item.tags))
        item.isArchived = true
        try? modelContext.save()
    }
}

struct IdeasView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Idea.updatedAt, order: .reverse) private var allIdeas: [Idea]
    @State private var showingNewIdea = false
    @State private var editingIdea: Idea?
    @State private var showArchived = false

    private var ideas: [Idea] {
        allIdeas.filter { showArchived ? $0.isArchived : !$0.isArchived }
    }

    var body: some View {
        PageContainer {
            VStack(alignment: .leading, spacing: CMTheme.sectionSpacing) {
                HStack(alignment: .bottom) {
                    PageHeader("想法库")
                    Spacer()
                    Button { showingNewIdea = true } label: {
                        Label("记录想法", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                Toggle("查看已归档", isOn: $showArchived)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 0) {
                    QuietDivider()
                    if ideas.isEmpty {
                        EmptyState(
                            showArchived ? "没有归档想法" : "想法库还是空的",
                            message: "这里允许内容只是一种可能，不必立即判断价值。",
                            actionTitle: showArchived ? nil : "记录第一个想法"
                        ) { showingNewIdea = true }
                    } else {
                        ForEach(ideas) { idea in
                            Button { editingIdea = idea } label: {
                                ContentListRow(
                                    title: idea.title,
                                    details: idea.details,
                                    metadata: idea.updatedAt.compactChineseDate,
                                    tags: idea.tags
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if idea.isArchived {
                                    Button("恢复") { idea.isArchived = false; try? modelContext.save() }
                                } else {
                                    Button("转为近期事项") { convertToNearTerm(idea) }
                                    Button("转为长期目标") { convertToGoal(idea) }
                                    Divider()
                                    Button("归档") { idea.isArchived = true; try? modelContext.save() }
                                }
                            }
                            QuietDivider()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewIdea) { IdeaEditor() }
        .sheet(item: $editingIdea) { IdeaEditor(idea: $0) }
    }

    private func convertToNearTerm(_ idea: Idea) {
        modelContext.insert(NearTermItem(title: idea.title, details: idea.details, tags: idea.tags))
        idea.isArchived = true
        try? modelContext.save()
    }

    private func convertToGoal(_ idea: Idea) {
        let end = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
        modelContext.insert(Goal(title: idea.title, details: idea.details, startDate: .now, endDate: end, tags: idea.tags))
        idea.isArchived = true
        try? modelContext.save()
    }
}

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InboxEntry.createdAt, order: .reverse) private var entries: [InboxEntry]
    @State private var text = ""

    var body: some View {
        PageContainer {
            VStack(alignment: .leading, spacing: CMTheme.sectionSpacing) {
                PageHeader("收集箱")

                HStack(alignment: .top, spacing: 12) {
                    MultilineEditor(placeholder: "写下一件暂时不想分类的事情…", text: $text)
                        .frame(height: 82)
                    Button("放进收集箱") { addEntry() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(text.trimmed.isEmpty)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading("尚未整理", trailingText: "\(entries.count) 条")
                        .padding(.bottom, 12)
                    QuietDivider()
                    if entries.isEmpty {
                        EmptyState("收集箱是空的", message: "所有念头都已经有了去处。")
                    } else {
                        ForEach(entries) { entry in
                            InboxRow(entry: entry)
                            QuietDivider()
                        }
                    }
                }
            }
        }
    }

    private func addEntry() {
        let value = text.trimmed
        guard !value.isEmpty else { return }
        modelContext.insert(InboxEntry(text: value))
        try? modelContext.save()
        text = ""
    }
}

private struct InboxRow: View {
    @Environment(\.modelContext) private var modelContext
    let entry: InboxEntry

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.text)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                Text(entry.createdAt.compactChineseDate)
                    .font(.system(size: 10))
                    .foregroundStyle(CMTheme.textTertiary)
            }
            Spacer()
            Menu("整理到…") {
                Button("想法库") { convertToIdea() }
                Button("近期事项") { convertToNearTerm() }
                Button("长期目标") { convertToGoal() }
                Divider()
                Button("删除", role: .destructive) { delete() }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, CMTheme.rowVerticalPadding)
    }

    private var parsed: (title: String, details: String) {
        TextParser.titleAndDetails(from: entry.text)
    }

    private func convertToIdea() {
        modelContext.insert(Idea(title: parsed.title, details: parsed.details))
        delete()
    }

    private func convertToNearTerm() {
        modelContext.insert(NearTermItem(title: parsed.title, details: parsed.details))
        delete()
    }

    private func convertToGoal() {
        let end = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
        modelContext.insert(Goal(title: parsed.title, details: parsed.details, startDate: .now, endDate: end))
        delete()
    }

    private func delete() {
        modelContext.delete(entry)
        try? modelContext.save()
    }
}

private struct ContentListRow: View {
    let title: String
    let details: String
    let metadata: String?
    let tags: [Tag]

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(CMTheme.textPrimary)
                if !details.trimmed.isEmpty {
                    Text(details)
                        .font(.system(size: 12))
                        .foregroundStyle(CMTheme.textSecondary)
                        .lineLimit(2)
                        .lineSpacing(3)
                }
                TagPills(tags: tags)
            }
            Spacer()
            if let metadata {
                Text(metadata)
                    .font(.system(size: 11))
                    .foregroundStyle(CMTheme.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CMTheme.textTertiary)
                .padding(.top, 2)
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }
}

struct NearTermEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: NearTermItem?
    @State private var title: String
    @State private var details: String
    @State private var tagNames: String
    @State private var errorMessage: String?

    init(item: NearTermItem? = nil) {
        self.item = item
        _title = State(initialValue: item?.title ?? "")
        _details = State(initialValue: item?.details ?? "")
        _tagNames = State(initialValue: item?.tags.map(\.name).joined(separator: ", ") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: item == nil ? "新建近期事项" : "编辑近期事项", subtitle: "把暂时不能处理、又不想忘记的事情安放在这里。")
            TextField("事项名称", text: $title).calmTextField()
            MultilineEditor(placeholder: "补充背景或想法（可选）", text: $details).frame(height: 105)
            TextField("标签，用逗号分隔", text: $tagNames).calmTextField()
            if let errorMessage { Text(errorMessage).font(.system(size: 12)).foregroundStyle(CMTheme.color(for: "clay")) }
            HStack {
                if let item {
                    Button(item.isArchived ? "恢复" : "归档") {
                        item.isArchived.toggle()
                        try? modelContext.save()
                        dismiss()
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                Spacer()
                SheetFooter(canSave: !title.trimmed.isEmpty, cancel: { dismiss() }, save: save)
            }
        }
        .padding(28)
        .frame(width: 590)
        .background(CMTheme.canvas)
    }

    private func save() {
        do {
            let tags = try TagService.resolve(commaSeparatedNames: tagNames, in: modelContext)
            let target = item ?? NearTermItem(title: title.trimmed, reviewDate: .now)
            target.title = title.trimmed
            target.details = details.trimmed
            target.tags = tags
            target.updatedAt = .now
            if item == nil { modelContext.insert(target) }
            try modelContext.save()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct IdeaEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let idea: Idea?
    @State private var title: String
    @State private var details: String
    @State private var tagNames: String
    @State private var errorMessage: String?

    init(idea: Idea? = nil) {
        self.idea = idea
        _title = State(initialValue: idea?.title ?? "")
        _details = State(initialValue: idea?.details ?? "")
        _tagNames = State(initialValue: idea?.tags.map(\.name).joined(separator: ", ") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: idea == nil ? "记录想法" : "编辑想法", subtitle: "允许它暂时只是一种可能。")
            TextField("想法标题", text: $title).calmTextField()
            MultilineEditor(placeholder: "写下这条想法…", text: $details).frame(height: 180)
            TextField("标签，用逗号分隔", text: $tagNames).calmTextField()
            if let errorMessage { Text(errorMessage).font(.system(size: 12)).foregroundStyle(CMTheme.color(for: "clay")) }
            HStack {
                if let idea {
                    Button(idea.isArchived ? "恢复" : "归档") {
                        idea.isArchived.toggle()
                        try? modelContext.save()
                        dismiss()
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                Spacer()
                SheetFooter(canSave: !title.trimmed.isEmpty, cancel: { dismiss() }, save: save)
            }
        }
        .padding(28)
        .frame(width: 590)
        .background(CMTheme.canvas)
    }

    private func save() {
        do {
            let tags = try TagService.resolve(commaSeparatedNames: tagNames, in: modelContext)
            let target = idea ?? Idea(title: title.trimmed)
            target.title = title.trimmed
            target.details = details.trimmed
            target.tags = tags
            target.updatedAt = .now
            if idea == nil { modelContext.insert(target) }
            try modelContext.save()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
