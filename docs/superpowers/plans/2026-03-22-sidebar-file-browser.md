# Sidebar File Browser — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a project-aware sidebar file browser with folder tree, file management (create/rename/delete), and auto-refresh.

**Architecture:** New `FileTreeModel` (ObservableObject) scans a root folder, builds a tree of `FileNode` structs, and watches for filesystem changes. `SidebarView` renders the tree with context menus. ContentView wraps the existing content in an `HSplitView` with the sidebar on the left.

**Tech Stack:** SwiftUI (List, DisclosureGroup), FileManager, DispatchSource, security-scoped bookmarks

**Spec:** `docs/superpowers/specs/2026-03-22-sidebar-file-browser-design.md`

---

## File Map

| File | Responsibility |
|------|---------------|
| `Sources/Sidebar/FileNode.swift` | Data model for tree nodes (file or folder) |
| `Sources/Sidebar/FileTreeModel.swift` | Scans folder, builds tree, watches filesystem, file operations |
| `Sources/Sidebar/SidebarView.swift` | SwiftUI tree view with context menus and inline rename |
| `Sources/App/ContentView.swift` | Add sidebar toggle + HSplitView wrapping |
| `Sources/App/OnYourMarksApp.swift` | Add Open Folder + Toggle Sidebar menu items |
| `Sources/App/Notifications.swift` | Add new notification names |
| `Tests/FileTreeModelTests.swift` | Tests for scanning, filtering, file operations |

---

## Task 1: FileNode Data Model

**Files:**
- Create: `Sources/Sidebar/FileNode.swift`

- [ ] **Step 1: Create FileNode**

```swift
// Sources/Sidebar/FileNode.swift
import Foundation

struct FileNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isFolder: Bool
    var children: [FileNode]

    var isMarkdownFile: Bool {
        !isFolder && ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    init(url: URL, isFolder: Bool, children: [FileNode] = []) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.isFolder = isFolder
        self.children = children
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`

- [ ] **Step 3: Commit**

```
git add Sources/Sidebar/FileNode.swift
git commit -m "feat: add FileNode data model for sidebar tree"
```

---

## Task 2: FileTreeModel

**Files:**
- Create: `Sources/Sidebar/FileTreeModel.swift`
- Create: `Tests/FileTreeModelTests.swift`

- [ ] **Step 1: Write tests**

```swift
// Tests/FileTreeModelTests.swift
import Testing
import Foundation
@testable import OnYourMarks

@Suite("FileTreeModel")
struct FileTreeModelTests {

    private func createTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("onyourmarks-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Scans folder and finds md files")
    func scansFolderForMdFiles() throws {
        let dir = try createTempDir()
        try "# Test".write(to: dir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try "hello".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "# Doc".write(to: dir.appendingPathComponent("doc.markdown"), atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        model.scan(rootURL: dir)

        // Should have 2 md files, no txt
        let fileNames = model.rootNodes.map(\.name).sorted()
        #expect(fileNames == ["doc.markdown", "readme.md"])

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Includes folders containing md files")
    func includesFoldersWithMdFiles() throws {
        let dir = try createTempDir()
        let subDir = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "# Hello".write(to: subDir.appendingPathComponent("guide.md"), atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        model.scan(rootURL: dir)

        #expect(model.rootNodes.count == 1) // "docs" folder
        #expect(model.rootNodes.first?.isFolder == true)
        #expect(model.rootNodes.first?.children.count == 1)
        #expect(model.rootNodes.first?.children.first?.name == "guide.md")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Excludes folders with no md files")
    func excludesEmptyFolders() throws {
        let dir = try createTempDir()
        let emptyDir = dir.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        try "not md".write(to: emptyDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        model.scan(rootURL: dir)

        #expect(model.rootNodes.isEmpty)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Sorts folders before files, alphabetically")
    func sortsFoldersBeforeFiles() throws {
        let dir = try createTempDir()
        try "# Z".write(to: dir.appendingPathComponent("zebra.md"), atomically: true, encoding: .utf8)
        try "# A".write(to: dir.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)
        let subDir = dir.appendingPathComponent("beta")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "# B".write(to: subDir.appendingPathComponent("inner.md"), atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        model.scan(rootURL: dir)

        let names = model.rootNodes.map(\.name)
        #expect(names == ["beta", "alpha.md", "zebra.md"])

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Creates new file in folder")
    func createsNewFile() throws {
        let dir = try createTempDir()

        let model = FileTreeModel()
        model.scan(rootURL: dir)

        let newURL = model.createFile(in: dir)
        #expect(newURL != nil)
        #expect(FileManager.default.fileExists(atPath: newURL!.path))
        #expect(newURL!.pathExtension == "md")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Deletes file to trash")
    func deletesFile() throws {
        let dir = try createTempDir()
        let file = dir.appendingPathComponent("delete-me.md")
        try "# Delete".write(to: file, atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        let result = model.deleteFile(at: file)
        #expect(result)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Renames file")
    func renamesFile() throws {
        let dir = try createTempDir()
        let file = dir.appendingPathComponent("old-name.md")
        try "# Rename".write(to: file, atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        let newURL = model.renameFile(at: file, to: "new-name.md")
        #expect(newURL != nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: newURL!.path))

        try? FileManager.default.removeItem(at: dir)
    }
}
```

