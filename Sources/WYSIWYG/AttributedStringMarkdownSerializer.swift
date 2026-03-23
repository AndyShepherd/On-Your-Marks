// Sources/WYSIWYG/AttributedStringMarkdownSerializer.swift
import AppKit

struct AttributedStringMarkdownSerializer {
    let originalSource: String

    func serialize(_ attributedString: NSAttributedString) -> String {
        let blocks = splitIntoBlocks(attributedString)
        var result = ""
        for block in blocks {
            result += serializeBlock(block)
        }
        return result
    }

    // MARK: - Block Splitting

    /// Splits the attributed string into logical blocks separated by newlines.
    /// Each block is an NSAttributedString representing one paragraph/heading/list-item etc.
    private func splitIntoBlocks(_ attributedString: NSAttributedString) -> [NSAttributedString] {
        let fullString = attributedString.string
        var blocks: [NSAttributedString] = []
        var searchStart = fullString.startIndex

        while searchStart < fullString.endIndex {
            // Find the next newline
            if let newlineRange = fullString[searchStart...].firstIndex(of: "\n") {
                let lineEnd = fullString.index(after: newlineRange)
                let nsRange = NSRange(searchStart..<lineEnd, in: fullString)
                let block = attributedString.attributedSubstring(from: nsRange)
                blocks.append(block)
                searchStart = lineEnd
            } else {
                // No newline — remainder is a block
                let nsRange = NSRange(searchStart..<fullString.endIndex, in: fullString)
                if nsRange.length > 0 {
                    let block = attributedString.attributedSubstring(from: nsRange)
                    blocks.append(block)
                }
                break
            }
        }

        return blocks
    }

    // MARK: - Block Serialization

    private func serializeBlock(_ block: NSAttributedString) -> String {
        let fullRange = NSRange(location: 0, length: block.length)
        guard fullRange.length > 0 else { return "" }

        // If the first character carries a MarkdownBlockAttachment, delegate serialization to it.
        let attachmentAttrs = block.attributes(at: 0, effectiveRange: nil)
        if let attachment = attachmentAttrs[.attachment] as? MarkdownBlockAttachment {
            return attachment.serializeToMarkdown()
        }

        // Check attributes on the first character to determine block type
        let attrs = block.attributes(at: 0, effectiveRange: nil)

        // Check if the block has a source range and content matches original
        if let sourceRange = attrs[.markdownSourceRange] as? NSRange {
            let nsSource = originalSource as NSString
            if sourceRange.location >= 0,
               sourceRange.location + sourceRange.length <= nsSource.length {
                let originalText = nsSource.substring(with: sourceRange)
                // Compare the plain text content (stripping list prefixes and newlines)
                let blockText = stripListPrefix(block).trimmingCharacters(in: .newlines)
                let originalPlain = extractPlainContent(from: originalText).trimmingCharacters(in: .newlines)
                if blockText == originalPlain {
                    return originalText + "\n"
                }
            }
        }

        // Serialize from attributes
        if let headingLevel = attrs[.markdownHeading] as? Int {
            return serializeHeading(block, level: headingLevel)
        }

        if attrs[.markdownBlockquote] as? Bool == true {
            return serializeBlockquote(block)
        }

        if attrs[.markdownListItem] as? MarkdownListStyle != nil {
            return serializeListItem(block)
        }

        if attrs[.markdownCode] as? Bool == true {
            // Could be a code block (no inline formatting, no heading)
            let text = block.string.replacingOccurrences(of: "\n", with: "")
            if !text.isEmpty {
                return serializeInlineContent(block)
            }
        }

        return serializeInlineContent(block)
    }

    // MARK: - Heading Serialization

    private func serializeHeading(_ block: NSAttributedString, level: Int) -> String {
        let prefix = String(repeating: "#", count: level) + " "
        let content = block.string.trimmingCharacters(in: .newlines)
        return prefix + content + "\n"
    }

    // MARK: - Blockquote Serialization

    private func serializeBlockquote(_ block: NSAttributedString) -> String {
        let content = serializeInlineRuns(block).trimmingCharacters(in: .newlines)
        return "> " + content + "\n"
    }

    // MARK: - List Item Serialization

