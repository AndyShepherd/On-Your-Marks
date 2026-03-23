// Sources/WYSIWYG/MarkdownAttributedStringRenderer.swift
import AppKit
import Markdown

struct MarkdownAttributedStringRenderer: MarkupVisitor {
    typealias Result = NSMutableAttributedString

    private let originalSource: String

    // Cache @MainActor fonts at init time so visit methods don't need MainActor isolation.
    private let bodyFont: NSFont
    private let monoFont: NSFont

    /// Inline attribute state — propagated from parent to child during inline traversal.
    private var inlineAttributes: [NSAttributedString.Key: Any] = [:]

    @MainActor
    init(source: String) {
        self.originalSource = source
        self.bodyFont = MarkdownStyles.bodyFont
        self.monoFont = MarkdownStyles.monoFont
    }

    // MARK: - Public API

    mutating func render(_ document: Document) -> NSAttributedString {
        let result = visit(document)
        return result
    }

    // MARK: - Source Range Helper

    private func sourceRange(for markup: Markup) -> NSRange? {
        guard let range = markup.range else { return nil }
        let lines = originalSource.components(separatedBy: "\n")
        func offset(for loc: SourceLocation) -> Int? {
            let line = loc.line - 1
            let col = loc.column - 1
            guard line >= 0, line < lines.count else { return nil }
            var result = 0
            for i in 0..<line { result += (lines[i] as NSString).length + 1 }
            result += min(col, (lines[line] as NSString).length)
            return result
        }
        guard let start = offset(for: range.lowerBound),
              let end = offset(for: range.upperBound) else { return nil }
        return NSRange(location: start, length: max(0, end - start))
    }

    // MARK: - Inline Helpers

    private mutating func visitInlineChildren(of markup: Markup) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    private mutating func visitBlockChildren(of markup: Markup) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    private func applySourceRange(_ range: NSRange?, to attrStr: NSMutableAttributedString) {
        if let range {
            let fullRange = NSRange(location: 0, length: attrStr.length)
            attrStr.addAttribute(.markdownSourceRange, value: range as NSRange, range: fullRange)
        }
    }

    // MARK: - Default Visit

    mutating func defaultVisit(_ markup: Markup) -> NSMutableAttributedString {
        return visitInlineChildren(of: markup)
    }

    // MARK: - Block Elements

    mutating func visitDocument(_ document: Document) -> NSMutableAttributedString {
        return visitBlockChildren(of: document)
    }

