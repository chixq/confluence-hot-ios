import SwiftUI

enum FeedKind {
    case recent
    case popular

    var title: String {
        switch self {
        case .recent: return "Recently worked on"
        case .popular: return "Popular"
        }
    }

    var tabTitle: String {
        switch self {
        case .recent: return "工作"
        case .popular: return "热门"
        }
    }

    var subtitle: String {
        switch self {
        case .recent: return "最近更新的页面和博客"
        case .popular: return "站点中获得更多互动的内容"
        }
    }

    var emptyTitle: String {
        switch self {
        case .recent: return "暂无更新"
        case .popular: return "暂无热门内容"
        }
    }
}

struct ContentDateSection: Identifiable {
    let id: String
    let title: String
    let items: [ContentItem]
}

@MainActor
final class ContentFeedViewModel: ObservableObject {
    let kind: FeedKind

    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?
    @Published var lastLoadedAt: Date?

    private let pageSize = 30
    private var nextStart = 0

    init(kind: FeedKind) {
        self.kind = kind
    }

    func load(client: ConfluenceClient?, force: Bool = false) async {
        guard let client else { return }
        guard force || (!isLoading && items.isEmpty) else { return }

        isLoading = true
        errorMessage = nil
        nextStart = 0
        hasMore = true

        do {
            let page = try await fetchPage(client: client, start: nextStart, cachePolicy: force ? .reloadIgnoringCache : .useCache)
            items = page
            nextStart = page.count
            hasMore = page.count >= pageSize
            lastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMoreIfNeeded(currentItem item: ContentItem?, client: ConfluenceClient?) async {
        guard let client, hasMore, !isLoading, !isLoadingMore else { return }
        guard let item else {
            await loadMore(client: client)
            return
        }
        guard items.suffix(6).contains(where: { $0.id == item.id }) else { return }
        await loadMore(client: client)
    }

    private func loadMore(client: ConfluenceClient) async {
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await fetchPage(client: client, start: nextStart)
            let existingIDs = Set(items.map(\.id))
            let newItems = page.filter { !existingIDs.contains($0.id) }
            items.append(contentsOf: newItems)
            nextStart += page.count
            hasMore = page.count >= pageSize && !newItems.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchPage(client: ConfluenceClient, start: Int, cachePolicy: ConfluenceCachePolicy = .useCache) async throws -> [ContentItem] {
        switch kind {
        case .recent:
            return try await client.fetchRecentlyUpdated(start: start, limit: pageSize, cachePolicy: cachePolicy)
        case .popular:
            return try await client.fetchPopular(start: start, limit: pageSize, cachePolicy: cachePolicy)
        }
    }
}

struct AdaptiveFeedView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var sessionStore: SessionStore

    let kind: FeedKind
    let refreshToken: Int
    @StateObject private var viewModel: ContentFeedViewModel
    @State private var selectedItem: ContentItem?

    init(kind: FeedKind, refreshToken: Int = 0) {
        self.kind = kind
        self.refreshToken = refreshToken
        _viewModel = StateObject(wrappedValue: ContentFeedViewModel(kind: kind))
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height && proxy.size.width >= 700
            let shouldUseSplit = appSettings.landscapeSplitEnabled && isLandscape

            Group {
                if shouldUseSplit {
                    NavigationSplitView {
                        FeedListView(viewModel: viewModel, selectedItem: $selectedItem, compactNavigation: false, refreshToken: refreshToken)
                            .navigationTitle(kind.title)
                            .liquidNavigationChrome()
                    } detail: {
                        if let selectedItem {
                            ContentDetailView(item: selectedItem)
                                .id(selectedItem.id)
                        } else {
                            EmptyStateView(icon: "rectangle.split.2x1", title: "选择一篇内容", message: "横屏时可在左侧浏览列表，右侧阅读正文和回复")
                                .padding(24)
                        }
                    }
                    .task {
                        await viewModel.load(client: sessionStore.client, force: refreshToken > 0)
                        reconcileSelection()
                    }
                    .onReceive(viewModel.$items) { _ in
                        reconcileSelection()
                    }
                } else {
                    NavigationStack {
                        FeedListView(viewModel: viewModel, selectedItem: $selectedItem, compactNavigation: true, refreshToken: refreshToken)
                            .navigationTitle(kind.title)
                            .liquidNavigationChrome()
                    }
                }
            }
        }
    }

    private func reconcileSelection() {
        guard !viewModel.items.isEmpty else {
            selectedItem = nil
            return
        }
        if let selectedItem, viewModel.items.contains(where: { $0.id == selectedItem.id }) {
            return
        }
        selectedItem = viewModel.items.first
    }
}

struct FeedListView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var viewModel: ContentFeedViewModel
    @Binding var selectedItem: ContentItem?
    let compactNavigation: Bool
    let refreshToken: Int

