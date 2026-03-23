// Sources/WYSIWYG/WYSIWYGEditorView.swift
import SwiftUI
import Markdown

// MARK: - WYSIWYGTextView

/// NSTextView subclass that overrides copy/paste to interoperate cleanly with Markdown.
///
/// - **Paste HTML**: strips tags and inserts plain text.
/// - **Paste plain text**: passed through to super (the coordinator's `textDidChange`
///   will re-render it as Markdown on the next edit cycle).
/// - **Copy**: puts both the Markdown source and RTF on the pasteboard.
/// - **Cut**: copy then delete.
@MainActor
final class WYSIWYGTextView: NSTextView {

    weak var wysiwygCoordinator: WYSIWYGEditorView.Coordinator?

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // Prefer HTML — strip tags and insert as plain text so the editor can
        // re-interpret formatting via its own Markdown rendering pipeline.
        if let html = pasteboard.string(forType: .html) {
            let cleaned = html.replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression
            )
            // Decode common HTML entities
            let decoded = cleaned
                .replacingOccurrences(of: "&amp;",  with: "&")
                .replacingOccurrences(of: "&lt;",   with: "<")
                .replacingOccurrences(of: "&gt;",   with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;",  with: "'")
                .replacingOccurrences(of: "&nbsp;", with: " ")
            insertText(decoded, replacementRange: selectedRange())
            return
        }

        // Plain text — let the standard pipeline handle it.
        super.paste(sender)
    }

    override func copy(_ sender: Any?) {
        guard let storage = textStorage else {
            super.copy(sender)
            return
        }

        let range = selectedRange()
        guard range.length > 0 else { return }

        let selectedAttrStr = storage.attributedSubstring(from: range)
        let serializer = AttributedStringMarkdownSerializer(originalSource: "")
        let markdown = serializer.serialize(selectedAttrStr)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Primary type: plain Markdown string (interops with any text field)
        pasteboard.setString(markdown, forType: .string)
        // Secondary type: RTF for apps that understand rich text
        if let rtfData = selectedAttrStr.rtf(
            from: NSRange(location: 0, length: selectedAttrStr.length),
            documentAttributes: [:]
        ) {
            pasteboard.setData(rtfData, forType: .rtf)
        }
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        deleteBackward(sender)
    }
}



struct WYSIWYGEditorView: NSViewRepresentable {
    @Binding var text: String
    let useGFM: Bool
    @ObservedObject var toolbarState: WYSIWYGToolbarState

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = WYSIWYGTextView()
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
        textView.wysiwygCoordinator = context.coordinator
        context.coordinator.textView = textView

        // Register notification observers for format commands
        context.coordinator.registerNotificationObservers()

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

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeNotificationObservers()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WYSIWYGEditorView
        var isEditing = false
        weak var textView: NSTextView?
        var lastSerializedText: String = ""
        private var debounceTask: Task<Void, Never>?
        private var notificationObservers: [NSObjectProtocol] = []
        private let slashCommandMenu = SlashCommandMenu()
        private var slashCommandRange: NSRange?

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

        // MARK: - Notification Observers

        func registerNotificationObservers() {
            let nc = NotificationCenter.default

            let mappings: [(Notification.Name, @MainActor @Sendable (Coordinator) -> Void)] = [
                (.formatBold,           { $0.applyBold() }),
                (.formatItalic,         { $0.applyItalic() }),
                (.formatStrikethrough,  { $0.applyStrikethrough() }),
                (.formatCode,           { $0.applyInlineCode() }),
                (.formatBlockquote,     { $0.applyBlockquote() }),
                (.formatLink,           { $0.applyLink() }),
                (.formatImage,          { $0.applyImage() }),
                (.formatHorizontalRule, { $0.applyHorizontalRule() }),
                (.formatBulletList,     { $0.applyBulletList() }),
                (.formatNumberedList,   { $0.applyNumberedList() }),
                (.formatTaskList,       { $0.applyTaskList() }),
                (.formatTable,          { $0.applyTable() }),
            ]

            for (name, action) in mappings {
                let observer = nc.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    MainActor.assumeIsolated {
                        action(self)
                    }
                }
                notificationObservers.append(observer)
            }

