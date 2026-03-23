// Tests/WYSIWYGFormattingTests.swift
import Testing
import AppKit
@testable import OnYourMarks

@Suite("WYSIWYGFormatting")
struct WYSIWYGFormattingTests {

    // MARK: - Bold

    @Test("Toggle bold on — sets attribute and makes font bold")
    @MainActor
    func toggleBoldOn() {
        let storage = NSTextStorage(string: "hello", attributes: [.font: MarkdownStyles.bodyFont])
        WYSIWYGFormatting.toggleBold(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownStrong] as? Bool == true)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(NSFontManager.shared.traits(of: font!).contains(.boldFontMask))
    }

    @Test("Toggle bold off — removes attribute and bold trait")
    @MainActor
    func toggleBoldOff() {
        let boldFont = NSFontManager.shared.convert(MarkdownStyles.bodyFont, toHaveTrait: .boldFontMask)
        let storage = NSTextStorage(string: "hello", attributes: [
            .font: boldFont,
            .markdownStrong: true,
        ])
        WYSIWYGFormatting.toggleBold(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownStrong] == nil)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(!NSFontManager.shared.traits(of: font!).contains(.boldFontMask))
    }

    @Test("Toggle bold clears source range")
    @MainActor
    func toggleBoldClearsSourceRange() {
        let storage = NSTextStorage(string: "hello", attributes: [
            .font: MarkdownStyles.bodyFont,
            .markdownSourceRange: NSRange(location: 0, length: 10),
        ])
        WYSIWYGFormatting.toggleBold(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownSourceRange] == nil)
    }

    // MARK: - Italic

    @Test("Toggle italic on — sets attribute and makes font italic")
    @MainActor
    func toggleItalicOn() {
        let storage = NSTextStorage(string: "hello", attributes: [.font: MarkdownStyles.bodyFont])
        WYSIWYGFormatting.toggleItalic(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownEmphasis] as? Bool == true)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(NSFontManager.shared.traits(of: font!).contains(.italicFontMask))
    }

    @Test("Toggle italic off — removes attribute and italic trait")
    @MainActor
    func toggleItalicOff() {
        let italicFont = NSFontManager.shared.convert(MarkdownStyles.bodyFont, toHaveTrait: .italicFontMask)
        let storage = NSTextStorage(string: "hello", attributes: [
            .font: italicFont,
            .markdownEmphasis: true,
        ])
        WYSIWYGFormatting.toggleItalic(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownEmphasis] == nil)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(!NSFontManager.shared.traits(of: font!).contains(.italicFontMask))
    }

    // MARK: - Strikethrough

    @Test("Toggle strikethrough on — sets attribute and strikethrough style")
    @MainActor
    func toggleStrikethroughOn() {
        let storage = NSTextStorage(string: "hello", attributes: [.font: MarkdownStyles.bodyFont])
        WYSIWYGFormatting.toggleStrikethrough(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownStrikethrough] as? Bool == true)
        #expect(attrs[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test("Toggle strikethrough off — removes attribute and strikethrough style")
    @MainActor
    func toggleStrikethroughOff() {
        let storage = NSTextStorage(string: "hello", attributes: [
            .font: MarkdownStyles.bodyFont,
            .markdownStrikethrough: true,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        ])
        WYSIWYGFormatting.toggleStrikethrough(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownStrikethrough] == nil)
        #expect(attrs[.strikethroughStyle] == nil)
    }

    // MARK: - Inline Code

    @Test("Toggle inline code on — sets attribute and monospace font")
    @MainActor
    func toggleInlineCodeOn() {
        let storage = NSTextStorage(string: "hello", attributes: [.font: MarkdownStyles.bodyFont])
        WYSIWYGFormatting.toggleInlineCode(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownCode] as? Bool == true)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.isFixedPitch || font!.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    @Test("Toggle inline code off — removes attribute and restores body font")
    @MainActor
    func toggleInlineCodeOff() {
        let storage = NSTextStorage(string: "hello", attributes: [
            .font: MarkdownStyles.monoFont,
            .markdownCode: true,
        ])
        WYSIWYGFormatting.toggleInlineCode(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownCode] == nil)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize == MarkdownStyles.bodyFont.pointSize)
    }

    // MARK: - Heading

    @Test("Set heading level 1 — sets attribute and heading font")
    @MainActor
    func setHeading1() {
        let storage = NSTextStorage(string: "Title", attributes: [.font: MarkdownStyles.bodyFont])
        WYSIWYGFormatting.setHeading(level: 1, in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownHeading] as? Int == 1)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize == 28)
    }

    @Test("Set heading level 0 removes heading")
    @MainActor
    func removeHeading() {
        let storage = NSTextStorage(string: "Title", attributes: [
            .font: MarkdownStyles.headingFont(level: 1),
            .markdownHeading: 1,
        ])
        WYSIWYGFormatting.setHeading(level: 0, in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownHeading] == nil)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize == MarkdownStyles.bodyFont.pointSize)
    }

    // MARK: - Blockquote

    @Test("Toggle blockquote on — sets attribute and indented paragraph style")
    @MainActor
    func toggleBlockquoteOn() {
        let storage = NSTextStorage(string: "quoted", attributes: [
            .font: MarkdownStyles.bodyFont,
            .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
        ])
        WYSIWYGFormatting.toggleBlockquote(in: storage, range: NSRange(location: 0, length: 6))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownBlockquote] as? Bool == true)
        let style = attrs[.paragraphStyle] as? NSParagraphStyle
        #expect(style != nil)
        #expect(style!.headIndent > 0)
    }

    @Test("Toggle blockquote off — removes attribute and restores body style")
    @MainActor
    func toggleBlockquoteOff() {
        let storage = NSTextStorage(string: "quoted", attributes: [
            .font: MarkdownStyles.bodyFont,
            .markdownBlockquote: true,
            .paragraphStyle: MarkdownStyles.blockquoteParagraphStyle(depth: 1),
        ])
        WYSIWYGFormatting.toggleBlockquote(in: storage, range: NSRange(location: 0, length: 6))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownBlockquote] == nil)
        let style = attrs[.paragraphStyle] as? NSParagraphStyle
        #expect(style != nil)
        #expect(style!.headIndent == 0)
    }

    // MARK: - Link

    @Test("Set link — sets attribute, color, and underline")
    @MainActor
    func setLink() {
        let storage = NSTextStorage(string: "click", attributes: [.font: MarkdownStyles.bodyFont])
        WYSIWYGFormatting.setLink(url: "https://example.com", in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownLink] as? String == "https://example.com")
        #expect(attrs[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attrs[.foregroundColor] as? NSColor != nil)
    }

    @Test("Remove link — removes attributes")
    @MainActor
    func removeLink() {
        let storage = NSTextStorage(string: "click", attributes: [
            .font: MarkdownStyles.bodyFont,
            .markdownLink: "https://example.com",
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.linkColor,
        ])
        WYSIWYGFormatting.removeLink(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownLink] == nil)
        #expect(attrs[.underlineStyle] == nil)
        #expect(attrs[.foregroundColor] == nil)
    }
}
