import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ContentDetailView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    let item: ContentItem
    @State private var detail: ContentDetail?
    @State private var renderedHTML = ""
    @State private var comments: [CommentItem] = []
    @State private var isLoading = false
    @State private var isLoadingComments = false
    @State private var isPostingComment = false
    @State private var isPerformingOperation = false
    @State private var errorMessage: String?
    @State private var commentsErrorMessage: String?
    @State private var operationMessage: String?
    @State private var replyText = ""
    @State private var webContentHeight: CGFloat = 420
    @State private var detailZoom = 1.0
    @State private var exportedHTMLFile: ExportedHTMLFile?
    @State private var exportErrorMessage: String?
    @State private var isShowingEditor = false
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DetailHeaderView(item: item, title: detail?.title ?? item.title)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)

                if isLoading && detail == nil {
                    ProgressView()
                        .tint(AtlassianTheme.blue)
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if let errorMessage {
                    EmptyStateView(icon: "doc.text.magnifyingglass", title: "正文加载失败", message: errorMessage)
                } else if let detail {
                    HTMLContentView(
                        html: wrappedHTML(renderedHTML.isEmpty ? detail.renderedHTML : renderedHTML),
                        baseURL: sessionStore.configuration?.baseURL,
                        contentHeight: $webContentHeight,
                        minimumHeight: 420
                    )
                        .frame(height: webContentHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(6)
                        .liquidGlassPanel(cornerRadius: 30)
                        .padding(.horizontal, 16)
                }

                if let exportErrorMessage {
                    Text(exportErrorMessage)
                        .font(appSettings.subheadlineFont)
                        .foregroundStyle(AtlassianTheme.red)
                        .padding(.horizontal, 16)
                }

                if let operationMessage {
                    Text(operationMessage)
                        .font(appSettings.subheadlineFont)
                        .foregroundStyle(AtlassianTheme.mutedText)
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
                Menu {
                    Button {
                        prepareEdit()
                    } label: {
                        Label("修改文章", systemImage: "square.and.pencil")
                    }
                    .disabled(detail?.storageHTML == nil || isPerformingOperation)

                    Button {
                        zoomIn()
                    } label: {
                        Label("放大正文", systemImage: "plus.magnifyingglass")
                    }

                    Button {
                        zoomOut()
                    } label: {
                        Label("缩小正文", systemImage: "minus.magnifyingglass")
                    }

                    Button {
                        copyLink()
                    } label: {
                        Label("复制链接", systemImage: "link")
                    }

                    Button {
                        copyHTML()
                    } label: {
                        Label("复制 HTML", systemImage: "doc.on.doc")
                    }
                    .disabled(detail == nil)

                    Button {
                        Task { await copyAsNewPage() }
                    } label: {
                        Label("复制为副本", systemImage: "plus.square.on.square")
                    }
                    .disabled(detail == nil || isPerformingOperation)

                    if let baseURL = sessionStore.configuration?.baseURL,
                       let url = item.webURL(baseURL: baseURL) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("浏览器打开", systemImage: "safari")
                        }
                    }

                    Button {
                        exportHTML()
                    } label: {
                        Label("导出 HTML", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("删除文章", systemImage: "trash")
                    }
                    .disabled(isPerformingOperation)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        #if os(iOS)
        .sheet(item: $exportedHTMLFile) { file in
            ActivityView(activityItems: [file.url])
        }
        #endif
        .sheet(isPresented: $isShowingEditor) {
            if let detail {
                ContentEditorSheet(
                    title: detail.title,
                    storageHTML: detail.storageHTML ?? "",
                    isSaving: isPerformingOperation,
                    onCancel: { isShowingEditor = false },
                    onSave: { title, storageHTML in
                        Task { await updateArticle(title: title, storageHTML: storageHTML) }
                    }
                )
            }
        }
        .confirmationDialog("删除这篇文章？", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task { await deleteArticle() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后需要在 Confluence Web 中从回收站恢复。")
        }
        .task(id: item.id) {
            resetForCurrentItem()
            await load()
        }
    }

    private func resetForCurrentItem() {
        detail = nil
        renderedHTML = ""
        comments = []
        errorMessage = nil
        commentsErrorMessage = nil
        operationMessage = nil
        replyText = ""
        webContentHeight = 420
        detailZoom = 1.0
        exportErrorMessage = nil
    }

    private func load() async {
        guard let client = sessionStore.client else { return }
        isLoading = true
        isLoadingComments = true
        errorMessage = nil
        commentsErrorMessage = nil

        do {
            let fetchedDetail = try await client.fetchDetail(id: item.id)
            async let commentsTask = client.fetchComments(contentID: item.id)
            detail = fetchedDetail
            renderedHTML = await client.inlineAuthenticatedImages(in: fetchedDetail.renderedHTML, baseURL: sessionStore.configuration?.baseURL)
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
            comments = try await client.fetchComments(contentID: item.id, cachePolicy: .reloadIgnoringCache)
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

    private func prepareEdit() {
        guard detail?.storageHTML != nil else {
            operationMessage = "当前文章缺少可编辑正文"
            return
        }
        isShowingEditor = true
    }

    private func updateArticle(title: String, storageHTML: String) async {
        guard let client = sessionStore.client, let detail else { return }
        isPerformingOperation = true
        operationMessage = nil
        do {
            let updated = try await client.updateContent(
                id: detail.id,
                type: detail.type,
                title: title,
                storageHTML: storageHTML,
                versionNumber: detail.nextVersionNumber
            )
            self.detail = updated
            renderedHTML = await client.inlineAuthenticatedImages(in: updated.renderedHTML, baseURL: sessionStore.configuration?.baseURL)
            operationMessage = "文章已更新"
            isShowingEditor = false
        } catch {
            operationMessage = "更新失败：\(error.localizedDescription)"
        }
        isPerformingOperation = false
    }

    private func deleteArticle() async {
        guard let client = sessionStore.client else { return }
        isPerformingOperation = true
        operationMessage = nil
        do {
            try await client.deleteContent(id: item.id)
            operationMessage = "文章已删除"
            dismiss()
        } catch {
            operationMessage = "删除失败：\(error.localizedDescription)"
        }
        isPerformingOperation = false
    }

    private func copyAsNewPage() async {
        guard let client = sessionStore.client, let detail else { return }
        isPerformingOperation = true
        operationMessage = nil
        do {
            _ = try await client.copyContent(detail: detail)
            operationMessage = "已复制为新文章"
        } catch {
            operationMessage = "复制失败：\(error.localizedDescription)"
        }
        isPerformingOperation = false
    }

    private func zoomIn() {
        detailZoom = min(1.6, detailZoom + 0.1)
        webContentHeight = 420
    }

    private func zoomOut() {
        detailZoom = max(0.75, detailZoom - 0.1)
        webContentHeight = 420
    }

    private func copyLink() {
        guard let baseURL = sessionStore.configuration?.baseURL,
              let url = item.webURL(baseURL: baseURL) else {
            operationMessage = "当前文章没有可复制链接"
            return
        }
        setClipboard(url.absoluteString)
        operationMessage = "链接已复制"
    }

    private func copyHTML() {
        guard let detail else { return }
        setClipboard(detail.storageHTML ?? renderedHTML)
        operationMessage = "HTML 已复制"
    }

    private func exportHTML() {
        guard let detail else {
            exportErrorMessage = "正文尚未加载完成"
            return
        }

        do {
            let html = exportedHTML(detail: detail, bodyHTML: renderedHTML.isEmpty ? detail.renderedHTML : renderedHTML, comments: comments)
            let fileName = "\(safeFilename(detail.title)).html"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try html.write(to: url, atomically: true, encoding: .utf8)
            exportedHTMLFile = ExportedHTMLFile(url: url)
            exportErrorMessage = nil
        } catch {
            exportErrorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func exportedHTML(detail: ContentDetail, bodyHTML: String, comments: [CommentItem]) -> String {
        let commentHTML = comments.map { comment in
            """
            <section class="comment">
              <div class="comment-meta">\(htmlEscaped(comment.authorName)) \(htmlEscaped(comment.dateText ?? ""))</div>
              <div>\(comment.html)</div>
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(htmlEscaped(detail.title))</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; line-height: 1.62; margin: 32px auto; max-width: 880px; padding: 0 18px; color: #172B4D; }
            h1 { line-height: 1.2; }
            img, video { max-width: 100%; height: auto; border-radius: 8px; }
            table { border-collapse: collapse; min-width: 100%; }
            th, td { border: 1px solid #DFE1E6; padding: 8px 10px; vertical-align: top; }
            pre { overflow-x: auto; background: #F4F5F7; padding: 12px; border-radius: 8px; }
            .meta, .comment-meta { color: #626F86; font-size: 14px; }
            .comments { margin-top: 36px; border-top: 1px solid #DFE1E6; padding-top: 20px; }
            .comment { margin: 16px 0; padding-bottom: 16px; border-bottom: 1px solid #F1F2F4; }
          </style>
        </head>
        <body>
          <h1>\(htmlEscaped(detail.title))</h1>
          <p class="meta">\(htmlEscaped(item.activitySummary))</p>
          <article>\(bodyHTML)</article>
          <section class="comments">
            <h2>回复</h2>
            \(commentHTML.isEmpty ? "<p class=\"meta\">暂无回复</p>" : commentHTML)
          </section>
        </body>
        </html>
        """
    }

    private func safeFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Confluence-Page" : String(trimmed.prefix(80))
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func setClipboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }

    private func wrappedHTML(_ body: String) -> String {
        let text = appSettings.appearanceMode == .dark ? "#F4F5F7" : "#172B4D"
        let muted = appSettings.appearanceMode == .dark ? "#A5ADBA" : "#42526E"
        let border = appSettings.appearanceMode == .dark ? "#303849" : "#DFE1E6"
        let codeBackground = appSettings.appearanceMode == .dark ? "#242936" : "#F4F5F7"
        let tableHeader = appSettings.appearanceMode == .dark ? "#202635" : "#F8FAFD"

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          <style>
            :root { color-scheme: \(appSettings.appearanceMode == .dark ? "dark" : "light"); }
            html, body { margin: 0; padding: 0; background: transparent; }
            body {
              color: \(text);
              font-family: \(appSettings.fontChoice.cssFamily);
              font-size: \(Int(17 * appSettings.fontScale * detailZoom))px;
              line-height: 1.62;
              padding: 18px;
              word-wrap: break-word;
              overflow-wrap: anywhere;
            }
            h1, h2, h3, h4 { line-height: 1.22; margin: 22px 0 10px; }
            p { margin: 0 0 13px; }
            a { color: #0052CC; text-decoration: none; }
            img, video { max-width: 100%; height: auto; border-radius: 12px; }
            .table-scroll {
              width: 100%;
              overflow-x: auto;
              -webkit-overflow-scrolling: touch;
              margin: 14px 0;
              border: 1px solid \(border);
              border-radius: 12px;
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
            th { background: \(tableHeader); font-weight: 650; }
            pre, code {
              background: \(codeBackground);
              border-radius: 8px;
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            }
            pre { padding: 13px; overflow-x: auto; }
            blockquote {
              border-left: 3px solid #0052CC;
              margin: 12px 0;
              padding: 6px 0 6px 14px;
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

struct ExportedHTMLFile: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
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
                    .font(appSettings.fontChoice == .system ? .title3.weight(.bold) : appSettings.fontChoice.font(size: 21 * appSettings.fontScale, relativeTo: .title3))
                    .foregroundStyle(AtlassianTheme.text)
                CapsuleMetric(text: "\(comments.count)", systemName: "bubble.left.and.bubble.right.fill", tint: AtlassianTheme.teal)
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
                HStack(spacing: 10) {
                    IconBadge(systemName: "bubble.left", tint: AtlassianTheme.mutedText)
                    Text("暂无回复")
                        .font(appSettings.subheadlineFont)
                        .foregroundStyle(AtlassianTheme.mutedText)
                    Spacer()
                }
                .padding(14)
                .liquidGlassPanel(cornerRadius: 24)
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
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AtlassianTheme.separator.opacity(0.55), lineWidth: 0.8)
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
            .liquidGlassPanel(cornerRadius: 28)
        }
    }
}

struct DetailHeaderView: View {
    @EnvironmentObject private var appSettings: AppSettings

    let item: ContentItem
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TagView(text: item.typeLabel)
                if item.origin == .popular {
                    CapsuleMetric(text: "热门", systemName: "flame.fill", tint: Color(hex: 0xA15C00))
                }
            }

            Text(title)
                .font(appSettings.fontChoice == .system ? .title.weight(.bold) : appSettings.fontChoice.font(size: 28 * appSettings.fontScale, relativeTo: .title))
                .foregroundStyle(AtlassianTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                if let authorName = item.authorName, !authorName.isEmpty {
                    Label(authorName, systemImage: "person.crop.circle")
                        .lineLimit(1)
                }
                if !item.activitySummary.isEmpty {
                    Label(item.activitySummary, systemImage: "clock")
                        .lineLimit(2)
                }
            }
            .font(appSettings.subheadlineFont)
            .foregroundStyle(AtlassianTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CommentRow: View {
    @EnvironmentObject private var appSettings: AppSettings
    let comment: CommentItem
    @State private var contentHeight: CGFloat = 80

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AuthenticatedAvatarView(name: comment.authorName, path: comment.authorAvatarPath, tint: AtlassianTheme.mutedText, size: 38)

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
                    contentHeight: $contentHeight,
                    minimumHeight: 34
                )
                .frame(height: contentHeight)
            }
        }
        .padding(14)
        .liquidGlassPanel(cornerRadius: 24)
    }

    private func commentHTML(_ body: String) -> String {
        let text = appSettings.appearanceMode == .dark ? "#F4F5F7" : "#172B4D"
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body { margin: 0; padding: 0; background: transparent; color: \(text); }
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

struct ContentEditorSheet: View {
    @EnvironmentObject private var appSettings: AppSettings
    @State private var title: String
    @State private var storageHTML: String

    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: (String, String) -> Void

    init(title: String, storageHTML: String, isSaving: Bool, onCancel: @escaping () -> Void, onSave: @escaping (String, String) -> Void) {
        _title = State(initialValue: title)
        _storageHTML = State(initialValue: storageHTML)
        self.isSaving = isSaving
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("标题", text: $title)
                    .font(appSettings.headlineFont)
                    .textFieldStyle(.roundedBorder)

                Text("正文使用 Confluence storage HTML。")
                    .font(appSettings.subheadlineFont)
                    .foregroundStyle(AtlassianTheme.mutedText)

                TextEditor(text: $storageHTML)
                    .font(.system(size: 14, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(AtlassianTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AtlassianTheme.separator, lineWidth: 0.8)
                    )
            }
            .padding(16)
            .navigationTitle("修改文章")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), storageHTML)
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || storageHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#if os(iOS)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct HTMLContentView: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    @Binding var contentHeight: CGFloat
    var minimumHeight: CGFloat = 80

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
                    height = self.parent.minimumHeight
                }

                DispatchQueue.main.async {
                    self.parent.contentHeight = max(self.parent.minimumHeight, height)
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
    var minimumHeight: CGFloat = 80

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
                    height = self.parent.minimumHeight
                }

                DispatchQueue.main.async {
                    self.parent.contentHeight = max(self.parent.minimumHeight, height)
                }
            }
        }
    }
}
#endif
