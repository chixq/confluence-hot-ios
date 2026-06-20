import SwiftUI
import WebKit

struct ContentDetailView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.openURL) private var openURL

    let item: ContentItem
    @State private var detail: ContentDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var webContentHeight: CGFloat = 560

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    TagView(text: item.typeLabel)
                    Text(detail?.title ?? item.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AtlassianTheme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.activitySummary.isEmpty {
                        Text(item.activitySummary)
                            .font(.subheadline)
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
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 28)
        }
        .background(AtlassianTheme.background)
        .inlineNavigationTitle()
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
        .task {
            await load()
        }
    }

    private func load() async {
        guard let client = sessionStore.client else { return }
        isLoading = true
        errorMessage = nil

        do {
            detail = try await client.fetchDetail(id: item.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func wrappedHTML(_ body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          <style>
            :root { color-scheme: light; }
            html, body { margin: 0; padding: 0; background: #FFFFFF; }
            body {
              color: #172B4D;
              font: -apple-system-body;
              line-height: 1.52;
              padding: 18px;
              word-wrap: break-word;
            }
            a { color: #0052CC; text-decoration: none; }
            img, video { max-width: 100%; height: auto; border-radius: 6px; }
            table { border-collapse: collapse; width: 100%; overflow-x: auto; display: block; }
            th, td { border: 1px solid #DFE1E6; padding: 8px; vertical-align: top; }
            pre, code {
              background: #F4F5F7;
              border-radius: 6px;
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            }
            pre { padding: 12px; overflow-x: auto; }
            blockquote {
              border-left: 3px solid #0052CC;
              margin: 12px 0;
              padding: 4px 0 4px 12px;
              color: #42526E;
            }
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
