// Sources/Sidebar/FileNode.swift
import Foundation

struct FileNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isFolder: Bool
    var children: [FileNode]

    var isMarkdownFile: Bool {
        !isFolder && ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    init(url: URL, isFolder: Bool, children: [FileNode] = []) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.isFolder = isFolder
        self.children = children
    }
}
