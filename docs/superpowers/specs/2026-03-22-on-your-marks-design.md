# On Your Marks — Design Specification

**Date:** 2026-03-22
**Platform:** Native macOS app (macOS 26+)
**Language:** Swift / SwiftUI
**Architecture:** Modified Approach C — SwiftUI shell + WKWebView preview + STTextView (TextKit 2) editor

---

## 1. Overview

On Your Marks is a lightweight, native macOS Markdown viewer and editor. It prioritises fast preview with live file-watching (for use alongside external editors like Claude Code), a power-user raw editor, and comfortable reading — in that order.

### Use Case Priority

1. **Preview** — Rendered Markdown display with live file-watching. Primary use case: previewing files being written in Claude Code or other editors.
2. **Editor** — Raw Markdown editing with syntax highlighting, line numbers, and keyboard shortcuts.
3. **Reader** — Reviewing Markdown documents (READMEs, docs, notes) with occasional quick edits.

### Out of Scope (v1)

- WYSIWYG editor (v2 candidate)
- Export (PDF, HTML)
- Multiple file/project management
- Sidebar file browser
- Plugin system
- iOS/iPad

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────┐
│                   SwiftUI App Shell                  │
│  ┌───────────────────────────────────────────────┐  │
│  │  Toolbar: Segmented Control + Split Toggle    │  │
│  ├───────────────────────────────────────────────┤  │
│  │                                               │  │
│  │   ┌─────────────────┐  ┌─────────────────┐   │  │
│  │   │  Editor Panel    │  │  Preview Panel   │  │  │
│  │   │  (STTextView     │  │  (WKWebView      │  │  │
│  │   │   via NSView-    │  │   via NSView-    │  │  │
│  │   │   Representable) │  │   Representable) │  │  │
│  │   └────────┬─────────┘  └────────┬─────────┘  │  │
│  │            │                      │            │  │
│  └────────────┼──────────────────────┼────────────┘  │
│               │                      │               │
│  ┌────────────▼──────────────────────▼────────────┐  │
│  │              Document Model                     │  │
│  │   MarkdownDocument (ReferenceFileDocument)      │  │
│  │   FileWatcher (DispatchSource)                  │  │
│  ├─────────────────────────────────────────────────┤  │
│  │              Markdown Pipeline                   │  │
│  │   Parser (swift-markdown, CommonMark/GFM)       │  │
│  │   HTML Renderer (AST → HTML visitor)            │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### Key Components

- **SwiftUI App Shell** — Window management, toolbar, segmented control, split view toggle, menu bar, keyboard shortcuts.
- **Editor Panel** — STTextView wrapped in `NSViewRepresentable`, behind a `MarkdownEditing` protocol. The concrete implementation is `STTextViewEditor`. Swappable to native NSTextView if Apple improves TextKit 2 at WWDC26.
- **Preview Panel** — WKWebView rendering HTML with an embedded CSS stylesheet and highlight.js for code blocks.
- **Document Model** (`MarkdownDocument`) — Single source of truth. Conforms to `ReferenceFileDocument` for native macOS document lifecycle.
- **FileWatcher** — Monitors the file on disk via `DispatchSource.makeFileSystemObjectSource`, triggers reload/merge.
- **Markdown Pipeline** — Parser (configurable CommonMark vs GFM) → HTML Renderer → WKWebView.

### Data Flow

1. **External change:** File on disk → FileWatcher detects change → Document Model updates → both Editor and Preview refresh.
2. **User edit:** User types in Editor → Document Model updates → Preview refreshes (debounced ~200ms).
3. **User save:** Cmd+S → Document Model writes to disk → FileWatcher ignores self-triggered change (via content hash comparison — see Section 4).

---

## 3. Window Layout & Mode Switching

### Modes

The app has two **primary modes** controlled by a segmented control, and an independent **split view overlay**:

