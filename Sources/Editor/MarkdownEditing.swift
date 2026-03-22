import Foundation

/// Abstraction layer for the Markdown editor view.
/// Allows swapping STTextView for native NSTextView if Apple improves TextKit 2.
protocol MarkdownEditing: AnyObject {
    var text: String { get set }
    var cursorOffset: Int { get set }
    var scrollOffset: Int { get set }
    var selectedRange: NSRange { get set }
    func replaceSelection(with text: String)
    func insertAtCursor(_ text: String)
    func wrapSelection(prefix: String, suffix: String)
}
