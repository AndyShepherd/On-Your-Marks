// Sources/Preview/HTMLRenderer.swift
import Foundation
import Markdown

struct HTMLRenderer: MarkupVisitor {
    typealias Result = String

    var useGFM: Bool = true

    init(useGFM: Bool = true) {
        self.useGFM = useGFM
    }

    mutating func render(_ document: Document) -> String {
        return visit(document)
    }

    // MARK: - Helpers

    func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private mutating func visitChildren(of markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    // MARK: - MarkupVisitor default

    mutating func defaultVisit(_ markup: Markup) -> String {
        return visitChildren(of: markup)
    }

    // MARK: - Block elements

    mutating func visitDocument(_ document: Document) -> String {
        return visitChildren(of: document)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = heading.level
        let content = visitChildren(of: heading)
        return "<h\(level)>\(content)</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let content = visitChildren(of: paragraph)
        return "<p>\(content)</p>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let code = escapeHTML(codeBlock.code)
        if let language = codeBlock.language, !language.isEmpty {
            return """
            <div class="code-block-wrapper">\
            <button class="copy-button">Copy</button>\
            <pre><code class="language-\(language)">\(code)</code></pre>\
            </div>\n
            """
        } else {
            return """
            <div class="code-block-wrapper">\
            <button class="copy-button">Copy</button>\
            <pre><code>\(code)</code></pre>\
            </div>\n
            """
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let content = visitChildren(of: blockQuote)
        return "<blockquote>\n\(content)</blockquote>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let content = visitChildren(of: unorderedList)
        return "<ul>\n\(content)</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let content = visitChildren(of: orderedList)
        return "<ol>\n\(content)</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let content = visitChildren(of: listItem)
        return "<li>\(content)</li>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        return "<hr />\n"
    }

    // MARK: - Table elements

    mutating func visitTable(_ table: Table) -> String {
        guard useGFM else {
            return table.format()
        }
        let head = visitTableHead(table.head)
        let body = visitTableBody(table.body)
        return "<table>\n\(head)\(body)</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        var cells = ""
        for cell in tableHead.cells {
            let content = visitChildren(of: cell)
            cells += "<th>\(content)</th>\n"
        }
        return "<thead>\n<tr>\n\(cells)</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        var rows = ""
        for row in tableBody.rows {
            var cells = ""
            for cell in row.cells {
                let content = visitChildren(of: cell)
                cells += "<td>\(content)</td>\n"
            }
            rows += "<tr>\n\(cells)</tr>\n"
        }
        if rows.isEmpty { return "" }
        return "<tbody>\n\(rows)</tbody>\n"
    }

    // MARK: - Inline elements

    mutating func visitText(_ text: Markdown.Text) -> String {
        return escapeHTML(text.string)
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        let content = visitChildren(of: strong)
        return "<strong>\(content)</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        let content = visitChildren(of: emphasis)
        return "<em>\(content)</em>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        return "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Link) -> String {
        let content = visitChildren(of: link)
        if let destination = link.destination {
            return "<a href=\"\(destination)\">\(content)</a>"
        } else {
            return "<a>\(content)</a>"
        }
    }

    mutating func visitImage(_ image: Image) -> String {
        let src = image.source ?? ""
        let alt = image.title ?? visitChildren(of: image)
        return "<img src=\"\(src)\" alt=\"\(alt)\" />"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        return "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        return "\n"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        return escapeHTML(inlineHTML.rawHTML)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        return escapeHTML(html.rawHTML)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        let content = visitChildren(of: strikethrough)
        if useGFM {
            return "<del>\(content)</del>"
        } else {
            return content
        }
    }
}
