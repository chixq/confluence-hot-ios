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

struct ContentFeedView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let kind: FeedKind

    @State private var items: [ContentItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            SectionHeader(title: kind.title, subtitle: kind.subtitle)

            LazyVStack(spacing: 10) {
                if isLoading && items.isEmpty {
                    ProgressView()
                        .tint(AtlassianTheme.blue)
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if let errorMessage {
                    EmptyStateView(icon: "exclamationmark.triangle", title: "加载失败", message: errorMessage)
                } else if items.isEmpty {
                    EmptyStateView(icon: "tray", title: kind.emptyTitle, message: "换个时间刷新看看")
                } else {
                    ForEach(items) { item in
                        NavigationLink {
                            ContentDetailView(item: item)
                        } label: {
                            ContentRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(AtlassianTheme.background)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
    }

    private func load() async {
        guard let client = sessionStore.client else { return }
        isLoading = true
        errorMessage = nil

        do {
            switch kind {
            case .recent:
                items = try await client.fetchRecentlyUpdated()
            case .popular:
                items = try await client.fetchPopular()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
                .background(AtlassianTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
        .background(AtlassianTheme.background)
        .inlineNavigationTitle()
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
    let item: ContentItem

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
                    .font(.headline)
                    .foregroundStyle(AtlassianTheme.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    TagView(text: item.typeLabel)
                    if let spaceName = item.spaceName, !spaceName.isEmpty {
                        Text(spaceName)
                            .font(.caption)
                            .foregroundStyle(AtlassianTheme.mutedText)
                            .lineLimit(1)
                    }
                }

                if let authorName = item.authorName, !authorName.isEmpty {
                    Text(authorName)
                        .font(.caption)
                        .foregroundStyle(AtlassianTheme.mutedText)
                        .lineLimit(1)
                }

                if !item.activitySummary.isEmpty {
                    Text(item.activitySummary)
                        .font(.caption)
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
        .background(AtlassianTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AtlassianTheme.border, lineWidth: 0.5)
        )
    }

    private var iconBackground: Color {
        item.origin == .popular ? AtlassianTheme.yellow.opacity(0.18) : AtlassianTheme.blue.opacity(0.12)
    }

    private var iconForeground: Color {
        item.origin == .popular ? Color(hex: 0x974F0C) : AtlassianTheme.blue
    }
}

struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AtlassianTheme.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AtlassianTheme.blue.opacity(0.10))
            .clipShape(Capsule())
    }
}