    mutating func visitHeading(_ heading: Heading) -> NSMutableAttributedString {
        let level = heading.level
        let saved = inlineAttributes
        inlineAttributes[.markdownHeading] = level
        inlineAttributes[.font] = MarkdownStyles.headingFont(level: level)
        inlineAttributes[.paragraphStyle] = MarkdownStyles.paragraphStyle(forHeading: level)

        let content = visitInlineChildren(of: heading)
        content.append(NSAttributedString(string: "\n"))

        inlineAttributes = saved

        let fullRange = NSRange(location: 0, length: content.length)
        content.addAttribute(.markdownHeading, value: level, range: fullRange)
        content.addAttribute(.font, value: MarkdownStyles.headingFont(level: level), range: fullRange)
        content.addAttribute(.paragraphStyle, value: MarkdownStyles.paragraphStyle(forHeading: level), range: fullRange)
        applySourceRange(sourceRange(for: heading), to: content)
        return content
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSMutableAttributedString {
        let saved = inlineAttributes
        if inlineAttributes[.font] == nil {
            inlineAttributes[.font] = bodyFont
        }
        if inlineAttributes[.paragraphStyle] == nil {
            inlineAttributes[.paragraphStyle] = MarkdownStyles.bodyParagraphStyle
        }

        let content = visitInlineChildren(of: paragraph)
        content.append(NSAttributedString(string: "\n"))

        inlineAttributes = saved

        // Apply body font to any ranges that don't yet have a font
        let fullRange = NSRange(location: 0, length: content.length)
        content.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil {
                content.addAttribute(.font, value: self.bodyFont, range: range)
            }
        }
        // Apply paragraph style if not already set
        content.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            if value == nil {
                content.addAttribute(.paragraphStyle, value: MarkdownStyles.bodyParagraphStyle, range: range)
            }
        }
        applySourceRange(sourceRange(for: paragraph), to: content)
        return content
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSMutableAttributedString {
        let code = codeBlock.code
        let attrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .markdownCode: true,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let content = NSMutableAttributedString(string: code, attributes: attrs)
        // Code blocks from swift-markdown already end with \n; add block separator if needed
        if !code.hasSuffix("\n") {
            content.append(NSAttributedString(string: "\n", attributes: attrs))
        }
        applySourceRange(sourceRange(for: codeBlock), to: content)
        return content
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSMutableAttributedString {
        let saved = inlineAttributes
        // Calculate depth by walking ancestors
        var depth = 0
        var parent = blockQuote.parent
        while parent != nil {
            if parent is BlockQuote { depth += 1 }
            parent = parent?.parent
        }
        inlineAttributes[.markdownBlockquote] = true
        inlineAttributes[.paragraphStyle] = MarkdownStyles.blockquoteParagraphStyle(depth: depth + 1)
        inlineAttributes[.foregroundColor] = NSColor.secondaryLabelColor

        let content = visitBlockChildren(of: blockQuote)

        inlineAttributes = saved

        let fullRange = NSRange(location: 0, length: content.length)
        content.addAttribute(.markdownBlockquote, value: true, range: fullRange)
        applySourceRange(sourceRange(for: blockQuote), to: content)
        return content
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for item in unorderedList.listItems {
            let saved = inlineAttributes

            // Calculate list depth
            var depth = 0
            var parent: Markup? = unorderedList.parent
            while parent != nil {
                if parent is UnorderedList || parent is OrderedList { depth += 1 }
                parent = parent?.parent
            }

            let listStyle: MarkdownListStyle
            if let checkbox = item.checkbox {
                listStyle = .task(depth: depth, checked: checkbox == .checked)
            } else {
                listStyle = .unordered(depth: depth, marker: "\u{2022}")
            }

            inlineAttributes[.markdownListItem] = listStyle
            inlineAttributes[.paragraphStyle] = MarkdownStyles.listParagraphStyle(depth: depth)

            let itemContent = visitListItemContent(item, style: listStyle)
            result.append(itemContent)

            inlineAttributes = saved
        }
        applySourceRange(sourceRange(for: unorderedList), to: result)
        return result
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        var number = Int(orderedList.startIndex)
        for item in orderedList.listItems {
            let saved = inlineAttributes

            var depth = 0
            var parent: Markup? = orderedList.parent
            while parent != nil {
                if parent is UnorderedList || parent is OrderedList { depth += 1 }
                parent = parent?.parent
            }

            let listStyle = MarkdownListStyle.ordered(depth: depth, start: number)
            inlineAttributes[.markdownListItem] = listStyle
            inlineAttributes[.paragraphStyle] = MarkdownStyles.listParagraphStyle(depth: depth)

            let itemContent = visitListItemContent(item, style: listStyle)
            result.append(itemContent)

            inlineAttributes = saved
            number += 1
        }
        applySourceRange(sourceRange(for: orderedList), to: result)
        return result
    }

    private mutating func visitListItemContent(_ item: ListItem, style: MarkdownListStyle) -> NSMutableAttributedString {
        let prefix: String
        switch style {
        case .unordered(_, let marker):
            prefix = "\(marker)\t"
        case .ordered(_, let start):
            prefix = "\(start).\t"
        case .task(_, let checked):
            prefix = checked ? "\u{2611}\t" : "\u{2610}\t"
        }

        let result = NSMutableAttributedString()
        let prefixAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .markdownListItem: style,
        ]
        result.append(NSAttributedString(string: prefix, attributes: prefixAttrs))

        // Visit child blocks of the list item
        for child in item.children {
            let childResult = visit(child)
            result.append(childResult)
        }

        // Ensure it ends with newline
        if !result.string.hasSuffix("\n") {
            result.append(NSAttributedString(string: "\n"))
        }

        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.markdownListItem, value: style, range: fullRange)
        if let ps = inlineAttributes[.paragraphStyle] {
            result.addAttribute(.paragraphStyle, value: ps, range: fullRange)
        }
        applySourceRange(sourceRange(for: item), to: result)
        return result
    }

    mutating func visitListItem(_ listItem: ListItem) -> NSMutableAttributedString {
        // List items are handled by visitUnorderedList / visitOrderedList
        return visitBlockChildren(of: listItem)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSMutableAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        ]
        let result = NSMutableAttributedString(string: "\u{2500}\u{2500}\u{2500}\n", attributes: attrs)
        applySourceRange(sourceRange(for: thematicBreak), to: result)
        return result
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSMutableAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let content = NSMutableAttributedString(string: html.rawHTML, attributes: attrs)
        if !html.rawHTML.hasSuffix("\n") {
            content.append(NSAttributedString(string: "\n", attributes: attrs))
        }
        applySourceRange(sourceRange(for: html), to: content)
        return content
    }

    // MARK: - Table Elements

    mutating func visitTable(_ table: Table) -> NSMutableAttributedString {
        // Simple text representation for now
        let result = NSMutableAttributedString()
        result.append(visit(table.head))
        result.append(visit(table.body))
        applySourceRange(sourceRange(for: table), to: result)
        return result
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        var cellStrings: [String] = []
        for cell in tableHead.cells {
            let content = visitInlineChildren(of: cell)
            cellStrings.append(content.string)
        }
        let line = cellStrings.joined(separator: " | ")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
        ]
        result.append(NSAttributedString(string: line + "\n", attributes: attrs))
        return result
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for row in tableBody.rows {
            var cellStrings: [String] = []
            for cell in row.cells {
                let content = visitInlineChildren(of: cell)
                cellStrings.append(content.string)
            }
            let line = cellStrings.joined(separator: " | ")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
            ]
            result.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }
        return result
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Markdown.Text) -> NSMutableAttributedString {
        var attrs = inlineAttributes
        if attrs[.font] == nil {
            attrs[.font] = bodyFont
        }
        return NSMutableAttributedString(string: text.string, attributes: attrs)
    }

    mutating func visitStrong(_ strong: Strong) -> NSMutableAttributedString {
        let saved = inlineAttributes
        inlineAttributes[.markdownStrong] = true

        // Bold the font: if there's already a font, make it bold
        if let existingFont = inlineAttributes[.font] as? NSFont {
            inlineAttributes[.font] = NSFontManager.shared.convert(existingFont, toHaveTrait: .boldFontMask)
        } else {
            inlineAttributes[.font] = NSFont.boldSystemFont(ofSize: 16)
        }

        let result = visitInlineChildren(of: strong)

        // Ensure .markdownStrong is applied to entire range
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.markdownStrong, value: true, range: fullRange)

        inlineAttributes = saved
        return result
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSMutableAttributedString {
        let saved = inlineAttributes
        inlineAttributes[.markdownEmphasis] = true

        if let existingFont = inlineAttributes[.font] as? NSFont {
            inlineAttributes[.font] = NSFontManager.shared.convert(existingFont, toHaveTrait: .italicFontMask)
        } else {
            let baseFont = NSFont.systemFont(ofSize: 16)
            inlineAttributes[.font] = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        }

        let result = visitInlineChildren(of: emphasis)

        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.markdownEmphasis, value: true, range: fullRange)

        inlineAttributes = saved
        return result
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> NSMutableAttributedString {
        var attrs = inlineAttributes
        attrs[.font] = monoFont
        attrs[.markdownCode] = true
        attrs[.foregroundColor] = NSColor.secondaryLabelColor
        return NSMutableAttributedString(string: inlineCode.code, attributes: attrs)
    }

    mutating func visitLink(_ link: Link) -> NSMutableAttributedString {
        let saved = inlineAttributes
        if let dest = link.destination {
            inlineAttributes[.markdownLink] = dest
        }
        inlineAttributes[.foregroundColor] = NSColor.linkColor

        let result = visitInlineChildren(of: link)

        // Ensure link attribute covers the full range
        let fullRange = NSRange(location: 0, length: result.length)
        if let dest = link.destination {
            result.addAttribute(.markdownLink, value: dest, range: fullRange)
        }

        inlineAttributes = saved
        return result
    }

    mutating func visitImage(_ image: Image) -> NSMutableAttributedString {
        // Placeholder for now — later tasks will add real image attachments
        let alt = image.title ?? image.plainText
        let placeholder = "[Image: \(alt)]"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        return NSMutableAttributedString(string: placeholder, attributes: attrs)
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> NSMutableAttributedString {
        return NSMutableAttributedString(string: "\n")
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> NSMutableAttributedString {
        return NSMutableAttributedString(string: " ")
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> NSMutableAttributedString {
        var attrs = inlineAttributes
        attrs[.font] = monoFont
        attrs[.foregroundColor] = NSColor.secondaryLabelColor
        return NSMutableAttributedString(string: inlineHTML.rawHTML, attributes: attrs)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSMutableAttributedString {
        let saved = inlineAttributes
        inlineAttributes[.markdownStrikethrough] = true
        inlineAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue

        let result = visitInlineChildren(of: strikethrough)

        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.markdownStrikethrough, value: true, range: fullRange)
        result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)

        inlineAttributes = saved
        return result
    }
}
