// Sources/Preview/PreviewBridge.swift
import Foundation
import WebKit

class PreviewBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onScrollPositionChanged: ((Double) -> Void)?
    var pendingScrollPercentage: Double = 0

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "scrollPosition",
              let body = message.body as? [String: Any],
              let percentage = body["percentage"] as? Double else {
            return
        }
        onScrollPositionChanged?(percentage)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let percentage = pendingScrollPercentage
        webView.evaluateJavaScript("restoreScroll(\(percentage))") { _, _ in }
    }
}