- **Preview** (Cmd+1) — Full-width rendered Markdown. Read-only.
- **Editor** (Cmd+2) — Full-width raw Markdown editing with line numbers and syntax highlighting.

### Split View

Split view is an **independent toggle**, not a third mode. It overlays the current segmented control state:

- **Cmd+\\** or toolbar button toggles split view on/off.
- When split is active, both Editor and Preview are shown side by side with a resizable divider. The segmented control is visually deselected (both segments unhighlighted).
- Pressing Cmd+1 or Cmd+2 while split is active **exits split view** and switches to the selected full-width mode.
- Split view state is persisted independently from the mode selection via `UserDefaults`.

### State Preservation

- **Editor cursor position:** Stored as a character offset in the document model. Restored when switching back to Editor or Split mode.
- **Editor scroll position:** Stored as a character offset of the first visible line.
- **Preview scroll position:** Stored as a percentage of total document height. When switching from Editor to Preview, the scroll position is approximated from the editor's cursor offset (map character offset to percentage of total content). Exact heading-anchor synchronisation is a v2 enhancement.

### Behaviour

- Opens in **Preview** mode on first launch.
- Last-used mode and split state remembered via `UserDefaults`.

---

## 4. File Handling & Conflict Resolution

### Document Lifecycle

Uses `ReferenceFileDocument` (SwiftUI's document protocol for reference-type models):

- Native Open/Save/Save As via standard macOS file dialogs.
- Unsaved-changes dot in the title bar.
- Drag-and-drop `.md` files onto the app icon or window.
- Recent files in the File menu.
- CLI argument support: `open -a "On Your Marks" file.md`.
- Registers as handler for `.md` UTType.

### Single-Document Behaviour

The app uses `DocumentGroup` which naturally supports multiple windows, but v1 does not actively prevent this. If the user opens a second file, macOS will open a second window — this is acceptable default behaviour. "Single-document" means we don't invest in multi-document UX (tabs, sidebar, project management) — not that we block multiple windows.

### Drag-and-Drop on Open Document

When a file is dragged onto a window that has an open document with unsaved changes:

- macOS `DocumentGroup` handles this natively — it opens a **new window** for the dropped file. The existing window and its unsaved changes are unaffected.

### New Document Flow

Cmd+N (File → New) creates an untitled in-memory document. The user edits freely. On first save (Cmd+S), a Save dialog prompts for the file location and name. The `.md` extension is appended by default.

### File Watching

```
File on disk changes
        │
        ▼
  FileWatcher fires (DispatchSource)
        │
        ▼
  Compute SHA-256 hash of new file content
  Compare to last-known hash ──Match──▶ Ignore (self-triggered or no-op)
        │
        No match (genuine external change)
        ▼
  Is the document dirty (unsaved edits)?
        │                    │
        No                  Yes
        ▼                    ▼
  Silent reload         Show dialog:
  (preserve scroll      "File changed on disk.
   & cursor position)    Reload / Keep Mine"
```

- **FileWatcher debounce:** The FileWatcher debounces events at 150ms before triggering a reload, to coalesce rapid successive writes (e.g., Claude Code saving multiple times in quick succession).
- **Self-change detection:** On save and on load, compute and store a SHA-256 hash of the file content. When the FileWatcher fires (after debounce), hash the new file content and compare. If hashes match, the change is either self-triggered or a no-op — ignore it. This avoids timestamp-resolution issues.
- **Conflict handling (v1):** When the document is dirty and an external change arrives, show a simple two-option dialog: **Reload** (discard local edits, load disk version) or **Keep Mine** (ignore the external change, keep editing). When "Keep Mine" is chosen, update the last-known hash to reflect the current disk content, so subsequent no-op FileWatcher events are correctly ignored. A 3-way merge is deferred to v2.
- **Preview mode** always auto-reloads silently (read-only, no conflict possible).

### Error Handling — File Operations

- **File deleted while open:** The FileWatcher detects deletion. Show an alert: "The file has been deleted. Save a copy or close." The document remains in memory with its content intact, marked as untitled.
- **File becomes unreadable (permissions):** On reload failure, show an alert: "Unable to read file. Check permissions." The last-loaded content remains in memory.
- **Save failure:** Surface the system error in a standard macOS alert sheet. Do not discard the in-memory content.

---

## 5. Markdown Pipeline

### Parser

Apple's [swift-markdown](https://github.com/apple/swift-markdown) — pure Swift, supports both CommonMark and GFM extensions natively. One library, two configurations toggled by the GFM switch.

### Rendering Pipeline

1. **Parse:** `swift-markdown` parses the Markdown source into an AST.
2. **Visit:** Custom `HTMLVisitor` walks the AST and emits HTML:
   - Wraps code blocks with language class for highlight.js.
   - Adds copy button markup to fenced code blocks.
   - Generates semantic HTML (`<h1>`, `<ul>`, `<table>`, etc.).
3. **Template:** Injects rendered HTML into a shell HTML page containing:
   - A single CSS file using `@media (prefers-color-scheme: dark)` for light/dark mode. System fonts (SF Pro for body, SF Mono for code), system-appropriate spacing.
   - Bundled highlight.js for syntax highlighting.
   - Copy-button JS behaviour.
4. **Display:** `WKWebView.loadHTMLString(_:baseURL:)` renders the final page. The `baseURL` is set to the directory containing the `.md` file, so relative image paths (`![](./img/screenshot.png)`) and sibling file links resolve correctly.

### Performance

- Re-render on edit debounced at ~200ms.
- v1 uses full `loadHTMLString` reload on each render. The WKWebView restores scroll position via a JS callback that sets `window.scrollTo()` after load, using the stored scroll percentage. Incremental DOM diffing is a v2 optimisation if scroll-position jank proves to be a problem in practice.

### Syntax Highlighting (Preview)

- highlight.js bundled in app resources (not CDN).
- Ships with the following languages: Swift, Python, JavaScript, TypeScript, Go, Rust, Ruby, Bash, JSON, YAML, HTML, CSS, SQL, Markdown (14 languages).
- Theme adapts to light/dark mode via CSS variables.

### Copy Button

- Each fenced code block gets a "Copy" button in the top-right corner.
- Copies raw code (no highlighting markup) via `navigator.clipboard.writeText()`.
- Brief "Copied!" confirmation animation.

### GFM Toggle

- Accessible via View menu → Toggle GFM (Cmd+Shift+G).
- Also available as a checkbox in the toolbar.
- Switches the parser configuration and re-renders.
- Preference persisted via `UserDefaults`.

### Error Handling — Parsing

- `swift-markdown` is lenient by design — malformed Markdown is rendered as-is rather than causing a parse error. No special error handling needed for the parser.
- If `WKWebView` fails to load (extremely unlikely with local HTML), the preview pane shows a centered error message: "Unable to render preview."

---

## 6. Editor Features

### STTextView Configuration

The editor integrates syntax highlighting via STTextView's delegate/content-storage APIs. A custom `MarkdownHighlighter` applies token-based highlighting using regex patterns on the attributed string content. The exact integration mechanism (delegate method vs. `NSTextContentStorage` subclass) should be determined at implementation time based on the pinned STTextView version's API.

| Feature | Implementation |
|---------|---------------|
| Line numbers | Built into STTextView — enable the gutter |
| Syntax highlighting | `MarkdownHighlighter` conforming to STTextView's `STTextViewHighlighter` protocol |
| Find/Replace | Standard macOS Find Bar (Cmd+F / Cmd+Opt+F) |
| Undo/Redo | Native `UndoManager` integration |
| Auto-indent | On Return after a list item (`- ` or `1. `), auto-insert the next list prefix |
| Tab handling | Tab inserts 4 spaces (configurable). Shift+Tab dedents. |

### Fonts

- **Editor font:** SF Mono, 13pt default. Font size adjustable via Cmd+Plus / Cmd+Minus (standard macOS zoom).
- **Preview body font:** SF Pro, 16px default.
- **Preview heading sizes:** H1 2em, H2 1.5em, H3 1.25em, H4 1em bold — standard typographic scale.
- **Preview code font:** SF Mono, 14px.

### Markdown Keyboard Shortcuts

| Shortcut | Action | No-selection behaviour |
|----------|--------|----------------------|
| Cmd+B | Wrap selection in `**bold**` | Insert `****` with cursor between |
| Cmd+I | Wrap selection in `*italic*` | Insert `**` with cursor between |
| Cmd+K | Insert link `[selection](url)` with `url` selected | Insert `[](url)` with cursor inside `[]` |
| Cmd+Shift+K | Insert image `![alt](url)` | Insert `![](url)` with cursor inside `[]` |
| Cmd+E | Wrap selection in `` `code` `` | Insert ` `` ` with cursor between |
| Cmd+Shift+E | Insert fenced code block | Insert block with cursor on content line |
| Cmd+Shift+L | Insert `---` horizontal rule | — |
| Cmd+] / Cmd+[ | Increase/decrease heading level | Operates on current line |

**Shortcut conflict notes:**
- **Cmd+Shift+L** for horizontal rule (not Cmd+L) to avoid conflicting with the standard macOS convention of Cmd+L for address bar / "Go to Line" in editors.
- **Cmd+E** overrides the standard macOS "Use Selection for Find" — this is intentional; inline code wrapping is more valuable in a Markdown editor. "Use Selection for Find" remains accessible via the Edit → Find submenu.
- **Cmd+] / Cmd+[** are used for heading levels, which differs from indent/outdent in some editors — intentional since Tab/Shift+Tab handle indentation in this app.
- **Heading submenu** (H1–H6) items are accessible via the Format → Heading submenu by mouse/menu only. The keyboard-driven alternative is Cmd+] / Cmd+[ to step through levels.

### Syntax Highlighting Colours

All colours use `NSColor` semantic colours, adapting to light/dark mode and the system accent colour:

- **Headings:** bold + brighter foreground
- **Bold markers:** dimmed delimiters, content rendered bold
- **Italic markers:** dimmed delimiters, content rendered italic
- **Code:** monospace with subtle background tint
- **Links:** link text in accent/blue, URL dimmed
- **Blockquotes:** accent bar colour
- **List markers:** accent colour

### Swappability

The editor view is behind a `MarkdownEditing` protocol that defines the interface (set/get text content, cursor position, scroll offset, apply highlighting). The concrete `STTextViewEditor` conforms to this protocol. If Apple ships improved TextKit 2 / NSTextView at WWDC26, a new `NativeTextViewEditor` conformance replaces the implementation without touching any other component.

---

## 7. Keyboard Shortcuts & Menu Bar

### Standard macOS Shortcuts (framework-provided)

Cmd+O (Open), Cmd+S (Save), Cmd+Shift+S (Save As), Cmd+Z/Cmd+Shift+Z (Undo/Redo), Cmd+F (Find), Cmd+Opt+F (Find & Replace), Cmd+W (Close), Cmd+Q (Quit), Cmd+C/V/X/A (Copy/Paste/Cut/Select All), Cmd+N (New), Cmd+Plus/Cmd+Minus (Zoom).

### App-Specific Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+1 | Preview mode |
| Cmd+2 | Editor mode |
| Cmd+\\ | Toggle split view |
| Cmd+Shift+G | Toggle GFM mode |

### Menu Bar Structure

```
On Your Marks
├── File:    New, Open, Open Recent ▶, Save, Save As, Close
├── Edit:    Undo, Redo, Cut, Copy, Paste, Select All, Find ▶
├── View:    Preview (⌘1), Editor (⌘2), Toggle Split (⌘\),
│            Toggle GFM (⌘⇧G)
├── Format:  Bold (⌘B), Italic (⌘I), Code (⌘E), Link (⌘K),
│            Heading ▶ (H1–H6), Horizontal Rule (⌘⇧L)
├── Window:  standard macOS window menu
└── Help:    standard
```

---

## 8. Dependencies

| Package | Version | Purpose | Notes |
|---------|---------|---------|-------|
| [apple/swift-markdown](https://github.com/apple/swift-markdown) | ≥ 0.4.0 | Markdown parsing (CommonMark + GFM) | Apple-maintained, pure Swift. Pin to latest stable. |
| [krzyzanowskim/STTextView](https://github.com/krzyzanowskim/STTextView) | ≥ 0.9.0 | Text editor (TextKit 2) | Use latest stable. Check changelog for breaking changes on update. |
| highlight.js (bundled JS) | 11.x | Code syntax highlighting in preview | Bundled in app resources. Custom build with 14 languages only. |

---

## 9. Project Structure

```
On Your Marks/
├── Package.swift (or .xcodeproj)
├── Sources/
│   ├── App/
│   │   ├── OnYourMarksApp.swift          # @main, DocumentGroup setup
│   │   └── ContentView.swift             # Mode switching, split view layout
│   ├── Document/
│   │   ├── MarkdownDocument.swift        # ReferenceFileDocument, source of truth
│   │   └── FileWatcher.swift             # DispatchSource file monitoring + SHA-256
│   ├── Editor/
│   │   ├── MarkdownEditing.swift         # Protocol for editor abstraction
│   │   ├── STTextViewEditor.swift        # NSViewRepresentable wrapping STTextView
│   │   ├── MarkdownHighlighter.swift     # STTextViewHighlighter conformance
│   │   └── EditorKeyCommands.swift       # Cmd+B, Cmd+K, etc.
│   ├── Preview/
│   │   ├── MarkdownPreviewView.swift     # NSViewRepresentable wrapping WKWebView
│   │   ├── HTMLRenderer.swift            # AST → HTML visitor
│   │   └── PreviewBridge.swift           # JS ↔ Swift communication
│   ├── Pipeline/
│   │   └── MarkdownParser.swift          # Parser config (CommonMark vs GFM)
│   └── Resources/
│       ├── preview.html                  # HTML template shell
│       ├── preview.css                   # Styles with @media prefers-color-scheme
│       ├── highlight.min.js              # Bundled highlight.js (custom build)
│       └── highlight-theme.css           # Code block theme (light/dark via CSS vars)
├── Tests/
│   ├── MarkdownParserTests.swift
│   ├── HTMLRendererTests.swift
│   ├── FileWatcherTests.swift
│   └── DocumentTests.swift
└── Info.plist                            # UTType registration for .md
```

---

## 10. Non-Functional Requirements

- **Lightweight, fast launch** — minimal dependencies, no heavy frameworks.
- **Native macOS look and feel** — standard menu bar, keyboard shortcuts, dark mode support, SF fonts.
- **macOS 26+** target.
- **Performance target** — files up to 10,000 lines should parse and render within the 200ms debounce window. Larger files are supported but may have perceptible render lag.
- **Minimum window size** — 800x500 points, to ensure split view remains usable.
- **Accessibility** — VoiceOver support via standard SwiftUI/AppKit accessibility APIs. Both STTextView and WKWebView provide baseline accessibility. Custom accessibility labels added to toolbar controls (segmented control, split toggle, GFM checkbox).

---

## 11. Future Considerations (v2+)

- WYSIWYG editor mode
- Export to PDF/HTML
- Multi-document tabs
- Custom CSS themes for preview
- Swap STTextView for native NSTextView if Apple improves TextKit 2 at WWDC26
- 3-way merge for file conflict resolution (instead of Reload / Keep Mine dialog)
- Incremental DOM updates for preview performance on large files
- Heading-anchor synchronised scrolling between editor and preview
