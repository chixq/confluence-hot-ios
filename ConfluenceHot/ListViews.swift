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
    @ObservedObject var viewModel: ContentFeedViewModel
    @Binding var selectedItem: ContentItem?
    let compactNavigation: Bool

    var body: some View {
        List {
            Section {
                SectionHeader(title: viewModel.kind.title, subtitle: viewModel.kind.subtitle)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                        .tint(AtlassianTheme.blue)
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if let errorMessage = viewModel.errorMessage {
                    EmptyStateView(icon: "exclamationmark.triangle", title: "加载失败", message: errorMessage)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if viewModel.items.isEmpty {
                    EmptyStateView(icon: "tray", title: viewModel.kind.emptyTitle, message: "换个时间刷新看看")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.items) { item in
                        row(for: item)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
    private func row(for item: ContentItem) -> some View {
        if compactNavigation {
            NavigationLink {
                ContentDetailView(item: item)
                    .id(item.id)
            } label: {
                ContentRow(item: item, isSelected: false)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                selectedItem = item
            } label: {
                ContentRow(item: item, isSelected: selectedItem?.id == item.id)
            }
            .buttonStyle(.plain)
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var query = ""
    @State private var items: [ContentItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            SectionHeader(title: "搜索", subtitle: sessionStore.configuration?.baseURL.host)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AtlassianTheme.mutedText)
                    TextField("标题或正文", text: $query)
                        .submitLabel(.search)
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
                .padding(12)
                .liquidGlassPanel(cornerRadius: 22)

                Button {
                    Task { await search() }
                } label: {
                    Label("搜索", systemImage: "arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isLoading)
            }
            .padding(.horizontal, 16)

            LazyVStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(AtlassianTheme.blue)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let errorMessage {
                    EmptyStateView(icon: "exclamationmark.triangle", title: "搜索失败", message: errorMessage)
                } else {
                    ForEach(items) { item in
                        NavigationLink {
                            ContentDetailView(item: item)
                                .id(item.id)
                        } label: {
                            ContentRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(LiquidBackground())
        .inlineNavigationTitle()
        .liquidNavigationChrome()
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconBackground)
                Image(systemName: item.type.lowercased().contains("blog") ? "text.bubble" : "doc.text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconForeground)
            }
            .frame(width: 42, height: 42)

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

                if let authorName = item.authorName, !authorName.isEmpty {
                    Text(authorName)
                        .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
                        .foregroundStyle(AtlassianTheme.mutedText)
                        .lineLimit(1)
                }

                if !item.activitySummary.isEmpty {
                    Text(item.activitySummary)
                        .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
                        .foregroundStyle(AtlassianTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AtlassianTheme.mutedText)
                .padding(.top, 5)
        }
        .padding(14)
        .liquidGlassPanel(cornerRadius: 24, isSelected: isSelected)
    }

    private var iconBackground: Color {
        item.origin == .popular ? AtlassianTheme.yellow.opacity(0.18) : AtlassianTheme.blue.opacity(0.12)
    }

    private var iconForeground: Color {
        item.origin == .popular ? Color(hex: 0x974F0C) : AtlassianTheme.blue
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
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.32), lineWidth: 0.7))
    }
}
