import SwiftUI

enum FeedKind {
    case recent
    case popular

    var title: String {
        switch self {
        case .recent:
            return "最新"
        case .popular:
            return "热门"
        }
    }

    var subtitle: String {
        switch self {
        case .recent:
            return "最近更新的页面和博客"
        case .popular:
            return "站点中获得更多互动的内容"
        }
    }

    var emptyTitle: String {
        switch self {
        case .recent:
            return "暂无更新"
        case .popular:
            return "暂无热门内容"
        }
    }
}

@MainActor
final class ContentFeedViewModel: ObservableObject {
    let kind: FeedKind

    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var lastLoadedAt: Date?

    init(kind: FeedKind) {
        self.kind = kind
    }

    func load(client: ConfluenceClient?, force: Bool = false) async {
        guard let client else { return }
        guard force || !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            switch kind {
            case .recent:
                items = try await client.fetchRecentlyUpdated()
            case .popular:
                items = try await client.fetchPopular()
            }
            lastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: shouldUseSplit)
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
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject var viewModel: ContentFeedViewModel
    @Binding var selectedItem: ContentItem?
    let compactNavigation: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: viewModel.kind.title, subtitle: viewModel.kind.subtitle)

                if let lastLoadedAt = viewModel.lastLoadedAt {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.icloud")
                        Text("已更新 \(lastLoadedAt.formatted(date: .omitted, time: .shortened))")
                    }
                    .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
                    .foregroundStyle(AtlassianTheme.mutedText)
                    .padding(.horizontal, 22)
                    .padding(.top, -8)
                }

                content
            }
            .padding(.bottom, 28)
        }
        .background(LiquidBackground())
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

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView()
                .tint(AtlassianTheme.blue)
                .frame(maxWidth: .infinity, minHeight: 260)
                .padding(.horizontal, 16)
        } else if let errorMessage = viewModel.errorMessage {
            EmptyStateView(icon: "exclamationmark.triangle", title: "加载失败", message: errorMessage)
                .padding(.horizontal, 16)
        } else if viewModel.items.isEmpty {
            EmptyStateView(icon: "tray", title: viewModel.kind.emptyTitle, message: "换个时间刷新看看")
                .padding(.horizontal, 16)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    row(for: item)
                    if index < viewModel.items.count - 1 {
                        Divider()
                            .padding(.leading, 72)
                            .padding(.trailing, 12)
                    }
                }
            }
            .padding(8)
            .liquidGlassPanel(cornerRadius: 30)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func row(for item: ContentItem) -> some View {
        if compactNavigation {
            NavigationLink {
                ContentDetailView(item: item)
                    .id(item.id)
            } label: {
                ContentRow(item: item, isSelected: false, showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                selectedItem = item
            } label: {
                ContentRow(item: item, isSelected: selectedItem?.id == item.id, showsChevron: false)
            }
            .buttonStyle(.plain)
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @State private var query = ""
    @State private var items: [ContentItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "搜索", subtitle: sessionStore.configuration?.baseURL.host)

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AtlassianTheme.mutedText)
                        TextField("标题或正文", text: $query)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .onSubmit {
                                Task { await search() }
                            }
                        if !query.isEmpty {
                            Button {
                                query = ""
                                items = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AtlassianTheme.mutedText)
                            }
                        }
                    }
                    .font(appSettings.baseFont)
                    .liquidField()

                    Button {
                        Task { await search() }
                    } label: {
                        Label("搜索", systemImage: "arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)

                searchResults
            }
            .padding(.bottom, 28)
        }
        .background(LiquidBackground())
        .inlineNavigationTitle()
        .liquidNavigationChrome()
    }

    @ViewBuilder
    private var searchResults: some View {
        if isLoading {
            ProgressView()
                .tint(AtlassianTheme.blue)
                .frame(maxWidth: .infinity, minHeight: 180)
                .padding(.horizontal, 16)
        } else if let errorMessage {
            EmptyStateView(icon: "exclamationmark.triangle", title: "搜索失败", message: errorMessage)
                .padding(.horizontal, 16)
        } else if items.isEmpty && !query.isEmpty {
            EmptyStateView(icon: "magnifyingglass", title: "暂无结果", message: "换个关键词试试")
                .padding(.horizontal, 16)
        } else if items.isEmpty {
            EmptyStateView(icon: "text.magnifyingglass", title: "查找 Confluence 内容", message: "输入标题、正文关键词或页面主题")
                .padding(.horizontal, 16)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        ContentDetailView(item: item)
                            .id(item.id)
                    } label: {
                        ContentRow(item: item, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 72)
                            .padding(.trailing, 12)
                    }
                }
            }
            .padding(8)
            .liquidGlassPanel(cornerRadius: 30)
            .padding(.horizontal, 16)
        }
    }

    private func search() async {
        guard let client = sessionStore.client else { return }
        isLoading = true
        errorMessage = nil

        do {
            items = try await client.search(query)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct ContentRow: View {
    @EnvironmentObject private var appSettings: AppSettings

    let item: ContentItem
    var isSelected = false
    var showsChevron = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemName: iconName, tint: iconForeground)

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(appSettings.headlineFont)
                    .foregroundStyle(AtlassianTheme.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    TagView(text: item.typeLabel)
                    if let spaceName = item.spaceName, !spaceName.isEmpty {
                        Text(spaceName)
                            .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
                            .foregroundStyle(AtlassianTheme.mutedText)
                        .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    if let authorName = item.authorName, !authorName.isEmpty {
                        Label(authorName, systemImage: "person.crop.circle")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }

                    if !item.activitySummary.isEmpty {
                        Text(item.activitySummary)
                            .lineLimit(1)
                    }
                }
                .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
                .foregroundStyle(AtlassianTheme.mutedText)

                if let excerpt = item.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
                        .foregroundStyle(AtlassianTheme.mutedText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AtlassianTheme.mutedText.opacity(0.75))
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(isSelected ? AtlassianTheme.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var iconName: String {
        if item.origin == .popular {
            return "flame.fill"
        }
        return item.type.lowercased().contains("blog") ? "text.bubble.fill" : "doc.text.fill"
    }

    private var iconForeground: Color {
        item.origin == .popular ? Color(hex: 0xA15C00) : AtlassianTheme.blue
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
