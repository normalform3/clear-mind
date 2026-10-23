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
    @Environment(\.cmPalette) private var palette
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [Goal]
    @State private var selection: SidebarSection = .overview
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var showingQuickCapture = false
    @State private var bootstrapError: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            AppSidebar(selection: selection, onSelect: navigate)
                .navigationSplitViewColumnWidth(min: 208, ideal: 224, max: 240)
        } detail: {
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
                ToolbarItemGroup(placement: .primaryAction) {
                    if isSearchPresented {
                        TextField("搜索所有内容", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(.horizontal, 9)
                            .frame(width: 176, height: 28)
                            .background(
                                palette.toolbarControlSurface,
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
                    .foregroundStyle(palette.textSecondary)
                    .background(palette.toolbarControlSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                    .foregroundStyle(palette.textSecondary)
                    .background(palette.toolbarControlSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel("记到收集箱")
                    .accessibilityIdentifier("global-quick-capture")
                    .help("记到收集箱（⌘N）")
                }
            }
            .background(palette.canvas)
        }
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

private struct AppSidebar: View {
    @Environment(\.cmPalette) private var palette
    @EnvironmentObject private var appearance: AppearanceStore
    @State private var showingAppearance = false

    let selection: SidebarSection
    let onSelect: (SidebarSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Clear Mind")
                .font(.system(size: 21, weight: .medium, design: .serif))
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    group("今天", sections: [.overview])
                    group("推进", sections: [.goals, .nearTerm])
                    group("收纳", sections: [.ideas, .inbox])
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }

            Button {
                showingAppearance = true
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 16, weight: .regular))
                        .frame(width: 20)
                    Text("外观设置")
                    Spacer()
                    Circle()
                        .fill(palette.primary)
                        .frame(width: 10, height: 10)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(palette.hover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .popover(isPresented: $showingAppearance, arrowEdge: .trailing) {
                ThemeSwitcher(onClose: { showingAppearance = false })
            }
            .accessibilityValue(appearance.selection.title)
            .accessibilityIdentifier("appearance-menu")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.sidebar)
    }

    private func group(_ title: String, sections: [SidebarSection]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(sections) { section in
                Button { onSelect(section) } label: {
                    HStack(spacing: 11) {
                        Image(systemName: section.icon)
                            .font(.system(size: 16, weight: .regular))
                            .frame(width: 20)
                        Text(section.title)
                            .font(.system(size: 13, weight: selection == section ? .semibold : .regular))
                        Spacer()
                    }
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selection == section ? palette.active : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityValue(selection == section ? "已选择" : "未选择")
                .accessibilityIdentifier("sidebar-item-\(section.rawValue)")
            }
        }
    }
}

private struct ThemeSwitcher: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cmPalette) private var palette
    @EnvironmentObject private var appearance: AppearanceStore

    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("外观设置")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            ForEach(AppearanceTheme.allCases) { theme in
                Button {
                    select(theme)
                } label: {
                    HStack(spacing: 12) {
                        themePreview(theme)
                        Text(theme.title)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 16)
                        Text("⌥⌘\(theme.shortcutNumber)")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                        if appearance.selection == theme {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.primaryFill)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(appearance.selection == theme ? palette.active : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityValue(appearance.selection == theme ? "已选择" : "未选择")
                .accessibilityIdentifier("theme-option-\(theme.rawValue)")
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(palette.cardSurface)
        .onExitCommand(perform: onClose)
    }

    private func select(_ theme: AppearanceTheme) {
        if reduceMotion {
            appearance.select(theme)
        } else {
            withAnimation(.easeOut(duration: 0.2)) { appearance.select(theme) }
        }
    }

    private func themePreview(_ theme: AppearanceTheme) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme.palette.sidebar)
            Rectangle().fill(theme.palette.canvas)
            Rectangle().fill(theme.palette.primary)
        }
        .frame(width: 42, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.separator, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct QuickCaptureSheet: View {
    @Environment(\.cmPalette) private var palette
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
        .background(palette.canvas)
    }
}

private struct SearchResultsView: View {
    @Environment(\.cmPalette) private var palette
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
                                .foregroundStyle(palette.textSecondary)
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
