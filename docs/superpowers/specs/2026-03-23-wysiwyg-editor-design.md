# WYSIWYG Editor — Design Specification

**Date:** 2026-03-23
**Platform:** Native macOS (macOS 15+)
**Language:** Swift / SwiftUI / AppKit
**Architecture:** NSTextView with custom attributed string pipeline

---

## 1. Overview

Add a WYSIWYG editing mode to On Your Marks as a third mode alongside the existing Preview and Raw Editor. The WYSIWYG presents a Notion/Bear-style rich text editing experience where Markdown syntax is invisible — users see formatted headings, bold text, rendered images, and editable tables. The underlying storage format remains Markdown.

### Target Audience

Non-technical users who want to write and edit Markdown documents without learning Markdown syntax. The WYSIWYG should be a fully self-contained editing environment that doesn't require switching to the raw editor for any common operation.

### Design Decisions

- **Full coverage:** All Markdown elements are editable in WYSIWYG — headings, bold/italic/strikethrough, links, images, lists (including GFM task lists), blockquotes, code blocks (with language), tables, horizontal rules.
- **Full-width only:** WYSIWYG does not participate in split view. Split view remains Raw Editor + Preview. When the user switches to WYSIWYG while split view is active, split view is automatically turned off. The split toggle button is disabled while in WYSIWYG mode.
- **Fixed toolbar + slash commands:** A persistent toolbar strip for discoverability, plus `/` commands for keyboard-driven power users.
- **Native implementation:** NSTextView (TextKit 2) with custom NSTextAttachments, not a web-based editor.
- **GFM required (prerequisite fix):** The existing `MarkdownParser.parse()` ignores the `useGFM` flag — it calls `Document(parsing: source)` without options. This is a pre-existing bug affecting Preview too. As a prerequisite to this work, `MarkdownParser` must be updated to pass GFM parsing options to `Document(parsing:options:)` when `useGFM` is true, enabling table and strikethrough support across all modes.

---

## 2. Core Architecture — The Round-Trip Pipeline

### The Pipeline

```
                    Load                              Save
Markdown string ──────▶ swift-markdown AST ──────▶ NSAttributedString
                                                        │
                                                   [user edits]
                                                        │
NSAttributedString ──────▶ Markdown string ◀────── AttributedString
                    (custom serializer)                 walker
```

### Custom Attributes as Metadata

Every piece of text in the attributed string carries custom `NSAttributedString.Key` attributes tagging what Markdown construct it came from:

```swift
extension NSAttributedString.Key {
    static let markdownHeading       = NSAttributedString.Key("md.heading")       // Int (1-6)
    static let markdownStrong        = NSAttributedString.Key("md.strong")        // Bool
    static let markdownEmphasis      = NSAttributedString.Key("md.emphasis")      // Bool
    static let markdownLink          = NSAttributedString.Key("md.link")          // String (URL)
    static let markdownCode          = NSAttributedString.Key("md.code")          // Bool
    static let markdownBlockquote    = NSAttributedString.Key("md.blockquote")    // Bool
    static let markdownListItem      = NSAttributedString.Key("md.listItem")      // MarkdownListStyle
    static let markdownStrikethrough = NSAttributedString.Key("md.strikethrough") // Bool
    static let markdownSourceRange   = NSAttributedString.Key("md.sourceRange")   // NSRange (byte offset into original source)
}

/// Encodes all list serialization details needed for round-trip fidelity.
enum MarkdownListStyle: Hashable {
    case unordered(depth: Int, marker: Character)  // marker: '-', '*', or '+'
    case ordered(depth: Int, start: Int)           // start: the number this item begins at
    case task(depth: Int, checked: Bool)           // GFM task list: - [ ] or - [x]
}
```

### Original Source Retention

The `markdownSourceRange` attribute stores an `NSRange` representing byte offsets into the original Markdown source string. The `MarkdownAttributedStringRenderer` retains a copy of the original source string alongside the attributed string. This pair (original source + attributed string with source ranges) enables the diff-and-patch serialization strategy described in Section 6. When the attributed string is modified by user edits, affected blocks have their `markdownSourceRange` cleared, signaling the serializer to re-generate those blocks from scratch.

