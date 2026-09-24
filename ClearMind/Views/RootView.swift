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

enum AppNavigationRoute: Hashable {
    case goal(UUID)
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [Goal]
    @State private var selection: SidebarSection = .overview
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var showingQuickCapture = false
    @State private var bootstrapError: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                if searchText.trimmed.isEmpty {
                    selectedContent
                } else {
                    SearchResultsView(query: searchText, onOpenSection: { section in
                        navigate(to: section)
                    })
                }
            }
            .navigationTitle(selection.title)
            .navigationDestination(for: AppNavigationRoute.self) { route in
                switch route {
                case let .goal(goalID):
                    if let goal = goals.first(where: { $0.id == goalID }) {
                        GoalDetailView(goal: goal)
                    } else {
                        ContentUnavailableView(
                            "找不到这个目标",
                            systemImage: "scope",
                            description: Text("它可能已经被删除。")
                        )
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                navigationMenu
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if isSearchPresented {
                    TextField("搜索所有内容", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 9)
                        .frame(width: 176, height: 28)
                        .background(
                            CMTheme.toolbarControlSurface,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .focused($isSearchFocused)
                        .onExitCommand { dismissSearch() }
                        .accessibilityIdentifier("global-search-field")
                }

                Button {
                    isSearchPresented ? dismissSearch() : presentSearch()
                } label: {
                    Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(CMTheme.textSecondary)
                .background(CMTheme.toolbarControlSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityLabel(isSearchPresented ? "关闭搜索" : "搜索所有内容")
                .accessibilityIdentifier("global-search-toggle")
                .help(isSearchPresented ? "关闭搜索" : "搜索所有内容（⌘F）")

                Button {
                    showingQuickCapture = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(CMTheme.textSecondary)
                .background(CMTheme.toolbarControlSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityLabel("记到收集箱")
                .accessibilityIdentifier("global-quick-capture")
                .help("记到收集箱（⌘N）")
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .focusGlobalSearch)) { _ in
            presentSearch()
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selection {
        case .overview: DashboardView(onNavigate: navigate)
        case .goals: GoalsView()
        case .nearTerm: NearTermView()
        case .ideas: IdeasView()
        case .inbox: InboxView()
        }
    }

    private var navigationMenu: some View {
        Menu {
            Section("今天") {
                navigationMenuItem(for: .overview)
            }

            Section("推进") {
                navigationMenuItem(for: .goals)
                navigationMenuItem(for: .nearTerm)
            }

            Section("收纳") {
                navigationMenuItem(for: .ideas)
                navigationMenuItem(for: .inbox)
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(CMTheme.textSecondary)
        .background(CMTheme.toolbarControlSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("切换页面")
        .accessibilityIdentifier("global-navigation-menu")
        .help("切换页面")
    }

    private func navigationMenuItem(for section: SidebarSection) -> some View {
        Toggle(isOn: Binding(
            get: { selection == section },
            set: { isOn in
                if isOn { navigate(to: section) }
            }
        )) {
            Label(section.title, systemImage: section.icon)
        }
        .accessibilityIdentifier("global-navigation-item-\(section.rawValue)")
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }

    private func presentSearch() {
        isSearchPresented = true
        Task { @MainActor in isSearchFocused = true }
    }

    private func dismissSearch() {
        isSearchPresented = false
        searchText = ""
    }

    private func navigate(to section: SidebarSection) {
        selection = section
        navigationPath = NavigationPath()
        dismissSearch()
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
                    .accessibilityIdentifier("global-search-results")
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
