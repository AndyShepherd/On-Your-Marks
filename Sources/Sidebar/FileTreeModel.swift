// Sources/Sidebar/FileTreeModel.swift
import Foundation
import CoreServices

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
