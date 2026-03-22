// Sources/Preview/MarkdownPreviewView.swift
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let htmlContent: String
    let baseURL: URL?
    @Binding var scrollPercentage: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: PreviewBridge {
        var lastLoadedHTML: String = ""
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.onScrollPositionChanged = { percentage in
            DispatchQueue.main.async { [self] in
                scrollPercentage = percentage
            }
        }

        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "scrollPosition")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Skip reload if content hasn't changed
        guard htmlContent != context.coordinator.lastLoadedHTML else { return }
        context.coordinator.lastLoadedHTML = htmlContent

        // Load the HTML template from bundle, replace placeholder
        guard let templateURL = Bundle.module.url(forResource: "preview", withExtension: "html"),
              let template = try? String(contentsOf: templateURL, encoding: .utf8) else {
            webView.loadHTMLString(
                "<html><body><p>Unable to render preview.</p></body></html>",
                baseURL: nil
            )
            return
        }

        let fullHTML = template.replacingOccurrences(of: "{{CONTENT}}", with: htmlContent)
        let effectiveBaseURL = baseURL ?? Bundle.module.resourceURL
        webView.loadHTMLString(fullHTML, baseURL: effectiveBaseURL)

        // Restore scroll position after load
        let percentage = scrollPercentage
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            webView.evaluateJavaScript("restoreScroll(\(percentage))") { _, _ in }
        }
    }
}
