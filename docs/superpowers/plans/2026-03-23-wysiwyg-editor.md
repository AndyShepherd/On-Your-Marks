# WYSIWYG Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native WYSIWYG editing mode as a third mode alongside Preview and Raw Editor, using NSTextView with custom attributed string metadata for Markdown round-trip fidelity.

**Architecture:** NSTextView wrapped in NSViewRepresentable renders Markdown as rich attributed text. Custom `NSAttributedString.Key` attributes tag each element's Markdown type. A `MarkdownAttributedStringRenderer` (MarkupVisitor) converts AST → attributed string; an `AttributedStringMarkdownSerializer` converts it back. Complex blocks (tables, images, code blocks) use NSTextAttachment with NSTextAttachmentViewProvider.

**Tech Stack:** Swift 6, SwiftUI, AppKit (NSTextView/TextKit 2), swift-markdown (already a dependency)

**Spec:** `docs/superpowers/specs/2026-03-23-wysiwyg-editor-design.md`

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `Sources/WYSIWYG/MarkdownAttributes.swift` | Custom `NSAttributedString.Key` definitions + `MarkdownListStyle` enum |
| `Sources/WYSIWYG/MarkdownAttributedStringRenderer.swift` | `MarkupVisitor` that produces `NSAttributedString` from AST |
| `Sources/WYSIWYG/AttributedStringMarkdownSerializer.swift` | Walks `NSAttributedString` → Markdown string |
| `Sources/WYSIWYG/MarkdownBlockAttachment.swift` | Protocol + base NSTextAttachment/ViewProvider for block elements |
| `Sources/WYSIWYG/WYSIWYGEditorView.swift` | `NSViewRepresentable` wrapping NSTextView + delegate |
| `Sources/WYSIWYG/WYSIWYGToolbarView.swift` | SwiftUI toolbar strip with SF Symbol buttons |
| `Sources/WYSIWYG/WYSIWYGFormatting.swift` | Formatting commands (bold, italic, etc.) as attributed string operations |
| `Sources/WYSIWYG/SlashCommandMenu.swift` | NSPopover with filtered command list |
| `Sources/WYSIWYG/Attachments/HorizontalRuleAttachment.swift` | HR divider line view |
| `Sources/WYSIWYG/Attachments/CodeBlockAttachment.swift` | Code block with language picker |
| `Sources/WYSIWYG/Attachments/ImageAttachment.swift` | Image display + alt text + edit popover |
| `Sources/WYSIWYG/Attachments/TableAttachment.swift` | Editable table grid view |
| `Tests/MarkdownAttributedStringRendererTests.swift` | Renderer unit tests |
| `Tests/AttributedStringMarkdownSerializerTests.swift` | Serializer + round-trip tests |
| `Tests/WYSIWYGFormattingTests.swift` | Formatting command tests |
| `Tests/TableAttachmentTests.swift` | Table serialization tests |
| `Tests/SlashCommandTests.swift` | Slash command menu tests |
| `Tests/Fixtures/*.md` | Corpus test fixtures for round-trip fidelity |

### Modified Files

| File | Changes |
|------|---------|
| `Sources/App/ContentView.swift` | Add `.wysiwyg` to `ViewMode` enum; add WYSIWYG panel to `mainContent`; guard `FormatCommandReceivers` to `.editor` only |
| `Sources/App/MainWindowView.swift` | Update `MainWindowToolbar` segmented control to 3 segments; disable split toggle for WYSIWYG; add `switchToWYSIWYG` notification handler |
| `Sources/App/OnYourMarksApp.swift` | Add Cmd+2 for WYSIWYG, shift Editor to Cmd+3; add Cmd+Shift+X strikethrough |
| `Sources/App/Notifications.swift` | Add `.switchToWYSIWYG`, `.formatStrikethrough` |
| `Sources/Editor/EditorKeyCommands.swift` | Add `strikethrough` function |
| `Package.swift` | Add test resources for corpus fixtures |

**Note:** The spec mentions fixing `MarkdownParser` to pass GFM options, but this is unnecessary — swift-markdown uses cmark-gfm under the hood and always parses GFM extensions (tables, strikethrough). The existing `parsesGFMTable` test confirms this. The `useGFM` flag controls rendering behavior in `HTMLRenderer`, not parsing. No parser changes needed.

**Test framework:** This project uses **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`), NOT XCTest. All tests in this plan MUST use Swift Testing.

---

## Task 1: MarkdownAttributes — Custom Keys and Types

**Files:**
- Create: `Sources/WYSIWYG/MarkdownAttributes.swift`

- [ ] **Step 1: Create the MarkdownAttributes file**

```swift
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
    static let bodyFont = NSFont.systemFont(ofSize: 16)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

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

    static var bodyParagraphStyle: NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 8
        style.lineHeightMultiple = 1.4
        return style
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
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```
feat: add MarkdownAttributes — custom NSAttributedString keys and visual styles
```

---

## Task 2: MarkdownAttributedStringRenderer — AST to Attributed String

**Files:**
- Create: `Sources/WYSIWYG/MarkdownAttributedStringRenderer.swift`
- Create: `Tests/MarkdownAttributedStringRendererTests.swift`

- [ ] **Step 1: Write failing tests for basic elements**

```swift
// Tests/MarkdownAttributedStringRendererTests.swift
import Testing
import AppKit
import Markdown
@testable import OnYourMarks

@Suite("MarkdownAttributedStringRenderer")
struct MarkdownAttributedStringRendererTests {

    private func render(_ markdown: String) -> NSAttributedString {
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse(markdown)
        var renderer = MarkdownAttributedStringRenderer(source: markdown)
        return renderer.render(doc)
    }

    @Test("Plain paragraph")
    func plainParagraph() {
        let result = render("Hello world")
        #expect(result.string == "Hello world\n")
    }

    @Test("Heading level 1")
    func headingLevel1() {
        let result = render("# Title")
        #expect(result.string == "Title\n")
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownHeading] as? Int == 1)
    }

    @Test("Bold text")
    func boldText() {
        let result = render("**bold**")
        #expect(result.string == "bold\n")
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownStrong] as? Bool == true)
    }

    @Test("Italic text")
    func italicText() {
        let result = render("*italic*")
        #expect(result.string == "italic\n")
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownEmphasis] as? Bool == true)
    }

    @Test("Nested bold and italic")
    func nestedBoldItalic() {
        let result = render("**bold *and italic***")
        let attrs = result.attributes(at: 6, effectiveRange: nil)
        #expect(attrs[.markdownStrong] as? Bool == true)
        #expect(attrs[.markdownEmphasis] as? Bool == true)
    }

    @Test("Strikethrough text")
    func strikethroughText() {
        let result = render("~~deleted~~")
        #expect(result.string == "deleted\n")
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownStrikethrough] as? Bool == true)
    }

    @Test("Inline code")
    func inlineCode() {
        let result = render("`code`")
        #expect(result.string == "code\n")
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownCode] as? Bool == true)
    }

    @Test("Link with URL")
    func link() {
        let result = render("[text](https://example.com)")
        #expect(result.string == "text\n")
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownLink] as? String == "https://example.com")
    }

    @Test("Unordered list")
    func unorderedList() {
        let result = render("- item one\n- item two")
        #expect(result.string.contains("item one"))
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownListItem] != nil)
    }

    @Test("Task list items")
    func taskList() {
        let result = render("- [ ] unchecked\n- [x] checked")
        #expect(result.string.contains("unchecked"))
        #expect(result.string.contains("checked"))
    }

    @Test("Nested lists")
    func nestedList() {
        let result = render("- outer\n  - inner")
        #expect(result.string.contains("outer"))
        #expect(result.string.contains("inner"))
    }

    @Test("Blockquote")
    func blockquote() {
        let result = render("> quoted text")
        #expect(result.string.contains("quoted text"))
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownBlockquote] as? Bool == true)
    }

    @Test("HTML block preserved as raw")
    func htmlBlock() {
        let result = render("<div>custom</div>")
        #expect(result.string.contains("<div>custom</div>"))
    }

    @Test("Source ranges are set")
    func sourceRangesAreSet() {
        let source = "# Heading\n\nParagraph"
        let result = render(source)
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownSourceRange] as? NSRange != nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MarkdownAttributedStringRendererTests`
Expected: Compilation error — `MarkdownAttributedStringRenderer` doesn't exist yet.