    var body: some View {
        List {
            if viewModel.kind == .recent {
                WorkBentoHeader()
                    .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 10, trailing: 20))
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            }

            if viewModel.isLoading && viewModel.items.isEmpty {
                loadingRow
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                EmptyStateView(icon: "exclamationmark.triangle", title: "加载失败", message: errorMessage)
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else if viewModel.items.isEmpty {
                EmptyStateView(icon: "tray", title: viewModel.kind.emptyTitle, message: "换个时间刷新看看")
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(groupedItems) { section in
                    Section {
                        ForEach(section.items) { item in
                            row(for: item)
                                .onAppear {
                                    Task {
                                        await viewModel.loadMoreIfNeeded(currentItem: item, client: sessionStore.client)
                                    }
                                }
                        }
                    } header: {
                        Text(section.title)
                            .font(.system(size: 21, weight: .semibold))
                            .textCase(nil)
                            .foregroundStyle(AtlassianTheme.mutedText)
                            .padding(.top, 16)
                    }
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(AtlassianTheme.blue)
                        Spacer()
                    }
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
                } else if viewModel.hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreIfNeeded(currentItem: nil, client: sessionStore.client)
                            }
                        }
                        .listRowBackground(AtlassianTheme.background)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AtlassianTheme.background)
        .inlineNavigationTitle()
        .liquidNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.load(client: sessionStore.client, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .refreshable {
            await viewModel.load(client: sessionStore.client, force: true)
        }
        .task {
            await viewModel.load(client: sessionStore.client, force: refreshToken > 0)
        }
    }

    private var loadingRow: some View {
        ProgressView()
            .tint(AtlassianTheme.blue)
            .frame(maxWidth: .infinity, minHeight: 260)
            .listRowBackground(AtlassianTheme.background)
            .listRowSeparator(.hidden)
    }

    private var groupedItems: [ContentDateSection] {
        ContentGrouper.group(items: viewModel.items)
    }

    @ViewBuilder
    private func row(for item: ContentItem) -> some View {
        if compactNavigation {
            NavigationLink {
                ContentDetailView(item: item)
                    .id(item.id)
            } label: {
                ContentRow(item: item)
            }
            .listRowBackground(AtlassianTheme.background)
        } else {
            Button {
                selectedItem = item
            } label: {
                ContentRow(item: item, isSelected: selectedItem?.id == item.id, showsChevron: false)
            }
            .buttonStyle(.plain)
            .listRowBackground(AtlassianTheme.background)
        }
    }
}

@MainActor
final class WorkBentoViewModel: ObservableObject {
    @Published private(set) var remoteDrafts: [ContentItem] = []
    @Published private(set) var localDrafts: [LocalArticleDraft] = []
    @Published private(set) var todos: [TodoItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUpdatingTodos = false
    @Published var errorMessage: String?

    private var todoStorageKey: String?

    var openTodoCount: Int {
        todos.filter { !$0.isDone }.count
    }

    var draftCount: Int {
        localDrafts.count + remoteDrafts.count
    }

    func load(client: ConfluenceClient?, user: UserProfile?, configuration: ServerConfiguration?) async {
        guard let client else { return }
        todoStorageKey = Self.todoKey(configuration: configuration, user: user)
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        async let draftsTask = loadDrafts(client: client)
        remoteDrafts = await draftsTask
        localDrafts = LocalArticleDraftStore.load()
        todos = todoStorageKey.flatMap { LocalTodoStore.load(key: $0) } ?? []
        isLoading = false
    }

    func addTodo(title: String) async {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var updated = todos
        updated.insert(TodoItem(id: UUID().uuidString, title: cleaned, isDone: false), at: 0)
        await saveTodos(updated)
    }

    func toggleTodo(_ item: TodoItem) async {
        let updated = todos.map { current in
            current.id == item.id ? TodoItem(id: current.id, title: current.title, isDone: !current.isDone) : current
        }
        await saveTodos(updated)
    }

    func deleteTodo(_ item: TodoItem) async {
        await saveTodos(todos.filter { $0.id != item.id })
    }

    private func saveTodos(_ updated: [TodoItem]) async {
        guard let todoStorageKey else { return }
        isUpdatingTodos = true
        errorMessage = nil
        defer { isUpdatingTodos = false }
        todos = updated
        LocalTodoStore.save(updated, key: todoStorageKey)
    }

    private func loadDrafts(client: ConfluenceClient) async -> [ContentItem] {
        do {
            return try await client.fetchDrafts()
        } catch {
            return []
        }
    }

    private static func todoKey(configuration: ServerConfiguration?, user: UserProfile?) -> String? {
        guard let configuration else { return nil }
        let userID = user?.stableID ?? configuration.username
        return "local.todos.\(configuration.baseURL.absoluteString)|\(userID)"
    }
}

private enum LocalTodoStore {
    static func load(key: String) -> [TodoItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            return []
        }
        return items
    }

