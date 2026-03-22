# Sidebar File Browser — Design Specification

**Date:** 2026-03-22
**Feature:** Project-aware sidebar file browser with folder tree and file management
**Extends:** On Your Marks v1

---

## 1. Overview

Add an optional sidebar file browser that shows the folder structure of an opened directory, filtered to `.md`/`.markdown` files only. The sidebar enables project-style navigation without replacing the existing single-file workflow.

---

## 2. Layout

- Sidebar sits on the **left** side of the window, separated by a resizable divider from the existing content area (preview/editor/split).
- Toggle via **Cmd+Shift+S** or View menu → "Toggle Sidebar".
- Sidebar visibility persisted to `UserDefaults`.
- When hidden, the app behaves exactly as today — no sidebar, single-document mode.

---

## 3. Folder Opening

- **File → Open Folder** (Cmd+Shift+O) opens an `NSOpenPanel` configured for directory selection.
- Last-opened folder stored in `UserDefaults` as a **security-scoped bookmark** (required for sandboxed apps to retain file access across launches).
- On launch, if a saved bookmark exists and resolves to a valid directory, the sidebar opens automatically with that folder.
- If the bookmark is stale (folder moved/deleted), the sidebar stays hidden and the bookmark is cleared.

---

## 4. Tree Structure

- Shows the full folder hierarchy under the opened root folder.
- **Only shows `.md` and `.markdown` files** — all other file types are hidden.
- **Only shows folders that contain `.md` files** (directly or in descendant subfolders) — empty or irrelevant folders are hidden.
- Folders are expandable/collapsible. Expansion state is persisted per-folder (keyed by relative path from root).
- Files sorted alphabetically within each folder. Folders sorted alphabetically and listed before files.
- Currently open file is highlighted in the sidebar.
- **Single-click** opens a file in the main content area (replaces the current document).
- The tree auto-refreshes when the filesystem changes (new files, deletions, renames). Uses `DispatchSource` directory monitoring on the root folder and subfolders.

---

## 5. File Management — Right-Click Context Menu

### On files:

| Action | Behaviour |
|--------|-----------|
| **Rename** | Inline editable text field in the sidebar. Commits on Enter/focus-loss. Validates `.md` extension is preserved. |
| **Delete** | Moves to Trash via `FileManager.trashItem(at:resultingItemURL:)`. Confirmation alert before deletion. If the deleted file was the currently open document, the content area clears. |
| **Reveal in Finder** | `NSWorkspace.shared.activateFileViewerSelecting([url])` |

### On folders:

| Action | Behaviour |
|--------|-----------|
| **New File** | Creates `Untitled.md` in the target folder (appends number if name exists: `Untitled 2.md`). Opens inline rename immediately. Opens the new file in the content area. |
| **New Folder** | Creates `New Folder` directory (appends number if name exists). Opens inline rename. |
| **Reveal in Finder** | `NSWorkspace.shared.activateFileViewerSelecting([url])` |

---

## 6. Unsaved Changes on File Switch

When the user clicks a different file in the sidebar while the current document has unsaved changes:
- **Auto-save** the current file to disk, then switch to the new file.
- This matches the workflow of a viewer/editor used alongside external tools — explicit save dialogs would interrupt the flow.

---

## 7. Architecture

### New Files

| File | Responsibility |
|------|---------------|
| `Sources/Sidebar/FileNode.swift` | Data model for a node in the file tree — either a folder or a file. Properties: `name`, `url`, `isFolder`, `children`, `isExpanded`. Identifiable, Hashable. |
| `Sources/Sidebar/FileTreeModel.swift` | `ObservableObject` that scans a root folder, builds the tree of `FileNode`s, watches for filesystem changes via `DispatchSource`, and performs file management operations (create, rename, delete). |
| `Sources/Sidebar/SidebarView.swift` | SwiftUI view: `List` with recursive `DisclosureGroup` for folders. Context menus on files and folders. Inline rename via `TextField`. Highlights the currently selected file. |

### Modified Files

| File | Changes |
|------|---------|
| `Sources/App/ContentView.swift` | Wrap existing content in an `HSplitView` with the sidebar on the left. Add sidebar toggle state, folder URL state, and file-selection handling (load selected file into `MarkdownDocument`). |
| `Sources/App/OnYourMarksApp.swift` | Add "Open Folder" menu item (Cmd+Shift+O). Add "Toggle Sidebar" menu item (Cmd+Shift+S). |
| `Sources/App/Notifications.swift` | Add notification names for `openFolder`, `toggleSidebar`. |

### Data Flow

```
User clicks "Open Folder" → NSOpenPanel → folder URL
    │
    ▼
FileTreeModel.scan(rootURL)
    │
    ▼
Recursively enumerate folder → filter .md files → build FileNode tree
    │
    ▼
Start DispatchSource watchers on root + subfolders
    │
    ▼
SidebarView displays tree via List + DisclosureGroup
    │
    ▼
User clicks a file → ContentView loads it into MarkdownDocument
    (auto-saves current file if dirty)
    │
    ▼
FileWatcher starts on the new file (existing behaviour)
```

---

## 8. Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+O | Open Folder |
| Cmd+Shift+S | Toggle Sidebar |

---

## 9. Security-Scoped Bookmarks

Since the app runs in the sandbox, folder access must be preserved across launches via security-scoped bookmarks:

```
Open Folder → User grants access via NSOpenPanel
    │
    ▼
Create bookmark: url.bookmarkData(options: .withSecurityScope)
    │
    ▼
Store bookmark data in UserDefaults (key: "sidebarFolderBookmark")
    │
    ▼
On next launch: resolve bookmark → startAccessingSecurityScopedResource()
    │
    ▼
On app quit or folder change: stopAccessingSecurityScopedResource()
```

---

## 10. Error Handling

- **Folder becomes inaccessible:** If the root folder is moved/deleted while the sidebar is open, show an alert and close the sidebar.
- **File operations fail:** Surface the system error in a standard macOS alert. Don't crash or silently fail.
- **Bookmark resolution fails:** Clear the stored bookmark and don't show the sidebar on launch. No error shown — the user simply opens a new folder.
