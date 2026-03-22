// Sources/Pipeline/MarkdownParser.swift
import Foundation
import Markdown

struct MarkdownParser {
    var useGFM: Bool

    func parse(_ source: String) -> Document {
        return Document(parsing: source)
    }
}