- [ ] **Step 3: Implement MarkdownAttributedStringRenderer**

Create `Sources/WYSIWYG/MarkdownAttributedStringRenderer.swift`. This is a `MarkupVisitor` that walks the swift-markdown AST and builds an `NSMutableAttributedString`. Key design points:

- Accept the original source string in `init` — retained for source range annotations.
- Each block visitor: create attributed string with visual styling + custom metadata keys + source range.
- Inline visitors: return attributed strings that the parent (paragraph/heading) assembles.
- For code blocks, images, tables: create `NSTextAttachment` instances (placeholder attachments for now — real attachment views come in later tasks).
- Paragraph separators: append `\n` after each block.

The full implementation should follow the pattern of the existing `HTMLRenderer` — implement each `visit*` method. Start with text-based elements; leave complex block attachments as simple text placeholders marked with a "raw" attribute. Later tasks will replace them with real attachments.

```swift
// Sources/WYSIWYG/MarkdownAttributedStringRenderer.swift
import AppKit
import Markdown

struct MarkdownAttributedStringRenderer: MarkupVisitor {
    typealias Result = NSMutableAttributedString

    let originalSource: String
    private var blockquoteDepth = 0
    private var listDepth = 0
    private var currentListMarker: Character = "-"
    private var currentListStart: Int = 1
    private var isOrdered = false

    init(source: String) {
        self.originalSource = source
    }

    mutating func render(_ document: Document) -> NSAttributedString {
        let result = visit(document)
        return result
    }

    // MARK: - Source Range Helper

    /// Convert swift-markdown SourceRange (1-based line:column) to NSRange (character offsets).
    private func sourceRange(for markup: Markup) -> NSRange? {
        guard let range = markup.range else { return nil }
        let lines = originalSource.components(separatedBy: "\n")

        func offset(for loc: SourceLocation) -> Int? {
            let line = loc.line - 1
            let col = loc.column - 1
            guard line >= 0, line < lines.count else { return nil }
            var result = 0
            for i in 0..<line {
                result += (lines[i] as NSString).length + 1
            }
            result += min(col, (lines[line] as NSString).length)
            return result
        }

        guard let start = offset(for: range.lowerBound),
              let end = offset(for: range.upperBound) else { return nil }
        return NSRange(location: start, length: max(0, end - start))
    }

    // MARK: - Default

    mutating func defaultVisit(_ markup: Markup) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    // MARK: - Block Elements

    mutating func visitDocument(_ document: Document) -> NSMutableAttributedString {
        return defaultVisit(document)
    }

    mutating func visitHeading(_ heading: Heading) -> NSMutableAttributedString {
        let content = defaultVisit(heading)
        let fullRange = NSRange(location: 0, length: content.length)
        content.addAttributes([
            .font: MarkdownStyles.headingFont(level: heading.level),
            .paragraphStyle: MarkdownStyles.paragraphStyle(forHeading: heading.level),
            .markdownHeading: heading.level,
        ], range: fullRange)
        if let sr = sourceRange(for: heading) {
            content.addAttribute(.markdownSourceRange, value: sr, range: fullRange)
        }
        content.append(NSAttributedString(string: "\n"))
        return content
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSMutableAttributedString {
        let content = defaultVisit(paragraph)
        let fullRange = NSRange(location: 0, length: content.length)
        content.addAttributes([
            .font: MarkdownStyles.bodyFont,
            .paragraphStyle: MarkdownStyles.bodyParagraphStyle,
        ], range: fullRange)
        if blockquoteDepth > 0 {
            content.addAttributes([
                .markdownBlockquote: true,
                .paragraphStyle: MarkdownStyles.blockquoteParagraphStyle(depth: blockquoteDepth),
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: fullRange)
        }
        if let sr = sourceRange(for: paragraph) {
            content.addAttribute(.markdownSourceRange, value: sr, range: fullRange)
        }
        content.append(NSAttributedString(string: "\n"))
        return content
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSMutableAttributedString {
        blockquoteDepth += 1
        let result = defaultVisit(blockQuote)
        blockquoteDepth -= 1
        return result
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> NSMutableAttributedString {
        listDepth += 1
        isOrdered = false
        let result = defaultVisit(list)
        listDepth -= 1
        return result
    }

    mutating func visitOrderedList(_ list: OrderedList) -> NSMutableAttributedString {
        listDepth += 1
        isOrdered = true
        currentListStart = Int(list.startIndex)
        let result = defaultVisit(list)
        listDepth -= 1
        return result
    }

    mutating func visitListItem(_ listItem: ListItem) -> NSMutableAttributedString {
        let bullet: String
        let style: MarkdownListStyle

        // Check for GFM task list checkbox
        if let checkbox = listItem.checkbox {
            let checked = (checkbox == .checked)
            bullet = checked ? "☑\t" : "☐\t"
            style = .task(depth: listDepth, checked: checked)
        } else if isOrdered {
            let num = currentListStart
            currentListStart += 1
            bullet = "\(num).\t"
            style = .ordered(depth: listDepth, start: num)
        } else {
            bullet = "-\t"
            style = .unordered(depth: listDepth, marker: "-")
        }

        let content = defaultVisit(listItem)
        let bulletStr = NSMutableAttributedString(string: bullet, attributes: [
            .font: MarkdownStyles.bodyFont,
            .foregroundColor: NSColor.controlAccentColor,
        ])
        bulletStr.append(content)
        let fullRange = NSRange(location: 0, length: bulletStr.length)
        bulletStr.addAttributes([
            .paragraphStyle: MarkdownStyles.listParagraphStyle(depth: listDepth),
            .markdownListItem: style,
        ], range: fullRange)
        return bulletStr
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSMutableAttributedString {
        // Placeholder: render as text "---" — Task 7 replaces with attachment
        let str = NSMutableAttributedString(string: "---\n", attributes: [
            .foregroundColor: NSColor.separatorColor,
            .font: MarkdownStyles.bodyFont,
        ])
        return str
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSMutableAttributedString {
        // Placeholder: render as monospace text — Task 8 replaces with attachment
        let lang = codeBlock.language ?? ""
        let header = lang.isEmpty ? "```\n" : "```\(lang)\n"
        let str = NSMutableAttributedString(string: header + codeBlock.code + "```\n", attributes: [
            .font: MarkdownStyles.monoFont,
            .backgroundColor: NSColor.controlBackgroundColor,
        ])
        return str
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Markdown.Text) -> NSMutableAttributedString {
        return NSMutableAttributedString(string: text.string, attributes: [
            .font: MarkdownStyles.bodyFont,
        ])
    }

    mutating func visitStrong(_ strong: Strong) -> NSMutableAttributedString {
        let content = defaultVisit(strong)
        let fullRange = NSRange(location: 0, length: content.length)
        content.addAttributes([
            .markdownStrong: true,
        ], range: fullRange)
        // Make existing font bold
        content.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if let font = value as? NSFont {
                let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                content.addAttribute(.font, value: bold, range: range)
            }
        }
        return content
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSMutableAttributedString {
        let content = defaultVisit(emphasis)
        let fullRange = NSRange(location: 0, length: content.length)
        content.addAttributes([
            .markdownEmphasis: true,
        ], range: fullRange)
        content.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if let font = value as? NSFont {
                let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                content.addAttribute(.font, value: italic, range: range)
            }
        }
        return content
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSMutableAttributedString {
        let content = defaultVisit(strikethrough)
        let fullRange = NSRange(location: 0, length: content.length)
        content.addAttributes([
            .markdownStrikethrough: true,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        ], range: fullRange)
        return content
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> NSMutableAttributedString {
        return NSMutableAttributedString(string: inlineCode.code, attributes: [
            .font: MarkdownStyles.monoFont,
            .backgroundColor: NSColor.quaternaryLabelColor,
            .markdownCode: true,
        ])
    }

    mutating func visitLink(_ link: Link) -> NSMutableAttributedString {
        let content = defaultVisit(link)
        let fullRange = NSRange(location: 0, length: content.length)
        if let dest = link.destination {
            content.addAttributes([
                .markdownLink: dest,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: fullRange)
        }
        return content
    }

    mutating func visitImage(_ image: Image) -> NSMutableAttributedString {
        // Placeholder: render alt text as link — Task 9 replaces with attachment
        // Note: alt text comes from children, NOT image.title (which is the HTML title attr)
        let alt = defaultVisit(image).string
        let src = image.source ?? ""
        return NSMutableAttributedString(string: "[\(alt.isEmpty ? "image" : alt)](\(src))", attributes: [
            .font: MarkdownStyles.bodyFont,
            .foregroundColor: NSColor.linkColor,
        ])
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSMutableAttributedString {
        // Preserve raw HTML as monospace text — not editable as rich formatting
        return NSMutableAttributedString(string: html.rawHTML + "\n", attributes: [
            .font: MarkdownStyles.monoFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .backgroundColor: NSColor.controlBackgroundColor,
        ])
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> NSMutableAttributedString {
        return NSMutableAttributedString(string: inlineHTML.rawHTML, attributes: [
            .font: MarkdownStyles.monoFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> NSMutableAttributedString {
        return NSMutableAttributedString(string: "\n")
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> NSMutableAttributedString {
        return NSMutableAttributedString(string: " ")
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter MarkdownAttributedStringRendererTests`
Expected: Most tests pass. Fix any failures from source range placeholder.

- [ ] **Step 5: Commit**

```
feat: add MarkdownAttributedStringRenderer — AST to attributed string visitor
```

---

## Task 3: AttributedStringMarkdownSerializer — Attributed String to Markdown

**Files:**
- Create: `Sources/WYSIWYG/AttributedStringMarkdownSerializer.swift`
- Create: `Tests/AttributedStringMarkdownSerializerTests.swift`

- [ ] **Step 1: Write failing round-trip tests**

```swift
// Tests/AttributedStringMarkdownSerializerTests.swift
import Testing
import AppKit
import Markdown
@testable import OnYourMarks

@Suite("AttributedStringMarkdownSerializer")
struct AttributedStringMarkdownSerializerTests {

    private func roundTrip(_ markdown: String) -> String {
        let parser = MarkdownParser(useGFM: true)
        let doc = parser.parse(markdown)
        var renderer = MarkdownAttributedStringRenderer(source: markdown)
        let attrStr = renderer.render(doc)
        let serializer = AttributedStringMarkdownSerializer(originalSource: markdown)
        return serializer.serialize(attrStr)
    }

    @Test("Plain paragraph round-trips")
    func plainParagraph() {
        #expect(roundTrip("Hello world") == "Hello world\n")
    }

    @Test("Heading round-trips")
    func heading() {
        #expect(roundTrip("# Title") == "# Title\n")
    }

    @Test("Bold round-trips")
    func boldText() {
        #expect(roundTrip("**bold**") == "**bold**\n")
    }

    @Test("Italic round-trips")
    func italicText() {
        #expect(roundTrip("*italic*") == "*italic*\n")
    }

    @Test("Strikethrough round-trips")
    func strikethroughText() {
        #expect(roundTrip("~~deleted~~") == "~~deleted~~\n")
    }

    @Test("Inline code round-trips")
    func inlineCode() {
        #expect(roundTrip("`code`") == "`code`\n")
    }

    @Test("Link round-trips")
    func link() {
        #expect(roundTrip("[text](https://example.com)") == "[text](https://example.com)\n")
    }

    @Test("Unordered list round-trips")
    func unorderedList() {
        let input = "- item one\n- item two\n"
        let result = roundTrip(input)
        #expect(result.contains("- item one"))
        #expect(result.contains("- item two"))
    }

    @Test("Nested list round-trips")
    func nestedList() {
        let input = "- outer\n  - inner\n"
        let result = roundTrip(input)
        #expect(result.contains("outer"))
        #expect(result.contains("inner"))
    }

    @Test("Blockquote round-trips")
    func blockquote() {
        let result = roundTrip("> quoted text")
        #expect(result.contains("> quoted text"))
    }

    @Test("New content without source ranges serializes correctly")
    func newContentWithoutSourceRanges() {
        let str = NSMutableAttributedString(string: "Hello", attributes: [
            .font: MarkdownStyles.bodyFont,
            .markdownStrong: true,
        ])
        let serializer = AttributedStringMarkdownSerializer(originalSource: "")
        let result = serializer.serialize(str)
        #expect(result == "**Hello**\n")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AttributedStringMarkdownSerializerTests`
Expected: Compilation error — serializer doesn't exist yet.

- [ ] **Step 3: Implement AttributedStringMarkdownSerializer**

Create `Sources/WYSIWYG/AttributedStringMarkdownSerializer.swift`. Key design:

- Walk the attributed string block by block (split on `\n` boundaries).
- For each block: check if it has a `markdownSourceRange` with unmodified content → emit original source verbatim.
- For modified/new blocks: read custom attributes and emit corresponding Markdown syntax.
- For attachments: call `serializeToMarkdown()` on the attachment.
- Inline formatting: track attribute transitions and emit `**`, `*`, `` ` ``, `[text](url)`, etc.

```swift
// Sources/WYSIWYG/AttributedStringMarkdownSerializer.swift
import AppKit

struct AttributedStringMarkdownSerializer {
    let originalSource: String

    func serialize(_ attributedString: NSAttributedString) -> String {
        var output = ""
        let fullRange = NSRange(location: 0, length: attributedString.length)

        // Walk block by block
        var blockStart = 0
        let str = attributedString.string as NSString

        while blockStart < str.length {
            // Find end of this block (next newline)
            let remaining = NSRange(location: blockStart, length: str.length - blockStart)
            var blockEnd = str.range(of: "\n", range: remaining).location
            if blockEnd == NSNotFound {
                blockEnd = str.length
            } else {
                blockEnd += 1 // include the newline
            }

            let blockRange = NSRange(location: blockStart, length: blockEnd - blockStart)
            let blockText = str.substring(with: blockRange)

            // Check for source range (unmodified block)
            if blockRange.length > 0 {
                let attrs = attributedString.attributes(at: blockStart, effectiveRange: nil)

                if let sourceRange = attrs[.markdownSourceRange] as? NSRange,
                   sourceRange.location != NSNotFound {
                    // Emit original source verbatim
                    let nsOriginal = originalSource as NSString
                    if sourceRange.location + sourceRange.length <= nsOriginal.length {
                        output += nsOriginal.substring(with: sourceRange)
                        if !output.hasSuffix("\n") { output += "\n" }
                        blockStart = blockEnd
                        continue
                    }
                }

                // Serialize from attributes
                output += serializeBlock(attributedString, range: blockRange)
            }

            blockStart = blockEnd
        }

        return output
    }

    private func serializeBlock(_ attrStr: NSAttributedString, range: NSRange) -> String {
        let attrs = attrStr.attributes(at: range.location, effectiveRange: nil)

        // Check for heading
        if let level = attrs[.markdownHeading] as? Int {
            let prefix = String(repeating: "#", count: level) + " "
            let content = serializeInlines(attrStr, range: range)
            return prefix + content + "\n"
        }

        // Check for blockquote
        if attrs[.markdownBlockquote] as? Bool == true {
            let content = serializeInlines(attrStr, range: range)
            return "> " + content + "\n"
        }

        // Check for list item
        if let listStyle = attrs[.markdownListItem] as? MarkdownListStyle {
            let content = serializeInlines(attrStr, range: range)
            // Strip the leading bullet/number that the renderer prepended
            let cleanContent = stripListPrefix(content)
            switch listStyle {
            case .unordered(_, let marker):
                return "\(marker) \(cleanContent)\n"
            case .ordered(_, let start):
                return "\(start). \(cleanContent)\n"
            case .task(_, let checked):
                return "- [\(checked ? "x" : " ")] \(cleanContent)\n"
            }
        }

        // Default: plain paragraph
        let content = serializeInlines(attrStr, range: range)
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\n"
        }
        return content + "\n"
    }

    private func serializeInlines(_ attrStr: NSAttributedString, range: NSRange) -> String {
        var result = ""
        attrStr.enumerateAttributes(in: range) { attrs, attrRange, _ in
            let text = (attrStr.string as NSString).substring(with: attrRange)
                .trimmingCharacters(in: .newlines)

            if text.isEmpty { return }

            var formatted = text

            // Apply inline formatting in order
            if attrs[.markdownCode] as? Bool == true {
                formatted = "`\(text)`"
            } else {
                if attrs[.markdownStrong] as? Bool == true {
                    formatted = "**\(formatted)**"
                }
                if attrs[.markdownEmphasis] as? Bool == true {
                    formatted = "*\(formatted)*"
                }
                if attrs[.markdownStrikethrough] as? Bool == true {
                    formatted = "~~\(formatted)~~"
                }
            }

            if let url = attrs[.markdownLink] as? String {
                formatted = "[\(text)](\(url))"
            }

            result += formatted
        }
        return result
    }

    private func stripListPrefix(_ text: String) -> String {
        // Remove leading "- \t", "1.\t", etc. that the renderer added
        if let tabIndex = text.firstIndex(of: "\t") {
            return String(text[text.index(after: tabIndex)...])
                .trimmingCharacters(in: .newlines)
        }
        return text.trimmingCharacters(in: .newlines)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AttributedStringMarkdownSerializerTests`
Expected: Tests pass. Fix any round-trip mismatches.

- [ ] **Step 5: Commit**

```
feat: add AttributedStringMarkdownSerializer — attributed string to Markdown
```

---

## Task 4: ViewMode, Notifications, and Menu Bar Updates

**Files:**
- Modify: `Sources/App/ContentView.swift:5-8`
- Modify: `Sources/App/Notifications.swift`
- Modify: `Sources/App/OnYourMarksApp.swift:75-97`
- Modify: `Sources/App/MainWindowView.swift:236-294` (MainWindowToolbar)
- Modify: `Sources/App/MainWindowView.swift:326-361` (SidebarAndViewModeReceivers)
- Modify: `Sources/Editor/EditorKeyCommands.swift`

- [ ] **Step 1: Add ViewMode.wysiwyg and new notifications**

In `Sources/App/ContentView.swift`, change the enum:

```swift
enum ViewMode: Int, CaseIterable {
    case preview = 0
    case editor = 1
    case wysiwyg = 2
}
```

In `Sources/App/Notifications.swift`, add:

```swift
static let switchToWYSIWYG = Notification.Name("switchToWYSIWYG")
static let formatStrikethrough = Notification.Name("formatStrikethrough")
```

- [ ] **Step 2: Update OnYourMarksApp.swift menu bar**

In `Sources/App/OnYourMarksApp.swift`, update the view mode section (after `.toolbar`):

Change the "Editor" button from Cmd+2 to Cmd+3, and add WYSIWYG as Cmd+2:

```swift
Button("Preview") {
    NotificationCenter.default.post(name: .switchToPreview, object: nil)
}
.keyboardShortcut("1", modifiers: .command)

Button("WYSIWYG") {
    NotificationCenter.default.post(name: .switchToWYSIWYG, object: nil)
}
.keyboardShortcut("2", modifiers: .command)

Button("Editor") {
    NotificationCenter.default.post(name: .switchToEditor, object: nil)
}
.keyboardShortcut("3", modifiers: .command)
```

Add strikethrough to the Format menu after Inline Code:

```swift
Button("Strikethrough") {
    NotificationCenter.default.post(name: .formatStrikethrough, object: nil)
}
.keyboardShortcut("x", modifiers: [.command, .shift])
```

- [ ] **Step 3: Add strikethrough to EditorKeyCommands**

In `Sources/Editor/EditorKeyCommands.swift`, add:

```swift
static func strikethrough(text: inout String, selectedRange: inout NSRange) {
    wrap(text: &text, selectedRange: &selectedRange, prefix: "~~", suffix: "~~")
}
```

- [ ] **Step 4: Update MainWindowToolbar segmented control**

In `Sources/App/MainWindowView.swift`, update `modePicker` in `MainWindowToolbar`:

```swift
private var modePicker: some View {
    Picker("Mode", selection: Binding(
        get: { tabManager.activeTab?.isSplitView == true ? nil : tabManager.activeTab?.viewMode ?? .preview },
        set: { newValue in
            if let mode = newValue {
                tabManager.activeTab?.viewMode = mode
                if mode == .wysiwyg {
                    tabManager.activeTab?.isSplitView = false
                }
                if mode != .wysiwyg {
                    // Only clear split for non-wysiwyg if explicitly selected
                    tabManager.activeTab?.isSplitView = false
                }
            }
        }
    )) {
        Text("Preview").tag(ViewMode?.some(.preview))
        Text("WYSIWYG").tag(ViewMode?.some(.wysiwyg))
        Text("Editor").tag(ViewMode?.some(.editor))
    }
    .pickerStyle(.segmented)
    .frame(width: 300)
    .accessibilityLabel("View mode")
}
```

Update `splitToggle` to disable when WYSIWYG is active:

```swift
private var splitToggle: some View {
    Toggle(isOn: Binding(
        get: { tabManager.activeTab?.isSplitView ?? false },
        set: { tabManager.activeTab?.isSplitView = $0 }
    )) {
        Image(systemName: "rectangle.split.2x1")
    }
    .help("Toggle Split View")
    .accessibilityLabel("Toggle split view")
    .disabled(tabManager.activeTab?.viewMode == .wysiwyg)
}
```

- [ ] **Step 5: Add switchToWYSIWYG notification handler**

In `SidebarAndViewModeReceivers`, add:

```swift
.onReceive(NotificationCenter.default.publisher(for: .switchToWYSIWYG)) { _ in
    tabManager.activeTab?.viewMode = .wysiwyg
    tabManager.activeTab?.isSplitView = false
}
```

Add strikethrough to `FormatCommandReceivers`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .formatStrikethrough)) { _ in
    applyFormatCommand { EditorKeyCommands.strikethrough(text: &$0, selectedRange: &$1) }
}
```

- [ ] **Step 6: Update ContentView to guard format commands**

In `ContentView.swift`, update `applyFormatCommand`:

```swift
private func applyFormatCommand(_ command: (inout String, inout NSRange) -> Void) {
    guard tab.viewMode == .editor || tab.isSplitView else { return }
    // ... rest unchanged
}
```

This already guards correctly — `.wysiwyg` won't pass the guard. No change needed if the existing code is as shown.

- [ ] **Step 7: Build and verify**

Run: `swift build`
Expected: Builds successfully. The `.wysiwyg` case in the `switch` in `mainContent` will need a placeholder — add:

```swift
case .wysiwyg:
    Text("WYSIWYG — coming soon")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 8: Commit**

```
feat: add ViewMode.wysiwyg, Cmd+2 shortcut, 3-segment toolbar, strikethrough
```

---

## Task 5: WYSIWYGEditorView — NSViewRepresentable Shell

**Files:**
- Create: `Sources/WYSIWYG/WYSIWYGEditorView.swift`
- Modify: `Sources/App/ContentView.swift` (replace placeholder)

- [ ] **Step 1: Create WYSIWYGEditorView**

```swift
// Sources/WYSIWYG/WYSIWYGEditorView.swift
import SwiftUI
import AppKit
import Markdown

struct WYSIWYGEditorView: NSViewRepresentable {
    @Binding var text: String
    let useGFM: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Typography
        textView.textContainerInset = NSSize(width: 40, height: 20)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.documentView = textView
        scrollView.drawsBackground = false

        // Initial render
        context.coordinator.loadMarkdown(text, useGFM: useGFM)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard !context.coordinator.isEditing else { return }
        if context.coordinator.lastLoadedText != text {
            context.coordinator.loadMarkdown(text, useGFM: useGFM)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WYSIWYGEditorView
        var textView: NSTextView?
        var isEditing = false
        var lastLoadedText = ""
        private var serializeTask: Task<Void, Never>?

        init(_ parent: WYSIWYGEditorView) {
            self.parent = parent
        }

        func loadMarkdown(_ markdown: String, useGFM: Bool) {
            guard let textView else { return }
            lastLoadedText = markdown
            let parser = MarkdownParser(useGFM: useGFM)
            let doc = parser.parse(markdown)
            var renderer = MarkdownAttributedStringRenderer(source: markdown)
            let attrStr = renderer.render(doc)
            textView.textStorage?.setAttributedString(attrStr)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let textStorage = textView.textStorage else { return }

            isEditing = true
            // Debounced serialization
            serializeTask?.cancel()
            serializeTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let attrStr = NSAttributedString(attributedString: textStorage)
                let serializer = AttributedStringMarkdownSerializer(originalSource: self.lastLoadedText)
                let markdown = serializer.serialize(attrStr)
                self.lastLoadedText = markdown
                self.parent.text = markdown
                self.isEditing = false
            }
        }
    }
}
```

- [ ] **Step 2: Wire into ContentView**

In `Sources/App/ContentView.swift`, replace the WYSIWYG placeholder in the `switch`:

```swift
case .wysiwyg:
    wysiwygPanel
```

Add the panel property:

```swift
private var wysiwygPanel: some View {
    WYSIWYGEditorView(
        text: Binding(
            get: { tab.document.text },
            set: { tab.document.text = $0 }
        ),
        useGFM: useGFM
    )
}
```

- [ ] **Step 3: Build and test manually**

Run: `swift build`
Expected: Build succeeds. Test by running the app — switching to WYSIWYG should show formatted Markdown content. Editing should work and changes should sync back.

- [ ] **Step 4: Commit**

```
feat: add WYSIWYGEditorView — NSTextView with Markdown rendering and serialization
```

---

## Task 6: WYSIWYGToolbarView — Formatting Toolbar

**Files:**
- Create: `Sources/WYSIWYG/WYSIWYGToolbarView.swift`
- Create: `Sources/WYSIWYG/WYSIWYGFormatting.swift`
- Create: `Tests/WYSIWYGFormattingTests.swift`
- Modify: `Sources/App/ContentView.swift` (add toolbar above WYSIWYG)

- [ ] **Step 1: Write failing tests for formatting operations**

```swift
// Tests/WYSIWYGFormattingTests.swift
import Testing
import AppKit
@testable import OnYourMarks

@Suite("WYSIWYGFormatting")
struct WYSIWYGFormattingTests {

    @Test("Toggle bold on — sets attribute and makes font bold")
    func toggleBoldOn() {
        let storage = NSTextStorage(string: "hello world", attributes: [
            .font: MarkdownStyles.bodyFont,
        ])
        let range = NSRange(location: 0, length: 5)
        WYSIWYGFormatting.toggleBold(in: storage, range: range)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownStrong] as? Bool == true)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(NSFontManager.shared.traits(of: font!).contains(.boldFontMask))
    }

    @Test("Toggle bold off — removes attribute and reverts font")
    func toggleBoldOff() {
        let boldFont = NSFontManager.shared.convert(MarkdownStyles.bodyFont, toHaveTrait: .boldFontMask)
        let storage = NSTextStorage(string: "hello", attributes: [
            .font: boldFont,
            .markdownStrong: true,
        ])
        let range = NSRange(location: 0, length: 5)
        WYSIWYGFormatting.toggleBold(in: storage, range: range)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownStrong] == nil)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(!NSFontManager.shared.traits(of: font!).contains(.boldFontMask))
    }

    @Test("Toggle italic — sets attribute and makes font italic")
    func toggleItalic() {
        let storage = NSTextStorage(string: "hello", attributes: [
            .font: MarkdownStyles.bodyFont,
        ])
        WYSIWYGFormatting.toggleItalic(in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownEmphasis] as? Bool == true)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(NSFontManager.shared.traits(of: font!).contains(.italicFontMask))
    }

    @Test("Set heading level — sets attribute and heading font")
    func setHeadingLevel() {
        let storage = NSTextStorage(string: "Title", attributes: [
            .font: MarkdownStyles.bodyFont,
        ])
        WYSIWYGFormatting.setHeading(level: 2, in: storage, range: NSRange(location: 0, length: 5))
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.markdownHeading] as? Int == 2)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize == MarkdownStyles.headingFont(level: 2).pointSize)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WYSIWYGFormattingTests`
Expected: Compilation error.

- [ ] **Step 3: Implement WYSIWYGFormatting**

```swift
// Sources/WYSIWYG/WYSIWYGFormatting.swift
import AppKit

enum WYSIWYGFormatting {

    static func toggleBold(in storage: NSTextStorage, range: NSRange) {
        storage.beginEditing()
        let isActive = storage.attributes(at: range.location, effectiveRange: nil)[.markdownStrong] as? Bool == true
        if isActive {
            storage.removeAttribute(.markdownStrong, range: range)
            // Revert font to non-bold
            storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let unbolded = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                    storage.addAttribute(.font, value: unbolded, range: attrRange)
                }
            }
        } else {
            storage.addAttribute(.markdownStrong, value: true, range: range)
            storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let bolded = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    storage.addAttribute(.font, value: bolded, range: attrRange)
                }
            }
        }
        // Clear source range (block is now modified)
        storage.removeAttribute(.markdownSourceRange, range: range)
        storage.endEditing()
    }

    static func toggleItalic(in storage: NSTextStorage, range: NSRange) {
        storage.beginEditing()
        let isActive = storage.attributes(at: range.location, effectiveRange: nil)[.markdownEmphasis] as? Bool == true
        if isActive {
            storage.removeAttribute(.markdownEmphasis, range: range)
            storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let unitalic = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                    storage.addAttribute(.font, value: unitalic, range: attrRange)
                }
            }
        } else {
            storage.addAttribute(.markdownEmphasis, value: true, range: range)
            storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                    storage.addAttribute(.font, value: italic, range: attrRange)
                }
            }
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
        storage.endEditing()
    }

    static func toggleStrikethrough(in storage: NSTextStorage, range: NSRange) {
        storage.beginEditing()
        let isActive = storage.attributes(at: range.location, effectiveRange: nil)[.markdownStrikethrough] as? Bool == true
        if isActive {
            storage.removeAttribute(.markdownStrikethrough, range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
        } else {
            storage.addAttribute(.markdownStrikethrough, value: true, range: range)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
        storage.endEditing()
    }

    static func toggleInlineCode(in storage: NSTextStorage, range: NSRange) {
        storage.beginEditing()
        let isActive = storage.attributes(at: range.location, effectiveRange: nil)[.markdownCode] as? Bool == true
        if isActive {
            storage.removeAttribute(.markdownCode, range: range)
            storage.removeAttribute(.backgroundColor, range: range)
            storage.addAttribute(.font, value: MarkdownStyles.bodyFont, range: range)
        } else {
            storage.addAttribute(.markdownCode, value: true, range: range)
            storage.addAttribute(.font, value: MarkdownStyles.monoFont, range: range)
            storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: range)
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
        storage.endEditing()
    }

    static func setHeading(level: Int, in storage: NSTextStorage, range: NSRange) {
        storage.beginEditing()
        if level == 0 {
            // Remove heading
            storage.removeAttribute(.markdownHeading, range: range)
            storage.addAttribute(.font, value: MarkdownStyles.bodyFont, range: range)
            storage.addAttribute(.paragraphStyle, value: MarkdownStyles.bodyParagraphStyle, range: range)
        } else {
            storage.addAttribute(.markdownHeading, value: level, range: range)
            storage.addAttribute(.font, value: MarkdownStyles.headingFont(level: level), range: range)
            storage.addAttribute(.paragraphStyle, value: MarkdownStyles.paragraphStyle(forHeading: level), range: range)
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
        storage.endEditing()
    }

    static func toggleBlockquote(in storage: NSTextStorage, range: NSRange) {
        storage.beginEditing()
        let isActive = storage.attributes(at: range.location, effectiveRange: nil)[.markdownBlockquote] as? Bool == true
        if isActive {
            storage.removeAttribute(.markdownBlockquote, range: range)
            storage.addAttribute(.paragraphStyle, value: MarkdownStyles.bodyParagraphStyle, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
        } else {
            storage.addAttribute(.markdownBlockquote, value: true, range: range)
            storage.addAttribute(.paragraphStyle, value: MarkdownStyles.blockquoteParagraphStyle(depth: 1), range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
        storage.removeAttribute(.markdownSourceRange, range: range)
        storage.endEditing()
    }

    static func setLink(url: String, in storage: NSTextStorage, range: NSRange) {
        storage.beginEditing()
        storage.addAttribute(.markdownLink, value: url, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        storage.removeAttribute(.markdownSourceRange, range: range)
        storage.endEditing()
    }

    static func removeLink(in storage: NSTextStorage, range: NSRange) {
        storage.beginEditing()
        storage.removeAttribute(.markdownLink, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
        storage.removeAttribute(.markdownSourceRange, range: range)
        storage.endEditing()
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter WYSIWYGFormattingTests`
Expected: All pass.

- [ ] **Step 5: Implement WYSIWYGToolbarView**

```swift
// Sources/WYSIWYG/WYSIWYGToolbarView.swift
import SwiftUI

struct WYSIWYGToolbarView: View {
    let onBold: () -> Void
    let onItalic: () -> Void
    let onStrikethrough: () -> Void
    let onCode: () -> Void
    let onLink: () -> Void
    let onImage: () -> Void
    let onBulletList: () -> Void
    let onNumberedList: () -> Void
    let onTaskList: () -> Void
    let onBlockquote: () -> Void
    let onHorizontalRule: () -> Void
    let onTable: () -> Void
    let onHeading: (Int) -> Void

    // Active state tracking
    var isBold: Bool = false
    var isItalic: Bool = false
    var isStrikethrough: Bool = false
    var isCode: Bool = false
    var isBlockquote: Bool = false
    var currentHeadingLevel: Int = 0

    var body: some View {
        HStack(spacing: 2) {
            // Heading picker
            Menu {
                Button("Paragraph") { onHeading(0) }
                Divider()
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { onHeading(level) }
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            .frame(width: 36)

            Divider().frame(height: 20)

            // Inline formatting
            toolbarButton("bold", isActive: isBold, label: "Bold", action: onBold)
            toolbarButton("italic", isActive: isItalic, label: "Italic", action: onItalic)
            toolbarButton("strikethrough", isActive: isStrikethrough, label: "Strikethrough", action: onStrikethrough)
            toolbarButton("chevron.left.forwardslash.chevron.right", isActive: isCode, label: "Inline Code", action: onCode)

            Divider().frame(height: 20)

            // Links & Images
            toolbarButton("link", action: onLink)
            toolbarButton("photo", action: onImage)

            Divider().frame(height: 20)

            // Lists & Quotes
            toolbarButton("list.bullet", action: onBulletList)
            toolbarButton("list.number", action: onNumberedList)
            toolbarButton("checklist", action: onTaskList)
            toolbarButton("text.quote", isActive: isBlockquote, action: onBlockquote)

            Divider().frame(height: 20)

            // Blocks
            toolbarButton("minus", action: onHorizontalRule)
            toolbarButton("tablecells", action: onTable)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func toolbarButton(_ symbol: String, isActive: Bool = false, label: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
                .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.isEmpty ? symbol : label)
    }
}
```

- [ ] **Step 6: Wire toolbar into ContentView**

Update `wysiwygPanel` in `ContentView.swift`:

```swift
private var wysiwygPanel: some View {
    VStack(spacing: 0) {
        WYSIWYGToolbarView(
            onBold: { /* wire to WYSIWYGEditorView formatting */ },
            onItalic: { },
            onStrikethrough: { },
            onCode: { },
            onLink: { },
            onImage: { },
            onBulletList: { },
            onNumberedList: { },
            onTaskList: { },
            onBlockquote: { },
            onHorizontalRule: { },
            onTable: { },
            onHeading: { _ in }
        )
        Divider()
        WYSIWYGEditorView(
            text: Binding(
                get: { tab.document.text },
                set: { tab.document.text = $0 }
            ),
            useGFM: useGFM
        )
    }
}
```

Note: The toolbar-to-editor communication will need a shared coordinator or callback mechanism. The simplest approach is to store a reference to the WYSIWYGEditorView's coordinator and call formatting methods on it. This wiring can be refined when the coordinator is accessible — for now, the toolbar renders correctly with placeholder callbacks.

- [ ] **Step 7: Build and verify**

Run: `swift build`
Expected: Build succeeds. The toolbar displays above the WYSIWYG editor.

- [ ] **Step 8: Commit**

```
feat: add WYSIWYGToolbarView and WYSIWYGFormatting — toolbar with SF Symbols and formatting operations
```

---

## Task 7: HorizontalRuleAttachment

**Files:**
- Create: `Sources/WYSIWYG/MarkdownBlockAttachment.swift`
- Create: `Sources/WYSIWYG/Attachments/HorizontalRuleAttachment.swift`
- Modify: `Sources/WYSIWYG/MarkdownAttributedStringRenderer.swift` (replace HR placeholder)

- [ ] **Step 1: Create the protocol and base view provider**

```swift
// Sources/WYSIWYG/MarkdownBlockAttachment.swift
import AppKit

protocol MarkdownBlockAttachment: AnyObject {
    func serializeToMarkdown() -> String
}
```

- [ ] **Step 2: Create HorizontalRuleAttachment**

```swift
// Sources/WYSIWYG/Attachments/HorizontalRuleAttachment.swift
import AppKit

final class HorizontalRuleAttachment: NSTextAttachment, MarkdownBlockAttachment {
    func serializeToMarkdown() -> String {
        return "---\n"
    }
}

final class HorizontalRuleViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 20))
        divider.frame = NSRect(x: 20, y: 9, width: 360, height: 1)
        divider.autoresizingMask = [.width]
        container.addSubview(divider)

        self.view = container
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 20)
    }
}
```

- [ ] **Step 3: Update renderer to use attachment**

In `MarkdownAttributedStringRenderer.visitThematicBreak`, replace the text placeholder with:

```swift
mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSMutableAttributedString {
    let attachment = HorizontalRuleAttachment()
    // Set the view provider directly on the attachment instance
    attachment.allowsTextAttachmentView = true
    let str = NSMutableAttributedString(attachment: attachment)
    str.append(NSAttributedString(string: "\n"))
    return str
}
```

The view provider is set on the attachment via `NSTextAttachment.allowsTextAttachmentView = true` and overriding `viewProvider(for:location:textContainer:)` or assigning a view provider factory. At implementation time, use whichever TextKit 2 API is cleanest for the macOS 15 SDK — either subclass `NSTextAttachment` and override `viewProvider(for:...)`, or configure it externally.

- [ ] **Step 4: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```
feat: add HorizontalRuleAttachment — native divider line in WYSIWYG
```

---

## Task 8: CodeBlockAttachment

**Files:**
- Create: `Sources/WYSIWYG/Attachments/CodeBlockAttachment.swift`
- Modify: `Sources/WYSIWYG/MarkdownAttributedStringRenderer.swift` (replace code block placeholder)

- [ ] **Step 1: Create CodeBlockAttachment**

A code block attachment contains:
- An `NSTextView` with monospace font and subtle background
- A language label/picker in the top-right corner
- Conforms to `MarkdownBlockAttachment`

```swift
// Sources/WYSIWYG/Attachments/CodeBlockAttachment.swift
import AppKit

final class CodeBlockAttachment: NSTextAttachment, MarkdownBlockAttachment {
    var code: String
    var language: String

    init(code: String, language: String) {
        self.code = code
        self.language = language
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func serializeToMarkdown() -> String {
        if language.isEmpty {
            return "```\n\(code)```\n"
        }
        return "```\(language)\n\(code)```\n"
    }
}
```

Create corresponding `NSTextAttachmentViewProvider` subclass that renders the code content in a styled NSTextView with background colour and language label. The view provider should update `code` and `language` on the attachment when the user edits.

- [ ] **Step 2: Update renderer to use attachment**

Replace the `visitCodeBlock` placeholder in `MarkdownAttributedStringRenderer` to create a `CodeBlockAttachment` and insert it.

- [ ] **Step 3: Build and verify**

Run: `swift build`
Expected: Build succeeds. Code blocks appear as styled regions.

- [ ] **Step 4: Commit**

```
feat: add CodeBlockAttachment — editable code blocks with language picker
```

---

## Task 9: ImageAttachment

**Files:**
- Create: `Sources/WYSIWYG/Attachments/ImageAttachment.swift`
- Modify: `Sources/WYSIWYG/MarkdownAttributedStringRenderer.swift` (replace image placeholder)

- [ ] **Step 1: Create ImageAttachment**

- Displays the image loaded from the relative path
- Shows alt text as editable caption below
- Click → popover for editing source URL and alt text
- Conforms to `MarkdownBlockAttachment`
- Supports drag-and-drop insertion

- [ ] **Step 2: Update renderer**

Replace `visitImage` placeholder to use `ImageAttachment`.

- [ ] **Step 3: Build and verify**

Run: `swift build`

- [ ] **Step 4: Commit**

```
feat: add ImageAttachment — inline images with caption and edit popover
```

---

## Task 10: TableAttachment

**Files:**
- Create: `Sources/WYSIWYG/Attachments/TableAttachment.swift`
- Create: `Tests/TableAttachmentTests.swift`
- Modify: `Sources/WYSIWYG/MarkdownAttributedStringRenderer.swift` (add table visitor)

- [ ] **Step 1: Write failing tests for table serialization**

```swift
// Tests/TableAttachmentTests.swift
import Testing
import AppKit
@testable import OnYourMarks

@Suite("TableAttachment")
struct TableAttachmentTests {

    @Test("Basic table serializes to GFM pipe syntax")
    func basicTableSerialization() {
        let attachment = TableAttachment(
            headers: ["A", "B"],
            rows: [["1", "2"], ["3", "4"]],
            alignments: [.left, .left]
        )
        let result = attachment.serializeToMarkdown()
        #expect(result.contains("| A | B |"))
        #expect(result.contains("| :--- | :--- |"))
        #expect(result.contains("| 1 | 2 |"))
        #expect(result.contains("| 3 | 4 |"))
    }

    @Test("Add row appends empty row")
    func addRow() {
        let attachment = TableAttachment(
            headers: ["A"],
            rows: [["1"]],
            alignments: [.left]
        )
        attachment.addRow()
        #expect(attachment.rows.count == 2)
        #expect(attachment.rows[1] == [""])
    }

    @Test("Add column extends headers and all rows")
    func addColumn() {
        let attachment = TableAttachment(
            headers: ["A"],
            rows: [["1"]],
            alignments: [.left]
        )
        attachment.addColumn()
        #expect(attachment.headers == ["A", ""])
        #expect(attachment.rows[0] == ["1", ""])
    }
}
```

- [ ] **Step 2: Implement TableAttachment**

A table attachment with:
- Grid of `NSTextField` cells
- Tab navigation between cells
- Right-click context menu (add/remove row/column, set alignment)
- GFM pipe syntax serialization

- [ ] **Step 3: Run tests**

Run: `swift test --filter TableAttachmentTests`
Expected: All pass.

- [ ] **Step 4: Update renderer with visitTable**

Add table parsing to `MarkdownAttributedStringRenderer` — create a `TableAttachment` from the AST `Table` node.

- [ ] **Step 5: Commit**

```
feat: add TableAttachment — editable table grid with GFM serialization
```

---

## Task 11: SlashCommandMenu

**Files:**
- Create: `Sources/WYSIWYG/SlashCommandMenu.swift`
- Modify: `Sources/WYSIWYG/WYSIWYGEditorView.swift` (add slash command detection)

- [ ] **Step 1: Create SlashCommandMenu**

An `NSPopover` containing a filterable list of commands. Anchors to the cursor position. Commands: heading (1-6), bullet, numbered, task, quote, code, table, image, divider.

- [ ] **Step 2: Write SlashCommandTests**

```swift
// Tests/SlashCommandTests.swift
import Testing
import AppKit
@testable import OnYourMarks

@Suite("SlashCommandMenu")
struct SlashCommandTests {

    @Test("All commands are present")
    func allCommandsPresent() {
        let commands = SlashCommandMenu.allCommands
        #expect(commands.contains { $0.name == "heading" })
        #expect(commands.contains { $0.name == "bullet" })
        #expect(commands.contains { $0.name == "numbered" })
        #expect(commands.contains { $0.name == "task" })
        #expect(commands.contains { $0.name == "quote" })
        #expect(commands.contains { $0.name == "code" })
        #expect(commands.contains { $0.name == "table" })
        #expect(commands.contains { $0.name == "image" })
        #expect(commands.contains { $0.name == "divider" })
    }

    @Test("Filter narrows results")
    func filterNarrows() {
        let filtered = SlashCommandMenu.allCommands.filter { $0.name.hasPrefix("he") }
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "heading")
    }
}
```

- [ ] **Step 3: Add slash detection to WYSIWYGEditorView coordinator**

In the `textView(_:shouldChangeTextIn:replacementString:)` delegate method, detect when `/` is typed at the start of an empty paragraph and show the popover.

- [ ] **Step 4: Build and verify**

Run: `swift build`
Test: Type `/` on an empty line — popover should appear.

- [ ] **Step 5: Commit**

```
feat: add SlashCommandMenu — / commands for block insertion
```

---

## Task 12: Toolbar-Editor Communication and Format Command Integration

**Files:**
- Modify: `Sources/WYSIWYG/WYSIWYGEditorView.swift`
- Modify: `Sources/App/ContentView.swift`

- [ ] **Step 1: Add formatting methods to WYSIWYGEditorView coordinator**

Expose methods on the coordinator that the toolbar can call: `applyBold()`, `applyItalic()`, etc. Each method reads the current selection from `textView.selectedRange()` and calls the corresponding `WYSIWYGFormatting` static method.

- [ ] **Step 2: Wire toolbar callbacks**

Use an `@StateObject` or `ObservableObject` bridge to connect the SwiftUI toolbar to the AppKit coordinator. Alternatively, use `NotificationCenter` — the WYSIWYG coordinator listens for `formatBold`, `formatItalic`, etc. notifications and applies them as attributed string operations.

- [ ] **Step 3: Add active state tracking**

The toolbar needs to know which formatting is active at the cursor. Add a `textViewDidChangeSelection` implementation that reads attributes at the cursor and updates published state.

- [ ] **Step 4: Build and verify**

Run: `swift build`
Test: Select text in WYSIWYG, click Bold in toolbar → text becomes bold. Click again → bold removed.

- [ ] **Step 5: Commit**

```
feat: wire WYSIWYG toolbar to editor — formatting buttons and active state tracking
```

---

## Task 13: Copy/Paste Behavior

**Files:**
- Modify: `Sources/WYSIWYG/WYSIWYGEditorView.swift`

- [ ] **Step 1: Override paste to handle HTML and Markdown**

Subclass or configure the NSTextView to override `paste(_:)` and `readSelection(from:type:)`:

- Check `NSPasteboard.general` for HTML type first — if present, parse it into a simplified Markdown string, then render as attributed string via the renderer pipeline.
- If no HTML, check for plain text — parse as Markdown and render.
- Falls back to default paste behavior if conversion fails.

- [ ] **Step 2: Override copy to place Markdown on pasteboard**

Override `writeSelection(to:type:)`:

- Serialize the selected attributed string range to Markdown via `AttributedStringMarkdownSerializer`.
- Place both `NSPasteboard.PasteboardType.string` (Markdown text) and `.rtf` (rich text) on the pasteboard.

- [ ] **Step 3: Build and verify**

Run: `swift build`
Test: Copy text from a web page → paste into WYSIWYG → should render with formatting. Copy from WYSIWYG → paste into a text editor → should paste as Markdown.

- [ ] **Step 4: Commit**

```
feat: add WYSIWYG copy/paste — HTML-to-Markdown paste and multi-format copy
```

---

## Task 14: Round-Trip Corpus Tests

**Files:**
- Create: `Tests/Fixtures/` (directory with sample .md files)
- Modify: `Tests/AttributedStringMarkdownSerializerTests.swift`
- Modify: `Package.swift` (add test resources)

- [ ] **Step 1: Update Package.swift for test resources**

In `Package.swift`, add a `resources` declaration to the test target:

```swift
.testTarget(
    name: "OnYourMarksTests",
    dependencies: [
        "OnYourMarks",
        .product(name: "Markdown", package: "swift-markdown"),
    ],
    path: "Tests",
    resources: [
        .copy("Fixtures"),
    ]
),
```

- [ ] **Step 2: Create test fixtures**

Create 3-4 representative Markdown files in `Tests/Fixtures/`:
- `simple.md` — headings, paragraphs, bold, italic, links
- `lists.md` — nested bullet lists, ordered lists, task lists
- `complex.md` — tables, code blocks, blockquotes, images, mixed content
- `readme-sample.md` — a realistic README with all common elements

- [ ] **Step 3: Write corpus round-trip test**

```swift
// Add to Tests/AttributedStringMarkdownSerializerTests.swift:

@Test("Corpus files round-trip without changes")
func corpusRoundTrip() throws {
    let fixturesURL = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    let files = try FileManager.default.contentsOfDirectory(at: fixturesURL, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "md" }

    for file in files {
        let original = try String(contentsOf: file, encoding: .utf8)
        let result = roundTrip(original)
        #expect(result == original, "Round-trip failed for \(file.lastPathComponent)")
    }
}
```

- [ ] **Step 4: Run and fix**

Run: `swift test --filter corpusRoundTrip`
Fix serializer issues until all fixtures pass.

- [ ] **Step 5: Commit**

```
test: add round-trip corpus tests for WYSIWYG serialization fidelity
```

---

## Task 15: Mode-Switching Integration Test

**Files:**
- Modify: `Tests/AttributedStringMarkdownSerializerTests.swift`

- [ ] **Step 1: Write mode-switching test**

```swift
// Add to Tests/AttributedStringMarkdownSerializerTests.swift:

@Test("Mode switching preserves content")
func modeSwitchingPreservesContent() {
    let original = "# Hello\n\nThis is **bold** and *italic*.\n\n- list item\n"
    let result = roundTrip(original)
    #expect(result == original)
}
```

- [ ] **Step 2: Run and verify**

Run: `swift test --filter testModeSwitchingPreservesContent`
Expected: PASS

- [ ] **Step 3: Commit**

```
test: add mode-switching integration test
```

---

## Task 16: Final Polish and Cleanup

- [ ] **Step 1: Run full test suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 2: Build the app bundle**

Run: `swift build -c release`
Expected: Clean release build.

- [ ] **Step 3: Manual testing checklist**

- Open a `.md` file → switch to WYSIWYG → headings, bold, links display correctly
- Edit text in WYSIWYG → switch to Raw Editor → Markdown is correct
- Switch to Preview → renders the same as WYSIWYG edits
- Toolbar buttons toggle formatting
- Slash commands insert blocks
- Code blocks display with monospace + language
- Tables are editable
- Images display (if relative path available)
- Horizontal rules display as dividers
- Undo/redo works
- Cmd+1/2/3 switch modes correctly
- Split view is disabled when in WYSIWYG

- [ ] **Step 4: Commit any final fixes**

```
fix: WYSIWYG polish and cleanup
```
