// Sources/Sidebar/FileTreeModel.swift
import Foundation

@MainActor
final class FileTreeModel: ObservableObject {
    @Published var nodes: [FileNode] = []

    private var rootURL: URL?
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    deinit {
        directorySource?.cancel()
        directorySource = nil
        fileDescriptor = -1
    }

    // MARK: - Public API

    func scan(rootURL: URL) {
        self.rootURL = rootURL
        refresh()
        startWatching()
    }

    func refresh() {
        guard let rootURL else { return }
        nodes = buildTree(at: rootURL)
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

    private func stopWatching() {
        directorySource?.cancel()
        directorySource = nil
        fileDescriptor = -1
    }
}
