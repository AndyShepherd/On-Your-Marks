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
        let textView = scrollView.documentView as! STTextView

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

        init(_ parent: STTextViewEditor) {
            self.parent = parent
        }

        func textViewDidChangeText(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }
            isEditing = true
            parent.text = textView.string
            isEditing = false

            // Apply syntax highlighting after text change
            let highlighter = MarkdownHighlighter()
            highlighter.highlight(textView)
        }
    }
}
