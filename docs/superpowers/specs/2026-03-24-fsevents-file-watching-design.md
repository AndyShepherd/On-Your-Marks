# FSEvents-Based Recursive File Watching

**Date:** 2026-03-24
**Status:** Approved
**Scope:** `Sources/Sidebar/FileTreeModel.swift`, `Tests/FileTreeModelTests.swift`

## Problem

The sidebar file tree does not reliably detect new files added by external apps (VS Code, terminal, etc.). The current `DispatchSourceFileSystemObject` watcher only monitors the root directory's file descriptor — changes in subdirectories are invisible, and even root-level detection is unreliable for some external write patterns.

## Solution

Replace `DispatchSourceFileSystemObject` with Apple's `FSEventStream` API, which recursively monitors an entire directory tree with a single stream.

## Design

### What Changes

**Single file modified:** `FileTreeModel.swift`

**Removed:**
- `private var directorySource: DispatchSourceFileSystemObject?`
- `private var fileDescriptor: Int32`
- Current `startWatching()` / `stopWatching()` implementations

**Added:**
- `private var eventStream: FSEventStreamRef?`
- New `startWatching()` using `FSEventStreamCreate` pointed at `rootURL`
- New `stopWatching()` that calls `FSEventStreamStop`, `FSEventStreamInvalidate`, `FSEventStreamRelease`
- A C-compatible callback function that bridges to `self.refresh()` on MainActor

**Internal change to `closeFolder()`:** Currently references `directorySource` directly. Will be updated to call `stopWatching()` instead, keeping its public signature unchanged.

**Unchanged:** All public API signatures (`scan`, `closeFolder`, `refresh`, `createFile`, `createFolder`, `deleteFile`, `renameFile`), `SidebarView`, `MainWindowView`.

### FSEvents Configuration

- **Latency:** `2.0` seconds — coalesces rapid bursts into one refresh call
- **Flags:** `useCFTypes` (omit `fileEvents` — per-file granularity is unused since `refresh()` does a full rescan)
- **Scheduling:** `FSEventStreamSetDispatchQueue` with `DispatchQueue.main` — callback fires on main thread, simplifying the MainActor hop
- **Scope:** Recursive by default (FSEvents' natural behavior)

### Callback Bridge Pattern

`FSEventStreamCreate` requires a C function pointer, not a Swift closure. The callback must be a **free function or static method** — not a capturing closure. The bridge:

1. Pass `Unmanaged.passUnretained(self).toOpaque()` as context in `startWatching()`
2. In the callback (a free function), recover via `Unmanaged<FileTreeModel>.fromOpaque(info).takeUnretainedValue()`
3. Dispatch to MainActor: `Task { @MainActor in model.refresh() }`

`passUnretained` is safe because `FileTreeModel` owns the stream lifecycle — `stopWatching()` tears down the stream in `deinit` before the pointer goes stale.

### `deinit` and MainActor Isolation

Under strict concurrency, `deinit` on a `@MainActor` class cannot access actor-isolated properties. The `eventStream` property will be marked `nonisolated(unsafe)` since its lifecycle is tightly controlled by `startWatching()`/`stopWatching()`, allowing safe access in `deinit`.

### Cleanup

`deinit` calls the standard three-step FSEvents teardown:
1. `FSEventStreamStop(stream)`
2. `FSEventStreamInvalidate(stream)`
3. `FSEventStreamRelease(stream)`

## Testing

### New Test: `testWatcherDetectsNewFile`

1. Create a temp directory
2. Call `scan(rootURL:)` to start watching
3. Write a new `.md` file via `FileManager` (simulating external creation)
4. Poll with short sleeps (200ms intervals, ~3 second timeout) using Swift Testing's `#expect` — the existing test suite uses Swift Testing (`import Testing`, `@Suite`, `@Test`), not XCTest
5. Assert `nodes` contains the new file

### Existing Tests

No changes needed — the public API is identical. All `createFile`, `deleteFile`, `renameFile`, and tree-building tests remain valid.

## Constraints

- Target: Small notes folders (tens to low hundreds of files)
- Detection latency: Within a few seconds is acceptable
- Primary use case: Files created by external apps (terminal, text editors)
- App Sandbox: FSEvents works for paths granted via user-selected file access and security-scoped bookmarks (both are configured in the app's entitlements)
