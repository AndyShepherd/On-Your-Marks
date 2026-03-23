// Sources/WYSIWYG/WYSIWYGFormatting.swift
import AppKit

enum WYSIWYGFormatting {

    // MARK: - Bold

    @MainActor
    static func toggleBold(in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }

        let isActive = storage.attributes(at: range.location, effectiveRange: nil)[.markdownStrong] as? Bool == true

        storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let currentFont = (value as? NSFont) ?? MarkdownStyles.bodyFont
            let fm = NSFontManager.shared
            let newFont: NSFont
            if isActive {
                newFont = fm.convert(currentFont, toNotHaveTrait: .boldFontMask)
            } else {
                newFont = fm.convert(currentFont, toHaveTrait: .boldFontMask)
            }
            storage.addAttribute(.font, value: newFont, range: subRange)
        }

        if isActive {
            storage.removeAttribute(.markdownStrong, range: range)
        } else {
            storage.addAttribute(.markdownStrong, value: true, range: range)
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
    }

    // MARK: - Italic

    @MainActor
    static func toggleItalic(in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }

        let isActive = storage.attributes(at: range.location, effectiveRange: nil)[.markdownEmphasis] as? Bool == true

        storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let currentFont = (value as? NSFont) ?? MarkdownStyles.bodyFont
            let fm = NSFontManager.shared
            let newFont: NSFont
            if isActive {
                newFont = fm.convert(currentFont, toNotHaveTrait: .italicFontMask)
            } else {
                newFont = fm.convert(currentFont, toHaveTrait: .italicFontMask)
            }
            storage.addAttribute(.font, value: newFont, range: subRange)
        }

        if isActive {
            storage.removeAttribute(.markdownEmphasis, range: range)
        } else {
            storage.addAttribute(.markdownEmphasis, value: true, range: range)
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
    }

    // MARK: - Strikethrough

    @MainActor
    static func toggleStrikethrough(in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }

        let isActive = storage.attributes(at: range.location, effectiveRange: nil)[.markdownStrikethrough] as? Bool == true

        if isActive {
            storage.removeAttribute(.markdownStrikethrough, range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
        } else {
            storage.addAttribute(.markdownStrikethrough, value: true, range: range)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
    }

    // MARK: - Inline Code

    @MainActor
    static func toggleInlineCode(in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }

        let isActive = storage.attributes(at: range.location, effectiveRange: nil)[.markdownCode] as? Bool == true

        if isActive {
            storage.removeAttribute(.markdownCode, range: range)
            storage.addAttribute(.font, value: MarkdownStyles.bodyFont, range: range)
        } else {
            storage.addAttribute(.markdownCode, value: true, range: range)
            storage.addAttribute(.font, value: MarkdownStyles.monoFont, range: range)
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
    }

    // MARK: - Heading

    @MainActor
    static func setHeading(level: Int, in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }

        if level >= 1 && level <= 6 {
            storage.addAttribute(.markdownHeading, value: level, range: range)
            storage.addAttribute(.font, value: MarkdownStyles.headingFont(level: level), range: range)
            storage.addAttribute(.paragraphStyle, value: MarkdownStyles.paragraphStyle(forHeading: level), range: range)
        } else {
            // level 0 means remove heading
            storage.removeAttribute(.markdownHeading, range: range)
            storage.addAttribute(.font, value: MarkdownStyles.bodyFont, range: range)
            storage.addAttribute(.paragraphStyle, value: MarkdownStyles.bodyParagraphStyle, range: range)
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
    }

    // MARK: - Blockquote

    @MainActor
    static func toggleBlockquote(in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }

        let isActive = storage.attributes(at: range.location, effectiveRange: nil)[.markdownBlockquote] as? Bool == true

        if isActive {
            storage.removeAttribute(.markdownBlockquote, range: range)
            storage.addAttribute(.paragraphStyle, value: MarkdownStyles.bodyParagraphStyle, range: range)
        } else {
            storage.addAttribute(.markdownBlockquote, value: true, range: range)
            storage.addAttribute(.paragraphStyle, value: MarkdownStyles.blockquoteParagraphStyle(depth: 1), range: range)
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
    }

    // MARK: - Link

    @MainActor
    static func setLink(url: String, in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }

        storage.addAttribute(.markdownLink, value: url, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        storage.removeAttribute(.markdownSourceRange, range: range)
    }

    @MainActor
    static func removeLink(in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }

        storage.removeAttribute(.markdownLink, range: range)
        storage.removeAttribute(.foregroundColor, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.removeAttribute(.markdownSourceRange, range: range)
    }
}
