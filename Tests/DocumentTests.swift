// Tests/DocumentTests.swift
import Testing
import Foundation
import UniformTypeIdentifiers
@testable import OnYourMarks

@Suite("MarkdownDocument")
struct DocumentTests {

    @Test("New document has empty content")
    func newDocumentEmpty() {
        let doc = MarkdownDocument()
        #expect(doc.text == "")
    }

    @Test("Document initialises from string data")
    func initFromData() throws {
        let content = "# Hello\n\nSome content."
        let data = Data(content.utf8)
        let doc = try MarkdownDocument(data: data)
        #expect(doc.text == content)
    }

    @Test("Document serialises to UTF-8 data")
    func serialisesToData() {
        let doc = MarkdownDocument(text: "# Test")
        let data = doc.data()
        let result = String(data: data, encoding: .utf8)
        #expect(result == "# Test")
    }

    @Test("Content hash changes when text changes")
    func contentHashChanges() {
        let doc = MarkdownDocument(text: "Hello")
        let hash1 = doc.contentHash
        doc.userDidEdit("World")
        let hash2 = doc.contentHash
        #expect(hash1 != hash2)
    }

    @Test("Content hash is stable for same content")
    func contentHashStable() {
        let doc1 = MarkdownDocument(text: "Same content")
        let doc2 = MarkdownDocument(text: "Same content")
        #expect(doc1.contentHash == doc2.contentHash)
    }

    @Test("Document tracks dirty state")
    func tracksModification() {
        let doc = MarkdownDocument(text: "Original")
        #expect(!doc.isDirty)
        doc.userDidEdit("Modified")
        #expect(doc.isDirty)
    }
}
