# Print Feature + Startup Bug Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Cmd+P print via native macOS dialog, fix Finder open hang, and make sidebar tree loading async.

**Architecture:** Three independent changes sharing no code. Print creates a temporary WKWebView and calls `printOperation()`. Finder fix adds `application(_:open:)` to AppDelegate. Tree loading moves `buildTree` to a background Task.

**Tech Stack:** Swift 6.2, SwiftUI, WebKit (WKWebView), AppKit (NSPrintOperation), CoreServices (FSEvents)

**Spec:** `docs/superpowers/specs/2026-04-06-print-and-bugfixes-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/App/Notifications.swift` | Modify | Add `.printDocument` and `.openFileFromFinder` |
| `Sources/Resources/preview.css` | Modify | Add `@media print` stylesheet block |
| `Sources/App/OnYourMarksApp.swift` | Modify | Add Print menu item + `application(_:open:)` on AppDelegate |
| `Sources/App/MainWindowView.swift` | Modify | Add `printDocument()` method + Finder open receiver |
| `Sources/Sidebar/FileTreeModel.swift` | Modify | Make `buildTree` async |
| `Sources/Sidebar/SidebarView.swift` | Modify | Show loading indicator while tree builds |

---

## Task 1: Add print stylesheet to preview.css

**Files:**
- Modify: `Sources/Resources/preview.css:124` (append after last line)

- [ ] **Step 1: Append the `@media print` block**

Add at the end of `Sources/Resources/preview.css`:

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

    body {
        max-width: none;
        padding: 0;
        background: white;
        color: #1d1d1f;
    }

    .copy-button { display: none !important; }

    pre code { border: 1px solid #d2d2d7; }

    pre, blockquote, table, img { break-inside: avoid; }

    h1, h2, h3 { break-after: avoid; }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Resources/preview.css
git commit -m "feat: add print-optimized stylesheet for @media print"
```

---

## Task 2: Add notification names

**Files:**
- Modify: `Sources/App/Notifications.swift:38` (before closing brace)

- [ ] **Step 1: Add `.printDocument` and `.openFileFromFinder` notification names**

Add these two lines before the closing `}` of the `Notification.Name` extension in `Sources/App/Notifications.swift`, after the `scrollToHeading` line:

```swift
    static let printDocument = Notification.Name("printDocument")
    static let openFileFromFinder = Notification.Name("openFileFromFinder")