When the user applies formatting (e.g., selects text and hits Cmd+B), the corresponding custom attribute is set on that range. The serializer reads these attributes to emit correct Markdown.

### Two New Core Components

1. **`MarkdownAttributedStringRenderer`** — a `MarkupVisitor` (like the existing `HTMLRenderer`) that walks a swift-markdown AST and produces an `NSAttributedString` with:
   - Visual styling (fonts, colors, paragraph styles) for display
   - Custom metadata attributes for round-trip serialization
   - `NSTextAttachment` instances for complex blocks (images, tables, code blocks)
   - Source range annotations from the original Markdown

2. **`AttributedStringMarkdownSerializer`** — walks an `NSAttributedString` and emits a Markdown string by reading the custom attributes and calling `serializeToMarkdown()` on any embedded `MarkdownBlockAttachment` instances.

### What Stays The Same

- `MarkdownDocument` holds the raw Markdown string as source of truth
- `MarkdownParser` (swift-markdown) does the parsing
- The WYSIWYG view reads from and writes to `document.text`, same as the raw editor
- `FileWatcher`, dirty tracking, hash comparison — all unchanged

---

## 3. View Layer — NSTextView

### Why NSTextView, Not STTextView

STTextView is optimised for code editing (line numbers, monospace, raw text). The WYSIWYG needs:
- **NSTextAttachments** for embedded images and tables
- **Rich paragraph styles** (heading sizes, blockquote indentation, list markers)
- **Native undo/redo** with attributed string changes

NSTextView handles all of this with TextKit 2 on macOS 15+.

### View Structure

```
WYSIWYGEditorView (NSViewRepresentable)
├── NSScrollView
│   └── NSTextView
│       ├── NSTextContentStorage (attributed string backing)
│       └── NSTextAttachments
│           ├── ImageAttachment (inline images)
│           ├── TableAttachment (editable table grid)
│           └── CodeBlockAttachment (syntax-highlighted code region)
└── WYSIWYGToolbarView (SwiftUI, above the text view)
```

### Mode Integration

The `ViewMode` enum gains a third case. To avoid breaking the existing `editor = 1` raw value (which may be persisted), WYSIWYG is appended after editor:

```swift
enum ViewMode: Int, CaseIterable {
    case preview = 0
    case editor = 1
    case wysiwyg = 2
}
```

The segmented control in the toolbar becomes three segments: **Preview | WYSIWYG | Editor**. Note: the segmented control order (Preview, WYSIWYG, Editor) differs from the enum raw value order — the control is built with an explicit ordering array, not by iterating `CaseIterable`. Keyboard shortcuts: Cmd+1 (Preview), Cmd+2 (WYSIWYG), Cmd+3 (Editor).

### Split View Interaction

- When the user switches to WYSIWYG mode while `isSplitView` is true, `isSplitView` is automatically set to false.
- The split view toggle button is **disabled** (greyed out) while WYSIWYG is the active mode.
- When switching from WYSIWYG back to Preview or Editor, the previous `isSplitView` state is **not** restored — the user must re-enable split view manually.

### Data Flow

1. **Switching to WYSIWYG:** Read `document.text` → parse with swift-markdown → `MarkdownAttributedStringRenderer` → set as NSTextView content.
2. **User edits:** NSTextView delegate fires on change → serialize via `AttributedStringMarkdownSerializer` → write to `document.text` (debounced 200ms).
3. **Switching away:** The serialized Markdown is already in `document.text` — Preview and Raw Editor read it as normal.

### Undo/Redo

NSTextView's built-in `UndoManager` handles undo/redo. All formatting operations (applying bold, changing heading level, etc.) must apply **both** the visual styling attributes and the custom Markdown metadata attributes in a single `beginEditing()`/`endEditing()` transaction on the `NSTextStorage`. This ensures undo reverts both together atomically — the user never sees a state where visual bold is present but `markdownStrong` is missing, or vice versa.

