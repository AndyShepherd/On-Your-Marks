# FSEvents File Watching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-directory DispatchSource watcher with FSEvents for recursive file change detection in the sidebar.

**Architecture:** Swap the `DispatchSourceFileSystemObject` + file descriptor in `FileTreeModel` with an `FSEventStreamRef` scheduled on the main dispatch queue. A free function callback bridges FSEvents' C API back to Swift's `@MainActor` context via `Unmanaged` pointer. All public API stays unchanged.

**Tech Stack:** Swift, CoreServices (FSEvents), Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-24-fsevents-file-watching-design.md`

---

### Task 1: Replace stored properties

**Files:**
- Modify: `Sources/Sidebar/FileTreeModel.swift:9-10`

- [ ] **Step 1: Replace the DispatchSource properties with FSEventStream property**

Replace lines 9-10:

```swift
private var directorySource: DispatchSourceFileSystemObject?
private var fileDescriptor: Int32 = -1
```

With:

```swift
nonisolated(unsafe) private var eventStream: FSEventStreamRef?
```

`nonisolated(unsafe)` is needed because `deinit` on a `@MainActor` class cannot access actor-isolated properties under strict concurrency. The lifecycle is tightly controlled so this is safe.

- [ ] **Step 2: Add `import CoreServices` at the top of the file**

Add after `import Foundation` (line 2):

```swift
import CoreServices
```

**Note:** Do NOT attempt a build after this task — `deinit` and `closeFolder()` still reference the removed properties. Task 2 fixes this.

---

### Task 2: Update `deinit` and `closeFolder()`

**Files:**
- Modify: `Sources/Sidebar/FileTreeModel.swift:12-16` (deinit)
- Modify: `Sources/Sidebar/FileTreeModel.swift:26-31` (closeFolder)

- [ ] **Step 1: Update `deinit`**

Replace lines 12-16:

```swift
deinit {
    directorySource?.cancel()
    directorySource = nil
    fileDescriptor = -1
}
```

With:

```swift
deinit {
    if let stream = eventStream {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
```

- [ ] **Step 2: Update `closeFolder()` to use `stopWatching()`**

Replace lines 26-31:

```swift
func closeFolder() {
    directorySource?.cancel()
    directorySource = nil
    rootURL = nil
    nodes = []
}
```

With:

```swift
func closeFolder() {
    stopWatching()
    rootURL = nil
    nodes = []
}
```

**Note:** Do NOT attempt a build after this task — `startWatching()`/`stopWatching()` still reference the removed properties. Task 4 fixes this.

---

### Task 3: Implement the FSEvents callback (free function)

**Files:**
- Modify: `Sources/Sidebar/FileTreeModel.swift` (add before the class, after imports)

- [ ] **Step 1: Add the free function callback above the class definition**

Insert after the `import` statements, before `@MainActor`:

```swift
private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo else { return }
    let model = Unmanaged<FileTreeModel>.fromOpaque(clientInfo).takeUnretainedValue()
    Task { @MainActor in
        model.refresh()
    }
}
```

- [ ] **Step 2: Verify the project builds**

Run: `xcodebuild build -scheme "On Your Marked" -destination "platform=macOS" -quiet`

Expected: Build succeeds. The callback is defined but not yet called.

---

### Task 4: Rewrite `startWatching()` and `stopWatching()`

**Files:**
- Modify: `Sources/Sidebar/FileTreeModel.swift:144-176`

- [ ] **Step 1: Replace `startWatching()` implementation**

Replace lines 144-170:

```swift
private func startWatching() {
    stopWatching()
    guard let rootURL else { return }

    let fd = open(rootURL.path, O_EVTONLY)
    guard fd >= 0 else { return }
    fileDescriptor = fd

    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: [.write, .delete, .rename, .link],
        queue: .main
    )

    source.setEventHandler { [weak self] in
        Task { @MainActor in
            self?.refresh()
        }
    }

    source.setCancelHandler { [fd] in
        close(fd)
    }

    directorySource = source
    source.resume()
}
```

With:

```swift
private func startWatching() {
    stopWatching()
    guard let rootURL else { return }

    var context = FSEventStreamContext(
        version: 0,
        info: Unmanaged.passUnretained(self).toOpaque(),
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
```

- [ ] **Step 2: Replace `stopWatching()` implementation**

Replace lines 172-176:

```swift
private func stopWatching() {
    directorySource?.cancel()
    directorySource = nil
    fileDescriptor = -1
}
```

With:

```swift
private func stopWatching() {
    guard let stream = eventStream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    eventStream = nil
}
```

- [ ] **Step 3: Verify the project builds**

Run: `xcodebuild build -scheme "On Your Marked" -destination "platform=macOS" -quiet`

Expected: Build succeeds with no errors or warnings.

- [ ] **Step 4: Run existing tests to confirm no regressions**

Run: `xcodebuild test -scheme "On Your Marked" -destination "platform=macOS" -quiet`

Expected: All 7 existing `FileTreeModelTests` pass.

- [ ] **Step 5: Commit**

Message: `feat: replace DispatchSource with FSEvents for recursive directory watching`

Stage: `Sources/Sidebar/FileTreeModel.swift`

---

### Task 5: Add watcher integration test

**Files:**
- Modify: `Tests/FileTreeModelTests.swift`

- [ ] **Step 1: Write the test**

Add at the end of the `FileTreeModelTests` struct (before the closing `}`):

```swift
@Test("Watcher detects externally added file")
func watcherDetectsExternallyAddedFile() async throws {
    let root = try makeTempDir()
    defer { cleanup(root) }

    let model = FileTreeModel()
    model.scan(rootURL: root)
    #expect(model.nodes.isEmpty)

    // Simulate an external app creating a file
    try "# External".write(
        to: root.appendingPathComponent("external.md"),
        atomically: true,
        encoding: .utf8
    )

    // Poll until FSEvents delivers the event (2s latency + margin)
    var detected = false
    for _ in 0..<20 {
        try await Task.sleep(for: .milliseconds(200))
        if model.nodes.contains(where: { $0.name == "external.md" }) {
            detected = true
            break
        }
    }

    #expect(detected, "Watcher should detect externally added .md file")
}
```

- [ ] **Step 2: Write the subfolder detection test**

Add after the previous test:

```swift
@Test("Watcher detects file added in subfolder")
func watcherDetectsFileInSubfolder() async throws {
    let root = try makeTempDir()
    defer { cleanup(root) }

    let model = FileTreeModel()
    model.scan(rootURL: root)
    #expect(model.nodes.isEmpty)

    // Simulate an external app creating a subfolder with a file
    let sub = root.appendingPathComponent("notes")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try "# Nested".write(
        to: sub.appendingPathComponent("nested.md"),
        atomically: true,
        encoding: .utf8
    )

    // Poll until FSEvents delivers the event (2s latency + margin)
    var detected = false
    for _ in 0..<20 {
        try await Task.sleep(for: .milliseconds(200))
        let folder = model.nodes.first(where: { $0.name == "notes" })
        if folder?.children.contains(where: { $0.name == "nested.md" }) == true {
            detected = true
            break
        }
    }

    #expect(detected, "Watcher should detect file added in a subfolder")
}
```

- [ ] **Step 3: Run the new tests**

Run: `xcodebuild test -scheme "On Your Marked" -destination "platform=macOS" -quiet`

Expected: All 9 tests pass (7 existing + 2 new).

- [ ] **Step 4: Commit**

Message: `test: add integration tests for FSEvents watcher detecting new files`

Stage: `Tests/FileTreeModelTests.swift`

---

### Task 6: Manual smoke test

- [ ] **Step 1: Build and run the app**

Run: `xcodebuild build -scheme "On Your Marked" -destination "platform=macOS" -quiet`

Then open the app from Xcode or the build products.

- [ ] **Step 2: Open a folder in the sidebar**

Use File > Open Folder and select a test directory with some `.md` files.

- [ ] **Step 3: From Terminal, create a new file in the root**

```bash
touch /path/to/your/folder/new-test-file.md
```

Verify it appears in the sidebar within ~2-3 seconds.

- [ ] **Step 4: From Terminal, create a new file in a subfolder**

```bash
mkdir -p /path/to/your/folder/subfolder
touch /path/to/your/folder/subfolder/nested-file.md
```

Verify the subfolder and file appear in the sidebar within ~2-3 seconds.

- [ ] **Step 5: From Terminal, delete a file**

```bash
rm /path/to/your/folder/new-test-file.md
```

Verify it disappears from the sidebar within ~2-3 seconds.
