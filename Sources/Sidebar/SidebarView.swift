// Sources/Sidebar/SidebarView.swift
import SwiftUI
import AppKit

struct SidebarView: View {
    @ObservedObject var treeModel: FileTreeModel
    @Binding var selectedFileURL: URL?

    @State private var renamingURL: URL?
    @State private var renameText: String = ""
    @State private var deletingURL: URL?
    @State private var showDeleteAlert = false

    var body: some View {
        VStack {
            if treeModel.nodes.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .frame(minWidth: 200)
        .alert("Delete File?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let url = deletingURL {
                    treeModel.deleteFile(at: url)
                    if selectedFileURL == url {
                        selectedFileURL = nil
                    }
                }
                deletingURL = nil
            }
            Button("Cancel", role: .cancel) {
                deletingURL = nil
            }
        } message: {
            Text("Are you sure you want to delete \"\(deletingURL?.lastPathComponent ?? "this file")\"?")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Markdown files")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileList: some View {
        List(selection: $selectedFileURL) {
            ForEach(treeModel.nodes) { node in
                SidebarNodeView(
                    node: node,
                    treeModel: treeModel,
                    selectedFileURL: $selectedFileURL,
                    renamingURL: $renamingURL,
                    renameText: $renameText,
                    deletingURL: $deletingURL,
                    showDeleteAlert: $showDeleteAlert
                )
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Node View (broken out to avoid recursive opaque types)

private struct SidebarNodeView: View {
    let node: FileNode
    @ObservedObject var treeModel: FileTreeModel
    @Binding var selectedFileURL: URL?
    @Binding var renamingURL: URL?
    @Binding var renameText: String
    @Binding var deletingURL: URL?
    @Binding var showDeleteAlert: Bool

    var body: some View {
        if node.isFolder {
            folderContent
        } else {
            fileContent
        }
    }

    @ViewBuilder
    private var folderContent: some View {
        DisclosureGroup {
            ForEach(node.children) { child in
                SidebarNodeView(
                    node: child,
                    treeModel: treeModel,
                    selectedFileURL: $selectedFileURL,
                    renamingURL: $renamingURL,
                    renameText: $renameText,
                    deletingURL: $deletingURL,
                    showDeleteAlert: $showDeleteAlert
                )
            }
        } label: {
            Label(node.name, systemImage: "folder")
        }
        .contextMenu {
            Button("New File") {
                if let newURL = treeModel.createFile(in: node.url) {
                    selectedFileURL = newURL
                }
            }
            Button("New Folder") {
                treeModel.createFolder(in: node.url)
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
        }
    }

    @ViewBuilder
    private var fileContent: some View {
        if renamingURL == node.url {
            TextField("Name", text: $renameText)
                .textFieldStyle(.plain)
                .onSubmit {
                    commitRename()
                }
                .onExitCommand {
                    renamingURL = nil
                }
        } else {
            Label(node.name, systemImage: "doc.text")
                .tag(node.url)
                .contextMenu {
                    Button("Rename") {
                        renameText = node.url.deletingPathExtension().lastPathComponent
                        renamingURL = node.url
                    }
                    Button("Delete") {
                        deletingURL = node.url
                        showDeleteAlert = true
                    }
                    Divider()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([node.url])
                    }
                }
        }
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            renamingURL = nil
            return
        }
        if let newURL = treeModel.renameFile(at: node.url, to: trimmed) {
            if selectedFileURL == node.url {
                selectedFileURL = newURL
            }
        }
        renamingURL = nil
    }
}
