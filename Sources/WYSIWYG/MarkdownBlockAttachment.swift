// Sources/WYSIWYG/MarkdownBlockAttachment.swift
import AppKit

protocol MarkdownBlockAttachment: AnyObject {
    func serializeToMarkdown() -> String
}
