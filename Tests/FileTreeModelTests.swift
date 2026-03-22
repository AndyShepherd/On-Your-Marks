// Tests/FileTreeModelTests.swift
import Testing
import Foundation
@testable import OnYourMarks

@Suite("FileTreeModel")
@MainActor
struct FileTreeModelTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTreeModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Scans folder and finds md files")
    func scansFolderAndFindsMDFiles() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try "# Readme".write(to: root.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try "notes".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "# Doc".write(to: root.appendingPathComponent("doc.markdown"), atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        model.scan(rootURL: root)

        #expect(model.nodes.count == 2)
        let names = model.nodes.map(\.name).sorted()
        #expect(names == ["doc.markdown", "readme.md"])
    }

    @Test("Includes folders containing md files")
    func includesFoldersWithMDFiles() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let subdir = root.appendingPathComponent("guides")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "# Guide".write(to: subdir.appendingPathComponent("guide.md"), atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        model.scan(rootURL: root)

        #expect(model.nodes.count == 1)
        #expect(model.nodes[0].isFolder)
        #expect(model.nodes[0].name == "guides")
        #expect(model.nodes[0].children.count == 1)
        #expect(model.nodes[0].children[0].name == "guide.md")
    }

    @Test("Excludes folders with no md files")
    func excludesFoldersWithNoMDFiles() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let subdir = root.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "text".write(to: subdir.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        model.scan(rootURL: root)

        #expect(model.nodes.isEmpty)
    }

    @Test("Sorts folders before files, alphabetically")
    func sortsFoldersBeforeFiles() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try "# Zebra".write(to: root.appendingPathComponent("zebra.md"), atomically: true, encoding: .utf8)
        try "# Alpha".write(to: root.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)

        let beta = root.appendingPathComponent("beta")
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
        try "# Inner".write(to: beta.appendingPathComponent("inner.md"), atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        model.scan(rootURL: root)

        let names = model.nodes.map(\.name)
        #expect(names == ["beta", "alpha.md", "zebra.md"])
    }

    @Test("Creates new file")
    func createsNewFile() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let model = FileTreeModel()
        model.scan(rootURL: root)

        let newURL = model.createFile(in: root)
        #expect(newURL != nil)
        #expect(FileManager.default.fileExists(atPath: newURL!.path))
        #expect(newURL!.pathExtension == "md")
    }

    @Test("Deletes file")
    func deletesFile() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let file = root.appendingPathComponent("delete-me.md")
        try "# Delete".write(to: file, atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        model.scan(rootURL: root)

        let success = model.deleteFile(at: file)
        #expect(success)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Renames file")
    func renamesFile() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let file = root.appendingPathComponent("old-name.md")
        try "# Rename".write(to: file, atomically: true, encoding: .utf8)

        let model = FileTreeModel()
        model.scan(rootURL: root)

        let newURL = model.renameFile(at: file, to: "new-name")
        #expect(newURL != nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: newURL!.path))
        #expect(newURL!.lastPathComponent == "new-name.md")
    }
}
