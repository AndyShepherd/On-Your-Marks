# Print Feature + Startup Bug Fixes — Design Spec

**Date:** 2026-04-06
**Status:** Approved

---

## Overview

Three items in one batch:

1. **Print function** — Cmd+P to print the rendered markdown preview via the native macOS print dialog
2. **Finder open hang** — Fix app hanging when opening `.md` files via right-click > Open With in Finder
3. **Slow tree loading** — Make sidebar folder tree load asynchronously on startup

---

## 1. Print Function

### Trigger

- **Cmd+P** keyboard shortcut
- **File > Print...** menu item

### Behaviour

From any view mode (Preview, Rich Editor, Raw Editor), Cmd+P always prints the rendered HTML preview of the current document — not the raw text or WYSIWYG view.

No custom headers or footers. Clean output only.

### Architecture

1. User presses Cmd+P → posts `.printDocument` notification
2. `MainWindowView.printDocument()` renders the active tab's markdown to full HTML using the existing `renderHTML(for:)` method
3. A temporary off-screen `WKWebView` loads the HTML
4. Once loaded (`webView.navigationDelegate` callback), call `webView.printOperation(with:)` to get an `NSPrintOperation`
5. Run the print operation with `runModal(for:delegate:didRun:contextInfo:)` — shows the native macOS Print dialog
6. Temporary WebView is released after completion

### Print Stylesheet

Append an `@media print` block to `Sources/Resources/preview.css`:

```css
@media print {
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
    }

    @page { margin: 0.75in; }
    body { max-width: none; padding: 0; background: white; color: #1d1d1f; }
    .copy-button { display: none !important; }
    pre code { border: 1px solid #d2d2d7; }
    pre, blockquote, table, img { break-inside: avoid; }
    h1, h2, h3 { break-after: avoid; }
}
```

This also improves the existing Export PDF output automatically.

### Menu Placement

In the `CommandGroup(replacing: .saveItem)` block in `OnYourMarksApp.swift`, add "Print..." with Cmd+P after Save As and before Export PDF:

```
Save          ⌘S
Save As...    ⇧⌘S
---
Print...      ⌘P
---
Export as PDF...   ⇧⌘P
Export as HTML...
```

### Files Modified

- `Sources/Resources/preview.css` — append `@media print` block
- `Sources/App/Notifications.swift` — add `.printDocument`
- `Sources/App/OnYourMarksApp.swift` — add Print menu item
- `Sources/App/MainWindowView.swift` — add `printDocument()` method, wire into notification receivers

---

## 2. Finder Open Hang

### Problem

When a user right-clicks a `.md` file in Finder and opens it with this app, the app hangs. The `Info.plist` correctly declares `CFBundleDocumentTypes` for `net.daringfireball.markdown`, so Finder offers the app. But the app uses `WindowGroup` (not `DocumentGroup`) and the `AppDelegate` does not implement `application(_:open:)`. macOS sends the open-file Apple Event, it goes unhandled, and the system blocks waiting for a response.

### Fix

Add `application(_:open:)` to `AppDelegate` in `OnYourMarksApp.swift`. This method:

1. Ensures a window exists (using `requestNewWindow()` if needed)
2. Posts a notification (e.g., `.openFileFromFinder`) with the URLs
3. `MainWindowView` receives the notification and calls `tabManager.openFile(url)` for each URL

### Files Modified

- `Sources/App/OnYourMarksApp.swift` — add `application(_:open:)` to `AppDelegate`
- `Sources/App/Notifications.swift` — add `.openFileFromFinder`
- `Sources/App/MainWindowView.swift` — add notification receiver for `.openFileFromFinder`

---

## 3. Slow Tree Loading

### Problem

`restoreSavedFolder()` calls `fileTreeModel.scan(rootURL:)` which synchronously calls `buildTree(at:)` — a recursive `FileManager.contentsOfDirectory` traversal on the main thread. For large folder trees, this blocks the UI on startup.

### Fix

Make `buildTree` run in a background task:

1. Add a `@Published var isLoading: Bool = false` to `FileTreeModel`
2. In `scan(rootURL:)`, set `isLoading = true`, then dispatch `buildTree` to a `Task.detached`
3. When complete, publish the result back to `nodes` on `@MainActor` and set `isLoading = false`
4. `refresh()` (called from FSEvents callback) uses the same async pattern
5. Optionally show a subtle loading indicator in the sidebar while `isLoading` is true

### Files Modified

- `Sources/Sidebar/FileTreeModel.swift` — make `buildTree` async, add `isLoading` state
- `Sources/Sidebar/SidebarView.swift` — optionally show loading indicator

---

## Testing Notes

- **Print:** Verify Cmd+P shows system print dialog from all three view modes. Verify print output uses light theme and hides Copy buttons.
- **Finder open:** Build the app, right-click a `.md` file in Finder, choose "Open With > On Your Marked". Verify the file opens without hanging.
- **Tree loading:** Open a large folder (100+ files). Verify the app is responsive immediately and the tree populates after a brief moment.
