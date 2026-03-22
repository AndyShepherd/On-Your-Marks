// Tests/FileWatcherTests.swift
import Testing
import Foundation
@testable import OnYourMarks

@Suite("FileWatcher")
struct FileWatcherTests {

    @Test("Detects external file change")
    func detectsChange() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try "initial".write(to: file, atomically: true, encoding: .utf8)

        var changeDetected = false
        let watcher = FileWatcher(url: file, knownHash: FileWatcher.sha256(of: file)!) { newContent in
            changeDetected = true
        }
        watcher.start()

        try "modified".write(to: file, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400))

        #expect(changeDetected)

        watcher.stop()
        try? FileManager.default.removeItem(at: file)
    }

    @Test("Ignores self-triggered change via matching hash")
    func ignoresSelfChange() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        let content = "unchanged"
        try content.write(to: file, atomically: true, encoding: .utf8)

        var changeDetected = false
        let hash = FileWatcher.sha256(of: file)!
        let watcher = FileWatcher(url: file, knownHash: hash) { _ in
            changeDetected = true
        }
        watcher.start()

        try content.write(to: file, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400))

        #expect(!changeDetected)

        watcher.stop()
        try? FileManager.default.removeItem(at: file)
    }

    @Test("SHA-256 hash is consistent for same content")
    func hashConsistency() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try "test content".write(to: file, atomically: true, encoding: .utf8)

        let hash1 = FileWatcher.sha256(of: file)
        let hash2 = FileWatcher.sha256(of: file)
        #expect(hash1 == hash2)
        #expect(hash1 != nil)

        try? FileManager.default.removeItem(at: file)
    }
}