```

- [ ] **Step 2: Commit**

```bash
git add Sources/App/Notifications.swift
git commit -m "feat: add printDocument and openFileFromFinder notification names"
```

---

## Task 3: Add Print menu item and Finder open handler to App

**Files:**
- Modify: `Sources/App/OnYourMarksApp.swift:56-67` (save item command group)
- Modify: `Sources/App/OnYourMarksApp.swift:210-244` (AppDelegate class)

- [ ] **Step 1: Add Print menu item**

In `Sources/App/OnYourMarksApp.swift`, in the `CommandGroup(replacing: .saveItem)` block, add a Print button and divider after the Save As button (after line 55) and before the existing Divider + Export PDF:

Replace:

```swift
                Divider()

                Button("Export as PDF...") {
```

With:

```swift
                Divider()

                Button("Print...") {
                    NotificationCenter.default.post(name: .printDocument, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Export as PDF...") {
```

- [ ] **Step 2: Add `application(_:open:)` to AppDelegate**

In `Sources/App/OnYourMarksApp.swift`, add this method to the `AppDelegate` class, after the `applicationShouldHandleReopen` method (after line 243):

```swift
    func application(_ application: NSApplication, open urls: [URL]) {
        let mdURLs = urls.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "md" || ext == "markdown"
        }
        guard !mdURLs.isEmpty else { return }

        Task { @MainActor in
            if !hasVisibleWindow() {
                Self.requestNewWindow()
                try? await Task.sleep(for: .milliseconds(500))
            }
            for url in mdURLs {
                NotificationCenter.default.post(
                    name: .openFileFromFinder,
                    object: url
                )
            }
        }
    }
```

Note: `hasVisibleWindow()` is a free function at file scope (line 192), but `application(_:open:)` is inside `AppDelegate` (an `NSObject` subclass, not `@MainActor` by default). The `Task { @MainActor in ... }` block gives us main-actor access to call the static methods and post notifications.

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
cd "/Users/andyshepherd/Downloads/Code/On Your Marks" && swift build 2>&1 | tail -5
```

Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/OnYourMarksApp.swift
git commit -m "feat: add Print menu item (Cmd+P) and Finder open handler"
```

---

## Task 4: Add printDocument and openFileFromFinder handlers to MainWindowView

**Files:**
- Modify: `Sources/App/MainWindowView.swift:543-572` (MainWindowNotificationReceivers)
- Modify: `Sources/App/MainWindowView.swift:617-652` (TabAndDocumentReceivers)
- Modify: `Sources/App/MainWindowView.swift:258-290` (near exportPDF method)

- [ ] **Step 1: Add `printDocument` to MainWindowNotificationReceivers**

In `Sources/App/MainWindowView.swift`, update the `MainWindowNotificationReceivers` struct to accept and pass through the new closures. Replace the struct (lines 543-572):

```swift
struct MainWindowNotificationReceivers: ViewModifier {
    @ObservedObject var tabManager: TabDocumentManager
    @Binding var showSidebar: Bool
    @Binding var useGFM: Bool
    let openFolder: (URL) -> Void
    let openFolderPanel: () -> Void
    let openDocumentPanel: () -> Void
    let saveActiveDocument: () -> Void
    let saveActiveDocumentAs: () -> Void
    let exportPDF: () -> Void
    let exportHTML: () -> Void
    let printDocument: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(SidebarAndViewModeReceivers(
                tabManager: tabManager,
                showSidebar: $showSidebar,
                useGFM: $useGFM,
                openFolder: openFolder,
                openFolderPanel: openFolderPanel
            ))
            .modifier(TabAndDocumentReceivers(
                tabManager: tabManager,
                openDocumentPanel: openDocumentPanel,
                saveActiveDocument: saveActiveDocument,
                saveActiveDocumentAs: saveActiveDocumentAs,
                exportPDF: exportPDF,
                exportHTML: exportHTML,
                printDocument: printDocument
            ))
    }
}
```

- [ ] **Step 2: Add receivers to TabAndDocumentReceivers**

Update the `TabAndDocumentReceivers` struct (lines 617-652) to add the `printDocument` closure and the `.openFileFromFinder` receiver:

```swift
struct TabAndDocumentReceivers: ViewModifier {
    @ObservedObject var tabManager: TabDocumentManager
    let openDocumentPanel: () -> Void
    let saveActiveDocument: () -> Void
    let saveActiveDocumentAs: () -> Void
    let exportPDF: () -> Void
    let exportHTML: () -> Void
    let printDocument: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                tabManager.closeActiveTabWithPrompt()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextTab)) { _ in
                tabManager.nextTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .previousTab)) { _ in
                tabManager.previousTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDocument)) { _ in
                openDocumentPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFileFromFinder)) { notification in
                if let url = notification.object as? URL {
                    tabManager.openFile(url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveDocument)) { _ in
                saveActiveDocument()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveDocumentAs)) { _ in
                saveActiveDocumentAs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
                exportPDF()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportHTML)) { _ in
                exportHTML()
            }
            .onReceive(NotificationCenter.default.publisher(for: .printDocument)) { _ in
                printDocument()
            }
    }
}
```

- [ ] **Step 3: Add `printDocument()` method to MainWindowView**

In `Sources/App/MainWindowView.swift`, add the `printDocument()` method after the `exportHTML()` method (after line 301):

```swift
    private func printDocument() {
        guard let tab = tabManager.activeTab else { return }
        let html = renderHTML(for: tab)

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = Bundle.module
        #else
        bundle = Bundle.main
        #endif
        let baseURL = tab.fileURL?.deletingLastPathComponent() ?? bundle.resourceURL
        webView.loadHTMLString(html, baseURL: baseURL)

        // Wait for load, then print
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
            printInfo.topMargin = 54
            printInfo.bottomMargin = 54
            printInfo.leftMargin = 54
            printInfo.rightMargin = 54

            let printOp = webView.printOperation(with: printInfo)
            printOp.showsPrintPanel = true
            printOp.showsProgressPanel = true

            if let window = NSApp.keyWindow {
                printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            } else {
                printOp.run()
            }
        }
    }
