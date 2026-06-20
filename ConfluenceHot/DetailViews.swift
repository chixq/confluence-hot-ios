import SwiftUI
import WebKit

struct ContentDetailView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.openURL) private var openURL

    let item: ContentItem
    @State private var detail: ContentDetail?
    @State private var comments: [CommentItem] = []
    @State private var isLoading = false
    @State private var isLoadingComments = false
    @State private var isPostingComment = false
    @State private var errorMessage: String?
    @State private var commentsErrorMessage: String?
    @State private var replyText = ""
    @State private var webContentHeight: CGFloat = 560

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    TagView(text: item.typeLabel)
                    Text(detail?.title ?? item.title)
                        .font(appSettings.titleFont)
                        .foregroundStyle(AtlassianTheme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.activitySummary.isEmpty {
                        Text(item.activitySummary)
                            .font(appSettings.subheadlineFont)
                            .foregroundStyle(AtlassianTheme.mutedText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                if isLoading && detail == nil {
                    ProgressView()
                        .tint(AtlassianTheme.blue)
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if let errorMessage {
                    EmptyStateView(icon: "doc.text.magnifyingglass", title: "正文加载失败", message: errorMessage)
                } else if let detail {
                    HTMLContentView(
                        html: wrappedHTML(detail.renderedHTML),
                        baseURL: sessionStore.configuration?.baseURL,
                        contentHeight: $webContentHeight
                    )
                        .frame(height: webContentHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .liquidGlassPanel(cornerRadius: 24)
                        .padding(.horizontal, 16)
                }

                CommentSectionView(
                    comments: comments,
                    isLoading: isLoadingComments,
                    isPosting: isPostingComment,
                    errorMessage: commentsErrorMessage,
                    replyText: $replyText,
                    onReload: { await loadComments() },
                    onSubmit: { await submitComment() }
                )
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 28)
        }
        .background(LiquidBackground())
        .inlineNavigationTitle()
        .liquidNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let baseURL = sessionStore.configuration?.baseURL,
                   let url = item.webURL(baseURL: baseURL) {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .task(id: item.id) {
            resetForCurrentItem()
            await load()
        }
    }

    private func resetForCurrentItem() {
        detail = nil
        comments = []
        errorMessage = nil
        commentsErrorMessage = nil
        replyText = ""
        webContentHeight = 560
    }

    private func load() async {
        guard let client = sessionStore.client else { return }
        isLoading = true
        isLoadingComments = true
        errorMessage = nil
        commentsErrorMessage = nil

        do {
            async let detailTask = client.fetchDetail(id: item.id)
            async let commentsTask = client.fetchComments(contentID: item.id)
            detail = try await detailTask
            comments = try await commentsTask
        } catch {
            if detail == nil {
                errorMessage = error.localizedDescription
            } else {
                commentsErrorMessage = error.localizedDescription
            }
        }

        isLoading = false
        isLoadingComments = false
    }

    private func loadComments() async {
        guard let client = sessionStore.client else { return }
        isLoadingComments = true
        commentsErrorMessage = nil

        do {
            comments = try await client.fetchComments(contentID: item.id)
        } catch {
            commentsErrorMessage = error.localizedDescription
        }

        isLoadingComments = false
    }

    private func submitComment() async {
        guard let client = sessionStore.client else { return }
        isPostingComment = true
        commentsErrorMessage = nil

        do {
            let comment = try await client.postComment(contentID: item.id, containerType: detail?.type ?? item.type, text: replyText)
            replyText = ""
            comments.append(comment)
            await loadComments()
        } catch {
            commentsErrorMessage = error.localizedDescription
        }

        isPostingComment = false
    }

    private func wrappedHTML(_ body: String) -> String {
        let background = appSettings.appearanceMode == .dark ? "#1B1F29" : "#FFFFFF"
        let text = appSettings.appearanceMode == .dark ? "#F4F5F7" : "#172B4D"
        let muted = appSettings.appearanceMode == .dark ? "#A5ADBA" : "#42526E"
        let border = appSettings.appearanceMode == .dark ? "#303849" : "#DFE1E6"
        let codeBackground = appSettings.appearanceMode == .dark ? "#242936" : "#F4F5F7"

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          <style>
            :root { color-scheme: \(appSettings.appearanceMode == .dark ? "dark" : "light"); }
            html, body { margin: 0; padding: 0; background: \(background); }
            body {
              color: \(text);
              font-family: \(appSettings.fontChoice.cssFamily);
              font-size: \(Int(16 * appSettings.fontScale))px;
              line-height: 1.52;
              padding: 18px;
              word-wrap: break-word;
              overflow-wrap: anywhere;
            }
            a { color: #0052CC; text-decoration: none; }
            img, video { max-width: 100%; height: auto; border-radius: 6px; }
            .table-scroll {
              width: 100%;
              overflow-x: auto;
              -webkit-overflow-scrolling: touch;
              margin: 12px 0;
              border: 1px solid \(border);
              border-radius: 6px;
            }
            table {
              border-collapse: collapse;
              min-width: 100%;
              width: max-content;
              max-width: none;
              table-layout: auto;
              margin: 0;
            }
            th, td {
              border: 1px solid \(border);
              padding: 9px 10px;
              vertical-align: top;
              white-space: normal;
              min-width: 96px;
            }
            th { background: \(codeBackground); font-weight: 600; }
            pre, code {
              background: \(codeBackground);
              border-radius: 6px;
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            }
            pre { padding: 12px; overflow-x: auto; }
            blockquote {
              border-left: 3px solid #0052CC;
              margin: 12px 0;
              padding: 4px 0 4px 12px;
              color: \(muted);
            }
          </style>
        </head>
        <body>\(body)
          <script>
            document.querySelectorAll('table').forEach(function(table) {
              if (!table.parentElement.classList.contains('table-scroll')) {
                var wrapper = document.createElement('div');
                wrapper.className = 'table-scroll';
                table.parentNode.insertBefore(wrapper, table);
                wrapper.appendChild(table);
              }
            });
          </script>
        </body>
        </html>
        """
    }
}

struct CommentSectionView: View {
    @EnvironmentObject private var appSettings: AppSettings

    let comments: [CommentItem]
    let isLoading: Bool
    let isPosting: Bool
    let errorMessage: String?
    @Binding var replyText: String
    let onReload: () async -> Void
    let onSubmit: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("回复")
                    .font(appSettings.titleFont)
                    .foregroundStyle(AtlassianTheme.text)
                Spacer()
                Button {
                    Task { await onReload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(appSettings.subheadlineFont)
                    .foregroundStyle(AtlassianTheme.red)
            }

            if isLoading && comments.isEmpty {
                ProgressView()
                    .tint(AtlassianTheme.blue)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if comments.isEmpty {
                Text("暂无回复")
                    .font(appSettings.subheadlineFont)
                    .foregroundStyle(AtlassianTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .liquidGlassPanel(cornerRadius: 22)
            } else {
                ForEach(comments) { comment in
                    CommentRow(comment: comment)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("添加回复")
                    .font(appSettings.headlineFont)
                    .foregroundStyle(AtlassianTheme.text)

                TextEditor(text: $replyText)
                    .font(appSettings.baseFont)
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.34), lineWidth: 1)
                    )

                Button {
                    Task { await onSubmit() }
                } label: {
                    if isPosting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("发送回复", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isPosting || replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .liquidGlassPanel(cornerRadius: 24)
        }
    }
}

struct CommentRow: View {
    @EnvironmentObject private var appSettings: AppSettings
    let comment: CommentItem
    @State private var contentHeight: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(comment.authorName)
                    .font(appSettings.headlineFont)
                    .foregroundStyle(AtlassianTheme.text)
                Spacer()
                if let dateText = comment.dateText {
                    Text(dateText)
                        .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
                        .foregroundStyle(AtlassianTheme.mutedText)
                }
            }

            HTMLContentView(
                html: commentHTML(comment.html),
                baseURL: nil,
                contentHeight: $contentHeight
            )
            .frame(height: contentHeight)
        }
        .padding(14)
        .liquidGlassPanel(cornerRadius: 24)
    }

    private func commentHTML(_ body: String) -> String {
        let background = appSettings.appearanceMode == .dark ? "#1B1F29" : "#FFFFFF"
        let text = appSettings.appearanceMode == .dark ? "#F4F5F7" : "#172B4D"
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body { margin: 0; padding: 0; background: \(background); color: \(text); }
            body {
              font-family: \(appSettings.fontChoice.cssFamily);
              font-size: \(Int(15 * appSettings.fontScale))px;
              line-height: 1.5;
              overflow-wrap: anywhere;
            }
            p { margin: 0 0 8px 0; }
            a { color: #0052CC; text-decoration: none; }
            img { max-width: 100%; height: auto; }
          </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}

#if os(iOS)
struct HTMLContentView: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    @Binding var contentHeight: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        uiView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLContentView
        var loadedHTML: String?

        init(parent: HTMLContentView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                let height: CGFloat
                if let value = result as? CGFloat {
                    height = value
                } else if let value = result as? Double {
                    height = CGFloat(value)
                } else {
                    height = 560
                }

                DispatchQueue.main.async {
                    self.parent.contentHeight = max(560, height)
                }
            }
        }
    }
}
#else
struct HTMLContentView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    @Binding var contentHeight: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        nsView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLContentView
        var loadedHTML: String?

        init(parent: HTMLContentView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                let height: CGFloat
                if let value = result as? CGFloat {
                    height = value
                } else if let value = result as? Double {
                    height = CGFloat(value)
                } else {
                    height = 560
                }

                DispatchQueue.main.async {
                    self.parent.contentHeight = max(560, height)
                }
            }
        }
    }
}
#endif
