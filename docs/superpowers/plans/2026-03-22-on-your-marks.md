# On Your Marks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS Markdown viewer/editor with live file-watching, syntax-highlighted preview via WKWebView, and a power-user raw editor via STTextView.

**Architecture:** SwiftUI app shell using `DocumentGroup` + `ReferenceFileDocument`. Preview panel renders Markdown → HTML in a WKWebView with highlight.js. Editor panel uses STTextView (TextKit 2) wrapped in `NSViewRepresentable` behind a `MarkdownEditing` protocol for swappability.

**Tech Stack:** Swift, SwiftUI, AppKit (bridged), WebKit, swift-markdown (Apple), STTextView (krzyzanowskim), highlight.js (bundled)

**Spec:** `docs/superpowers/specs/2026-03-22-on-your-marks-design.md`

---

## File Map

### Files to Create

| File | Responsibility |
|------|---------------|
| `Package.swift` | SPM manifest: dependencies (swift-markdown, STTextView), macOS 26+ target |
| `Sources/App/OnYourMarksApp.swift` | `@main` entry, `DocumentGroup` with `MarkdownDocument` |
| `Sources/App/ContentView.swift` | Mode switching (segmented control), split view toggle, layout |
| `Sources/Document/MarkdownDocument.swift` | `ReferenceFileDocument` conformance, source of truth for content + dirty state |
| `Sources/Document/FileWatcher.swift` | `DispatchSource` file monitoring, SHA-256 hashing, 150ms debounce |
| `Sources/Pipeline/MarkdownParser.swift` | Wraps swift-markdown with CommonMark/GFM toggle |
| `Sources/Preview/HTMLRenderer.swift` | `MarkupVisitor` → HTML string with code block markup for highlight.js |
| `Sources/Preview/MarkdownPreviewView.swift` | `NSViewRepresentable` wrapping `WKWebView`, loads rendered HTML |
| `Sources/Preview/PreviewBridge.swift` | `WKScriptMessageHandler` for JS→Swift (copy button, scroll position reporting) |
| `Sources/Editor/MarkdownEditing.swift` | Protocol: get/set text, cursor position, scroll offset |
| `Sources/Editor/STTextViewEditor.swift` | `NSViewRepresentable` wrapping `STTextView`, conforms to `MarkdownEditing` |
| `Sources/Editor/MarkdownHighlighter.swift` | Regex-based syntax highlighting applied via `NSAttributedString` attributes |
| `Sources/Editor/EditorKeyCommands.swift` | Cmd+B/I/K/E/etc. handlers operating on text + selection |
| `Sources/Resources/preview.html` | HTML shell template with `{{CONTENT}}` placeholder |
| `Sources/Resources/preview.css` | Native macOS styling, `@media prefers-color-scheme`, SF fonts |
| `Sources/Resources/highlight.min.js` | Custom highlight.js build (14 languages) |
| `Sources/Resources/highlight-theme.css` | Code block theme with CSS variables for light/dark |
| `Tests/MarkdownParserTests.swift` | Parser correctness for CommonMark + GFM |
| `Tests/HTMLRendererTests.swift` | HTML output verification, code block structure |
| `Tests/FileWatcherTests.swift` | Debounce, hash comparison, self-change detection |
| `Tests/DocumentTests.swift` | Load, save, dirty state, content hash |
| `Tests/EditorKeyCommandsTests.swift` | Shortcut behaviour with/without selection |
| `Info.plist` | UTType registration for `.md` files |
| `OnYourMarks.entitlements` | App Sandbox with read/write file access |

---

## Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/App/OnYourMarksApp.swift`
- Create: `Info.plist`
- Create: `OnYourMarks.entitlements`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OnYourMarks",
    platforms: [
        .macOS(.v15) // macOS 26+ — update to .v16 when SDK ships
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/krzyzanowskim/STTextView.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "OnYourMarks",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "STTextViewSwiftUI", package: "STTextView"),
                .product(name: "STTextViewAppKit", package: "STTextView"),
            ],
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "OnYourMarksTests",
            dependencies: [
                "OnYourMarks",
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Tests"
        ),
    ]
)
```

- [ ] **Step 2: Create minimal app entry point**

```swift
// Sources/App/OnYourMarksApp.swift
import SwiftUI

@main
struct OnYourMarksApp: App {
    var body: some Scene {
        WindowGroup {
            Text("On Your Marks")
                .frame(minWidth: 800, minHeight: 500)
        }
    }
}
```

- [ ] **Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>On Your Marks</string>
    <key>CFBundleIdentifier</key>
    <string>com.onyourmarks.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>net.daringfireball.markdown</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.plain-text</string>
            </array>
            <key>UTTypeDescription</key>
            <string>Markdown Document</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>md</string>
                    <string>markdown</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
```

- [ ] **Step 4: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Resolve dependencies and verify build**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED (may show warnings, no errors)

- [ ] **Step 6: Commit**

```bash
git init
echo ".build/\n.swiftpm/\n.superpowers/\nDerivedData/" > .gitignore
git add Package.swift Sources/App/OnYourMarksApp.swift Info.plist OnYourMarks.entitlements .gitignore
git commit -m "feat: scaffold On Your Marks macOS app with dependencies"
```

---

## Task 2: Markdown Parser

**Files:**
- Create: `Sources/Pipeline/MarkdownParser.swift`
- Create: `Tests/MarkdownParserTests.swift`

- [ ] **Step 1: Write failing tests for the parser**

```swift
// Tests/MarkdownParserTests.swift
import Testing
import Foundation
@testable import OnYourMarks

@Suite("MarkdownParser")
struct MarkdownParserTests {

    @Test("Parses basic CommonMark heading")
    func parsesHeading() {
        let parser = MarkdownParser(useGFM: false)
        let doc = parser.parse("# Hello World")
        // Document should have one child (heading)
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
        // Should contain a table element
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
        // swift-markdown always parses GFM nodes — filtering happens in HTMLRenderer
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
```

Note: Import `Markdown` module for `Markdown.Table` type reference. The `@testable import OnYourMarks` gives access to `MarkdownParser`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test --filter MarkdownParserTests`
Expected: FAIL — `MarkdownParser` not found

- [ ] **Step 3: Implement MarkdownParser**

```swift
// Sources/Pipeline/MarkdownParser.swift
import Foundation
import Markdown

struct MarkdownParser {
    var useGFM: Bool

    func parse(_ source: String) -> Document {
        return Document(parsing: source)
    }
}
```

**Important:** `swift-markdown` is built on `cmark-gfm` and always parses GFM extensions (tables, strikethrough, task lists). There is no parse-time toggle to disable them. The GFM toggle is therefore implemented in the **renderer**, not the parser. When `useGFM` is false, the `HTMLRenderer` skips GFM-specific AST nodes (tables render as plain text, strikethrough renders without `<del>`). The `useGFM` flag is passed through to `HTMLRenderer` — see Task 3. The parser always produces the full AST regardless.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test --filter MarkdownParserTests`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Pipeline/MarkdownParser.swift Tests/MarkdownParserTests.swift
git commit -m "feat: add MarkdownParser with CommonMark/GFM toggle"
```

---

## Task 3: HTML Renderer

**Files:**
- Create: `Sources/Preview/HTMLRenderer.swift`
- Create: `Tests/HTMLRendererTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/HTMLRendererTests.swift
import Testing
import Foundation
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
        #expect(html.contains("<li>Item 1</li>"))
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test --filter HTMLRendererTests`
Expected: FAIL — `HTMLRenderer` not found

- [ ] **Step 3: Implement HTMLRenderer**

```swift
// Sources/Preview/HTMLRenderer.swift
import Foundation
import Markdown

struct HTMLRenderer: MarkupVisitor {
    typealias Result = String
    var useGFM: Bool = true