Undo/redo triggers the same `textDidChange` delegate callback as normal editing, so the debounced serialization runs automatically and the serialized Markdown stays consistent.

### Format Command Handling

The WYSIWYG view handles formatting commands (Cmd+B, Cmd+I, etc.) **independently** from the existing `FormatCommandReceivers` / `EditorKeyCommands` infrastructure, which operates on raw `String` + `NSRange`. When in WYSIWYG mode, the `WYSIWYGEditorView` intercepts these notifications and applies them as attributed string operations on the NSTextView. The existing `FormatCommandReceivers` modifier is only active when `viewMode == .editor`.

### Copy/Paste

- **Paste from external apps (HTML on pasteboard):** Convert to Markdown-attributed text. Use `NSPasteboard`'s HTML type, parse it into a simplified Markdown AST, then render as attributed string. Falls back to plain text paste if conversion fails.
- **Paste plain text:** Parse as Markdown and render as attributed string. If it looks like raw Markdown (contains `#`, `**`, etc.), it renders formatted. Otherwise it's plain prose.
- **Copy from WYSIWYG:** Places both plain text (as serialized Markdown) and rich text on the pasteboard, so pasting into other apps works naturally.

### Find & Replace

NSTextView's built-in Find Bar (Cmd+F) works in WYSIWYG mode and searches the visible text content (not Markdown syntax). Searching for `**` or `#` will not match formatting — this is expected since the user doesn't see those characters.

---

## 4. Complex Blocks — Tables, Images, Code Blocks

Each uses `NSTextAttachment` with a custom view embedded in the text flow via `NSTextAttachmentViewProvider` (the TextKit 2 API for view-based attachments). Each attachment provides a custom `NSTextAttachmentViewProvider` subclass that creates and sizes the embedded view. All conform to:

```swift
protocol MarkdownBlockAttachment {
    func serializeToMarkdown() -> String
}
```

The serializer calls `serializeToMarkdown()` when it encounters an attachment instead of reading text attributes.

### Attachment Sizing

Each `NSTextAttachmentViewProvider` returns an `NSView` with an intrinsic content size. The attachment view's width is constrained to the text container width. For dynamic content (tables that grow as rows are added), the view provider calls `NSTextAttachment.invalidateIntrinsicContentSize()` to trigger re-layout. Tables wider than the text container scroll horizontally within their attachment view.

### Images

- `NSTextAttachment` displaying the actual image, loaded from the relative path (same as Preview)
- Editable caption below showing the alt text
- Click → popover to change source URL or alt text
- Insert via toolbar button, `/image` slash command → file picker, or **drag and drop** an image file into the editor

### Tables

- `NSTextAttachment` containing a custom `NSView` — a grid of editable `NSTextField` cells
- The attachment tracks row/column structure and cell contents
- Click any cell to edit, Tab to navigate between cells
- Right-click context menu: add/remove row, add/remove column, set column alignment (left/center/right)
- Insert via toolbar or `/table` → creates a 2x2 starter table
- Serializes to GFM pipe syntax with alignment markers (`:---`, `:---:`, `---:`)

### Code Blocks

- `NSTextAttachment` containing a styled `NSTextView` with:
  - Monospace font, subtle background colour
  - Language label/picker in top-right corner
- Content is plain text — no Markdown formatting applies inside
- Insert via toolbar or `/code`

### Horizontal Rules

- `NSTextAttachment` containing a thin `NSView` (styled divider line)
- Not editable — visual separator only
- Delete by placing cursor adjacent and pressing backspace
- Insert via toolbar or `/divider`

### Blockquotes

- Styled paragraphs (not attachments): left indent + coloured left border via paragraph style and custom background drawing
- The `markdownBlockquote` attribute handles serialization
- Toggle via toolbar or `/quote`

---

## 5. Toolbar & Slash Commands

### Fixed Toolbar

A SwiftUI view above the NSTextView. Single compact row:

