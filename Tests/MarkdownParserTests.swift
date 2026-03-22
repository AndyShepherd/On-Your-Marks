// Tests/MarkdownParserTests.swift
import Testing
import Foundation
import Markdown
@testable import OnYourMarks

@Suite("MarkdownParser")
struct MarkdownParserTests {

    @Test("Parses basic CommonMark heading")
    func parsesHeading() {
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse("# Hello World")
        #expect(doc.childCount == 1)
    }

    @Test("Parses GFM table when GFM enabled")
    func parsesGFMTable() {
        let input = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let parserGFM = MarkdownParser(useGFM: true)
        let doc = parserGFM.parse(input)
        let hasTable = doc.children.contains { $0 is Markdown.Table }
        #expect(hasTable)
    }

    @Test("CommonMark mode still parses table in AST (GFM filtering is in renderer)")
    func commonMarkStillParsesTable() {
        let input = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse(input)
        let hasTable = doc.children.contains { $0 is Markdown.Table }
        #expect(hasTable)
    }

    @Test("Parses GFM strikethrough")
    func parsesStrikethrough() {
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse("~~deleted~~")
        #expect(doc.childCount > 0)
    }
}
