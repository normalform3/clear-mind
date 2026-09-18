import SwiftData
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case goals
    case nearTerm
    case ideas
    case inbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "安心总览"
        case .goals: "长期目标"
        case .nearTerm: "近期事项"
        case .ideas: "想法库"
        case .inbox: "收集箱"
        }
    }

    var icon: String {
        switch self {
        case .overview: "rectangle.grid.1x2"
        case .goals: "scope"
        case .nearTerm: "tray.full"
        case .ideas: "lightbulb"
        case .inbox: "square.and.pencil"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selection: SidebarSection? = .overview
    @State private var searchText = ""
    @State private var showingQuickCapture = false
    @State private var bootstrapError: String?

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
                    .padding(.vertical, 4)
            }
            .navigationSplitViewColumnWidth(min: 144, ideal: 152, max: 160)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                Text("仅保存在本机")
                    .font(.system(size: 10))
                    .foregroundStyle(CMTheme.textTertiary)
                    .lineLimit(1)
                    .padding(.vertical, 12)
                    .help("所有内容仅保存在这台 Mac")
            }
        } detail: {
            Group {
                if searchText.trimmed.isEmpty {
                    selectedContent
                } else {
                    SearchResultsView(query: searchText, onOpenSection: { section in
                        selection = section
                        searchText = ""
                    })
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "搜索所有内容")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingQuickCapture = true
                    } label: {
                        Label("记到收集箱", systemImage: "square.and.pencil")
                    }
                    .help("记到收集箱（⌘N）")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(CMTheme.canvas)
        .sheet(isPresented: $showingQuickCapture) {
            QuickCaptureSheet()
        }
        .alert("本地数据库暂时不可用", isPresented: Binding(
            get: { bootstrapError != nil },
            set: { if !$0 { bootstrapError = nil } }
        )) {
            Button("好") { bootstrapError = nil }
        } message: {
            Text(bootstrapError ?? "未知错误")
        }
        .task {
            do {
                try AppBootstrapper.ensureDefaultTemplate(in: modelContext)
                try UITestFixtureSeeder.seedIfRequested(in: modelContext)
                try GoalOrderService.normalizeIfNeeded(in: modelContext)
            } catch {
                bootstrapError = error.localizedDescription
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showQuickCapture)) { _ in
            showingQuickCapture = true
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selection ?? .overview {
        case .overview: DashboardView(onNavigate: { selection = $0 })
        case .goals: GoalsView()
        case .nearTerm: NearTermView()
        case .ideas: IdeasView()
        case .inbox: InboxView()
        }
    }
}

private struct QuickCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(title: "先放下这件事", subtitle: "无需现在分类，之后再决定它属于哪里。")
            MultilineEditor(placeholder: "写下脑中的事情…", text: $text)
                .frame(height: 150)
            SheetFooter(canSave: !text.trimmed.isEmpty, saveTitle: "放进收集箱", cancel: { dismiss() }) {
                modelContext.insert(InboxEntry(text: text.trimmed))
                try? modelContext.save()
                dismiss()
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(CMTheme.canvas)
    }
}

private struct SearchResultsView: View {
    @Query private var goals: [Goal]
    @Query private var nearTermItems: [NearTermItem]
    @Query private var ideas: [Idea]
    @Query private var inboxEntries: [InboxEntry]

    let query: String
    let onOpenSection: (SidebarSection) -> Void

    private var key: String { query.normalizedKey }

    var body: some View {
        PageContainer {
            VStack(alignment: .leading, spacing: 30) {
                PageHeader("搜索“\(query)”")
                resultSection("长期目标", section: .goals, rows: goals.filter { matches($0.title, $0.details, $0.tags.map(\.name).joined(separator: " ")) }.map { ($0.title, $0.details) })
                resultSection("近期事项", section: .nearTerm, rows: nearTermItems.filter { !$0.isArchived && matches($0.title, $0.details, $0.tags.map(\.name).joined(separator: " ")) }.map { ($0.title, $0.details) })
                resultSection("想法", section: .ideas, rows: ideas.filter { !$0.isArchived && matches($0.title, $0.details, $0.tags.map(\.name).joined(separator: " ")) }.map { ($0.title, $0.details) })
                resultSection("收集箱", section: .inbox, rows: inboxEntries.filter { matches($0.text) }.map { (TextParser.titleAndDetails(from: $0.text).title, $0.text) })
            }
        }
    }

    private func matches(_ values: String...) -> Bool {
        values.joined(separator: " ").normalizedKey.contains(key)
    }

    @ViewBuilder
    private func resultSection(_ title: String, section: SidebarSection, rows: [(String, String)]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(title, actionTitle: "打开") { onOpenSection(section) }
                    .padding(.bottom, 10)
                QuietDivider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.0)
                            .font(.system(size: 14, weight: .medium))
                        if !row.1.trimmed.isEmpty {
                            Text(row.1)
                                .font(.system(size: 12))
                                .foregroundStyle(CMTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, CMTheme.rowVerticalPadding)
                    QuietDivider()
                }
            }
        }
    }
}