All buttons use SF Symbols for a native macOS look. Toggle buttons highlight when the formatting is active at the cursor position.

| Button | SF Symbol | Action |
|--------|-----------|--------|
| **H▾** | `textformat.size` | Dropdown picker: Paragraph, H1–H6 |
| **B** | `bold` | Toggle bold |
| **I** | `italic` | Toggle italic |
| **S** | `strikethrough` | Toggle strikethrough |
| **<>** | `chevron.left.forwardslash.chevron.right` | Toggle inline code |
| **Link** | `link` | Insert/edit link (URL popover) |
| **Image** | `photo` | Insert image (file picker / drag-drop) |
| **Bullet** | `list.bullet` | Toggle bullet list |
| **Numbered** | `list.number` | Toggle ordered list |
| **Task** | `checklist` | Toggle task list (checkboxes) |
| **Quote** | `text.quote` | Toggle blockquote |
| **Rule** | `minus` | Insert horizontal rule |
| **Table** | `tablecells` | Insert table (2x2) |

Toolbar buttons reflect active state at cursor position via `textViewDidChangeSelection`.

### Slash Commands

When the user types `/` at the beginning of an empty paragraph (including line 1 of a document, after any block element, or on any blank line), a floating `NSPopover` appears anchored to the cursor:

| Command | Action |
|---------|--------|
| `/heading 1-6` | Insert/convert to heading |
| `/bullet` | Start bullet list |
| `/numbered` | Start numbered list |
| `/quote` | Start blockquote |
| `/code` | Insert code block |
| `/table` | Insert 2x2 table |
| `/image` | Open image file picker |
| `/divider` | Insert horizontal rule |
| `/task` | Start task list (checkboxes) |

The menu filters as the user types after `/`. Arrow keys navigate, Enter selects, Escape dismisses. The `/` and filter text are replaced by the inserted element.

### Keyboard Shortcuts

