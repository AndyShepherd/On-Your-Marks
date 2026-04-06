// Sources/Preview/MarkdownPreviewView.swift
import SwiftUI
import WebKit

private let resourceBundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle.main
    #endif
}()

struct MarkdownPreviewView: NSViewRepresentable {
    let htmlContent: String
    let baseURL: URL?
    @Binding var scrollPercentage: Double

    private static func loadResource(_ name: String, ext: String) -> String {
        guard let url = resourceBundle.url(forResource: name, withExtension: ext),
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
        context.coordinator.onScrollPositionChanged = { [self] percentage in
            // Defer state mutation to avoid publishing during view updates
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                scrollPercentage = percentage
            }
        }

        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "scrollPosition")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
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

        let effectiveBaseURL = baseURL ?? resourceBundle.resourceURL
        context.coordinator.pendingScrollPercentage = scrollPercentage
        webView.loadHTMLString(fullHTML, baseURL: effectiveBaseURL)
    }
}