    static func save(_ items: [TodoItem], key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum LocalArticleDraftStore {
    private static let key = "local.article.drafts"

    static func load() -> [LocalArticleDraft] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let drafts = try? JSONDecoder().decode([LocalArticleDraft].self, from: data) else {
            return []
        }
        return drafts.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(_ draft: LocalArticleDraft) {
        var drafts = load().filter { $0.contentID != draft.contentID }
        drafts.insert(draft, at: 0)
        persist(drafts)
    }

    static func remove(contentID: String) {
        persist(load().filter { $0.contentID != contentID })
    }

    private static func persist(_ drafts: [LocalArticleDraft]) {
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct WorkBentoHeader: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = WorkBentoViewModel()
    @State private var showsDrafts = false
    @State private var showsTodos = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    showsDrafts = true
                } label: {
                    WorkBentoTile(
                        title: "草稿箱",
                        subtitle: "编辑中的页面",
                        count: viewModel.draftCount,
                        systemImage: "doc.text.fill",
                        iconColor: Color(hex: 0xDFFCF0),
                        gradient: [Color(hex: 0x20C997), Color(hex: 0x0B8F5A)]
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showsTodos = true
                } label: {
                    WorkBentoTile(
                        title: "待办",
                        subtitle: "本地任务列表",
                        count: viewModel.openTodoCount,
                        systemImage: "checkmark.circle.fill",
                        iconColor: Color(hex: 0xFFE9E6),
                        gradient: [Color(hex: 0xFF5A52), Color(hex: 0xD92D20)]
                    )
                }
                .buttonStyle(.plain)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AtlassianTheme.red)
            }
        }
        .task {
            await viewModel.load(client: sessionStore.client, user: sessionStore.user, configuration: sessionStore.configuration)
        }
        .refreshable {
            await viewModel.load(client: sessionStore.client, user: sessionStore.user, configuration: sessionStore.configuration)
        }
        .sheet(isPresented: $showsDrafts) {
            NavigationStack {
                DraftInboxView(localDrafts: viewModel.localDrafts, remoteDrafts: viewModel.remoteDrafts)
            }
        }
        .sheet(isPresented: $showsTodos) {
            NavigationStack {
                TodoListView(viewModel: viewModel)
            }
        }
    }
}

struct WorkBentoTile: View {
    @EnvironmentObject private var appSettings: AppSettings

    let title: String
    let subtitle: String
    let count: Int
    let systemImage: String
    let iconColor: Color
    let gradient: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(iconColor)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.18), in: Circle())

                Spacer()

                Text("\(count)")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(appSettings.headlineFont)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: gradient.last?.opacity(0.20) ?? .clear, radius: 12, x: 0, y: 6)
    }
}

struct DraftInboxView: View {
    let localDrafts: [LocalArticleDraft]
    let remoteDrafts: [ContentItem]

