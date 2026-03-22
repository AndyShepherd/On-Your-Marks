// Sources/Preview/PreviewBridge.swift
import Foundation
import WebKit

class PreviewBridge: NSObject, WKScriptMessageHandler {
    var onScrollPositionChanged: ((Double) -> Void)?

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
}
