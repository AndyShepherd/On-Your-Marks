// Sources/App/ContentView.swift
import SwiftUI
import AppKit

enum ViewMode: Int, CaseIterable {
    case preview = 0
    case editor = 1
}

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    let fileURL: URL?
    @State private var viewMode: ViewMode = .preview
    @State private var isSplitView = false
    @State private var cursorOffset: Int = 0
    @State private var editorScrollOffset: Int = 0
    @State private var scrollPercentage: Double = 0
    @State private var useGFM = UserDefaults.standard.object(forKey: "useGFM") == nil ? true : UserDefaults.standard.bool(forKey: "useGFM")
    @State private var renderedHTML: String = ""
    @State private var renderTask: Task<Void, Never>?
    @State private var fileWatcher: FileWatcher?
    @State private var showConflictAlert = false
    @State private var showDeletedAlert = false
    @State private var pendingExternalContent: String = ""
    @State private var showSidebar = UserDefaults.standard.bool(forKey: "showSidebar")
    @StateObject private var fileTreeModel = FileTreeModel()
    @State private var sidebarSelectedURL: URL?

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let text = document.text
            let gfm = useGFM
            let html = await Task.detached {
                let parser = MarkdownParser(useGFM: gfm)
                let doc = parser.parse(text)
                var renderer = HTMLRenderer(useGFM: gfm)
                return renderer.render(doc)
            }.value
            guard !Task.isCancelled else { return }
            renderedHTML = html
        }
    }

    private var baseURL: URL? {
        fileURL?.deletingLastPathComponent()
    }

    var body: some View {
        HSplitView {
            if showSidebar {
                SidebarView(
                    treeModel: fileTreeModel,
                    selectedFileURL: $sidebarSelectedURL
                )
            }
            mainContent
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            viewMode = ViewMode(rawValue: UserDefaults.standard.integer(forKey: "viewMode")) ?? .preview
            isSplitView = UserDefaults.standard.bool(forKey: "isSplitView")
            scheduleRender()
            startFileWatcher()
            restoreSavedFolder()
        }
        .onDisappear {
            fileWatcher?.stop()
        }
        .onChange(of: document.text) { _, _ in scheduleRender() }
        .onChange(of: useGFM) { _, _ in scheduleRender() }
        .onChange(of: viewMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "viewMode")
        }
        .onChange(of: isSplitView) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "isSplitView")
        }
        .onChange(of: sidebarSelectedURL) { _, newURL in
            guard let url = newURL, !url.isFileURL || url != fileURL else { return }
            // Auto-save current if dirty
            if document.isDirty, let currentURL = fileURL {
                try? document.data().write(to: currentURL, options: .atomic)
                document.didSave()
            }
            // Load new file
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                document.text = content
                document.didLoad()
                scheduleRender()
                // Restart file watcher for new file
                fileWatcher?.stop()
                let doc = document
                fileWatcher = FileWatcher(url: url, knownHash: doc.contentHash) { [weak doc] newContent in
                    guard let document = doc else { return }
                    if newContent.isEmpty {
                        showDeletedAlert = true
                    } else if document.isDirty {
                        pendingExternalContent = newContent
                        showConflictAlert = true
                    } else {
                        document.text = newContent
                        document.didLoad()
                    }
                }
                fileWatcher?.start()
            }
        }
        .modifier(ViewModeReceivers(viewMode: $viewMode, isSplitView: $isSplitView, useGFM: $useGFM))
        .modifier(SidebarReceivers(showSidebar: $showSidebar, openFolderPanel: openFolderPanel))
        .modifier(FormatCommandReceivers(applyFormatCommand: applyFormatCommand))
        .alert("File Changed on Disk", isPresented: $showConflictAlert) {
            Button("Reload") {
                document.text = pendingExternalContent
                document.didLoad()
                fileWatcher?.updateKnownHash(document.contentHash)
            }
            Button("Keep Mine", role: .cancel) {
                if let url = document.fileURL, let hash = FileWatcher.sha256(of: url) {
                    fileWatcher?.updateKnownHash(hash)
                }
            }
        } message: {
            Text("The file has been modified by another application. Reload the external version or keep your changes?")
        }
        .alert("File Deleted", isPresented: $showDeletedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The file has been deleted from disk. Your content is still in memory.")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: Binding(
                    get: { isSplitView ? nil : viewMode },
                    set: { newValue in
                        if let mode = newValue {
                            viewMode = mode
                            isSplitView = false
                        }
                    }
                )) {
                    Text("Preview").tag(ViewMode?.some(.preview))
                    Text("Editor").tag(ViewMode?.some(.editor))
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityLabel("View mode")
            }

            ToolbarItem {
                Toggle(isOn: $isSplitView) {
                    Image(systemName: "rectangle.split.2x1")
                }
                .help("Toggle Split View")
                .accessibilityLabel("Toggle split view")
            }

            ToolbarItem {
                Toggle(isOn: $useGFM) {
                    Text("GFM")
                }
                .toggleStyle(.checkbox)
                .help("GitHub Flavored Markdown")
                .accessibilityLabel("Toggle GitHub Flavored Markdown")
                .onChange(of: useGFM) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "useGFM")
                }
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            Group {
                if isSplitView {
                    HSplitView {
                        editorPanel
                        previewPanel
                    }
                } else {
                    switch viewMode {
                    case .preview:
                        previewPanel
                    case .editor:
                        editorPanel
                    }
                }
            }
        }
    }

    private var previewPanel: some View {
        MarkdownPreviewView(
            htmlContent: renderedHTML,
            baseURL: baseURL,
            scrollPercentage: $scrollPercentage
        )
    }

    private var editorPanel: some View {
        STTextViewEditor(
            text: $document.text,
            cursorOffset: $cursorOffset,
            scrollOffset: $editorScrollOffset
        )
    }

    private func applyFormatCommand(_ command: (inout String, inout NSRange) -> Void) {
        // Only apply format commands when in editor or split mode
        guard viewMode == .editor || isSplitView else { return }
        var text = document.text
        var range = NSRange(location: cursorOffset, length: 0) // simplified — real impl should get actual selection
        command(&text, &range)
        document.userDidEdit(text)
        cursorOffset = range.location
    }

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse"

        if panel.runModal() == .OK, let url = panel.url {
            saveBookmark(for: url)
            fileTreeModel.scan(rootURL: url)
            showSidebar = true
            UserDefaults.standard.set(true, forKey: "showSidebar")
        }
    }

    private func saveBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: "sidebarFolderBookmark")
    }

    private func restoreSavedFolder() {
        guard let data = UserDefaults.standard.data(forKey: "sidebarFolderBookmark") else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            UserDefaults.standard.removeObject(forKey: "sidebarFolderBookmark")
            return
        }
        guard !isStale, url.startAccessingSecurityScopedResource() else {
            UserDefaults.standard.removeObject(forKey: "sidebarFolderBookmark")
            return
        }
        fileTreeModel.scan(rootURL: url)
        showSidebar = true
    }

    private func startFileWatcher() {
        fileWatcher?.stop()
        guard let url = fileURL else { return }

        let doc = document
        fileWatcher = FileWatcher(url: url, knownHash: doc.lastKnownHash) { [weak doc] newContent in
            guard let document = doc else { return }

            if newContent.isEmpty {
                // File was deleted
                showDeletedAlert = true
                return
            }

            if document.isDirty {
                // Conflict — show dialog
                pendingExternalContent = newContent
                showConflictAlert = true
            } else {
                // Silent reload
                document.text = newContent
                document.didLoad()
            }
        }
        fileWatcher?.start()
    }
}