- [ ] **Step 2: Run tests to see them fail**

- [ ] **Step 3: Implement FileTreeModel**

```swift
// Sources/Sidebar/FileTreeModel.swift
import Foundation
import Combine

final class FileTreeModel: ObservableObject {
    @Published var rootNodes: [FileNode] = []
    @Published var rootURL: URL?

    private var dirWatchers: [DispatchSourceFileSystemObject] = []

    func scan(rootURL: URL) {
        self.rootURL = rootURL
        rootNodes = buildTree(at: rootURL)
        startWatching(rootURL)
    }

    func refresh() {
        guard let url = rootURL else { return }
        rootNodes = buildTree(at: url)
    }

    // MARK: - Tree Building

    private func buildTree(at url: URL) -> [FileNode] {
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
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDir {
                let children = buildTree(at: itemURL)
                // Only include folders that contain md files (directly or nested)
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

        // Sort: folders first (alphabetically), then files (alphabetically)
        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return folders + files
    }

    // MARK: - File Operations

    func createFile(in folderURL: URL) -> URL? {
        let fm = FileManager.default
        var name = "Untitled.md"
        var counter = 2
        var targetURL = folderURL.appendingPathComponent(name)

        while fm.fileExists(atPath: targetURL.path) {
            name = "Untitled \(counter).md"
            targetURL = folderURL.appendingPathComponent(name)
            counter += 1
        }

        do {
            try "".write(to: targetURL, atomically: true, encoding: .utf8)
            refresh()
            return targetURL
        } catch {
            return nil
        }
    }

    func createFolder(in parentURL: URL) -> URL? {
        let fm = FileManager.default
        var name = "New Folder"
        var counter = 2
        var targetURL = parentURL.appendingPathComponent(name)

        while fm.fileExists(atPath: targetURL.path) {
            name = "New Folder \(counter)"
            targetURL = parentURL.appendingPathComponent(name)
            counter += 1
        }

        do {
            try fm.createDirectory(at: targetURL, withIntermediateDirectories: false)
            refresh()
            return targetURL
        } catch {
            return nil
        }
    }

    func deleteFile(at url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            refresh()
            return true
        } catch {
            return false
        }
    }

    func renameFile(at url: URL, to newName: String) -> URL? {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            refresh()
            return newURL
        } catch {
            return nil
        }
    }

    // MARK: - Directory Watching

    private func startWatching(_ url: URL) {
        stopWatching()
        watchDirectory(url)
    }

    private func watchDirectory(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.refresh()
        }

        source.setCancelHandler {
            close(fd)
        }

        dirWatchers.append(source)
        source.resume()
    }

    func stopWatching() {
        dirWatchers.forEach { $0.cancel() }
        dirWatchers.removeAll()
    }

    deinit {
        stopWatching()
    }
}
```

- [ ] **Step 4: Run tests to see them pass**
- [ ] **Step 5: Commit**

```
git add Sources/Sidebar/FileTreeModel.swift Tests/FileTreeModelTests.swift
git commit -m "feat: add FileTreeModel with folder scanning and file operations"
```

---

## Task 3: SidebarView

**Files:**
- Create: `Sources/Sidebar/SidebarView.swift`

- [ ] **Step 1: Implement SidebarView**

