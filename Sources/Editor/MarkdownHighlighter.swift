// Sources/Editor/MarkdownHighlighter.swift
import AppKit
import STTextView

@MainActor
struct MarkdownHighlighter {

    private static let patterns: [(NSRegularExpression, [NSAttributedString.Key: Any])] = {
        let heading = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$", options: .anchorsMatchLines)
        let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(.+?)(\\*\\*|__)", options: [])
        let italic = try! NSRegularExpression(pattern: "(?<![*_])([*_])(?![*_])(.+?)(?<![*_])\\1(?![*_])", options: [])
        let inlineCode = try! NSRegularExpression(pattern: "`([^`]+)`", options: [])
        let codeBlock = try! NSRegularExpression(pattern: "^```.*$", options: .anchorsMatchLines)
        let link = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", options: [])
        let blockquote = try! NSRegularExpression(pattern: "^>\\s?(.*)$", options: .anchorsMatchLines)
        let listMarker = try! NSRegularExpression(pattern: "^(\\s*)([-*+]|\\d+\\.)\\s", options: .anchorsMatchLines)
        let horizontalRule = try! NSRegularExpression(pattern: "^(-{3,}|\\*{3,}|_{3,})\\s*$", options: .anchorsMatchLines)

        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold)
        ]
        let italicAttrs: [NSAttributedString.Key: Any] = [
            .obliqueness: 0.2
        ]
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .backgroundColor: NSColor.quaternaryLabelColor
        ]
        let codeBlockAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ]
        let linkAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor
        ]
        let blockquoteAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let listMarkerAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.controlAccentColor
        ]
        let hrAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.separatorColor
        ]

        return [
            (heading, headingAttrs),
            (codeBlock, codeBlockAttrs),
            (bold, boldAttrs),
            (italic, italicAttrs),
            (inlineCode, codeAttrs),
            (link, linkAttrs),
            (blockquote, blockquoteAttrs),
            (listMarker, listMarkerAttrs),
            (horizontalRule, hrAttrs),
        ]
    }()

    func highlight(_ textView: STTextView) {
        let text = textView.string
        guard !text.isEmpty else { return }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        // Reset to defaults
        textView.setAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor
        ], range: fullRange)

        // Apply patterns
        for (regex, attrs) in Self.patterns {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let matchRange = match?.range else { return }
                textView.addAttributes(attrs, range: matchRange)
            }
        }
    }
}