```

- [ ] **Step 4: Update the modifier call site to pass `printDocument`**

In `Sources/App/MainWindowView.swift`, update the `.modifier(MainWindowNotificationReceivers(...))` call (around line 34) to include the new closure:

Replace:

```swift
            .modifier(MainWindowNotificationReceivers(
                tabManager: tabManager,
                showSidebar: $showSidebar,
                useGFM: $useGFM,
                openFolder: openFolder,
                openFolderPanel: openFolderPanel,
                openDocumentPanel: openDocumentPanel,
                saveActiveDocument: saveActiveDocument,
                saveActiveDocumentAs: saveActiveDocumentAs,
                exportPDF: exportPDF,
                exportHTML: exportHTML
            ))
```

With:

```swift
            .modifier(MainWindowNotificationReceivers(
                tabManager: tabManager,
                showSidebar: $showSidebar,
                useGFM: $useGFM,
                openFolder: openFolder,
                openFolderPanel: openFolderPanel,
                openDocumentPanel: openDocumentPanel,
                saveActiveDocument: saveActiveDocument,
                saveActiveDocumentAs: saveActiveDocumentAs,
                exportPDF: exportPDF,
                exportHTML: exportHTML,
                printDocument: printDocument
            ))
```

- [ ] **Step 5: Build to verify compilation**

Run:
```bash
cd "/Users/andyshepherd/Downloads/Code/On Your Marks" && swift build 2>&1 | tail -5
```

Expected: Build succeeds with no errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/MainWindowView.swift
git commit -m "feat: add print and Finder-open notification handlers"
```

---

## Task 5: Make FileTreeModel build tree asynchronously

**Files:**
- Modify: `Sources/Sidebar/FileTreeModel.swift`

- [ ] **Step 1: Add `isLoading` property and make `buildTree` nonisolated**

Replace the entire `FileTreeModel` class in `Sources/Sidebar/FileTreeModel.swift` (lines 21-203):

```swift
@MainActor
final class FileTreeModel: ObservableObject {
    @Published var nodes: [FileNode] = []
    @Published private(set) var isLoading = false

    @Published private(set) var rootURL: URL?
    nonisolated(unsafe) private var eventStream: FSEventStreamRef?
    nonisolated(unsafe) private var retainedSelf: Unmanaged<FileTreeModel>?

    deinit {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        retainedSelf?.release()
    }

    // MARK: - Public API

    func scan(rootURL: URL) {
        self.rootURL = rootURL
        refreshAsync()
        startWatching()
    }

    func closeFolder() {
        stopWatching()
        rootURL = nil
        nodes = []
    }

    func refresh() {
        guard let rootURL else { return }
        nodes = Self.buildTree(at: rootURL)
    }

    func refreshAsync() {
        guard let rootURL else { return }
        isLoading = true
        let url = rootURL
        Task.detached {
            let result = Self.buildTree(at: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.nodes = result
                self.isLoading = false
            }
        }
    }

    @discardableResult
    func createFile(in folder: URL) -> URL? {
        var name = "Untitled.md"
        var url = folder.appendingPathComponent(name)
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            counter += 1
            name = "Untitled \(counter).md"
            url = folder.appendingPathComponent(name)
        }
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            refresh()
            return url
        } catch {
            return nil
        }
    }

    @discardableResult
    func createFolder(in parent: URL) -> URL? {
        var name = "New Folder"
        var url = parent.appendingPathComponent(name)
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            counter += 1
            name = "New Folder \(counter)"
            url = parent.appendingPathComponent(name)
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            refresh()
            return url
        } catch {
            return nil
        }
    }

    @discardableResult
    func deleteFile(at url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            refresh()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func renameFile(at url: URL, to newName: String) -> URL? {
        let ext = url.pathExtension
        var finalName = newName
        if !newName.lowercased().hasSuffix(".md") && !newName.lowercased().hasSuffix(".markdown") {
            finalName = newName + (ext.isEmpty ? ".md" : ".\(ext)")
        }
        let newURL = url.deletingLastPathComponent().appendingPathComponent(finalName)
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            refresh()
            return newURL
        } catch {
            return nil
        }
    }

    // MARK: - Tree Building

    private nonisolated static func buildTree(at url: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var folders: [FileNode] = []
        var files: [FileNode] = []

        for itemURL in contents {
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false

            if isDirectory {
                let children = buildTree(at: itemURL)
                if !children.isEmpty {
                    folders.append(FileNode(url: itemURL, isFolder: true, children: children))
                }
            } else {
                let ext = itemURL.pathExtension.lowercased()
                if ext == "md" || ext == "markdown" {
                    files.append(FileNode(url: itemURL, isFolder: false))
                }
            }
        }

        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return folders + files
    }

    // MARK: - Directory Watching

    private func startWatching() {
        stopWatching()
        guard let rootURL else { return }

        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained

        var context = FSEventStreamContext(
            version: 0,
            info: retained.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            [rootURL.path as CFString] as CFArray,
            FSEventsGetCurrentEventId(),
            2.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else { return }

        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    private func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        retainedSelf?.release()
        retainedSelf = nil
    }
}
```