    mutating func render(_ document: Document) -> String {
        visit(document)
    }

    // MARK: - Block Elements

    mutating func defaultVisit(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitDocument(_ document: Document) -> String {
        document.children.map { visit($0) }.joined(separator: "\n")
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = heading.level
        let content = heading.children.map { visit($0) }.joined()
        return "<h\(level)>\(content)</h\(level)>"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let content = paragraph.children.map { visit($0) }.joined()
        return "<p>\(content)</p>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let code = escapeHTML(codeBlock.code.trimmingCharacters(in: .newlines))
        let langClass: String
        if let language = codeBlock.language, !language.isEmpty {
            langClass = " class=\"language-\(escapeHTML(language))\""
        } else {
            langClass = ""
        }
        return """
        <div class="code-block-wrapper">
        <button class="copy-button" onclick="copyCode(this)">Copy</button>
        <pre><code\(langClass)>\(code)</code></pre>
        </div>
        """
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let content = blockQuote.children.map { visit($0) }.joined()
        return "<blockquote>\(content)</blockquote>"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let items = unorderedList.children.map { visit($0) }.joined()
        return "<ul>\(items)</ul>"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let items = orderedList.children.map { visit($0) }.joined()
        let start = orderedList.startIndex
        if start != 1 {
            return "<ol start=\"\(start)\">\(items)</ol>"
        }
        return "<ol>\(items)</ol>"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let content = listItem.children.map { visit($0) }.joined()
        return "<li>\(content)</li>"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>"
    }

    // MARK: - GFM Table

    mutating func visitTable(_ table: Markdown.Table) -> String {
        // Skip GFM tables when not in GFM mode — render as plain text
        guard useGFM else {
            return table.format()
        }
        let content = table.children.map { visit($0) }.joined()
        return "<table>\(content)</table>"
    }

    mutating func visitTableHead(_ tableHead: Markdown.Table.Head) -> String {
        let rows = tableHead.children.map { child -> String in
            let cells = child.children.map { cell -> String in
                let content = cell.children.map { visit($0) }.joined()
                return "<th>\(content)</th>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()
        return "<thead>\(rows)</thead>"
    }

    mutating func visitTableBody(_ tableBody: Markdown.Table.Body) -> String {
        let rows = tableBody.children.map { child -> String in
            let cells = child.children.map { cell -> String in
                let content = cell.children.map { visit($0) }.joined()
                return "<td>\(content)</td>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()
        return "<tbody>\(rows)</tbody>"
    }

    mutating func visitTableRow(_ tableRow: Markdown.Table.Row) -> String {
        let cells = tableRow.children.map { visit($0) }.joined()
        return "<tr>\(cells)</tr>"
    }

    mutating func visitTableCell(_ tableCell: Markdown.Table.Cell) -> String {
        let content = tableCell.children.map { visit($0) }.joined()
        return "<td>\(content)</td>"
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Text) -> String {
        escapeHTML(text.string)
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        let content = strong.children.map { visit($0) }.joined()
        return "<strong>\(content)</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        let content = emphasis.children.map { visit($0) }.joined()
        return "<em>\(content)</em>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Link) -> String {
        let content = link.children.map { visit($0) }.joined()
        let href = escapeHTML(link.destination ?? "")
        return "<a href=\"\(href)\">\(content)</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let alt = escapeHTML(image.plainText)
        let src = escapeHTML(image.source ?? "")
        return "<img src=\"\(src)\" alt=\"\(alt)\">"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        let content = strikethrough.children.map { visit($0) }.joined()
        // Skip strikethrough rendering when not in GFM mode
        guard useGFM else { return content }
        return "<del>\(content)</del>"
    }

    // MARK: - Helpers

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test --filter HTMLRendererTests`
Expected: All tests PASS. If any GFM-specific tests fail (table, strikethrough), check whether `swift-markdown` requires explicit GFM parsing options and adjust `MarkdownParser` accordingly.

- [ ] **Step 5: Commit**

```bash
git add Sources/Preview/HTMLRenderer.swift Tests/HTMLRendererTests.swift
git commit -m "feat: add HTMLRenderer with MarkupVisitor for Markdown → HTML"
```

---

## Task 4: Preview Resources (HTML, CSS, JS)

**Files:**
- Create: `Sources/Resources/preview.html`
- Create: `Sources/Resources/preview.css`
- Create: `Sources/Resources/highlight-theme.css`
- Download: `Sources/Resources/highlight.min.js`

- [ ] **Step 1: Create HTML template**

```html
<!-- Sources/Resources/preview.html -->
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="preview.css">
    <link rel="stylesheet" href="highlight-theme.css">
    <script src="highlight.min.js"></script>
</head>
<body>
    <article id="content">
        {{CONTENT}}
    </article>
    <script>
        hljs.highlightAll();

        function copyCode(button) {
            const wrapper = button.closest('.code-block-wrapper');
            const code = wrapper.querySelector('code');
            const text = code.textContent;
            navigator.clipboard.writeText(text).then(() => {
                button.textContent = 'Copied!';
                setTimeout(() => { button.textContent = 'Copy'; }, 1500);
            });
        }

        // Report scroll position to Swift
        window.addEventListener('scroll', () => {
            const scrollPercentage = window.scrollY /
                (document.documentElement.scrollHeight - window.innerHeight);
            window.webkit.messageHandlers.scrollPosition.postMessage(
                { percentage: scrollPercentage }
            );
        });

        // Restore scroll position after load
        function restoreScroll(percentage) {
            const target = percentage *
                (document.documentElement.scrollHeight - window.innerHeight);
            window.scrollTo(0, target);
        }
    </script>
</body>
</html>
```

- [ ] **Step 2: Create preview CSS**

```css
/* Sources/Resources/preview.css */
:root {
    --text-color: #1d1d1f;
    --bg-color: #ffffff;
    --code-bg: #f5f5f7;
    --border-color: #d2d2d7;
    --link-color: #0066cc;
    --blockquote-border: #d2d2d7;
    --blockquote-text: #6e6e73;
    --table-border: #d2d2d7;
    --table-header-bg: #f5f5f7;
    --hr-color: #d2d2d7;
    --copy-btn-bg: #e8e8ed;
    --copy-btn-hover: #d2d2d7;
}

@media (prefers-color-scheme: dark) {
    :root {
        --text-color: #f5f5f7;
        --bg-color: #1d1d1f;
        --code-bg: #2c2c2e;
        --border-color: #48484a;
        --link-color: #2997ff;
        --blockquote-border: #48484a;
        --blockquote-text: #98989d;
        --table-border: #48484a;
        --table-header-bg: #2c2c2e;
        --hr-color: #48484a;
        --copy-btn-bg: #3a3a3c;
        --copy-btn-hover: #48484a;
    }
}

* {
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
    font-size: 16px;
    line-height: 1.6;
    color: var(--text-color);
    background-color: var(--bg-color);
    max-width: 800px;
    margin: 0 auto;
    padding: 24px 32px;
    -webkit-font-smoothing: antialiased;
}

h1, h2, h3, h4, h5, h6 {
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", sans-serif;
    margin-top: 1.5em;
    margin-bottom: 0.5em;
    line-height: 1.25;
}

h1 { font-size: 2em; font-weight: 700; }
h2 { font-size: 1.5em; font-weight: 600; border-bottom: 1px solid var(--border-color); padding-bottom: 0.3em; }
h3 { font-size: 1.25em; font-weight: 600; }
h4 { font-size: 1em; font-weight: 600; }

p { margin: 0.75em 0; }

a { color: var(--link-color); text-decoration: none; }
a:hover { text-decoration: underline; }

code {
    font-family: "SF Mono", SFMono-Regular, Menlo, monospace;
    font-size: 0.875em;
    background-color: var(--code-bg);
    padding: 0.2em 0.4em;
    border-radius: 4px;
}

pre {
    margin: 0;
    overflow-x: auto;
}

pre code {
    display: block;
    padding: 16px;
    font-size: 14px;
    line-height: 1.5;
    background-color: var(--code-bg);
    border-radius: 8px;
    border: none;
}

.code-block-wrapper {
    position: relative;
    margin: 1em 0;
}

.copy-button {
    position: absolute;
    top: 8px;
    right: 8px;
    font-family: -apple-system, sans-serif;
    font-size: 12px;
    padding: 4px 10px;
    background: var(--copy-btn-bg);
    color: var(--text-color);
    border: none;
    border-radius: 4px;
    cursor: pointer;
    opacity: 0;
    transition: opacity 0.15s ease;
    z-index: 1;
}

.code-block-wrapper:hover .copy-button {
    opacity: 1;
}

.copy-button:hover {
    background: var(--copy-btn-hover);
}

blockquote {
    margin: 1em 0;
    padding: 0 1em;
    border-left: 3px solid var(--blockquote-border);
    color: var(--blockquote-text);
}

ul, ol { padding-left: 1.5em; margin: 0.75em 0; }
li { margin: 0.25em 0; }

table {
    border-collapse: collapse;
    width: 100%;
    margin: 1em 0;
}

th, td {
    padding: 8px 12px;
    border: 1px solid var(--table-border);
    text-align: left;
}

th {
    font-weight: 600;
    background-color: var(--table-header-bg);
}

hr {
    border: none;
    border-top: 1px solid var(--hr-color);
    margin: 2em 0;
}

img {
    max-width: 100%;
    height: auto;
    border-radius: 4px;
}

del {
    text-decoration: line-through;
    opacity: 0.6;
}
```

- [ ] **Step 3: Create highlight.js theme CSS**

```css
/* Sources/Resources/highlight-theme.css */
/* Light theme */
.hljs { color: var(--text-color); }
.hljs-keyword { color: #ad3da4; font-weight: 600; }
.hljs-string { color: #d12f1b; }
.hljs-number { color: #272ad8; }
.hljs-comment { color: #707f8c; font-style: italic; }
.hljs-type { color: #703daa; }
.hljs-function { color: #4b21b0; }
.hljs-built_in { color: #ad3da4; }
.hljs-literal { color: #ad3da4; }
.hljs-attr { color: #703daa; }
.hljs-selector-class { color: #4b21b0; }
.hljs-selector-tag { color: #ad3da4; }
.hljs-title { color: #4b21b0; }

@media (prefers-color-scheme: dark) {
    .hljs-keyword { color: #fc5fa3; }
    .hljs-string { color: #fc6c5d; }
    .hljs-number { color: #d0bf69; }
    .hljs-comment { color: #6c7986; }
    .hljs-type { color: #d0a8ff; }
    .hljs-function { color: #a167e6; }
    .hljs-built_in { color: #fc5fa3; }
    .hljs-literal { color: #fc5fa3; }
    .hljs-attr { color: #d0a8ff; }
    .hljs-selector-class { color: #a167e6; }
    .hljs-selector-tag { color: #fc5fa3; }
    .hljs-title { color: #a167e6; }
}
```

- [ ] **Step 4: Download highlight.js custom build**

Download a custom highlight.js build from https://highlightjs.org/download — select these 14 languages only: Swift, Python, JavaScript, TypeScript, Go, Rust, Ruby, Bash, JSON, YAML, HTML, CSS, SQL, Markdown. Save the downloaded `highlight.min.js` to `Sources/Resources/highlight.min.js`. The file should be ~40-60KB.

Alternatively, use npm to build: `npm install highlight.js && npx hljs-build --languages=swift,python,javascript,typescript,go,rust,ruby,bash,json,yaml,xml,css,sql,markdown`

- [ ] **Step 5: Verify build still succeeds**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Sources/Resources/
git commit -m "feat: add preview resources — HTML template, CSS, highlight.js"
```

---

## Task 5: Document Model

**Files:**
- Create: `Sources/Document/MarkdownDocument.swift`
- Create: `Tests/DocumentTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/DocumentTests.swift
import Testing
import Foundation
import UniformTypeIdentifiers
@testable import OnYourMarks

@Suite("MarkdownDocument")
struct DocumentTests {

    @Test("New document has empty content")
    func newDocumentEmpty() {
        let doc = MarkdownDocument()
        #expect(doc.text == "")
    }

    @Test("Document initialises from string data")
    func initFromData() throws {
        let content = "# Hello\n\nSome content."
        let data = Data(content.utf8)
        let doc = try MarkdownDocument(data: data)
        #expect(doc.text == content)
    }

    @Test("Document serialises to UTF-8 data")
    func serialisesToData() {
        let doc = MarkdownDocument(text: "# Test")
        let data = doc.data()
        let result = String(data: data, encoding: .utf8)
        #expect(result == "# Test")
    }

    @Test("Content hash changes when text changes")
    func contentHashChanges() {
        let doc = MarkdownDocument(text: "Hello")
        let hash1 = doc.contentHash
        doc.userDidEdit("World")
        let hash2 = doc.contentHash
        #expect(hash1 != hash2)
    }

    @Test("Content hash is stable for same content")
    func contentHashStable() {
        let doc1 = MarkdownDocument(text: "Same content")
        let doc2 = MarkdownDocument(text: "Same content")
        #expect(doc1.contentHash == doc2.contentHash)
    }

    @Test("Document tracks dirty state")
    func tracksModification() {
        let doc = MarkdownDocument(text: "Original")
        #expect(!doc.isDirty)
        doc.userDidEdit("Modified")
        #expect(doc.isDirty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test --filter DocumentTests`
Expected: FAIL — `MarkdownDocument` not found

- [ ] **Step 3: Implement MarkdownDocument**

```swift
// Sources/Document/MarkdownDocument.swift
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

final class MarkdownDocument: ReferenceFileDocument, ObservableObject {
    static var readableContentTypes: [UTType] { [.init("net.daringfireball.markdown")!] }
    static var writableContentTypes: [UTType] { [.init("net.daringfireball.markdown")!] }

    @Published var text: String
    @Published var isDirty: Bool = false

    /// SHA-256 hash of the current text content
    var contentHash: String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Hash of the last-saved/last-loaded content (for FileWatcher comparison)
    var lastKnownHash: String = ""

    /// File URL if document is backed by a file on disk
    var fileURL: URL?

    init(text: String = "") {
        self.text = text
        self.lastKnownHash = Self.computeHash(text)
    }

    /// Call this from the view layer when text changes via user editing
    func userDidEdit(_ newText: String) {
        text = newText
        isDirty = true
    }

    private static func computeHash(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - ReferenceFileDocument

    convenience init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.init(text: text)
        self.isDirty = false
    }

    required convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    func snapshot(contentType: UTType) throws -> Data {
        data()
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    // MARK: - Serialisation

    func data() -> Data {
        Data(text.utf8)
    }

    /// Call after saving to update the last-known hash and clear dirty state
    func didSave() {
        lastKnownHash = contentHash
        isDirty = false
    }

    /// Call after loading/reloading from disk
    func didLoad() {
        lastKnownHash = contentHash
        isDirty = false
    }
}
```

Note: The `UTType` initialiser from string (`UTType("net.daringfireball.markdown")`) requires the type to be declared in Info.plist or imported. If this doesn't resolve at runtime, fall back to `UTType.plainText` and filter by file extension. Verify during implementation.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test --filter DocumentTests`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Document/MarkdownDocument.swift Tests/DocumentTests.swift
git commit -m "feat: add MarkdownDocument with ReferenceFileDocument + SHA-256 hashing"
```

---

## Task 6: File Watcher

**Files:**
- Create: `Sources/Document/FileWatcher.swift`
- Create: `Tests/FileWatcherTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/FileWatcherTests.swift
import Testing
import Foundation
@testable import OnYourMarks

@Suite("FileWatcher")
struct FileWatcherTests {

    @Test("Detects external file change")
    func detectsChange() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try "initial".write(to: file, atomically: true, encoding: .utf8)

        var changeDetected = false
        let watcher = FileWatcher(url: file, knownHash: FileWatcher.sha256(of: file)!) { newContent in
            changeDetected = true
        }
        watcher.start()

        // Write external change
        try "modified".write(to: file, atomically: true, encoding: .utf8)

        // Wait for debounce (150ms) + margin
        try await Task.sleep(for: .milliseconds(400))

        #expect(changeDetected)

        watcher.stop()
        try? FileManager.default.removeItem(at: file)
    }

    @Test("Ignores self-triggered change via matching hash")
    func ignoresSelfChange() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        let content = "unchanged"
        try content.write(to: file, atomically: true, encoding: .utf8)

        var changeDetected = false
        let hash = FileWatcher.sha256(of: file)!
        let watcher = FileWatcher(url: file, knownHash: hash) { _ in
            changeDetected = true
        }
        watcher.start()

        // Write same content (simulates self-save)
        try content.write(to: file, atomically: true, encoding: .utf8)

        try await Task.sleep(for: .milliseconds(400))

        #expect(!changeDetected)

        watcher.stop()
        try? FileManager.default.removeItem(at: file)
    }

    @Test("SHA-256 hash is consistent for same content")
    func hashConsistency() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try "test content".write(to: file, atomically: true, encoding: .utf8)

        let hash1 = FileWatcher.sha256(of: file)
        let hash2 = FileWatcher.sha256(of: file)
        #expect(hash1 == hash2)
        #expect(hash1 != nil)

        try? FileManager.default.removeItem(at: file)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test --filter FileWatcherTests`
Expected: FAIL — `FileWatcher` not found

- [ ] **Step 3: Implement FileWatcher**

```swift
// Sources/Document/FileWatcher.swift
import Foundation
import CryptoKit

final class FileWatcher {
    private let url: URL
    private var knownHash: String
    private let onChange: (String) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.15 // 150ms

    init(url: URL, knownHash: String, onChange: @escaping (String) -> Void) {
        self.url = url
        self.knownHash = knownHash
        self.onChange = onChange
    }

    func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleFileEvent()
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        debounceWork?.cancel()
        source?.cancel()
        source = nil
    }

    func updateKnownHash(_ hash: String) {
        knownHash = hash
    }

    private func handleFileEvent() {
        // Debounce: cancel pending work, schedule new
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.checkForChange()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: work
        )
    }

    private func checkForChange() {
        guard let newHash = Self.sha256(of: url) else {
            // File may have been deleted
            onChange("")
            return
        }

        if newHash != knownHash {
            knownHash = newHash
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                onChange(content)
            }
        }
    }

    // MARK: - Static Helpers

    static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test --filter FileWatcherTests`
Expected: All tests PASS. The async file-watching tests may be flaky on CI — increase the sleep duration if needed.

**Known limitation:** `DispatchSource` monitors a file descriptor, not a path. After file deletion or rename, the source will fire the `.delete`/`.rename` event but cannot recover if the file is recreated at the same path. The app handles this by showing a deletion alert (Task 14). If the file is recreated, the user must reopen it. This is acceptable for v1.

- [ ] **Step 5: Commit**

```bash
git add Sources/Document/FileWatcher.swift Tests/FileWatcherTests.swift
git commit -m "feat: add FileWatcher with debounce + SHA-256 self-change detection"
```

---

## Task 7: Preview View (WKWebView)

**Files:**
- Create: `Sources/Preview/MarkdownPreviewView.swift`
- Create: `Sources/Preview/PreviewBridge.swift`

- [ ] **Step 1: Implement PreviewBridge**

```swift
// Sources/Preview/PreviewBridge.swift
import Foundation
import WebKit

class PreviewBridge: NSObject, WKScriptMessageHandler {
    var onScrollPositionChanged: ((Double) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "scrollPosition",
              let body = message.body as? [String: Any],
              let percentage = body["percentage"] as? Double else {
            return
        }
        onScrollPositionChanged?(percentage)
    }
}
```

- [ ] **Step 2: Implement MarkdownPreviewView**

```swift
// Sources/Preview/MarkdownPreviewView.swift
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let htmlContent: String
    let baseURL: URL?
    @Binding var scrollPercentage: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: PreviewBridge {
        var lastLoadedHTML: String = ""
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.onScrollPositionChanged = { [weak context] percentage in
            DispatchQueue.main.async {
                // Scroll position updates handled by parent
            }
        }
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "scrollPosition")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent BG
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Skip reload if content hasn't changed
        guard htmlContent != context.coordinator.lastLoadedHTML else { return }
        context.coordinator.lastLoadedHTML = htmlContent

        // Load the HTML template from bundle, replace placeholder
        guard let templateURL = Bundle.main.url(forResource: "preview", withExtension: "html"),
              let template = try? String(contentsOf: templateURL, encoding: .utf8) else {
            webView.loadHTMLString(
                "<html><body><p>Unable to render preview.</p></body></html>",
                baseURL: nil
            )
            return
        }

        let fullHTML = template.replacingOccurrences(of: "{{CONTENT}}", with: htmlContent)
        let effectiveBaseURL = baseURL ?? Bundle.main.resourceURL
        webView.loadHTMLString(fullHTML, baseURL: effectiveBaseURL)

        // Restore scroll position after load
        let percentage = scrollPercentage
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            webView.evaluateJavaScript("restoreScroll(\(percentage))") { _, _ in }
        }
    }
}
```

Note: The `updateNSView` will be called on every SwiftUI state change. The parent view should debounce HTML rendering so this isn't called on every keystroke. The scroll-restore delay (100ms) gives the WebView time to layout before scrolling — tune if needed.

- [ ] **Step 3: Verify build**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/Preview/MarkdownPreviewView.swift Sources/Preview/PreviewBridge.swift
git commit -m "feat: add MarkdownPreviewView with WKWebView + scroll bridge"
```

---

## Task 8: App Shell — Preview Mode

**Files:**
- Modify: `Sources/App/OnYourMarksApp.swift`
- Create: `Sources/App/ContentView.swift`

This task wires up the document model, parser, renderer, and preview view into a working app that opens `.md` files and shows a rendered preview.

- [ ] **Step 1: Update OnYourMarksApp to use DocumentGroup**

```swift
// Sources/App/OnYourMarksApp.swift
import SwiftUI

@main
struct OnYourMarksApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document)
        }
        .commands {
            // Custom menus will be added in Task 12
        }
    }
}
```

- [ ] **Step 2: Create ContentView with Preview mode**

```swift
// Sources/App/ContentView.swift
import SwiftUI

enum ViewMode: Int, CaseIterable {
    case preview = 0
    case editor = 1
}

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var viewMode: ViewMode = .preview
    @State private var isSplitView = false
    @State private var scrollPercentage: Double = 0
    @State private var useGFM = UserDefaults.standard.bool(forKey: "useGFM")

    @State private var renderedHTML: String = ""
    @State private var renderTask: Task<Void, Never>?

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let text = document.text
            let gfm = useGFM
            let parser = MarkdownParser(useGFM: gfm)
            let doc = parser.parse(text)
            var renderer = HTMLRenderer(useGFM: gfm)
            let html = renderer.render(doc)
            await MainActor.run { renderedHTML = html }
        }
    }

    private var baseURL: URL? {
        document.fileURL?.deletingLastPathComponent()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            Group {
                if isSplitView {
                    HSplitView {
                        editorPanel
                        previewPanel
                    }
                } else {
                    switch viewMode {
                    case .preview:
                        previewPanel
                    case .editor:
                        editorPanel
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear { scheduleRender() }
        .onChange(of: document.text) { _, _ in scheduleRender() }
        .onChange(of: useGFM) { _, _ in scheduleRender() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: Binding(
                    get: { isSplitView ? nil : viewMode },
                    set: { newValue in
                        if let mode = newValue {
                            viewMode = mode
                            isSplitView = false
                        }
                    }
                )) {
                    Text("Preview").tag(ViewMode?.some(.preview))
                    Text("Editor").tag(ViewMode?.some(.editor))
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            ToolbarItem {
                Toggle(isOn: $isSplitView) {
                    Image(systemName: "rectangle.split.2x1")
                }
                .help("Toggle Split View (⌘\\)")
            }

            ToolbarItem {
                Toggle(isOn: $useGFM) {
                    Text("GFM")
                }
                .toggleStyle(.checkbox)
                .help("GitHub Flavored Markdown (⌘⇧G)")
                .onChange(of: useGFM) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "useGFM")
                }
            }
        }
    }

    private var previewPanel: some View {
        MarkdownPreviewView(
            htmlContent: renderedHTML,
            baseURL: baseURL,
            scrollPercentage: $scrollPercentage
        )
    }

    @ViewBuilder
    private var editorPanel: some View {
        // Placeholder until Task 10
        TextEditor(text: $document.text)
            .font(.system(.body, design: .monospaced))
    }

}
```

Note: `scheduleRender()` debounces at 200ms. Add `.onChange(of: document.text) { _, _ in scheduleRender() }` and `.onChange(of: useGFM) { _, _ in scheduleRender() }` and `.onAppear { scheduleRender() }` to the body. The `editorPanel` uses a placeholder `TextEditor` for now — STTextView integration is Task 10.

- [ ] **Step 3: Build and run the app**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED. Open in Xcode (`open Package.swift`) to test running the app — it should launch with a document picker and display rendered Markdown preview.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/OnYourMarksApp.swift Sources/App/ContentView.swift
git commit -m "feat: wire up app shell with DocumentGroup and preview mode"
```

---

## Task 9: Editor Protocol

**Files:**
- Create: `Sources/Editor/MarkdownEditing.swift`

- [ ] **Step 1: Define the MarkdownEditing protocol**

```swift
// Sources/Editor/MarkdownEditing.swift
import Foundation

/// Abstraction layer for the Markdown editor view.
/// Allows swapping STTextView for native NSTextView if Apple improves TextKit 2.
protocol MarkdownEditing: AnyObject {
    /// The full text content of the editor
    var text: String { get set }

    /// Cursor position as a character offset from the start
    var cursorOffset: Int { get set }

    /// Character offset of the first visible line (for scroll restoration)
    var scrollOffset: Int { get set }

    /// The currently selected range (location + length)
    var selectedRange: NSRange { get set }

    /// Replace the selected range with new text
    func replaceSelection(with text: String)

    /// Insert text at the current cursor position
    func insertAtCursor(_ text: String)

    /// Wrap the current selection with prefix and suffix strings
    /// If no selection, insert prefix+suffix and place cursor between them
    func wrapSelection(prefix: String, suffix: String)
}
```

- [ ] **Step 2: Verify build**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/Editor/MarkdownEditing.swift
git commit -m "feat: add MarkdownEditing protocol for editor abstraction"
```

---

## Task 10: STTextView Editor Integration

**Files:**
- Create: `Sources/Editor/STTextViewEditor.swift`

- [ ] **Step 1: Implement STTextViewEditor**

```swift
// Sources/Editor/STTextViewEditor.swift
import SwiftUI
import STTextView
import STTextViewAppKit

struct STTextViewEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorOffset: Int
    @Binding var scrollOffset: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = STTextView.scrollableTextView()
        let textView = scrollView.documentView as! STTextView

        // Configure appearance
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.showLineNumbers = true
        textView.highlightSelectedLine = true
        textView.isIncrementalSearchingEnabled = true

        // Line height
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.3
        paragraph.defaultTabInterval = 28
        textView.typingAttributes[.paragraphStyle] = paragraph

        // Set delegate
        textView.delegate = context.coordinator

        // Initial content
        textView.text = text

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? STTextView else { return }

        // Only update text if it changed externally (not from user typing)
        if textView.text != text && !context.coordinator.isEditing {
            textView.text = text
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, STTextViewDelegate {
        var parent: STTextViewEditor
        var isEditing = false

        init(_ parent: STTextViewEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }
            isEditing = true
            parent.text = textView.text ?? ""
            isEditing = false
        }
    }
}
```

Note: STTextView's delegate API may differ from this — check the actual `STTextViewDelegate` protocol methods when implementing. The key pattern is:
1. `makeNSView` creates and configures the text view once
2. `updateNSView` pushes external changes in (guarded by `isEditing` to avoid loops)
3. The coordinator's delegate method pushes user edits out via the binding

- [ ] **Step 2: Update ContentView to use STTextViewEditor**

Replace the placeholder `editorPanel` in `Sources/App/ContentView.swift`:

```swift
    @State private var cursorOffset: Int = 0
    @State private var editorScrollOffset: Int = 0

    // Replace the existing editorPanel property:
    private var editorPanel: some View {
        STTextViewEditor(
            text: $document.text,
            cursorOffset: $cursorOffset,
            scrollOffset: $editorScrollOffset
        )
    }
```

- [ ] **Step 3: Build and verify**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED. Open in Xcode and run — the Editor tab should show an STTextView with line numbers and monospaced font.

- [ ] **Step 4: Commit**

```bash
git add Sources/Editor/STTextViewEditor.swift Sources/App/ContentView.swift
git commit -m "feat: integrate STTextView editor with line numbers"
```

---

## Task 11: Editor Syntax Highlighting

**Files:**
- Create: `Sources/Editor/MarkdownHighlighter.swift`

- [ ] **Step 1: Implement MarkdownHighlighter**

```swift
// Sources/Editor/MarkdownHighlighter.swift
import AppKit
import STTextView

/// Applies regex-based Markdown syntax highlighting to an STTextView's text storage.
struct MarkdownHighlighter {

    // MARK: - Token Patterns

    private static let patterns: [(NSRegularExpression, [NSAttributedString.Key: Any])] = {
        let heading = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$", options: .anchorsMatchLines)
        let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(.+?)(\\*\\*|__)", options: [])
        let italic = try! NSRegularExpression(pattern: "(?<![*_])([*_])(?![*_])(.+?)(?<![*_])\\1(?![*_])", options: [])
        let inlineCode = try! NSRegularExpression(pattern: "`([^`]+)`", options: [])
        let codeBlock = try! NSRegularExpression(pattern: "^```.*$", options: .anchorsMatchLines)
        let link = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", options: [])
        let blockquote = try! NSRegularExpression(pattern: "^>\\s?(.*)$", options: .anchorsMatchLines)
        let listMarker = try! NSRegularExpression(pattern: "^(\\s*)([-*+]|\\d+\\.)\\s", options: .anchorsMatchLines)
        let horizontalRule = try! NSRegularExpression(pattern: "^(-{3,}|\\*{3,}|_{3,})\\s*$", options: .anchorsMatchLines)

        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold)
        ]
        let italicAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular).withTraits(.italic)
        ]
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .backgroundColor: NSColor.quaternaryLabelColor
        ]
        let codeBlockAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ]
        let linkAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor
        ]
        let blockquoteAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let listMarkerAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.controlAccentColor
        ]
        let hrAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.separatorColor
        ]

        return [
            (heading, headingAttrs),
            (codeBlock, codeBlockAttrs),
            (bold, boldAttrs),
            (italic, italicAttrs),
            (inlineCode, codeAttrs),
            (link, linkAttrs),
            (blockquote, blockquoteAttrs),
            (listMarker, listMarkerAttrs),
            (horizontalRule, hrAttrs),
        ]
    }()

    // MARK: - Highlighting

    /// Apply syntax highlighting to the given attributed string
    func highlight(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        // Reset to defaults
        textStorage.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor
        ], range: fullRange)

        // Apply patterns
        for (regex, attrs) in Self.patterns {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let matchRange = match?.range else { return }
                textStorage.addAttributes(attrs, range: matchRange)
            }
        }
    }
}

// MARK: - NSFont extension

private extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
```

- [ ] **Step 2: Integrate highlighter into STTextViewEditor**

Add the highlighter call in `STTextViewEditor.swift`'s coordinator. In the `textDidChange` delegate method, after updating the binding:

```swift
func textDidChange(_ notification: Notification) {
    guard let textView = notification.object as? STTextView else { return }
    isEditing = true
    parent.text = textView.text ?? ""
    isEditing = false

    // Apply syntax highlighting
    if let textStorage = textView.textContentStorage?.textStorage {
        let highlighter = MarkdownHighlighter()
        highlighter.highlight(textStorage)
    }
}
```

Also apply highlighting in `makeNSView` after setting initial text, so the document is highlighted on open.

Note: Accessing `textContentStorage?.textStorage` depends on STTextView's internal API. If this path doesn't work, explore `textView.addAttributes(_:range:)` directly or the plugin system. Check STTextView docs during implementation.

- [ ] **Step 3: Build and verify**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED. When running, headings should appear bold, code should have a background tint, links should be blue.

- [ ] **Step 4: Commit**

```bash
git add Sources/Editor/MarkdownHighlighter.swift Sources/Editor/STTextViewEditor.swift
git commit -m "feat: add Markdown syntax highlighting in editor"
```

---

## Task 12: Editor Keyboard Shortcuts

**Files:**
- Create: `Sources/Editor/EditorKeyCommands.swift`
- Create: `Tests/EditorKeyCommandsTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/EditorKeyCommandsTests.swift
import Testing
import Foundation
@testable import OnYourMarks

@Suite("EditorKeyCommands")
struct EditorKeyCommandsTests {

    @Test("Bold wraps selection")
    func boldWithSelection() {
        var text = "Hello World"
        var range = NSRange(location: 6, length: 5) // "World"
        EditorKeyCommands.bold(text: &text, selectedRange: &range)
        #expect(text == "Hello **World**")
        #expect(range == NSRange(location: 8, length: 5)) // selection on "World"
    }

    @Test("Bold inserts markers with no selection")
    func boldNoSelection() {
        var text = "Hello "
        var range = NSRange(location: 6, length: 0)
        EditorKeyCommands.bold(text: &text, selectedRange: &range)
        #expect(text == "Hello ****")
        #expect(range == NSRange(location: 8, length: 0)) // cursor between **
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
        // "url" should be selected
        #expect(range == NSRange(location: 13, length: 3))
    }

    @Test("Link inserts template with no selection")
    func linkNoSelection() {
        var text = "Hello "
        var range = NSRange(location: 6, length: 0)
        EditorKeyCommands.link(text: &text, selectedRange: &range)
        #expect(text == "Hello [](url)")
        // cursor inside []
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
        // "url" should be selected
        #expect(range == NSRange(location: 14, length: 3))
    }

    @Test("Image inserts template with no selection")
    func imageNoSelection() {
        var text = ""
        var range = NSRange(location: 0, length: 0)
        EditorKeyCommands.image(text: &text, selectedRange: &range)
        #expect(text == "![](url)")
        // cursor inside []
        #expect(range == NSRange(location: 2, length: 0))
    }

    @Test("Code block inserts fenced block")
    func codeBlockInsertion() {
        var text = "Hello"
        var range = NSRange(location: 5, length: 0)
        EditorKeyCommands.codeBlock(text: &text, selectedRange: &range)
        #expect(text == "Hello```\n\n```")
        // cursor on content line
        #expect(range == NSRange(location: 9, length: 0))
    }

    @Test("Horizontal rule inserts ---")
    func horizontalRuleInsertion() {
        var text = "Hello"
        var range = NSRange(location: 5, length: 0)
        EditorKeyCommands.horizontalRule(text: &text, selectedRange: &range)
        #expect(text.contains("---"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test --filter EditorKeyCommandsTests`
Expected: FAIL — `EditorKeyCommands` not found

- [ ] **Step 3: Implement EditorKeyCommands**

```swift
// Sources/Editor/EditorKeyCommands.swift
import Foundation

enum EditorKeyCommands {

    // MARK: - Wrap Commands

    static func bold(text: inout String, selectedRange: inout NSRange) {
        wrap(text: &text, selectedRange: &selectedRange, prefix: "**", suffix: "**")
    }

    static func italic(text: inout String, selectedRange: inout NSRange) {
        wrap(text: &text, selectedRange: &selectedRange, prefix: "*", suffix: "*")
    }

    static func inlineCode(text: inout String, selectedRange: inout NSRange) {
        wrap(text: &text, selectedRange: &selectedRange, prefix: "`", suffix: "`")
    }

    // MARK: - Link / Image

    static func link(text: inout String, selectedRange: inout NSRange) {
        let nsText = text as NSString
        if selectedRange.length > 0 {
            let selected = nsText.substring(with: selectedRange)
            let replacement = "[\(selected)](url)"
            text = nsText.replacingCharacters(in: selectedRange, with: replacement)
            // Select "url"
            selectedRange = NSRange(
                location: selectedRange.location + selected.count + 3,
                length: 3
            )
        } else {
            let insertion = "[](url)"
            text = nsText.replacingCharacters(
                in: NSRange(location: selectedRange.location, length: 0),
                with: insertion
            )
            // Cursor inside []
            selectedRange = NSRange(location: selectedRange.location + 1, length: 0)
        }
    }

    static func image(text: inout String, selectedRange: inout NSRange) {
        let nsText = text as NSString
        if selectedRange.length > 0 {
            let selected = nsText.substring(with: selectedRange)
            let replacement = "![\(selected)](url)"
            text = nsText.replacingCharacters(in: selectedRange, with: replacement)
            selectedRange = NSRange(
                location: selectedRange.location + selected.count + 4,
                length: 3
            )
        } else {
            let insertion = "![](url)"
            text = nsText.replacingCharacters(
                in: NSRange(location: selectedRange.location, length: 0),
                with: insertion
            )
            selectedRange = NSRange(location: selectedRange.location + 2, length: 0)
        }
    }

    // MARK: - Code Block

    static func codeBlock(text: inout String, selectedRange: inout NSRange) {
        let insertion = "```\n\n```"
        let nsText = text as NSString
        text = nsText.replacingCharacters(
            in: NSRange(location: selectedRange.location, length: 0),
            with: insertion
        )
        // Cursor on the empty content line
        selectedRange = NSRange(location: selectedRange.location + 4, length: 0)
    }

    // MARK: - Horizontal Rule

    static func horizontalRule(text: inout String, selectedRange: inout NSRange) {
        let insertion = "\n---\n"
        let nsText = text as NSString
        text = nsText.replacingCharacters(
            in: NSRange(location: selectedRange.location, length: 0),
            with: insertion
        )
        selectedRange = NSRange(location: selectedRange.location + insertion.count, length: 0)
    }

    // MARK: - Heading Level

    static func increaseHeading(text: inout String, selectedRange: inout NSRange) {
        let lines = text.components(separatedBy: "\n")
        let (lineIndex, _) = lineAndOffset(for: selectedRange.location, in: text)
        guard lineIndex < lines.count else { return }

        var line = lines[lineIndex]
        let currentLevel = line.prefix(while: { $0 == "#" }).count
        guard currentLevel < 6 else { return }

        if currentLevel == 0 {
            line = "# " + line
        } else {
            line = "#" + line
        }

        var newLines = lines
        newLines[lineIndex] = line
        text = newLines.joined(separator: "\n")
        selectedRange = NSRange(location: selectedRange.location + 1, length: selectedRange.length)
    }

    static func decreaseHeading(text: inout String, selectedRange: inout NSRange) {
        let lines = text.components(separatedBy: "\n")
        let (lineIndex, _) = lineAndOffset(for: selectedRange.location, in: text)
        guard lineIndex < lines.count else { return }

        var line = lines[lineIndex]
        let currentLevel = line.prefix(while: { $0 == "#" }).count
        guard currentLevel > 0 else { return }

        if currentLevel == 1 {
            // Remove "# "
            line = String(line.dropFirst(2))
        } else {
            // Remove one "#"
            line = String(line.dropFirst(1))
        }

        var newLines = lines
        newLines[lineIndex] = line
        text = newLines.joined(separator: "\n")
        let offset = currentLevel == 1 ? 2 : 1
        selectedRange = NSRange(
            location: max(0, selectedRange.location - offset),
            length: selectedRange.length
        )
    }

    // MARK: - Helpers

    private static func wrap(text: inout String, selectedRange: inout NSRange, prefix: String, suffix: String) {
        let nsText = text as NSString
        if selectedRange.length > 0 {
            let selected = nsText.substring(with: selectedRange)
            let replacement = "\(prefix)\(selected)\(suffix)"
            text = nsText.replacingCharacters(in: selectedRange, with: replacement)
            selectedRange = NSRange(
                location: selectedRange.location + prefix.count,
                length: selected.count
            )
        } else {
            let insertion = "\(prefix)\(suffix)"
            text = nsText.replacingCharacters(
                in: NSRange(location: selectedRange.location, length: 0),
                with: insertion
            )
            selectedRange = NSRange(
                location: selectedRange.location + prefix.count,
                length: 0
            )
        }
    }

    private static func lineAndOffset(for charOffset: Int, in text: String) -> (line: Int, column: Int) {
        var line = 0
        var col = 0
        for (i, char) in text.enumerated() {
            if i == charOffset { break }
            if char == "\n" {
                line += 1
                col = 0
            } else {
                col += 1
            }
        }
        return (line, col)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test --filter EditorKeyCommandsTests`
Expected: All tests PASS

- [ ] **Step 5: Wire key commands into STTextViewEditor**

In `STTextViewEditor.swift`, add key event handling in `makeNSView` by subclassing or using STTextView's key handling mechanism. The shortcuts should call `EditorKeyCommands` methods and update the text view accordingly. This requires reading the current text and selection from the STTextView, calling the command, then writing back.

- [ ] **Step 6: Commit**

```bash
git add Sources/Editor/EditorKeyCommands.swift Tests/EditorKeyCommandsTests.swift Sources/Editor/STTextViewEditor.swift
git commit -m "feat: add Markdown keyboard shortcuts (bold, italic, link, heading, etc.)"
```

---

## Task 13: Menu Bar & App-Level Keyboard Shortcuts

**Files:**
- Modify: `Sources/App/OnYourMarksApp.swift`
- Modify: `Sources/App/ContentView.swift`

- [ ] **Step 1: Add custom commands to OnYourMarksApp**

```swift
// Update OnYourMarksApp.swift — add .commands modifier to DocumentGroup
.commands {
    // View menu
    CommandGroup(after: .toolbar) {
        Button("Preview") {
            NotificationCenter.default.post(name: .switchToPreview, object: nil)
        }
        .keyboardShortcut("1", modifiers: .command)

        Button("Editor") {
            NotificationCenter.default.post(name: .switchToEditor, object: nil)
        }
        .keyboardShortcut("2", modifiers: .command)

        Button("Toggle Split View") {
            NotificationCenter.default.post(name: .toggleSplit, object: nil)
        }
        .keyboardShortcut("\\", modifiers: .command)

        Divider()

        Button("Toggle GFM") {
            NotificationCenter.default.post(name: .toggleGFM, object: nil)
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])
    }

    // Format menu
    CommandMenu("Format") {
        Button("Bold") {
            NotificationCenter.default.post(name: .formatBold, object: nil)
        }
        .keyboardShortcut("b", modifiers: .command)

        Button("Italic") {
            NotificationCenter.default.post(name: .formatItalic, object: nil)
        }
        .keyboardShortcut("i", modifiers: .command)

        Button("Inline Code") {
            NotificationCenter.default.post(name: .formatCode, object: nil)
        }
        .keyboardShortcut("e", modifiers: .command)

        Button("Code Block") {
            NotificationCenter.default.post(name: .formatCodeBlock, object: nil)
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])

        Divider()

        Button("Link") {
            NotificationCenter.default.post(name: .formatLink, object: nil)
        }
        .keyboardShortcut("k", modifiers: .command)

        Button("Image") {
            NotificationCenter.default.post(name: .formatImage, object: nil)
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])

        Divider()

        Menu("Heading") {
            ForEach(1...6, id: \.self) { level in
                Button("H\(level)") {
                    NotificationCenter.default.post(
                        name: .formatHeading,
                        object: level
                    )
                }
            }
        }

        Button("Increase Heading Level") {
            NotificationCenter.default.post(name: .formatHeadingIncrease, object: nil)
        }
        .keyboardShortcut("]", modifiers: .command)

        Button("Decrease Heading Level") {
            NotificationCenter.default.post(name: .formatHeadingDecrease, object: nil)
        }
        .keyboardShortcut("[", modifiers: .command)

        Divider()

        Button("Horizontal Rule") {
            NotificationCenter.default.post(name: .formatHorizontalRule, object: nil)
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }
}
```

- [ ] **Step 2: Define notification names**

Add to a new file or an extension:

```swift
// Add to Sources/App/Notifications.swift
import Foundation

extension Notification.Name {
    static let switchToPreview = Notification.Name("switchToPreview")
    static let switchToEditor = Notification.Name("switchToEditor")
    static let toggleSplit = Notification.Name("toggleSplit")
    static let toggleGFM = Notification.Name("toggleGFM")
    static let formatBold = Notification.Name("formatBold")
    static let formatItalic = Notification.Name("formatItalic")
    static let formatCode = Notification.Name("formatCode")
    static let formatCodeBlock = Notification.Name("formatCodeBlock")
    static let formatLink = Notification.Name("formatLink")
    static let formatImage = Notification.Name("formatImage")
    static let formatHeading = Notification.Name("formatHeading")
    static let formatHeadingIncrease = Notification.Name("formatHeadingIncrease")
    static let formatHeadingDecrease = Notification.Name("formatHeadingDecrease")
    static let formatHorizontalRule = Notification.Name("formatHorizontalRule")
}
```

**Important:** Since `DocumentGroup` supports multiple windows, notification handlers in `ContentView` must check that their window is the key window before acting on format commands. In each `.onReceive` handler, guard with:
```swift
guard NSApp.keyWindow == /* this view's window */ else { return }
```
Alternatively, consider migrating to SwiftUI's `FocusedValue` system for a more idiomatic approach — this naturally scopes commands to the focused window. This is a v1.1 improvement if notifications work well enough initially.
```

- [ ] **Step 3: Handle notifications in ContentView**

Add `.onReceive` modifiers in ContentView to respond to the notification-based commands and update `viewMode`, `isSplitView`, `useGFM` state accordingly. Format commands should be forwarded to the active editor.

- [ ] **Step 4: Build and verify**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED. Menu bar should show File, Edit, View (with mode shortcuts), Format (with markdown shortcuts), Window, Help.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/OnYourMarksApp.swift Sources/App/ContentView.swift Sources/App/Notifications.swift
git commit -m "feat: add menu bar with View and Format menus + keyboard shortcuts"
```

---

## Task 14: File Watcher Integration

**Files:**
- Modify: `Sources/App/ContentView.swift`
- Modify: `Sources/Document/MarkdownDocument.swift`

- [ ] **Step 1: Add FileWatcher to ContentView**

Wire the FileWatcher into the document lifecycle in ContentView:

```swift
@State private var fileWatcher: FileWatcher?

// In body, add .onAppear and .onDisappear:
.onAppear {
    startFileWatcher()
}
.onDisappear {
    fileWatcher?.stop()
}
.onChange(of: document.fileURL) { _, _ in
    startFileWatcher()
}

private func startFileWatcher() {
    fileWatcher?.stop()
    guard let url = document.fileURL else { return }

    let doc = document // capture the class reference
    fileWatcher = FileWatcher(url: url, knownHash: doc.lastKnownHash) { [weak doc] newContent in
        guard let document = doc else { return }

        if newContent.isEmpty {
            // File was deleted
            // Show alert (implement via @State showDeletedAlert)
            return
        }

        if document.isDirty {
            // Conflict — show dialog
            // Implement via @State showConflictAlert
        } else {
            // Silent reload
            document.text = newContent
            document.didLoad()
        }
    }
    fileWatcher?.start()
}
```

- [ ] **Step 2: Add conflict dialog**

Add alert modifiers to ContentView for the conflict and deletion cases:

```swift
@State private var showConflictAlert = false
@State private var showDeletedAlert = false
@State private var pendingExternalContent: String = ""

// In body:
.alert("File Changed on Disk", isPresented: $showConflictAlert) {
    Button("Reload") {
        document.text = pendingExternalContent
        document.didLoad()
        fileWatcher?.updateKnownHash(document.contentHash)
    }
    Button("Keep Mine", role: .cancel) {
        // Update known hash to disk version to avoid re-triggering
        if let url = document.fileURL, let hash = FileWatcher.sha256(of: url) {
            fileWatcher?.updateKnownHash(hash)
        }
    }
} message: {
    Text("The file has been modified by another application. Reload the external version or keep your changes?")
}
.alert("File Deleted", isPresented: $showDeletedAlert) {
    Button("Save a Copy...") {
        // Trigger Save As
    }
    Button("Close", role: .destructive) {
        // Close window
    }
} message: {
    Text("The file has been deleted from disk. Your content is still in memory.")
}
```

- [ ] **Step 3: Update MarkdownDocument.didSave to notify FileWatcher**

After saving, update the FileWatcher's known hash so it ignores the self-triggered event:

```swift
// In the save flow (ContentView or wherever save is handled):
document.didSave()
fileWatcher?.updateKnownHash(document.contentHash)
```

- [ ] **Step 4: Build and test manually**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED. Manual test: open a file, edit it externally, verify the app reloads or shows the conflict dialog.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/ContentView.swift Sources/Document/MarkdownDocument.swift
git commit -m "feat: integrate FileWatcher with conflict dialog and self-change detection"
```

---

## Task 15: State Persistence & Polish

**Files:**
- Modify: `Sources/App/ContentView.swift`

- [ ] **Step 1: Persist view mode and split state**

```swift
// Add to ContentView:
@AppStorage("viewMode") private var savedViewMode: Int = ViewMode.preview.rawValue
@AppStorage("isSplitView") private var savedSplitView: Bool = false

// In .onAppear:
viewMode = ViewMode(rawValue: savedViewMode) ?? .preview
isSplitView = savedSplitView

// Add .onChange modifiers:
.onChange(of: viewMode) { _, newValue in
    savedViewMode = newValue.rawValue
}
.onChange(of: isSplitView) { _, newValue in
    savedSplitView = newValue
}
```

- [ ] **Step 2: Verify debounced rendering works end-to-end**

Debounced rendering was added in Task 8 via `scheduleRender()`. Verify it works correctly in all modes: preview-only, editor-only, and split view. Check that typing in the editor updates the preview after ~200ms without jank.

- [ ] **Step 3: Add auto-indent for list continuation and Tab handling**

In `STTextViewEditor.swift`, handle key events:

**Return key — list continuation:**
When the user presses Return at the end of a line matching `^\s*[-*+]\s` or `^\s*\d+\.\s`, insert a newline followed by the same list prefix. If the current list item is empty (just the marker), remove it instead.

**Tab key — insert 4 spaces:**
Intercept the Tab key and insert 4 spaces instead of a tab character.

**Shift+Tab — dedent:**
Intercept Shift+Tab and remove up to 4 leading spaces from the current line.

These key events should be handled via STTextView's key event mechanism — either by overriding `keyDown(with:)` on a subclass or via the delegate's key handling methods. Check STTextView's API at implementation time.

- [ ] **Step 4: Build and verify all features work together**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED. Full manual test:
1. Open a `.md` file → Preview renders
2. Switch to Editor → syntax highlighted, line numbers
3. Type text → Preview updates after 200ms
4. Cmd+B → wraps selection in bold
5. Toggle split view → side-by-side
6. External edit → reload or conflict dialog
7. Quit and reopen → same mode remembered

- [ ] **Step 5: Commit**

```bash
git add Sources/App/ContentView.swift Sources/Editor/STTextViewEditor.swift
git commit -m "feat: add state persistence, debounced rendering, list auto-indent"
```

---

## Task 16: Accessibility & Final Polish

**Files:**
- Modify: `Sources/App/ContentView.swift`
- Modify: `Sources/Editor/STTextViewEditor.swift`

- [ ] **Step 1: Add accessibility labels to toolbar controls**

```swift
// Segmented control
.accessibilityLabel("View mode")

// Split toggle
.accessibilityLabel("Toggle split view")

// GFM toggle
.accessibilityLabel("Toggle GitHub Flavored Markdown")
```

- [ ] **Step 2: Add window title with document name**

ContentView should show the filename in the window title. `DocumentGroup` handles this automatically via `ReferenceFileDocument`, but verify it works — the title bar should show "filename.md" with an unsaved-changes dot when dirty.

- [ ] **Step 3: Final build and run**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift build`
Expected: BUILD SUCCEEDED. Complete manual testing of all features.

- [ ] **Step 4: Run full test suite**

Run: `cd "/Users/andyshepherd/Downloads/On Your Marks" && swift test`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add accessibility labels and final polish"
```

---

## Summary

| Task | What it builds | Dependencies |
|------|---------------|-------------|
| 1 | Project scaffolding | — |
| 2 | Markdown parser | Task 1 |
| 3 | HTML renderer | Tasks 1, 2 |
| 4 | Preview resources (HTML/CSS/JS) | Task 1 |
| 5 | Document model | Task 1 |
| 6 | File watcher | Task 5 |
| 7 | Preview view (WKWebView) | Tasks 3, 4 |
| 8 | App shell — preview mode | Tasks 5, 7 |
| 9 | Editor protocol | Task 1 |
| 10 | STTextView editor | Tasks 8, 9 |
| 11 | Syntax highlighting | Task 10 |
| 12 | Keyboard shortcuts | Task 10 |
| 13 | Menu bar | Tasks 8, 12 |
| 14 | File watcher integration | Tasks 6, 8 |
| 15 | State persistence + debounce | Tasks 8, 10, 14 |
| 16 | Accessibility + polish | All above |

Tasks 2, 3, 4, 5 can be parallelised after Task 1. Tasks 6 and 9 can be parallelised. Tasks 11 and 12 can be parallelised.
