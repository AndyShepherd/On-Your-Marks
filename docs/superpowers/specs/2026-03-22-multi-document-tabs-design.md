# Multi-Document Tabs — Design Specification
*Date:** 2026-03-22 **Feature:** Multi-document tabs with sidebar integration ───
## 1. Overview
Replace `DocumentGroup` with a custom `WindowGroup` + `TabDocumentManager` architecture. Each tab holds an independent `MarkdownDocument` with its own file URL, view mode, and scroll state. The sidebar is shared across all tabs. ───
## 2. Architecture
`WindowGroup ` ` └── MainWindowView` `      ├── Sidebar (shared, FileTreeModel)` `      └── VStack` `           ├── TabBarView (horizontal tab strip)` `           └── ContentView (active tab's document)` `                ├── Preview / Editor / Split` `                └── FileWatcher (per-tab)`
### Key Change
`DocumentGroup` → `WindowGroup`. We lose the automatic document lifecycle (Open/Save/Recent) and manage it ourselves. We gain full control over tabs, the sidebar, and the document state. ───
## 3. Data Model
### TabItem
`TabItem (Identifiable) ` ` - id: UUID` ` - document: MarkdownDocument` ` - fileURL: URL?` ` - viewMode: ViewMode (.preview default)` ` - isSplitView: Bool (false default)` ` - scrollPercentage: Double (0 default)` ` - cursorOffset: Int (0 default)` ` - fileWatcher: FileWatcher? (per-tab)`
### TabDocumentManager (ObservableObject)
Properties:
- `tabs: [TabItem]`
- `activeTabIndex: Int`
- `activeTab: TabItem` (computed) Methods:
- `newTab()` — creates empty untitled tab, makes it active
- `openFile(_ url: URL)` — if URL already open in a tab, switch to it. Otherwise create new tab with file content.
- `closeTab(at index: Int)` — auto-save if dirty. If last tab, create a new empty tab (never zero tabs).
- `closeActiveTab()`
- `switchToTab(at index: Int)`
- `nextTab()` / `previousTab()`
- `moveTab(from: Int, to: Int)` — for drag reorder
- `saveActiveTab()` — write to disk, update hash
- `saveActiveTabAs(_ url: URL)` — save as new file ───
## 4. Tab Bar
- Horizontal strip between toolbar and content
- Each tab button shows: filename (or “Untitled”), unsaved dot (if dirty), close button (x on hover)
- Active tab visually distinct (background highlight)
- “+” button at the right end to create new tab
- Tabs are draggable for reordering
- Double-click tab to rename (future — not v1)
- Middle section scrolls horizontally if too many tabs ───
## 5. Keyboard Shortcuts
Shortcut | Action Cmd+T | New tab Cmd+W | Close active tab Cmd+Shift+] | Next tab Cmd+Shift+[ | Previous tab Cmd+O | Open file (in new tab) Cmd+S | Save active tab Cmd+Shift+S | Save As ───
## 6. Sidebar Integration
- Sidebar is shared across all tabs (same FileTreeModel)
- Single-click file in sidebar:
- If file is already open in a tab → switch to that tab
- Otherwise → open in new tab
- Sidebar selection highlight follows the active tab’s file ───
## 7. File Operations (manual, replacing DocumentGroup)
### Open (Cmd+O)
Show NSOpenPanel for .md files. Open selected file in a new tab (or switch to existing tab if already open).
### Save (Cmd+S)
If active tab has a fileURL → write to disk, call didSave(). If untitled (no fileURL) → show NSSavePanel, then save.
### Save As (Cmd+Shift+S)
Show NSSavePanel. Save to new location. Update tab’s fileURL.
### Window Title
Show active tab’s filename in the window title bar. Show unsaved dot via `NSWindow.isDocumentEdited`. ───
## 8. Per-Tab State
Each tab independently maintains:
- Its own MarkdownDocument (text content, dirty state)
- Its own FileWatcher (watching its specific file)
- Its own view mode (preview/editor/split)
- Its own scroll position and cursor offset
- Its own GFM toggle state When switching tabs, the content area swaps to show the active tab’s state. No state bleeds between tabs. ───
## 9. Files to Create/Modify
### New
- `Sources/Document/TabItem.swift`
- `Sources/Document/TabDocumentManager.swift`
- `Sources/App/TabBarView.swift`
- `Sources/App/MainWindowView.swift` — new top-level view wrapping sidebar + tab bar + content
### Modify
- `Sources/App/OnYourMarksApp.swift` — switch to WindowGroup, move document management here
- `Sources/App/ContentView.swift` — simplify to render a single tab’s content (remove document/sidebar management)
- `Sources/App/Notifications.swift` — add tab-related notifications
### Remove/Deprecate
- The `DocumentGroup` usage is fully replaced ───
## 10. Error Handling
- Close tab with unsaved changes: auto-save to disk. If untitled, prompt to save or discard.
- File deleted while tab is open: show alert, keep content in memory, mark tab as untitled.
- Save failure: show error alert, don’t close tab.
- 
- 