```swift
// Sources/Sidebar/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    @ObservedObject var treeModel: FileTreeModel
    @Binding var selectedFileURL: URL?
    @State private var renamingURL: URL?
    @State private var renameText: String = ""
    @State private var showDeleteConfirm = false
    @State private var deleteTargetURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            if treeModel.rootNodes.isEmpty {
                emptyState
            } else {
                List(selection: $selectedFileURL) {
                    ForEach(treeModel.rootNodes) { node in
                        nodeView(for: node)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 200)
        .alert("Delete File", isPresented: $showDeleteConfirm) {
            Button("Move to Trash", role: .destructive) {
                if let url = deleteTargetURL {
                    if selectedFileURL == url { selectedFileURL = nil }
                    _ = treeModel.deleteFile(at: url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let url = deleteTargetURL {
                Text("Move \"\(url.lastPathComponent)\" to the Trash?")
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No Markdown files")
                .foregroundStyle(.secondary)
                .font(.callout)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func nodeView(for node: FileNode) -> some View {
        if node.isFolder {
            DisclosureGroup {
                ForEach(node.children) { child in
                    nodeView(for: child)
                }
            } label: {
                folderLabel(for: node)
            }
            .contextMenu { folderContextMenu(for: node) }
        } else {
            fileLabel(for: node)
                .tag(node.url)
                .contextMenu { fileContextMenu(for: node) }
        }
    }

    @ViewBuilder
    private func folderLabel(for node: FileNode) -> some View {
        Label(node.name, systemImage: "folder")
    }

    @ViewBuilder
    private func fileLabel(for node: FileNode) -> some View {
        if renamingURL == node.url {
            TextField("Name", text: $renameText, onCommit: {
                commitRename(for: node)
            })
            .textFieldStyle(.plain)
            .onExitCommand { renamingURL = nil }
        } else {
            Label(node.name, systemImage: "doc.text")
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func fileContextMenu(for node: FileNode) -> some View {
        Button("Rename") {
            renamingURL = node.url
            renameText = node.name
        }
        Button("Delete") {
            deleteTargetURL = node.url
            showDeleteConfirm = true
        }
        Divider()
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
    }

    @ViewBuilder
    private func folderContextMenu(for node: FileNode) -> some View {
        Button("New File") {
            if let newURL = treeModel.createFile(in: node.url) {
                selectedFileURL = newURL
                // Start rename
                renamingURL = newURL
                renameText = newURL.lastPathComponent
            }
        }
        Button("New Folder") {
            _ = treeModel.createFolder(in: node.url)
        }
        Divider()
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
    }

    // MARK: - Rename

    private func commitRename(for node: FileNode) {
        guard !renameText.isEmpty, renameText != node.name else {
            renamingURL = nil
            return
        }
        // Ensure .md extension
        var newName = renameText
        let ext = (newName as NSString).pathExtension.lowercased()
        if ext != "md" && ext != "markdown" {
            newName += ".md"
        }
        if let newURL = treeModel.renameFile(at: node.url, to: newName) {
            if selectedFileURL == node.url {
                selectedFileURL = newURL
            }
        }
        renamingURL = nil
    }
}
```

- [ ] **Step 2: Verify build**
- [ ] **Step 3: Commit**

```
git add Sources/Sidebar/SidebarView.swift
git commit -m "feat: add SidebarView with tree, context menus, inline rename"
```

---

## Task 4: Integrate Sidebar into ContentView

**Files:**
- Modify: `Sources/App/ContentView.swift`
- Modify: `Sources/App/OnYourMarksApp.swift`
- Modify: `Sources/App/Notifications.swift`

- [ ] **Step 1: Add notification names**

Add to `Sources/App/Notifications.swift`:
```swift
static let openFolder = Notification.Name("openFolder")
static let toggleSidebar = Notification.Name("toggleSidebar")
```

- [ ] **Step 2: Add menu items to OnYourMarksApp.swift**

Add these in the `.commands` block, in the View section (after Toggle GFM):
```swift
Divider()

Button("Open Folder...") {
    NotificationCenter.default.post(name: .openFolder, object: nil)
}
.keyboardShortcut("o", modifiers: [.command, .shift])

Button("Toggle Sidebar") {
    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
}
.keyboardShortcut("s", modifiers: [.command, .shift])
```

- [ ] **Step 3: Add sidebar state and integration to ContentView**

Add new state variables:
```swift
@State private var showSidebar = UserDefaults.standard.bool(forKey: "showSidebar")
@StateObject private var fileTreeModel = FileTreeModel()
@State private var sidebarSelectedURL: URL?
```

Wrap `mainContent` in the body with an `HSplitView` that conditionally shows the sidebar:
```swift
var body: some View {
    HSplitView {
        if showSidebar {
            SidebarView(
                treeModel: fileTreeModel,
                selectedFileURL: $sidebarSelectedURL
            )
        }
        mainContent
    }
    // ... existing modifiers
}
```

