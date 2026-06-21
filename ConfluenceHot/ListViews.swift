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
    @StateObject private var viewModel: ContentFeedViewModel
    @State private var selectedItem: ContentItem?

    init(kind: FeedKind) {
        self.kind = kind
        _viewModel = StateObject(wrappedValue: ContentFeedViewModel(kind: kind))
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height && proxy.size.width >= 700
            let shouldUseSplit = appSettings.landscapeSplitEnabled && isLandscape

            Group {
                if shouldUseSplit {
                    NavigationSplitView {
                        FeedListView(viewModel: viewModel, selectedItem: $selectedItem, compactNavigation: false)
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
                        await viewModel.load(client: sessionStore.client)
                        reconcileSelection()
                    }
                    .onReceive(viewModel.$items) { _ in
                        reconcileSelection()
                    }
                } else {
                    NavigationStack {
                        FeedListView(viewModel: viewModel, selectedItem: $selectedItem, compactNavigation: true)
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

    var body: some View {
        List {
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
            await viewModel.load(client: sessionStore.client)
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
final class SearchViewModel: ObservableObject {
    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published var errorMessage: String?

    private let pageSize = 30
    private var nextStart = 0
    private var contentQuery = ""
    private var authorQuery = ""

    func search(client: ConfluenceClient?, content: String, author: String) async {
        guard let client else { return }
        contentQuery = content.trimmingCharacters(in: .whitespacesAndNewlines)
        authorQuery = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contentQuery.isEmpty || !authorQuery.isEmpty else {
            items = []
            hasMore = false
            return
        }

        isLoading = true
        errorMessage = nil
        nextStart = 0

        do {
            let page = try await client.searchContent(contentQuery: contentQuery, authorQuery: authorQuery, start: nextStart, limit: pageSize)
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
            let page = try await client.searchContent(contentQuery: contentQuery, authorQuery: authorQuery, start: nextStart, limit: pageSize)
            let existingIDs = Set(items.map(\.id))
            let newItems = page.filter { !existingIDs.contains($0.id) }
            items.append(contentsOf: newItems)
            nextStart += page.count
            hasMore = page.count >= pageSize && !newItems.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @StateObject private var viewModel = SearchViewModel()
    @State private var contentQuery = ""
    @State private var authorQuery = ""

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
            } else if viewModel.items.isEmpty && (!contentQuery.isEmpty || !authorQuery.isEmpty) {
                EmptyStateView(icon: "magnifyingglass", title: "暂无结果", message: "换个关键词试试")
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else if viewModel.items.isEmpty {
                EmptyStateView(icon: "text.magnifyingglass", title: "查找 Confluence 内容", message: "左侧搜作者，右侧搜标题或正文")
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(viewModel.items) { item in
                        NavigationLink {
                            ContentDetailView(item: item)
                                .id(item.id)
                        } label: {
                            ContentRow(item: item, highlightText: contentQuery, highlightAuthor: authorQuery)
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
    }

    private var searchFields: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                authorField
                contentField
            }
            VStack(spacing: 12) {
                authorField
                contentField
            }
        }
        .padding(.vertical, 8)
    }

    private var authorField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("作者", systemImage: "person.crop.circle")
                .font(appSettings.subheadlineFont)
                .foregroundStyle(AtlassianTheme.mutedText)
            TextField("作者 username", text: $authorQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { runSearch() }
                .liquidField()
        }
    }

    private var contentField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("内容", systemImage: "doc.text.magnifyingglass")
                .font(appSettings.subheadlineFont)
                .foregroundStyle(AtlassianTheme.mutedText)
            HStack(spacing: 8) {
                TextField("标题或正文关键词", text: $contentQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                Button {
                    runSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .disabled(contentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && authorQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .liquidField()
        }
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
            await viewModel.search(client: sessionStore.client, content: contentQuery, author: authorQuery)
        }
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
            await viewModel.load(client: sessionStore.client)
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

    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?

    private let pageSize = 30
    private var nextStart = 0

    init(space: ConfluenceSpace) {
        self.space = space
    }

    func load(client: ConfluenceClient?, force: Bool = false) async {
        guard let client else { return }
        guard force || (!isLoading && items.isEmpty) else { return }
        isLoading = true
        errorMessage = nil
        nextStart = 0
        hasMore = true

        do {
            let page = try await client.fetchSpaceContent(spaceKey: space.key, start: nextStart, limit: pageSize, cachePolicy: force ? .reloadIgnoringCache : .useCache)
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
            let page = try await client.fetchSpaceContent(spaceKey: space.key, start: nextStart, limit: pageSize)
            let existingIDs = Set(items.map(\.id))
            let newItems = page.filter { !existingIDs.contains($0.id) }
            items.append(contentsOf: newItems)
            nextStart += page.count
            hasMore = page.count >= pageSize && !newItems.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SpaceContentView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel: SpaceContentViewModel

    init(space: ConfluenceSpace) {
        _viewModel = StateObject(wrappedValue: SpaceContentViewModel(space: space))
    }

    var body: some View {
        List {
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
                EmptyStateView(icon: "doc", title: "暂无内容", message: "这个空间里还没有可见页面或博客")
                    .listRowBackground(AtlassianTheme.background)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(ContentGrouper.group(items: viewModel.items)) { section in
                    Section {
                        ForEach(section.items) { item in
                            NavigationLink {
                                ContentDetailView(item: item)
                                    .id(item.id)
                            } label: {
                                ContentRow(item: item)
                            }
                            .listRowBackground(AtlassianTheme.background)
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
        .navigationTitle(viewModel.space.name)
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
