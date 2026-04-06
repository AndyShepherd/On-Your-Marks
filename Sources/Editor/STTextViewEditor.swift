// Sources/Editor/STTextViewEditor.swift
import SwiftUI
import STTextView

struct STTextViewEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorOffset: Int
    @Binding var scrollOffset: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = STTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? STTextView else { return scrollView }

        // Configure appearance
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.highlightSelectedLine = true
        textView.isIncrementalSearchingEnabled = true
        textView.widthTracksTextView = true

        // Line height
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.3
        paragraph.defaultTabInterval = 28
        textView.typingAttributes[.paragraphStyle] = paragraph

        // Add line number ruler
        let rulerView = STLineNumberRulerView(textView: textView, scrollView: scrollView)
        rulerView.highlightSelectedLine = true
        scrollView.verticalRulerView = rulerView
        scrollView.rulersVisible = true

        // Set delegate
        textView.delegate = context.coordinator

        // Initial content
        textView.string = text

        // Apply syntax highlighting to initial content
        let highlighter = MarkdownHighlighter()
        highlighter.highlight(textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? STTextView else { return }

        // Only update text if it changed externally (not from user typing)
        if textView.string != text && !context.coordinator.isEditing {
            textView.string = text
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, @preconcurrency STTextViewDelegate {
        var parent: STTextViewEditor
        var isEditing = false
        let highlighter = MarkdownHighlighter()

        init(_ parent: STTextViewEditor) {
            self.parent = parent
        }

        func textViewDidChangeText(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }
            isEditing = true
            parent.text = textView.string
            isEditing = false

            highlighter.highlight(textView)
        }

        // MARK: - Key Interception: Tab, Shift+Tab, Return

        func textView(_ textView: STTextView, shouldChangeTextIn affectedCharRange: NSTextRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }

            // --- Tab: insert 4 spaces ---
            if replacement == "\t" {
                textView.insertText("    ", replacementRange: .notFound)
                return false
            }

            // --- Backtab (Shift+Tab): remove up to 4 leading spaces from current line ---
            if replacement == String(Character(Unicode.Scalar(NSBackTabCharacter)!)) {
                handleShiftTab(in: textView)
                return false
            }

            // --- Return: list auto-continuation ---
            if replacement == "\n" {
                return handleReturn(in: textView, affectedCharRange: affectedCharRange)
            }

            return true
        }

        // MARK: - Shift+Tab Helper

        private func handleShiftTab(in textView: STTextView) {
            let fullString = textView.string as NSString

            // Get the cursor offset within the full string
            let cursorOffset = cursorOffsetInTextView(textView)
            guard cursorOffset != NSNotFound else { return }

            // Find start of current line
            let lineRange = fullString.lineRange(for: NSRange(location: cursorOffset, length: 0))
            let lineStart = lineRange.location

            // Count leading spaces (up to 4)
            var spacesToRemove = 0
            while spacesToRemove < 4,
                  lineStart + spacesToRemove < fullString.length,
                  fullString.character(at: lineStart + spacesToRemove) == UInt16((" " as Character).asciiValue!) {
                spacesToRemove += 1
            }

            guard spacesToRemove > 0 else { return }

            // Remove the leading spaces via NSRange-based insertText
            let removeRange = NSRange(location: lineStart, length: spacesToRemove)
            textView.insertText("", replacementRange: removeRange)
        }

        // MARK: - Return Helper

        /// Returns true to let the default newline insertion happen, false if we handle it ourselves.
        private func handleReturn(in textView: STTextView, affectedCharRange: NSTextRange) -> Bool {
            let fullString = textView.string as NSString

            let cursorOffset = cursorOffsetInTextView(textView)
            guard cursorOffset != NSNotFound else { return true }

            // Find the current line range
            let lineRange = fullString.lineRange(for: NSRange(location: cursorOffset, length: 0))
            let lineText = fullString.substring(with: lineRange)

            // Strip trailing newline for matching
            let line = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText

            // Match unordered list prefix: "  - ", "* ", "+ ", etc.
            let bulletPattern = #"^(\s*[-*+]\s)"#
            // Match ordered list prefix: "1. ", "  2. ", etc.
            let orderedPattern = #"^(\s*\d+\.\s)"#

            if let bulletMatch = line.range(of: bulletPattern, options: .regularExpression) {
                let prefix = String(line[bulletMatch])
                let contentAfterPrefix = String(line.dropFirst(prefix.count))

                if contentAfterPrefix.isEmpty {
                    // Empty list item — cancel list by replacing the whole line with just a newline
                    textView.insertText("\n", replacementRange: lineRange)
                } else {
                    // Continue the list
                    textView.insertText("\n" + prefix, replacementRange: .notFound)
                }
                return false
            }

            if let orderedMatch = line.range(of: orderedPattern, options: .regularExpression) {
                let prefix = String(line[orderedMatch])
                let contentAfterPrefix = String(line.dropFirst(prefix.count))

                if contentAfterPrefix.isEmpty {
                    // Empty ordered item — cancel list
                    textView.insertText("\n", replacementRange: lineRange)
                } else {
                    // Increment the list number
                    let indentPattern = #"^(\s*)(\d+)\.\s"#
                    if let indentRange = line.range(of: indentPattern, options: .regularExpression),
                       let numRange = line.range(of: #"\d+"#, options: .regularExpression, range: indentRange) {
                        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                        let num = Int(line[numRange]) ?? 1
                        let nextPrefix = "\(indent)\(num + 1). "
                        textView.insertText("\n" + nextPrefix, replacementRange: .notFound)
                    } else {
                        textView.insertText("\n" + prefix, replacementRange: .notFound)
                    }
                }
                return false
            }

            // Default: let STTextView handle the newline
            return true
        }

        // MARK: - Utilities

        /// Returns the integer offset of the insertion point from the document start.
        private func cursorOffsetInTextView(_ textView: STTextView) -> Int {
            guard let selectionRange = textView.selectedTextRange() else { return NSNotFound }
            return textView.textLayoutManager.offset(
                from: textView.textLayoutManager.documentRange.location,
                to: selectionRange.location
            )
        }
    }
}
