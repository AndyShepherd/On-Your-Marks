// Tests/EdgeCaseTests.swift
import Testing
import AppKit
import Markdown
@testable import OnYourMarks

@Suite("Edge Cases")
struct EdgeCaseTests {

    // MARK: - Empty Document

    @Test("Empty string renders without crash")
    @MainActor func emptyRender() {
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse("")
        var renderer = MarkdownAttributedStringRenderer(source: "")
        let result = renderer.render(doc)
        #expect(result.length == 0 || result.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("Empty string serializes without crash")
    func emptySerialize() {
        let serializer = AttributedStringMarkdownSerializer(originalSource: "")
        let result = serializer.serialize(NSAttributedString())
        #expect(result.isEmpty || result == "\n")
    }

    @Test("Empty document round-trips")
    @MainActor func emptyRoundTrip() {
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse("")
        var renderer = MarkdownAttributedStringRenderer(source: "")
        let attrStr = renderer.render(doc)
        let serializer = AttributedStringMarkdownSerializer(originalSource: "")
        let _ = serializer.serialize(attrStr)
        // Just verifying no crash
    }

    // MARK: - Large Document

    @Test("Large document renders without crash")
    @MainActor func largeDocument() {
        let lines = (1...1000).map { "Line \($0) with some **bold** and *italic* text." }
        let source = lines.joined(separator: "\n\n")
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse(source)
        var renderer = MarkdownAttributedStringRenderer(source: source)
        let result = renderer.render(doc)
        #expect(result.length > 0)
    }

    // MARK: - Whitespace Only

    @Test("Whitespace-only document doesn't crash")
    @MainActor func whitespaceOnly() {
        let source = "   \n\n   \n\t\t\n"
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse(source)
        var renderer = MarkdownAttributedStringRenderer(source: source)
        let _ = renderer.render(doc)
    }

    // MARK: - Special Characters

    @Test("Document with only special characters")
    @MainActor func specialChars() {
        let source = "# <>&\"'\n\n`<script>alert('xss')</script>`\n"
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse(source)
        var renderer = MarkdownAttributedStringRenderer(source: source)
        let result = renderer.render(doc)
        #expect(result.length > 0)
    }

    // MARK: - Deeply Nested Lists

    @Test("Deeply nested list doesn't crash")
    @MainActor func deeplyNestedList() {
        var source = ""
        for i in 0..<10 {
            let indent = String(repeating: "  ", count: i)
            source += "\(indent)- Level \(i)\n"
        }
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse(source)
        var renderer = MarkdownAttributedStringRenderer(source: source)
        let result = renderer.render(doc)
        #expect(result.length > 0)
    }

    // MARK: - Table Edge Cases

    @Test("Table with empty cells serializes")
    func emptyTableCells() {
        let attachment = TableAttachment(
            headers: ["", ""],
            rows: [["", ""]],
            alignments: [.left, .left]
        )
        let result = attachment.serializeToMarkdown()
        #expect(result.contains("|"))
    }

    @Test("Table with single cell")
    func singleCellTable() {
        let attachment = TableAttachment(
            headers: ["A"],
            rows: [["1"]],
            alignments: [.left]
        )
        let result = attachment.serializeToMarkdown()
        #expect(result.contains("| A |"))
    }

    @Test("Table with many columns")
    func manyColumnsTable() {
        let headers = (1...20).map { "H\($0)" }
        let row = (1...20).map { "C\($0)" }
        let alignments = Array(repeating: ColumnAlignment.left, count: 20)
        let attachment = TableAttachment(headers: headers, rows: [row], alignments: alignments)
        let result = attachment.serializeToMarkdown()
        #expect(result.contains("H20"))
    }

    // MARK: - Formatting Edge Cases

    @Test("Toggle bold on empty range doesn't crash")
    @MainActor func boldEmptyRange() {
        let storage = NSTextStorage(string: "hello", attributes: [
            .font: MarkdownStyles.bodyFont,
        ])
        // Range with length 0 — should be a no-op, not a crash
        WYSIWYGFormatting.toggleBold(in: storage, range: NSRange(location: 0, length: 0))
        // No crash = pass
    }

    @Test("Toggle bold at end of string doesn't crash")
    @MainActor func boldAtEnd() {
        let storage = NSTextStorage(string: "hello", attributes: [
            .font: MarkdownStyles.bodyFont,
        ])
        WYSIWYGFormatting.toggleBold(in: storage, range: NSRange(location: 5, length: 0))
    }

    // MARK: - MarkdownDocument Edge Cases

    @Test("Document with zero bytes")
    func zeroByteDocument() throws {
        let doc = try MarkdownDocument(data: Data())
        #expect(doc.text.isEmpty)
    }

    @Test("Document content hash is stable")
    func contentHashStable() {
        let doc = MarkdownDocument(text: "test")
        let hash1 = doc.contentHash
        let hash2 = doc.contentHash
        #expect(hash1 == hash2)
    }

    // MARK: - Serializer Edge Cases

    @Test("Serializer handles attributed string with only newlines")
    func onlyNewlines() {
        let str = NSAttributedString(string: "\n\n\n")
        let serializer = AttributedStringMarkdownSerializer(originalSource: "")
        let _ = serializer.serialize(str)
    }

    @Test("Serializer handles attachment character")
    func attachmentChar() {
        let attachment = HorizontalRuleAttachment()
        let str = NSMutableAttributedString(attachment: attachment)
        let serializer = AttributedStringMarkdownSerializer(originalSource: "")
        let result = serializer.serialize(str)
        #expect(result.contains("---"))
    }
}