// MARK: - ViewModifiers for notification-based commands

struct ViewModeReceivers: ViewModifier {
    @Binding var viewMode: ViewMode
    @Binding var isSplitView: Bool
    @Binding var useGFM: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .switchToPreview)) { _ in
                viewMode = .preview
                isSplitView = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToEditor)) { _ in
                viewMode = .editor
                isSplitView = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSplit)) { _ in
                isSplitView.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleGFM)) { _ in
                useGFM.toggle()
            }
    }
}

struct SidebarReceivers: ViewModifier {
    @Binding var showSidebar: Bool
    let openFolderPanel: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openFolder)) { _ in
                openFolderPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                showSidebar.toggle()
                UserDefaults.standard.set(showSidebar, forKey: "showSidebar")
            }
    }
}

struct FormatCommandReceivers: ViewModifier {
    let applyFormatCommand: ((inout String, inout NSRange) -> Void) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .formatBold)) { _ in
                applyFormatCommand { EditorKeyCommands.bold(text: &$0, selectedRange: &$1) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .formatItalic)) { _ in
                applyFormatCommand { EditorKeyCommands.italic(text: &$0, selectedRange: &$1) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .formatCode)) { _ in
                applyFormatCommand { EditorKeyCommands.inlineCode(text: &$0, selectedRange: &$1) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .formatCodeBlock)) { _ in
                applyFormatCommand { EditorKeyCommands.codeBlock(text: &$0, selectedRange: &$1) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .formatLink)) { _ in
                applyFormatCommand { EditorKeyCommands.link(text: &$0, selectedRange: &$1) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .formatImage)) { _ in
                applyFormatCommand { EditorKeyCommands.image(text: &$0, selectedRange: &$1) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .formatHeadingIncrease)) { _ in
                applyFormatCommand { EditorKeyCommands.increaseHeading(text: &$0, selectedRange: &$1) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .formatHeadingDecrease)) { _ in
                applyFormatCommand { EditorKeyCommands.decreaseHeading(text: &$0, selectedRange: &$1) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .formatHorizontalRule)) { _ in
                applyFormatCommand { EditorKeyCommands.horizontalRule(text: &$0, selectedRange: &$1) }
            }
    }
}