    var body: some View {
        List {
            if localDrafts.isEmpty && remoteDrafts.isEmpty {
                EmptyStateView(icon: "doc.text", title: "暂无草稿", message: "所有编辑中的页面会出现在这里")
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else {
                if !localDrafts.isEmpty {
                    Section {
                        ForEach(localDrafts) { draft in
                            NavigationLink {
                                LocalDraftEditorView(draft: draft)
                            } label: {
                                ContentRow(item: draft.item)
                            }
                            .listRowBackground(AtlassianTheme.background)
                        }
                    } header: {
                        Text("本地未发布")
                            .textCase(nil)
                    }
                }

                if !remoteDrafts.isEmpty {
                    Section {
                        ForEach(remoteDrafts) { item in
                            NavigationLink {
                                ContentDetailView(item: item)
                                    .id(item.id)
                            } label: {
                                ContentRow(item: item)
                            }
                            .listRowBackground(AtlassianTheme.background)
                        }
                    } header: {
                        Text("Confluence 草稿")
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AtlassianTheme.background)
        .navigationTitle("草稿箱")
        .inlineNavigationTitle()
        .liquidNavigationChrome()
    }
}

struct LocalDraftEditorView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var message: String?

    let draft: LocalArticleDraft

    var body: some View {
        VStack(spacing: 0) {
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(AtlassianTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
            ContentEditorSheet(
                title: draft.title,
                storageHTML: draft.storageHTML,
                isSaving: isSaving,
                onCancel: { title, storageHTML in
                    LocalArticleDraftStore.save(
                        LocalArticleDraft(
                            id: draft.id,
                            contentID: draft.contentID,
                            title: title,
                            storageHTML: storageHTML,
                            spaceName: draft.spaceName,
                            type: draft.type,
                            webPath: draft.webPath,
                            updatedAt: Date()
                        )
                    )
                    dismiss()
                },
                onSave: { title, storageHTML in
                    Task { await publish(title: title, storageHTML: storageHTML) }
                }
            )
        }
    }

    private func publish(title: String, storageHTML: String) async {
        guard let client = sessionStore.client else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let detail = try await client.fetchDetail(id: draft.contentID, cachePolicy: .reloadIgnoringCache)
            _ = try await client.updateContent(
                id: detail.id,
                type: detail.type,
                title: title,
                storageHTML: storageHTML,
                versionNumber: detail.nextVersionNumber
            )
            LocalArticleDraftStore.remove(contentID: draft.contentID)
            message = "草稿已发布"
            dismiss()
        } catch {
            message = "发布失败：\(error.localizedDescription)"
        }
    }
}

struct TodoListView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject var viewModel: WorkBentoViewModel
    @State private var newTodoTitle = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("添加待办", text: $newTodoTitle)
                        .textFieldStyle(.plain)
                    Button {
                        Task {
                            await viewModel.addTodo(title: newTodoTitle)
                            newTodoTitle = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                    }
                    .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isUpdatingTodos)
                }
                .padding(.vertical, 6)
            }

