// Tests/HTMLRendererTests.swift
import Testing
import Foundation
import Markdown
@testable import OnYourMarks

@Suite("HTMLRenderer")
struct HTMLRendererTests {

    @Test("Renders heading as h1 tag")
    func rendersHeading() {
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse("# Hello")
        var renderer = HTMLRenderer(useGFM: true)
        let html = renderer.render(doc)
        #expect(html.contains("<h1>Hello</h1>"))
    }

    @Test("Renders paragraph")
    func rendersParagraph() {
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse("Some text here.")
        var renderer = HTMLRenderer(useGFM: true)
        let html = renderer.render(doc)
        #expect(html.contains("<p>Some text here.</p>"))
    }

    @Test("Renders bold text")
    func rendersBold() {
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse("This is **bold** text.")
        var renderer = HTMLRenderer(useGFM: true)
        let html = renderer.render(doc)
        #expect(html.contains("<strong>bold</strong>"))
    }

    @Test("Renders italic text")
    func rendersItalic() {
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse("This is *italic* text.")
        var renderer = HTMLRenderer(useGFM: true)
        let html = renderer.render(doc)
        #expect(html.contains("<em>italic</em>"))
    }

    @Test("Renders fenced code block with language class and copy button")
    func rendersCodeBlock() {
        let input = """
        ```swift
        let x = 1
        ```
        """
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse(input)
        var renderer = HTMLRenderer(useGFM: true)
        let html = renderer.render(doc)
        #expect(html.contains("class=\"language-swift\""))
        #expect(html.contains("copy-button"))
        #expect(html.contains("let x = 1"))
    }

    @Test("Renders code block without language")
    func rendersCodeBlockNoLanguage() {
        let input = """
        ```
        plain code
        ```
        """
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse(input)
        var renderer = HTMLRenderer(useGFM: true)
        let html = renderer.render(doc)
        #expect(html.contains("<code>"))
        #expect(html.contains("plain code"))
    }

    @Test("Renders unordered list")
    func rendersUnorderedList() {
        let input = """
        - Item 1
        - Item 2
        """
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse(input)
        var renderer = HTMLRenderer(useGFM: true)
        let html = renderer.render(doc)
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>"))
    }

    @Test("Renders link")
    func rendersLink() {
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse("[Click](https://example.com)")
        var renderer = HTMLRenderer(useGFM: true)
        let html = renderer.render(doc)
        #expect(html.contains("<a href=\"https://example.com\">Click</a>"))
    }

    @Test("Renders GFM table")
    func rendersTable() {
        let input = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse(input)
        var renderer = HTMLRenderer(useGFM: true)
        let html = renderer.render(doc)
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>"))
        #expect(html.contains("<td>"))
    }

    @Test("Escapes HTML entities in text")
    func escapesHTMLEntities() {
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse("Use <div> tags & \"quotes\"")
        var renderer = HTMLRenderer(useGFM: true)
        let html = renderer.render(doc)
        #expect(html.contains("&lt;div&gt;"))
        #expect(html.contains("&amp;"))
    }
}
