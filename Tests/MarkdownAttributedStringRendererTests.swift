// Tests/MarkdownAttributedStringRendererTests.swift
import Testing
import AppKit
import Markdown
@testable import OnYourMarks

@Suite("MarkdownAttributedStringRenderer")
struct MarkdownAttributedStringRendererTests {

    @MainActor
    private func render(_ markdown: String) -> NSAttributedString {
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse(markdown)
        var renderer = MarkdownAttributedStringRenderer(source: markdown)
        return renderer.render(doc)
    }

    @Test("Plain paragraph")
    @MainActor
    func plainParagraph() {
        let result = render("Hello world")
        #expect(result.string == "Hello world\n")
    }

    @Test("Heading level 1")
    @MainActor
    func headingLevel1() {
        let result = render("# Title")
        #expect(result.string == "Title\n")
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownHeading] as? Int == 1)
    }

    @Test("Bold text")
    @MainActor
    func boldText() {
        let result = render("**bold**")
        #expect(result.string == "bold\n")
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownStrong] as? Bool == true)
    }

    @Test("Italic text")
    @MainActor
    func italicText() {
        let result = render("*italic*")
        #expect(result.string == "italic\n")
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownEmphasis] as? Bool == true)
    }

    @Test("Nested bold and italic")
    @MainActor
    func nestedBoldItalic() {
        let result = render("**bold *and italic***")
        // Find "and italic" within the string — the exact offset may vary
        let str = result.string
        if let range = str.range(of: "and") {
            let nsRange = NSRange(range, in: str)
            let attrs = result.attributes(at: nsRange.location, effectiveRange: nil)
            #expect(attrs[.markdownStrong] as? Bool == true)
            #expect(attrs[.markdownEmphasis] as? Bool == true)
        }
    }

    @Test("Strikethrough text")
    @MainActor
    func strikethroughText() {
        let result = render("~~deleted~~")
        #expect(result.string.contains("deleted"))
        // Find the "deleted" text and check attributes
        let str = result.string
        if let range = str.range(of: "deleted") {
            let nsRange = NSRange(range, in: str)
            let attrs = result.attributes(at: nsRange.location, effectiveRange: nil)
            #expect(attrs[.markdownStrikethrough] as? Bool == true)
        }
    }

    @Test("Inline code")
    @MainActor
    func inlineCode() {
        let result = render("`code`")
        #expect(result.string.contains("code"))
        let str = result.string
        if let range = str.range(of: "code") {
            let nsRange = NSRange(range, in: str)
            let attrs = result.attributes(at: nsRange.location, effectiveRange: nil)
            #expect(attrs[.markdownCode] as? Bool == true)
        }
    }

    @Test("Link with URL")
    @MainActor
    func link() {
        let result = render("[text](https://example.com)")
        #expect(result.string.contains("text"))
        let str = result.string
        if let range = str.range(of: "text") {
            let nsRange = NSRange(range, in: str)
            let attrs = result.attributes(at: nsRange.location, effectiveRange: nil)
            #expect(attrs[.markdownLink] as? String == "https://example.com")
        }
    }

    @Test("Unordered list")
    @MainActor
    func unorderedList() {
        let result = render("- item one\n- item two")
        #expect(result.string.contains("item one"))
    }

    @Test("Blockquote")
    @MainActor
    func blockquote() {
        let result = render("> quoted text")
        #expect(result.string.contains("quoted text"))
    }

    @Test("Source ranges are set")
    @MainActor
    func sourceRangesAreSet() {
        let source = "# Heading\n\nParagraph"
        let result = render(source)
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownSourceRange] as? NSRange != nil)
    }
}