            if !viewModel.todos.isEmpty {
                Section {
                    ForEach(viewModel.todos) { item in
                        Button {
                            Task { await viewModel.toggleTodo(item) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(item.isDone ? AtlassianTheme.green : AtlassianTheme.mutedText)
                                Text(item.title)
                                    .font(appSettings.baseFont)
                                    .foregroundStyle(item.isDone ? AtlassianTheme.mutedText : AtlassianTheme.text)
                                    .strikethrough(item.isDone)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteTodo(item) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                EmptyStateView(icon: "checkmark.circle", title: "暂无待办", message: "把需要跟进的知识库事项放在这里")
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            }

            if viewModel.isUpdatingTodos {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(AtlassianTheme.blue)
                    Spacer()
                }
                .listRowBackground(AtlassianTheme.background)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AtlassianTheme.groupedBackground)
        .navigationTitle("待办")
        .inlineNavigationTitle()
        .liquidNavigationChrome()
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published var errorMessage: String?
    @Published private(set) var activeHighlight: String = ""

    private let pageSize = 30
    private var nextStart = 0
    private var query = ""
    private var cql: String?

    func search(client: ConfluenceClient?, query: String) async {
        guard let client else { return }
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cql = nil
        activeHighlight = self.query
        guard !self.query.isEmpty else {
            items = []
            hasMore = false
            return
        }

        isLoading = true
        errorMessage = nil
        nextStart = 0

        do {
            async let contentPageTask = client.searchContent(contentQuery: self.query, authorQuery: "", start: nextStart, limit: pageSize)
            async let authorPageTask = client.searchContent(contentQuery: "", authorQuery: self.query, start: nextStart, limit: pageSize)
            let merged = try await Self.merged(contentPageTask, authorPageTask)
            let page = Array(merged.prefix(pageSize))
            items = page
            nextStart = page.count
            hasMore = page.count >= pageSize
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func runPreset(_ preset: SearchPreset, client: ConfluenceClient?) async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        nextStart = 0
        hasMore = false
        query = ""
        cql = nil
        activeHighlight = ""

        do {
            switch preset.kind {
            case .mostReadThisWeek:
                let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().addingTimeInterval(-7 * 24 * 60 * 60)
                items = try await client.fetchPopular(start: 0, limit: 80, cachePolicy: .reloadIgnoringCache)
                    .filter { ($0.date ?? Date.distantPast) >= weekStart }
                    .prefix(10)
                    .map { $0 }
            case .mostCommentedThisWeek:
                let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().addingTimeInterval(-7 * 24 * 60 * 60)
                items = try await client.fetchPopular(start: 0, limit: 80, cachePolicy: .reloadIgnoringCache)
                    .filter { ($0.date ?? Date.distantPast) >= weekStart }
                    .sorted { ($0.commentCount ?? 0) > ($1.commentCount ?? 0) }
                    .prefix(10)
                    .map { $0 }
            case .createdThisWeek:
                let cql = "type in (page,blogpost) and created >= \"\(Self.weekStartString())\" order by created desc"
                items = try await client.fetchCQLSearch(cql: cql, start: 0, limit: 30)
                self.cql = cql
                hasMore = items.count >= pageSize
                nextStart = items.count
            case .customCQL:
                guard let customCQL = preset.cql?.trimmingCharacters(in: .whitespacesAndNewlines), !customCQL.isEmpty else {
                    items = []
                    break
                }
                items = try await client.fetchCQLSearch(cql: customCQL, start: 0, limit: 30)
                cql = customCQL
                hasMore = items.count >= pageSize
                nextStart = items.count
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMoreIfNeeded(currentItem item: ContentItem?, client: ConfluenceClient?) async {
        guard let client, hasMore, !isLoading, !isLoadingMore else { return }
        guard let item else {
            await loadMore(client: client)
            return
        }
        guard items.suffix(6).contains(where: { $0.id == item.id }) else { return }
        await loadMore(client: client)
    }

    private func loadMore(client: ConfluenceClient) async {
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page: [ContentItem]
            if let cql {
                page = try await client.fetchCQLSearch(cql: cql, start: nextStart, limit: pageSize)
            } else {
                page = try await client.searchContent(contentQuery: query, authorQuery: "", start: nextStart, limit: pageSize)
            }
            let existingIDs = Set(items.map(\.id))
            let newItems = page.filter { !existingIDs.contains($0.id) }
            items.append(contentsOf: newItems)
            nextStart += page.count
            hasMore = page.count >= pageSize && !newItems.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func merged(_ first: [ContentItem], _ second: [ContentItem]) -> [ContentItem] {
        var seen: Set<String> = []
        var output: [ContentItem] = []
        for item in first + second {
            guard !seen.contains(item.id) else { continue }
            seen.insert(item.id)
            output.append(item)
        }
        return output.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private static func weekStartString() -> String {
        let date = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct SearchView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @StateObject private var viewModel = SearchViewModel()
    @State private var query = ""
    @State private var customPresets = SearchPresetStore.load()
    @State private var isShowingPresetEditor = false
    @State private var presetName = ""
    @State private var presetCQL = ""
    let refreshToken: Int

    init(refreshToken: Int = 0) {
        self.refreshToken = refreshToken
    }

    var body: some View {
        List {
            Section {
                searchFields
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            }

            if viewModel.isLoading {
                loadingRow
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(icon: "exclamationmark.triangle", title: "搜索失败", message: errorMessage)
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else if viewModel.items.isEmpty && !query.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "暂无结果", message: "换个关键词试试")
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else if viewModel.items.isEmpty {
                EmptyStateView(icon: "text.magnifyingglass", title: "查找 Confluence 内容", message: "输入关键词或选择一个预设搜索")
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(viewModel.items) { item in
                        NavigationLink {
                            ContentDetailView(item: item)
                                .id(item.id)
                        } label: {
                            ContentRow(item: item, highlightText: viewModel.activeHighlight)
                        }
                        .listRowBackground(AtlassianTheme.background)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreIfNeeded(currentItem: item, client: sessionStore.client)
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView().tint(AtlassianTheme.blue)
                            Spacer()
                        }
                        .listRowBackground(AtlassianTheme.background)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("结果")
                        .font(.headline)
                        .textCase(nil)
                        .foregroundStyle(AtlassianTheme.mutedText)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AtlassianTheme.background)
        .navigationTitle("搜索")
        .inlineNavigationTitle()
        .liquidNavigationChrome()
        .sheet(isPresented: $isShowingPresetEditor) {
            NavigationStack {
                Form {
                    TextField("名称", text: $presetName)
                    TextField("CQL，例如 type = page order by lastmodified desc", text: $presetCQL, axis: .vertical)
                        .lineLimit(3...6)
                }
                .navigationTitle("添加预设")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { isShowingPresetEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let preset = SearchPreset(name: presetName, kind: .customCQL, cql: presetCQL)
                            customPresets.append(preset)
                            SearchPresetStore.save(customPresets)
                            presetName = ""
                            presetCQL = ""
                            isShowingPresetEditor = false
                        }
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || presetCQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .task(id: refreshToken) {
            if refreshToken > 0 {
                await viewModel.search(client: sessionStore.client, query: query)
            }
        }
    }

    private var searchFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("统一搜索", systemImage: "magnifyingglass")
                .font(appSettings.subheadlineFont)
                .foregroundStyle(AtlassianTheme.mutedText)

            HStack(spacing: 8) {
                TextField("标题、正文、作者关键词", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                Button {
                    runSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .liquidField()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchPreset.builtIns + customPresets) { preset in
                        Button {
                            Task { await viewModel.runPreset(preset, client: sessionStore.client) }
                        } label: {
                            Label(preset.name, systemImage: preset.systemImage)
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        isShowingPresetEditor = true
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var loadingRow: some View {
        ProgressView()
            .tint(AtlassianTheme.blue)
            .frame(maxWidth: .infinity, minHeight: 180)
            .listRowBackground(AtlassianTheme.background)
            .listRowSeparator(.hidden)
    }

    private func runSearch() {
        Task {
            await viewModel.search(client: sessionStore.client, query: query)
        }
    }
}

enum SearchPresetKind: String, Codable {
    case mostReadThisWeek
    case mostCommentedThisWeek
    case createdThisWeek
    case customCQL
}

struct SearchPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var kind: SearchPresetKind
    var cql: String?

    var systemImage: String {
        switch kind {
        case .mostReadThisWeek: return "eye"
        case .mostCommentedThisWeek: return "bubble.left.and.bubble.right"
        case .createdThisWeek: return "sparkles"
        case .customCQL: return "line.3.horizontal.decrease.circle"
        }
    }

    static let builtIns = [
        SearchPreset(name: "本周最多阅读 10 篇", kind: .mostReadThisWeek),
        SearchPreset(name: "本周最多回复 10 篇", kind: .mostCommentedThisWeek),
        SearchPreset(name: "本周新建", kind: .createdThisWeek)
    ]
}

enum SearchPresetStore {
    private static let key = "search.presets.custom"

    static func load() -> [SearchPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([SearchPreset].self, from: data) else {
            return []
        }
        return presets
    }

    static func save(_ presets: [SearchPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct ContentRow: View {
    @EnvironmentObject private var appSettings: AppSettings

    let item: ContentItem
    var isSelected = false
    var showsChevron = true
    var highlightText: String?
    var highlightAuthor: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AuthenticatedAvatarView(name: item.authorName ?? item.spaceName, path: item.authorAvatarPath, tint: avatarTint)

            VStack(alignment: .leading, spacing: 5) {
                Text(TextHighlighter.attributed(item.title, query: highlightText))
                    .font(appSettings.fontChoice == .system ? .system(size: 18, weight: .semibold) : appSettings.fontChoice.font(size: 18 * appSettings.fontScale, relativeTo: .headline))
                    .foregroundStyle(AtlassianTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(TextHighlighter.attributed(subtitle, query: highlightAuthor))
                    .font(appSettings.fontChoice.font(size: 15 * appSettings.fontScale, relativeTo: .subheadline))
                    .foregroundStyle(AtlassianTheme.mutedText)
                    .lineLimit(1)

                if let excerpt = item.excerpt, !excerpt.isEmpty {
                    Text(TextHighlighter.attributed(excerpt, query: highlightText))
                        .font(appSettings.fontChoice.font(size: 14 * appSettings.fontScale, relativeTo: .caption))
                        .foregroundStyle(AtlassianTheme.mutedText)
                        .lineLimit(2)
                } else if !item.activitySummary.isEmpty {
                    Text(item.activitySummary)
                        .font(appSettings.fontChoice.font(size: 14 * appSettings.fontScale, relativeTo: .caption))
                        .foregroundStyle(AtlassianTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AtlassianTheme.mutedText.opacity(0.65))
                    .padding(.top, 7)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isSelected ? AtlassianTheme.blue.opacity(0.12) : Color.clear)
    }

    private var subtitle: String {
        var pieces: [String] = []
        if let spaceName = item.spaceName, !spaceName.isEmpty {
            pieces.append(spaceName)
        }
        pieces.append(item.typeLabel)
        if let authorName = item.authorName, !authorName.isEmpty {
            pieces.append(authorName)
        }
        return pieces.joined(separator: " | ")
    }

    private var avatarTint: Color {
        item.origin == .popular ? Color(hex: 0xA15C00) : AtlassianTheme.mutedText
    }
}

struct TagView: View {
    @EnvironmentObject private var appSettings: AppSettings

    let text: String

    var body: some View {
        Text(text)
            .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
            .foregroundStyle(AtlassianTheme.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AtlassianTheme.blue.opacity(0.10), in: Capsule())
    }
}

enum ContentGrouper {
    static func group(items: [ContentItem]) -> [ContentDateSection] {
        var today: [ContentItem] = []
        var thisMonth: [ContentItem] = []
        var older: [ContentItem] = []
        var undated: [ContentItem] = []

        let calendar = Calendar.current
        let now = Date()
        for item in items {
            guard let date = item.date else {
                undated.append(item)
                continue
            }
            if calendar.isDateInToday(date) {
                today.append(item)
            } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
                thisMonth.append(item)
            } else {
                older.append(item)
            }
        }

        return [
            ContentDateSection(id: "today", title: "Today", items: today),
            ContentDateSection(id: "month", title: "This month", items: thisMonth),
            ContentDateSection(id: "older", title: "More than a month ago", items: older),
            ContentDateSection(id: "undated", title: "Earlier", items: undated)
        ].filter { !$0.items.isEmpty }
    }
}

@MainActor
final class SpacesViewModel: ObservableObject {
    @Published private(set) var spaces: [ConfluenceSpace] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?

    private let pageSize = 50
    private var nextStart = 0

    func load(client: ConfluenceClient?, force: Bool = false) async {
        guard let client else { return }
        guard force || (!isLoading && spaces.isEmpty) else { return }
        isLoading = true
        errorMessage = nil
        nextStart = 0
        hasMore = true

        do {
            let page = try await client.fetchSpaces(start: nextStart, limit: pageSize, cachePolicy: force ? .reloadIgnoringCache : .useCache)
            spaces = page
            nextStart = page.count
            hasMore = page.count >= pageSize
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMoreIfNeeded(space: ConfluenceSpace?, client: ConfluenceClient?) async {
        guard let client, hasMore, !isLoading, !isLoadingMore else { return }
        guard let space else {
            await loadMore(client: client)
            return
        }
        guard spaces.suffix(8).contains(where: { $0.key == space.key }) else { return }
        await loadMore(client: client)
    }

    private func loadMore(client: ConfluenceClient) async {
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await client.fetchSpaces(start: nextStart, limit: pageSize)
            let existingKeys = Set(spaces.map(\.key))
            let newSpaces = page.filter { !existingKeys.contains($0.key) }
            spaces.append(contentsOf: newSpaces)
            nextStart += page.count
            hasMore = page.count >= pageSize && !newSpaces.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SpacesView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = SpacesViewModel()
    let refreshToken: Int

    init(refreshToken: Int = 0) {
        self.refreshToken = refreshToken
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.spaces.isEmpty {
                ProgressView()
                    .tint(AtlassianTheme.blue)
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else if let errorMessage = viewModel.errorMessage, viewModel.spaces.isEmpty {
                EmptyStateView(icon: "folder.badge.questionmark", title: "空间加载失败", message: errorMessage)
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else if viewModel.spaces.isEmpty {
                EmptyStateView(icon: "folder", title: "暂无空间", message: "当前账号没有可见空间")
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(viewModel.spaces, id: \.key) { space in
                        NavigationLink {
                            SpaceContentView(space: space)
                        } label: {
                            SpaceRow(space: space)
                        }
                        .listRowBackground(AtlassianTheme.background)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreIfNeeded(space: space, client: sessionStore.client)
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView().tint(AtlassianTheme.blue)
                            Spacer()
                        }
                        .listRowBackground(AtlassianTheme.background)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Spaces")
                        .font(.system(size: 21, weight: .semibold))
                        .textCase(nil)
                        .foregroundStyle(AtlassianTheme.mutedText)
                        .padding(.top, 16)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AtlassianTheme.background)
        .navigationTitle("Spaces")
        .inlineNavigationTitle()
        .liquidNavigationChrome()
        .refreshable {
            await viewModel.load(client: sessionStore.client, force: true)
        }
        .task {
            await viewModel.load(client: sessionStore.client, force: refreshToken > 0)
        }
    }
}

struct SpaceRow: View {
    @EnvironmentObject private var appSettings: AppSettings

    let space: ConfluenceSpace

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(name: space.key, tint: AtlassianTheme.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(appSettings.fontChoice == .system ? .system(size: 18, weight: .semibold) : appSettings.fontChoice.font(size: 18 * appSettings.fontScale, relativeTo: .headline))
                    .foregroundStyle(AtlassianTheme.text)
                    .lineLimit(2)
                Text(space.key)
                    .font(appSettings.subheadlineFont)
                    .foregroundStyle(AtlassianTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }
}

@MainActor
final class SpaceContentViewModel: ObservableObject {
    let space: ConfluenceSpace
    let parent: ContentItem?

    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?

    private let pageSize = 30
    private var nextStart = 0

    init(space: ConfluenceSpace, parent: ContentItem? = nil) {
        self.space = space
        self.parent = parent
    }

    var title: String {
        parent?.title ?? space.name
    }

    var emptyTitle: String {
        parent == nil ? "暂无目录" : "暂无下级页面"
    }

    var emptyMessage: String {
        parent == nil ? "这个空间里还没有可见的根页面" : "这个页面下还没有可见的子页面"
    }

    func load(client: ConfluenceClient?, force: Bool = false) async {
        guard let client else { return }
        guard force || (!isLoading && items.isEmpty) else { return }
        isLoading = true
        errorMessage = nil
        nextStart = 0
        hasMore = true

        do {
            let page = try await fetchPage(client: client, start: nextStart)
            items = page
            nextStart = page.count
            hasMore = page.count >= pageSize
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMoreIfNeeded(currentItem item: ContentItem?, client: ConfluenceClient?) async {
        guard let client, hasMore, !isLoading, !isLoadingMore else { return }
        guard let item else {
            await loadMore(client: client)
            return
        }
        guard items.suffix(6).contains(where: { $0.id == item.id }) else { return }
        await loadMore(client: client)
    }

    private func loadMore(client: ConfluenceClient) async {
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await fetchPage(client: client, start: nextStart)
            let existingIDs = Set(items.map(\.id))
            let newItems = page.filter { !existingIDs.contains($0.id) }
            items.append(contentsOf: newItems)
            nextStart += page.count
            hasMore = page.count >= pageSize && !newItems.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchPage(client: ConfluenceClient, start: Int) async throws -> [ContentItem] {
        if let parent {
            return try await client.fetchChildPages(parentID: parent.id, start: start, limit: pageSize)
        }
        return try await client.fetchSpaceRootPages(spaceKey: space.key, start: start, limit: pageSize)
    }
}

struct SpaceContentView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel: SpaceContentViewModel

    init(space: ConfluenceSpace, parent: ContentItem? = nil) {
        _viewModel = StateObject(wrappedValue: SpaceContentViewModel(space: space, parent: parent))
    }

    var body: some View {
        List {
            if let parent = viewModel.parent {
                NavigationLink {
                    ContentDetailView(item: parent)
                        .id(parent.id)
                } label: {
                    HStack(spacing: 14) {
                        IconBadge(systemName: "doc.text", tint: AtlassianTheme.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("查看页面正文")
                                .font(.headline)
                                .foregroundStyle(AtlassianTheme.text)
                            Text(parent.title)
                                .font(.subheadline)
                                .foregroundStyle(AtlassianTheme.mutedText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(AtlassianTheme.background)
            }

            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
                    .tint(AtlassianTheme.blue)
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                EmptyStateView(icon: "doc.text.magnifyingglass", title: "内容加载失败", message: errorMessage)
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else if viewModel.items.isEmpty {
                EmptyStateView(icon: "folder", title: viewModel.emptyTitle, message: viewModel.emptyMessage)
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(viewModel.items) { item in
                        NavigationLink {
                            SpaceContentView(space: viewModel.space, parent: item)
                        } label: {
                            SpacePageRow(item: item)
                        }
                        .listRowBackground(AtlassianTheme.background)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreIfNeeded(currentItem: item, client: sessionStore.client)
                            }
                        }
                    }
                } header: {
                    Text(viewModel.parent == nil ? "页面目录" : "下级页面")
                        .font(.system(size: 21, weight: .semibold))
                        .textCase(nil)
                        .foregroundStyle(AtlassianTheme.mutedText)
                        .padding(.top, 16)
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().tint(AtlassianTheme.blue)
                        Spacer()
                    }
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AtlassianTheme.background)
        .navigationTitle(viewModel.title)
        .inlineNavigationTitle()
        .liquidNavigationChrome()
        .refreshable {
            await viewModel.load(client: sessionStore.client, force: true)
        }
        .task {
            await viewModel.load(client: sessionStore.client)
        }
    }
}

struct SpacePageRow: View {
    @EnvironmentObject private var appSettings: AppSettings

    let item: ContentItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemName: "doc.text", tint: AtlassianTheme.blue)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(appSettings.fontChoice == .system ? .system(size: 18, weight: .semibold) : appSettings.fontChoice.font(size: 18 * appSettings.fontScale, relativeTo: .headline))
                    .foregroundStyle(AtlassianTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(appSettings.subheadlineFont)
                    .foregroundStyle(AtlassianTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AtlassianTheme.mutedText.opacity(0.65))
                .padding(.top, 7)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var pieces: [String] = []
        if let authorName = item.authorName, !authorName.isEmpty {
            pieces.append(authorName)
        }
        if let dateText = item.dateText, !dateText.isEmpty {
            pieces.append(dateText)
        }
        pieces.append("点击进入下级目录")
        return pieces.joined(separator: " | ")
    }
}
