// Sources/WYSIWYG/MarkdownAttributes.swift
import AppKit

// MARK: - Custom Attributed String Keys

extension NSAttributedString.Key {
    static let markdownHeading       = NSAttributedString.Key("md.heading")
    static let markdownStrong        = NSAttributedString.Key("md.strong")
    static let markdownEmphasis      = NSAttributedString.Key("md.emphasis")
    static let markdownLink          = NSAttributedString.Key("md.link")
    static let markdownCode          = NSAttributedString.Key("md.code")
    static let markdownBlockquote    = NSAttributedString.Key("md.blockquote")
    static let markdownListItem      = NSAttributedString.Key("md.listItem")
    static let markdownStrikethrough = NSAttributedString.Key("md.strikethrough")
    static let markdownSourceRange   = NSAttributedString.Key("md.sourceRange")
    static let markdownBlockID       = NSAttributedString.Key("md.blockID")
}

// MARK: - List Style

enum MarkdownListStyle: Hashable {
    case unordered(depth: Int, marker: Character)
    case ordered(depth: Int, start: Int)
    case task(depth: Int, checked: Bool)
}

// MARK: - Visual Styles

enum MarkdownStyles {
    @MainActor static let bodyFont = NSFont.systemFont(ofSize: 16)
    @MainActor static let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    static func headingFont(level: Int) -> NSFont {
        let sizes: [CGFloat] = [28, 22, 18, 16, 14, 13]
        let size = level >= 1 && level <= 6 ? sizes[level - 1] : 16
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static func paragraphStyle(forHeading level: Int) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = level <= 2 ? 16 : 10
        style.paragraphSpacing = 8
        return style
    }

    nonisolated(unsafe) private static let _bodyParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 8
        style.lineHeightMultiple = 1.4
        return style.copy() as! NSParagraphStyle
    }()

    static var bodyParagraphStyle: NSMutableParagraphStyle {
        _bodyParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
    }

    static func blockquoteParagraphStyle(depth: Int) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = CGFloat(depth) * 20
        style.firstLineHeadIndent = CGFloat(depth) * 20
        style.paragraphSpacing = 8
        return style
    }

    static func listParagraphStyle(depth: Int) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = CGFloat(depth + 1) * 20
        style.headIndent = indent
        style.firstLineHeadIndent = indent - 16
        style.paragraphSpacing = 4
        let tabStop = NSTextTab(textAlignment: .left, location: indent)
        style.tabStops = [tabStop]
        return style
    }
}
