// Sources/Document/MarkdownDocument.swift
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

final class MarkdownDocument: ReferenceFileDocument, ObservableObject {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { [.plainText] }

    @Published var text: String
    @Published var isDirty: Bool = false

    /// SHA-256 hash of the current text content
    var contentHash: String {
        Self.computeHash(text)
    }

    /// Hash of the last-saved/last-loaded content (for FileWatcher comparison)
    var lastKnownHash: String = ""

    /// File URL if document is backed by a file on disk
    var fileURL: URL?

    init(text: String = "") {
        self.text = text
        self.lastKnownHash = Self.computeHash(text)
    }

    /// Call this from the view layer when text changes via user editing
    func userDidEdit(_ newText: String) {
        text = newText
        isDirty = true
    }

    private static func computeHash(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - ReferenceFileDocument

    convenience init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.init(text: text)
        self.isDirty = false
    }

    required convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    func snapshot(contentType: UTType) throws -> Data {
        data()
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    // MARK: - Serialisation

    func data() -> Data {
        Data(text.utf8)
    }

    /// Call after saving to update the last-known hash and clear dirty state
    func didSave() {
        lastKnownHash = contentHash
        isDirty = false
    }

    /// Call after loading/reloading from disk
    func didLoad() {
        lastKnownHash = contentHash
        isDirty = false
    }
}
