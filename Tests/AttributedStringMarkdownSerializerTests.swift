// Tests/AttributedStringMarkdownSerializerTests.swift
import Testing
import AppKit
import Markdown
@testable import OnYourMarks

@Suite("AttributedStringMarkdownSerializer")
struct AttributedStringMarkdownSerializerTests {

    @MainActor
    private func roundTrip(_ markdown: String) -> String {
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse(markdown)
        var renderer = MarkdownAttributedStringRenderer(source: markdown)
        let attrStr = renderer.render(doc)
        let serializer = AttributedStringMarkdownSerializer(originalSource: markdown)
        return serializer.serialize(attrStr)
    }

    @Test("Plain paragraph round-trips")
    @MainActor func plainParagraph() {
        let result = roundTrip("Hello world")
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello world")
    }

    @Test("Heading round-trips")
    @MainActor func heading() {
        let result = roundTrip("# Title")
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == "# Title")
    }

    @Test("Bold round-trips")
    @MainActor func boldText() {
        let result = roundTrip("**bold**")
        #expect(result.contains("**bold**"))
    }

    @Test("Italic round-trips")
    @MainActor func italicText() {
        let result = roundTrip("*italic*")
        #expect(result.contains("*italic*"))
    }

    @Test("Strikethrough round-trips")
    @MainActor func strikethroughText() {
        let result = roundTrip("~~deleted~~")
        #expect(result.contains("~~deleted~~"))
    }

    @Test("Inline code round-trips")
    @MainActor func inlineCode() {
        let result = roundTrip("`code`")
        #expect(result.contains("`code`"))
    }

    @Test("Link round-trips")
    @MainActor func link() {
        let result = roundTrip("[text](https://example.com)")
        #expect(result.contains("[text](https://example.com)"))
    }

    @Test("Blockquote round-trips")
    @MainActor func blockquote() {
        let result = roundTrip("> quoted text")
        #expect(result.contains("> quoted text"))
    }

    @Test("New content without source ranges serializes correctly")
    @MainActor func newContentWithoutSourceRanges() {
        let str = NSMutableAttributedString(string: "Hello", attributes: [
            .font: MarkdownStyles.bodyFont,
            .markdownStrong: true,
        ])
        let serializer = AttributedStringMarkdownSerializer(originalSource: "")
        let result = serializer.serialize(str)
        #expect(result.contains("**Hello**"))
    }
}