Add `.onChange(of: sidebarSelectedURL)` to handle file selection — when a new file is selected:
1. Auto-save current document if dirty
2. Load the selected file into `document`
3. Restart the file watcher for the new file

Add `.onReceive` handlers for the new notifications:
- `openFolder`: show `NSOpenPanel` in directory mode, call `fileTreeModel.scan(rootURL:)`, save bookmark, set `showSidebar = true`
- `toggleSidebar`: toggle `showSidebar`, persist to UserDefaults

Add `.onAppear` logic to restore saved folder bookmark on launch.

- [ ] **Step 4: Implement bookmark save/restore**

```swift
private func saveBookmark(for url: URL) {
    guard let data = try? url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    ) else { return }
    UserDefaults.standard.set(data, forKey: "sidebarFolderBookmark")
}

private func restoreSavedFolder() {
    guard let data = UserDefaults.standard.data(forKey: "sidebarFolderBookmark") else { return }
    var isStale = false
    guard let url = try? URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    ) else {
        UserDefaults.standard.removeObject(forKey: "sidebarFolderBookmark")
        return
    }
    guard !isStale, url.startAccessingSecurityScopedResource() else {
        UserDefaults.standard.removeObject(forKey: "sidebarFolderBookmark")
        return
    }
    fileTreeModel.scan(rootURL: url)
    showSidebar = true
}

private func openFolderPanel() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose a folder to browse"

    if panel.runModal() == .OK, let url = panel.url {
        saveBookmark(for: url)
        fileTreeModel.scan(rootURL: url)
        showSidebar = true
        UserDefaults.standard.set(true, forKey: "showSidebar")
    }
}
```

- [ ] **Step 5: Handle file selection (loading a file from sidebar)**

```swift
.onChange(of: sidebarSelectedURL) { _, newURL in
    guard let url = newURL else { return }
    // Auto-save current if dirty
    if document.isDirty {
        try? document.data().write(to: fileURL ?? url, options: .atomic)
        document.didSave()
    }
    // Load new file
    if let content = try? String(contentsOf: url, encoding: .utf8) {
        document.text = content
        document.didLoad()
        // The fileURL from DocumentGroup won't update automatically,
        // but the FileWatcher should be restarted for the new file.
        fileWatcher?.stop()
        fileWatcher = FileWatcher(url: url, knownHash: document.contentHash) { [weak document] newContent in
            guard let document else { return }
            if newContent.isEmpty {
                showDeletedAlert = true
            } else if document.isDirty {
                pendingExternalContent = newContent
                showConflictAlert = true
            } else {
                document.text = newContent
                document.didLoad()
            }
        }
        fileWatcher?.start()
    }
}
```

**Important note for implementer:** The `DocumentGroup` manages `fileURL` and document lifecycle. Loading a different file via the sidebar is working _outside_ the normal DocumentGroup flow — we're manually replacing the document's text content and setting up our own file watcher. This is a pragmatic approach that works but means the title bar won't update to show the new filename. A future improvement could use `WindowGroup` with manual document management instead of `DocumentGroup`, but that's a larger refactor.

- [ ] **Step 6: Build and verify**

Run: `swift build`

- [ ] **Step 7: Commit**

```
git add Sources/App/ContentView.swift Sources/App/OnYourMarksApp.swift Sources/App/Notifications.swift
git commit -m "feat: integrate sidebar file browser with folder opening and file navigation"
```

---

## Task 5: Build and Manual Test

- [ ] **Step 1: Run full test suite**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 2: Rebuild app bundle**

Run: `./build-app.sh && open ".build/release/On Your Marks.app"`

- [ ] **Step 3: Manual test**

1. Launch app → no sidebar visible
2. File → Open Folder → select a folder with .md files → sidebar appears
3. Click an .md file in sidebar → content loads
4. Right-click a file → Rename, Delete, Reveal in Finder all work
5. Right-click a folder → New File, New Folder work
6. Toggle sidebar with Cmd+Shift+S
7. Quit and relaunch → sidebar restores with the same folder

- [ ] **Step 4: Commit any fixes**

---

## Summary

| Task | What it builds | Dependencies |
|------|---------------|-------------|
| 1 | FileNode data model | — |
| 2 | FileTreeModel (scanning + file ops) | Task 1 |
| 3 | SidebarView (UI) | Tasks 1, 2 |
| 4 | ContentView + App integration | Tasks 1, 2, 3 |
| 5 | Build + manual test | All above |