Key changes:
- `buildTree` is now `private nonisolated static func` so it can run off the main actor
- New `refreshAsync()` calls `buildTree` in a `Task.detached` and publishes results back on `@MainActor`
- `scan()` calls `refreshAsync()` instead of `refresh()` (startup path)
- FSEvents callback still calls `refresh()` (synchronous) since those are small incremental updates while the app is already running
- `isLoading` property added for UI feedback

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
cd "/Users/andyshepherd/Downloads/Code/On Your Marks" && swift build 2>&1 | tail -5
```

Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Sidebar/FileTreeModel.swift
git commit -m "perf: async tree building to unblock startup UI"
```

---

## Task 6: Add loading indicator to SidebarView

**Files:**
- Modify: `Sources/Sidebar/SidebarView.swift:16-25`

- [ ] **Step 1: Update SidebarView body to show loading state**

In `Sources/Sidebar/SidebarView.swift`, replace the body's content (lines 16-25):

```swift
        VStack(spacing: 0) {
            if !treeModel.nodes.isEmpty || treeModel.isLoading {
                sidebarHeader
                Divider()
            }
            if treeModel.isLoading && treeModel.nodes.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if treeModel.nodes.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
```

This shows a spinner only on the first load when there are no nodes yet. Once nodes are populated, subsequent refreshes happen silently in the background.

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
cd "/Users/andyshepherd/Downloads/Code/On Your Marks" && swift build 2>&1 | tail -5
```

Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Sidebar/SidebarView.swift
git commit -m "feat: show loading indicator while sidebar tree builds"
```

---

## Task 7: Manual testing

- [ ] **Step 1: Build the app**

```bash
cd "/Users/andyshepherd/Downloads/Code/On Your Marks" && swift build 2>&1 | tail -5
```

- [ ] **Step 2: Test Print (Cmd+P)**

1. Open a markdown file in the app
2. Press Cmd+P
3. Verify: native macOS print dialog appears showing the rendered preview
4. Verify: output uses light theme (white background) even if app is in dark mode
5. Verify: no "Copy" buttons visible on code blocks in print preview
6. Cancel the print dialog

- [ ] **Step 3: Test Finder open**

1. Find a `.md` file in Finder
2. Right-click > Open With > On Your Marked
3. Verify: app opens the file without hanging
4. Verify: file content appears in a tab

- [ ] **Step 4: Test async tree loading**

1. Open a large folder (50+ markdown files spread across subdirectories)
2. Verify: the app window is responsive immediately
3. Verify: a loading spinner briefly appears in the sidebar
4. Verify: the tree populates once loading completes
