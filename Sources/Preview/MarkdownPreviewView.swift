// Sources/Preview/MarkdownPreviewView.swift
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let htmlContent: String
    let baseURL: URL?
    @Binding var scrollPercentage: Double

    private static func loadResource(_ name: String, ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }

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
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Skip reload if content hasn't changed
        guard htmlContent != context.coordinator.lastLoadedHTML else { return }
        context.coordinator.lastLoadedHTML = htmlContent

        // Load all resources from bundle and inline them into the HTML
        // This ensures CSS/JS work regardless of baseURL
        let css = Self.loadResource("preview", ext: "css")
        let highlightCSS = Self.loadResource("highlight-theme", ext: "css")
        let highlightJS = Self.loadResource("highlight.min", ext: "js")

        let fullHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>\(css)</style>
            <style>\(highlightCSS)</style>
            <script>\(highlightJS)</script>
        </head>
        <body>
            <article id="content">
                \(htmlContent)
            </article>
            <script>
                hljs.highlightAll();

                function copyCode(button) {
                    const wrapper = button.closest('.code-block-wrapper');
                    const code = wrapper.querySelector('code');
                    const text = code.textContent;
                    navigator.clipboard.writeText(text).then(function() {
                        button.textContent = 'Copied!';
                        setTimeout(function() { button.textContent = 'Copy'; }, 1500);
                    });
                }

                window.addEventListener('scroll', function() {
                    const scrollPercentage = window.scrollY /
                        Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                    window.webkit.messageHandlers.scrollPosition.postMessage(
                        { percentage: scrollPercentage }
                    );
                });

                function restoreScroll(percentage) {
                    const target = percentage *
                        (document.documentElement.scrollHeight - window.innerHeight);
                    window.scrollTo(0, target);
                }
            </script>
        </body>
        </html>
        """

        let effectiveBaseURL = baseURL ?? Bundle.module.resourceURL
        webView.loadHTMLString(fullHTML, baseURL: effectiveBaseURL)

        // Restore scroll position after load
        let percentage = scrollPercentage
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            webView.evaluateJavaScript("restoreScroll(\(percentage))") { _, _ in }
        }
    }
}
