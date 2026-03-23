// Sources/WYSIWYG/WYSIWYGEditorView.swift
import SwiftUI
import Markdown

struct WYSIWYGEditorView: NSViewRepresentable {
    @Binding var text: String
    let useGFM: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 40, height: 20)
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]

        // Default typing attributes
        textView.typingAttributes = [
            .font: MarkdownStyles.bodyFont,
            .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
        ]

        scrollView.documentView = textView
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Load initial content
        context.coordinator.loadMarkdown(text, into: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update text if it changed externally (not from user typing)
        if !context.coordinator.isEditing {
            let currentMarkdown = context.coordinator.lastSerializedText
            if text != currentMarkdown {
                context.coordinator.loadMarkdown(text, into: textView)
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WYSIWYGEditorView
        var isEditing = false
        weak var textView: NSTextView?
        var lastSerializedText: String = ""
        private var debounceTask: Task<Void, Never>?

        init(_ parent: WYSIWYGEditorView) {
            self.parent = parent
            self.lastSerializedText = parent.text
        }

        // MARK: - Load Markdown

        func loadMarkdown(_ source: String, into textView: NSTextView) {
            lastSerializedText = source
            let document = Document(parsing: source)
            var renderer = MarkdownAttributedStringRenderer(source: source)
            let attributed = renderer.render(document)

            guard let textStorage = textView.textStorage else { return }
            textStorage.beginEditing()
            textStorage.setAttributedString(attributed)
            textStorage.endEditing()
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true

            debounceTask?.cancel()
            debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                guard let self,
                      let textStorage = textView.textStorage else { return }

                let serializer = AttributedStringMarkdownSerializer(
                    originalSource: self.lastSerializedText
                )
                let markdown = serializer.serialize(textStorage)
                self.lastSerializedText = markdown
                self.parent.text = markdown
                self.isEditing = false
            }
        }
    }
}