            // Heading uses userInfo for level
            let headingObserver = nc.addObserver(
                forName: .formatHeading,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let level = notification.userInfo?["level"] as? Int ?? 0
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.applyHeading(level: level)
                }
            }
            notificationObservers.append(headingObserver)
        }

        func removeNotificationObservers() {
            let nc = NotificationCenter.default
            for observer in notificationObservers {
                nc.removeObserver(observer)
            }
            notificationObservers.removeAll()
        }

        // MARK: - Guard: Only act when this text view is first responder

        private var isFirstResponder: Bool {
            guard let textView else { return false }
            return textView.window?.firstResponder === textView
        }

        // MARK: - Format Actions

        func applyBold() {
            guard isFirstResponder,
                  let textView,
                  let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            WYSIWYGFormatting.toggleBold(in: storage, range: range)
            updateActiveState()
        }

        func applyItalic() {
            guard isFirstResponder,
                  let textView,
                  let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            WYSIWYGFormatting.toggleItalic(in: storage, range: range)
            updateActiveState()
        }

        func applyStrikethrough() {
            guard isFirstResponder,
                  let textView,
                  let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            WYSIWYGFormatting.toggleStrikethrough(in: storage, range: range)
            updateActiveState()
        }

        func applyInlineCode() {
            guard isFirstResponder,
                  let textView,
                  let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            WYSIWYGFormatting.toggleInlineCode(in: storage, range: range)
            updateActiveState()
        }

        func applyBlockquote() {
            guard isFirstResponder,
                  let textView,
                  let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            WYSIWYGFormatting.toggleBlockquote(in: storage, range: range)
            updateActiveState()
        }

        func applyHeading(level: Int) {
            guard isFirstResponder,
                  let textView,
                  let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            // For headings, extend to the full paragraph range
            let paragraphRange = (storage.string as NSString).paragraphRange(for: range)
            guard paragraphRange.length > 0 else { return }
            WYSIWYGFormatting.setHeading(level: level, in: storage, range: paragraphRange)
            updateActiveState()
        }

        func applyLink() {
            guard isFirstResponder,
                  let textView,
                  let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            // Set a placeholder URL; a future iteration may show a link dialog
            WYSIWYGFormatting.setLink(url: "https://", in: storage, range: range)
        }

        func applyImage() {
            // Image insertion requires a file picker; placeholder for now
        }

        func applyHorizontalRule() {
            guard isFirstResponder,
                  let textView,
                  let storage = textView.textStorage else { return }
            let location = textView.selectedRange().location
            let hr = NSAttributedString(string: "\n---\n", attributes: [
                .font: MarkdownStyles.bodyFont,
                .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
            ])
            storage.insert(hr, at: location)
        }

        func applyBulletList() {
            insertBlockPrefix("- ")
        }

        func applyNumberedList() {
            insertBlockPrefix("1. ")
        }

        func applyTaskList() {
            insertBlockPrefix("- [ ] ")
        }

        func applyTable() {
            guard isFirstResponder,
                  let textView,
                  let storage = textView.textStorage else { return }
            let location = textView.selectedRange().location
            let tableText = "\n| Column 1 | Column 2 |\n| --- | --- |\n| Cell | Cell |\n"
            let table = NSAttributedString(string: tableText, attributes: [
                .font: MarkdownStyles.bodyFont,
                .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
            ])
            storage.insert(table, at: location)
        }

        /// Insert a prefix at the beginning of the current line (for list-type blocks).
        private func insertBlockPrefix(_ prefix: String) {
            guard isFirstResponder,
                  let textView,
                  let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            let paragraphRange = (storage.string as NSString).paragraphRange(for: range)
            let lineStart = paragraphRange.location
            let prefixAttr = NSAttributedString(string: prefix, attributes: [
                .font: MarkdownStyles.bodyFont,
                .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
            ])
            storage.insert(prefixAttr, at: lineStart)
        }

        // MARK: - Active State Tracking

        func textViewDidChangeSelection(_ notification: Notification) {
            updateActiveState()
            // If the slash command menu is showing and selection changed away, dismiss
            if slashCommandMenu.isShowing {
                dismissSlashCommandIfNeeded()
            }
        }

        private func updateActiveState() {
            guard let textView,
                  let storage = textView.textStorage else { return }
            let state = parent.toolbarState
            let location = textView.selectedRange().location

            guard location < storage.length else {
                state.isBold = false
                state.isItalic = false
                state.isStrikethrough = false
                state.isCode = false
                state.isBlockquote = false
                state.headingLevel = 0
                return
            }

            let attrs = storage.attributes(at: location, effectiveRange: nil)
            state.isBold = attrs[.markdownStrong] as? Bool == true
            state.isItalic = attrs[.markdownEmphasis] as? Bool == true
            state.isStrikethrough = attrs[.markdownStrikethrough] as? Bool == true
            state.isCode = attrs[.markdownCode] as? Bool == true
            state.isBlockquote = attrs[.markdownBlockquote] as? Bool == true
            state.headingLevel = attrs[.markdownHeading] as? Int ?? 0
        }

        // MARK: - Slash Command Detection

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacement = replacementString else { return true }

            // Detect "/" typed at the start of a line
            if replacement == "/" {
                let text = (textView.textStorage?.string ?? "") as NSString
                let lineRange = text.paragraphRange(for: NSRange(location: affectedCharRange.location, length: 0))
                let lineStart = lineRange.location
                let textBeforeCursor = text.substring(with: NSRange(location: lineStart, length: affectedCharRange.location - lineStart))
                let trimmed = textBeforeCursor.trimmingCharacters(in: .whitespaces)

                if trimmed.isEmpty {
                    // Start slash command mode
                    slashCommandRange = NSRange(location: affectedCharRange.location, length: 1)
                    showSlashCommandMenu(in: textView, filter: "")
                    return true
                }
            }

            // If slash command is active, update filter or dismiss
            if let cmdRange = slashCommandRange, slashCommandMenu.isShowing {
                if replacement.isEmpty && affectedCharRange.length > 0 {
                    // Deletion
                    if affectedCharRange.location < cmdRange.location {
                        // Deleted before the slash -- dismiss
                        dismissSlashCommand()
                        return true
                    }
                    // Update the range and filter
                    let newLength = cmdRange.length - affectedCharRange.length
                    if newLength <= 0 {
                        dismissSlashCommand()
                        return true
                    }
                    slashCommandRange = NSRange(location: cmdRange.location, length: newLength)
                    let filterRange = NSRange(location: cmdRange.location + 1, length: newLength - 1)
                    if filterRange.length > 0, filterRange.location + filterRange.length <= (textView.textStorage?.length ?? 0) {
                        let filter = ((textView.textStorage?.string ?? "") as NSString).substring(with: filterRange)
                        slashCommandMenu.updateFilter(filter)
                    } else {
                        slashCommandMenu.updateFilter("")
                    }
                } else if !replacement.isEmpty {
                    if replacement == " " || replacement == "\n" {
                        dismissSlashCommand()
                        return true
                    }
                    // Extend the slash command range
                    let newLength = cmdRange.length + replacement.count
                    slashCommandRange = NSRange(location: cmdRange.location, length: newLength)

                    // Compute filter: everything after the "/"
                    // The replacement hasn't been applied yet, so build the filter from current text + replacement
                    let currentText = (textView.textStorage?.string ?? "") as NSString
                    let existingFilterStart = cmdRange.location + 1
                    let existingFilterLength = cmdRange.length - 1
                    var filter = ""
                    if existingFilterLength > 0, existingFilterStart + existingFilterLength <= currentText.length {
                        filter = currentText.substring(with: NSRange(location: existingFilterStart, length: existingFilterLength))
                    }
                    filter += replacement
                    slashCommandMenu.updateFilter(filter)
                }
            }

            return true
        }

        private func showSlashCommandMenu(in textView: NSTextView, filter: String) {
            let glyphIndex = textView.layoutManager?.glyphIndexForCharacter(at: textView.selectedRange().location) ?? 0
            var rect = textView.layoutManager?.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1),
                                                            in: textView.textContainer!) ?? .zero
            rect = NSRect(x: rect.origin.x + textView.textContainerInset.width,
                          y: rect.origin.y + textView.textContainerInset.height,
                          width: 1, height: rect.height)

            slashCommandMenu.show(relativeTo: rect, of: textView, filter: filter) { [weak self] command in
                self?.handleSlashCommand(command)
            }
        }

        private func handleSlashCommand(_ command: SlashCommand) {
            guard let textView,
                  let storage = textView.textStorage,
                  let cmdRange = slashCommandRange else { return }

            // Remove the slash and any typed filter text
            let deleteRange: NSRange
            if cmdRange.location + cmdRange.length <= storage.length {
                deleteRange = cmdRange
            } else {
                deleteRange = NSRange(location: cmdRange.location, length: storage.length - cmdRange.location)
            }

            storage.beginEditing()
            storage.deleteCharacters(in: deleteRange)
            storage.endEditing()

            slashCommandRange = nil

            // Apply the command
            switch command.name {
            case "heading":
                let range = NSRange(location: deleteRange.location, length: 0)
                let paragraphRange = (storage.string as NSString).paragraphRange(for: range)
                if paragraphRange.length > 0 {
                    WYSIWYGFormatting.setHeading(level: 1, in: storage, range: paragraphRange)
                }
            case "bullet":
                let prefix = NSAttributedString(string: "- ", attributes: [
                    .font: MarkdownStyles.bodyFont,
                    .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
                ])
                storage.insert(prefix, at: deleteRange.location)
            case "numbered":
                let prefix = NSAttributedString(string: "1. ", attributes: [
                    .font: MarkdownStyles.bodyFont,
                    .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
                ])
                storage.insert(prefix, at: deleteRange.location)
            case "task":
                let prefix = NSAttributedString(string: "- [ ] ", attributes: [
                    .font: MarkdownStyles.bodyFont,
                    .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
                ])
                storage.insert(prefix, at: deleteRange.location)
            case "quote":
                applyBlockquote()
            case "code":
                let block = NSAttributedString(string: "```\n\n```\n", attributes: [
                    .font: MarkdownStyles.monoFont,
                    .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
                ])
                storage.insert(block, at: deleteRange.location)
                // Place cursor inside the code block
                textView.setSelectedRange(NSRange(location: deleteRange.location + 4, length: 0))
            case "table":
                let tableText = "| Column 1 | Column 2 |\n| --- | --- |\n| Cell | Cell |\n"
                let table = NSAttributedString(string: tableText, attributes: [
                    .font: MarkdownStyles.bodyFont,
                    .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
                ])
                storage.insert(table, at: deleteRange.location)
            case "image":
                let placeholder = NSAttributedString(string: "![alt](url)", attributes: [
                    .font: MarkdownStyles.bodyFont,
                    .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
                ])
                storage.insert(placeholder, at: deleteRange.location)
            case "divider":
                let hr = NSAttributedString(string: "---\n", attributes: [
                    .font: MarkdownStyles.bodyFont,
                    .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
                ])
                storage.insert(hr, at: deleteRange.location)
            default:
                break
            }
        }

        private func dismissSlashCommand() {
            slashCommandMenu.dismiss()
            slashCommandRange = nil
        }

        private func dismissSlashCommandIfNeeded() {
            guard let textView, let cmdRange = slashCommandRange else {
                dismissSlashCommand()
                return
            }
            let cursor = textView.selectedRange().location
            if cursor < cmdRange.location || cursor > cmdRange.location + cmdRange.length {
                dismissSlashCommand()
            }
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