    private func serializeListItem(_ block: NSAttributedString) -> String {
        let attrs = block.attributes(at: 0, effectiveRange: nil)
        guard let style = attrs[.markdownListItem] as? MarkdownListStyle else {
            return serializeInlineContent(block)
        }

        let prefix: String
        switch style {
        case .unordered(_, _):
            prefix = "- "
        case .ordered(_, let start):
            prefix = "\(start). "
        case .task(_, let checked):
            prefix = checked ? "- [x] " : "- [ ] "
        }

        // Strip the visual prefix (bullet/number + tab) from the text
        let strippedBlock = stripVisualListPrefix(block)
        let content = serializeInlineRuns(strippedBlock).trimmingCharacters(in: .newlines)
        return prefix + content + "\n"
    }

    /// Strips the visual list prefix (e.g., "•\t", "1.\t", "☑\t") from the block.
    private func stripVisualListPrefix(_ block: NSAttributedString) -> NSAttributedString {
        let str = block.string
        // Look for tab character — everything before it (inclusive) is the visual prefix
        if let tabIndex = str.firstIndex(of: "\t") {
            let afterTab = str.index(after: tabIndex)
            let nsRange = NSRange(afterTab..<str.endIndex, in: str)
            if nsRange.length > 0 {
                return block.attributedSubstring(from: nsRange)
            }
        }
        return block
    }

    // MARK: - Inline Content Serialization

    private func serializeInlineContent(_ block: NSAttributedString) -> String {
        let content = serializeInlineRuns(block).trimmingCharacters(in: .newlines)
        return content + "\n"
    }

    /// Walk through the attributed string run-by-run and emit markdown.
    private func serializeInlineRuns(_ attrStr: NSAttributedString) -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: attrStr.length)
        guard fullRange.length > 0 else { return "" }

        attrStr.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            let text = (attrStr.string as NSString).substring(with: range)
            var content = text

            // Skip trailing newlines — they're block separators, not content
            if content == "\n" { return }

            let isStrong = attrs[.markdownStrong] as? Bool == true
            let isEmphasis = attrs[.markdownEmphasis] as? Bool == true
            let isStrikethrough = attrs[.markdownStrikethrough] as? Bool == true
            let isCode = attrs[.markdownCode] as? Bool == true
            let linkURL = attrs[.markdownLink] as? String

            // Code takes priority — no nesting inside backticks
            if isCode {
                result += "`\(content)`"
                return
            }

            // Build up wrapping from outside in: strikethrough, then bold, then italic
            if isStrikethrough { content = "~~\(content)~~" }
            if isStrong { content = "**\(content)**" }
            if isEmphasis { content = "*\(content)*" }

            if let url = linkURL {
                content = "[\(content)](\(url))"
            }

            result += content
        }

        return result
    }

    // MARK: - Helpers

    /// Strips visual list prefix and returns plain text for comparison.
    private func stripListPrefix(_ block: NSAttributedString) -> String {
        let str = block.string
        // Check if block is a list item with visual prefix
        let attrs = block.attributes(at: 0, effectiveRange: nil)
        if attrs[.markdownListItem] as? MarkdownListStyle != nil {
            if let tabIndex = str.firstIndex(of: "\t") {
                let afterTab = str.index(after: tabIndex)
                return String(str[afterTab...]).trimmingCharacters(in: .newlines)
            }
        }
        return str.trimmingCharacters(in: .newlines)
    }

    /// Extracts plain text content from a markdown source string for comparison.
    /// Strips markdown syntax to get just the text content.
    private func extractPlainContent(from markdown: String) -> String {
        var text = markdown

        // Strip heading prefixes
        if let match = text.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
            text = String(text[match.upperBound...])
        }

        // Strip blockquote prefix
        if let match = text.range(of: #"^>\s*"#, options: .regularExpression) {
            text = String(text[match.upperBound...])
        }

        // Strip list item prefixes: "- ", "* ", "1. ", "- [x] ", "- [ ] "
        if let match = text.range(of: #"^(\d+\.\s+|- \[[ x]\]\s+|[-*+]\s+)"#, options: .regularExpression) {
            text = String(text[match.upperBound...])
        }

        // Strip inline formatting markers
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "~~", with: "")
        text = text.replacingOccurrences(of: "*", with: "")
        text = text.replacingOccurrences(of: "_", with: "")
        text = text.replacingOccurrences(of: "`", with: "")

        // Strip link syntax: [text](url) -> text
        let linkPattern = #"\[([^\]]+)\]\([^)]+\)"#
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "$1"
            )
        }

        return text
    }
}