Same as the raw editor: Cmd+B (bold), Cmd+I (italic), Cmd+K (link), Cmd+E (inline code), Cmd+Shift+X (strikethrough), Cmd+Shift+E (code block), Cmd+Shift+L (horizontal rule), Cmd+]/[ (heading level). They toggle the corresponding custom attribute on the selection. Cmd+Shift+X for strikethrough is new — it should also be added to the raw editor's `EditorKeyCommands` for consistency.

**Note:** Cmd+E overrides macOS's "Use Selection for Find" — this is an intentional trade-off carried over from the raw editor, where inline code wrapping is more valuable. "Use Selection for Find" remains accessible via Edit → Find submenu.

---

## 6. Serialization & Round-Trip Fidelity

### The Problem

Markdown is syntactically ambiguous. The same content can be written as `**bold**` or `__bold__`, `- list` or `* list`, `# Heading` or `Heading\n======`. Naive serialization normalizes everything, destroying the original author's style choices.

### The Solution: Source-Anchored Attributes

When `MarkdownAttributedStringRenderer` builds the attributed string, it stores the **original source range** for each block via the `markdownSourceRange` attribute.

**On save**, the serializer uses a diff-and-patch strategy:

1. Walk the attributed string, build a list of blocks with their content and types.
2. For each block that has a `sourceRange` and hasn't been modified → **emit the original source text verbatim** (fast: just a substring copy from the retained original source).
3. For blocks that were modified or newly inserted → serialize fresh using consistent defaults (`**` for bold, `-` for bullets, `#` for headings).
4. Preserve original blank-line spacing between unmodified blocks.

### Serialization Performance

The diff-and-patch strategy is inherently performant: unmodified blocks are emitted as substring copies (O(1) per block), and only modified blocks require attribute walking and fresh serialization. For a 10,000-line document where the user edited one paragraph, the serializer touches only that paragraph's attributes. This easily fits within the 200ms debounce window. The serializer is not a full walk of all attributes — it's a block-level scan that short-circuits on unmodified source ranges.

### Practical Behaviour

- Open a file → edit one heading → save: only the heading line changes, everything else is byte-identical.
- Add a new paragraph: serialized with default style, surrounding blocks untouched.
- Delete a block: removed, surrounding spacing adjusted.
- Change a block's type (paragraph → heading): re-serialized from scratch for that block.

### Edge Cases

- **Unknown Markdown constructs** (footnotes, definition lists, etc.): preserved as raw text blocks with a "raw Markdown" attribute. Displayed with monospace styling and subtle border. Editable as raw text, not as rich formatting.
- **HTML blocks**: same treatment — displayed as raw, editable as text.
- **Link reference definitions** (`[id]: url`): preserved at their original positions, not rendered visually.

---

## 7. Testing Strategy

### Unit Tests

**`MarkdownAttributedStringRendererTests`:**
- Each Markdown element type → correct attributed string attributes
- Nested formatting (`**bold _and italic_**`) → both attributes set
- Complex blocks → correct `NSTextAttachment` types
- Source range attributes set correctly

**`AttributedStringMarkdownSerializerTests`:**
- Each element type: Markdown → attributed string → Markdown = identical output
- Mixed documents: parse a realistic README, serialize back, diff should be empty
- Edited documents: modify one block, verify only that block changes
- New content: attributed string built from scratch (no source ranges) → valid Markdown

**`TableAttachmentTests`:**
- Add/remove rows and columns
- Cell editing and tab navigation
- Serialization to GFM pipe syntax with alignment

**`SlashCommandTests`:**
- `/` triggers menu at correct positions
- Typing filters the menu
- Each command produces the correct block type

### Integration Tests

- **Round-trip corpus test:** a folder of `.md` files (READMEs, GFM tables, complex nesting). For each: parse → render to attributed string → serialize → compare to original.
- **Mode switching:** Raw → WYSIWYG → Raw → Preview, verify content is identical at each step.

---

## 8. File Structure (New/Modified)

```
Sources/
├── WYSIWYG/
│   ├── WYSIWYGEditorView.swift              # NSViewRepresentable wrapping NSTextView
│   ├── WYSIWYGToolbarView.swift             # SwiftUI toolbar with formatting buttons
│   ├── MarkdownAttributedStringRenderer.swift # AST → NSAttributedString visitor
│   ├── AttributedStringMarkdownSerializer.swift # NSAttributedString → Markdown
│   ├── MarkdownAttributes.swift             # Custom NSAttributedString.Key definitions
│   ├── MarkdownBlockAttachment.swift        # Protocol for complex block attachments
│   ├── SlashCommandMenu.swift               # NSPopover with filtered command list
│   └── Attachments/
│       ├── ImageAttachment.swift            # Image display + caption + edit popover
│       ├── TableAttachment.swift            # Editable table grid view
│       ├── CodeBlockAttachment.swift        # Syntax-highlighted code region
│       └── HorizontalRuleAttachment.swift   # Thin divider line view
├── App/
│   ├── ContentView.swift                    # Modified: add .wysiwyg case
│   └── MainWindowView.swift                 # Modified: update toolbar segmented control
Tests/
├── MarkdownAttributedStringRendererTests.swift
├── AttributedStringMarkdownSerializerTests.swift
├── TableAttachmentTests.swift
└── SlashCommandTests.swift
```

---

## 9. Non-Functional Requirements

- **Performance:** Documents up to 10,000 lines should load into the WYSIWYG within 500ms. Serialization back to Markdown should complete within the 200ms debounce window for typical documents.
- **No new dependencies:** Uses NSTextView (AppKit), swift-markdown (already present). No additional packages.
- **macOS 15+:** Required for TextKit 2 NSTextView features.
- **Accessibility:** NSTextView provides baseline VoiceOver support. Custom attachments should implement `NSAccessibility` protocols. Toolbar buttons need accessibility labels.
- **Dark mode:** All custom drawing (blockquote left border, code block background, table grid lines) uses `NSColor` semantic colours that adapt to light/dark appearance. NSTextView handles text colour automatically.
