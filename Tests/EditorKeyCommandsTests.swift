// Tests/EditorKeyCommandsTests.swift
import Testing
import Foundation
@testable import OnYourMarks

@Suite("EditorKeyCommands")
struct EditorKeyCommandsTests {

    @Test("Bold wraps selection")
    func boldWithSelection() {
        var text = "Hello World"
        var range = NSRange(location: 6, length: 5)
        EditorKeyCommands.bold(text: &text, selectedRange: &range)
        #expect(text == "Hello **World**")
        #expect(range == NSRange(location: 8, length: 5))
    }

    @Test("Bold inserts markers with no selection")
    func boldNoSelection() {
        var text = "Hello "
        var range = NSRange(location: 6, length: 0)
        EditorKeyCommands.bold(text: &text, selectedRange: &range)
        #expect(text == "Hello ****")
        #expect(range == NSRange(location: 8, length: 0))
    }

    @Test("Italic wraps selection")
    func italicWithSelection() {
        var text = "Hello World"
        var range = NSRange(location: 6, length: 5)
        EditorKeyCommands.italic(text: &text, selectedRange: &range)
        #expect(text == "Hello *World*")
        #expect(range == NSRange(location: 7, length: 5))
    }

    @Test("Inline code wraps selection")
    func codeWithSelection() {
        var text = "Hello World"
        var range = NSRange(location: 6, length: 5)
        EditorKeyCommands.inlineCode(text: &text, selectedRange: &range)
        #expect(text == "Hello `World`")
        #expect(range == NSRange(location: 7, length: 5))
    }

    @Test("Link wraps selection as link text")
    func linkWithSelection() {
        var text = "Click here"
        var range = NSRange(location: 0, length: 10)
        EditorKeyCommands.link(text: &text, selectedRange: &range)
        #expect(text == "[Click here](url)")
        #expect(range == NSRange(location: 13, length: 3))
    }

    @Test("Link inserts template with no selection")
    func linkNoSelection() {
        var text = "Hello "
        var range = NSRange(location: 6, length: 0)
        EditorKeyCommands.link(text: &text, selectedRange: &range)
        #expect(text == "Hello [](url)")
        #expect(range == NSRange(location: 7, length: 0))
    }

    @Test("Heading increase adds # prefix")
    func headingIncrease() {
        var text = "Hello World"
        var range = NSRange(location: 0, length: 0)
        EditorKeyCommands.increaseHeading(text: &text, selectedRange: &range)
        #expect(text == "# Hello World")
    }

    @Test("Heading increase from h1 to h2")
    func headingIncreaseFromH1() {
        var text = "# Hello World"
        var range = NSRange(location: 0, length: 0)
        EditorKeyCommands.increaseHeading(text: &text, selectedRange: &range)
        #expect(text == "## Hello World")
    }

    @Test("Heading decrease from h2 to h1")
    func headingDecrease() {
        var text = "## Hello World"
        var range = NSRange(location: 0, length: 0)
        EditorKeyCommands.decreaseHeading(text: &text, selectedRange: &range)
        #expect(text == "# Hello World")
    }

    @Test("Heading decrease from h1 removes heading")
    func headingDecreaseFromH1() {
        var text = "# Hello World"
        var range = NSRange(location: 0, length: 0)
        EditorKeyCommands.decreaseHeading(text: &text, selectedRange: &range)
        #expect(text == "Hello World")
    }

    @Test("Heading increase at h6 is a no-op")
    func headingIncreaseAtH6() {
        var text = "###### Hello World"
        var range = NSRange(location: 0, length: 0)
        EditorKeyCommands.increaseHeading(text: &text, selectedRange: &range)
        #expect(text == "###### Hello World")
    }

    @Test("Heading decrease on non-heading is a no-op")
    func headingDecreaseOnPlainText() {
        var text = "Hello World"
        var range = NSRange(location: 0, length: 0)
        EditorKeyCommands.decreaseHeading(text: &text, selectedRange: &range)
        #expect(text == "Hello World")
    }

    @Test("Image wraps selection as alt text")
    func imageWithSelection() {
        var text = "screenshot"
        var range = NSRange(location: 0, length: 10)
        EditorKeyCommands.image(text: &text, selectedRange: &range)
        #expect(text == "![screenshot](url)")
        #expect(range == NSRange(location: 14, length: 3))
    }

    @Test("Image inserts template with no selection")
    func imageNoSelection() {
        var text = ""
        var range = NSRange(location: 0, length: 0)
        EditorKeyCommands.image(text: &text, selectedRange: &range)
        #expect(text == "![](url)")
        #expect(range == NSRange(location: 2, length: 0))
    }

    @Test("Code block inserts fenced block")
    func codeBlockInsertion() {
        var text = "Hello"
        var range = NSRange(location: 5, length: 0)
        EditorKeyCommands.codeBlock(text: &text, selectedRange: &range)
        #expect(text.contains("```"))
    }

    @Test("Horizontal rule inserts ---")
    func horizontalRuleInsertion() {
        var text = "Hello"
        var range = NSRange(location: 5, length: 0)
        EditorKeyCommands.horizontalRule(text: &text, selectedRange: &range)
        #expect(text.contains("---"))
    }
}
