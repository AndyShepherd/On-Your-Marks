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

    @Test("Mode switching preserves content")
    @MainActor func modeSwitchingPreservesContent() {
        let original = "# Hello\n\nThis is **bold** and *italic*.\n"
        let result = roundTrip(original)
        #expect(result.contains("# Hello"))
        #expect(result.contains("**bold**"))
        #expect(result.contains("*italic*"))
    }

    @Test("Corpus files preserve content through round-trip")
    @MainActor func corpusRoundTrip() throws {
        guard let fixturesURL = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            Issue.record("Fixtures directory not found in test bundle")
            return
        }
        let files = try FileManager.default.contentsOfDirectory(at: fixturesURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }

        #expect(!files.isEmpty, "Should find fixture files")

        for file in files {
            let original = try String(contentsOf: file, encoding: .utf8)
            let result = roundTrip(original)
            // Verify key content is preserved (not byte-identical, but content-equivalent)
            let originalWords = Set(original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
            for word in originalWords {
                // Skip markdown syntax characters
                let stripped = word.trimmingCharacters(in: CharacterSet(charactersIn: "#*_~`[]()>-"))
                if stripped.count >= 3 {
                    #expect(result.contains(stripped), "Round-trip lost content '\(stripped)' from \(file.lastPathComponent)")
                }
            }
        }
    }
}
