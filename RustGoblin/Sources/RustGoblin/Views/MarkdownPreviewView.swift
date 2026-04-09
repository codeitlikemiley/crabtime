import AppKit
import SwiftUI
import WebKit

private final class PassthroughScrollWKWebView: WKWebView {
    var shouldPassScrollToParent = false

    override func scrollWheel(with event: NSEvent) {
        guard shouldPassScrollToParent else {
            super.scrollWheel(with: event)
            return
        }

        let internalScrollView = enclosingScrollView
        var ancestor: NSView? = superview

        while let current = ancestor {
            if let outerScrollView = current.enclosingScrollView, outerScrollView !== internalScrollView {
                outerScrollView.scrollWheel(with: event)
                return
            }
            ancestor = current.superview
        }

        nextResponder?.scrollWheel(with: event)
    }
}

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    var sourceURL: URL?
    var sizingMode: MarkdownDocumentView.SizingMode = .intrinsicHeight
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.heightMessageName)
        controller.add(context.coordinator, name: Coordinator.copyCodeMessageName)
        configuration.userContentController = controller

        let webView = PassthroughScrollWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false

        context.coordinator.webView = webView
        context.coordinator.parent = self
        context.coordinator.loadIfNeeded()
        context.coordinator.configureScrollBehavior()

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configureScrollBehavior()
        context.coordinator.loadIfNeeded()
    }
}

extension MarkdownPreviewView {
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let heightMessageName = "contentHeight"
        static let copyCodeMessageName = "copyCodeBlock"

        var parent: MarkdownPreviewView?
        weak var webView: WKWebView?
        @Binding private var contentHeight: CGFloat
        private let renderer = MarkdownHTMLRenderer()
        private var lastRenderSignature: String?

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func loadIfNeeded() {
            guard let parent, let webView else {
                return
            }

            let signature = "\(parent.sourceURL?.path ?? "")::\(parent.markdown.hashValue)"
            guard signature != lastRenderSignature else {
                return
            }

            lastRenderSignature = signature
            let html = renderer.render(markdown: parent.markdown, sourceURL: parent.sourceURL)
            let baseURL = parent.sourceURL?.deletingLastPathComponent()
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        func configureScrollBehavior() {
            guard let webView, let parent else {
                return
            }

            DispatchQueue.main.async {
                if let passthroughWebView = webView as? PassthroughScrollWKWebView {
                    passthroughWebView.shouldPassScrollToParent = parent.sizingMode == .intrinsicHeight
                }

                guard let scrollView = webView.enclosingScrollView else {
                    return
                }

                scrollView.drawsBackground = false
                scrollView.hasVerticalScroller = parent.sizingMode == .fill
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = parent.sizingMode != .fill
                scrollView.scrollerStyle = NSScroller.Style.overlay
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case Self.heightMessageName:
                guard parent?.sizingMode == .intrinsicHeight,
                      let value = message.body as? NSNumber
                else {
                    return
                }

                DispatchQueue.main.async {
                    self.contentHeight = max(140, CGFloat(truncating: value))
                }
            case Self.copyCodeMessageName:
                guard let code = message.body as? String else {
                    return
                }

                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code, forType: .string)
                }
            default:
                return
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}
