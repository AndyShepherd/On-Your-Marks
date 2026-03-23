// Sources/App/MainWindowView.swift
import SwiftUI
import AppKit
import WebKit
import Markdown

struct MainWindowView: View {
    @StateObject private var tabManager = TabDocumentManager()
    @StateObject private var fileTreeModel = FileTreeModel()
    @State private var showSidebar = UserDefaults.standard.bool(forKey: "showSidebar")
    @State private var sidebarSelectedURL: URL?
    @State private var showConflictAlert = false
    @State private var showDeletedAlert = false
    @State private var pendingExternalContent = ""
    @State private var useGFM = UserDefaults.standard.object(forKey: "useGFM") == nil
        ? true : UserDefaults.standard.bool(forKey: "useGFM")

    var body: some View {
        mainSplitView
            .frame(minWidth: 800, minHeight: 500)
            .modifier(MainWindowLifecycle(
                tabManager: tabManager,
                sidebarSelectedURL: $sidebarSelectedURL,
                useGFM: $useGFM,
                restoreSavedFolder: restoreSavedFolder,
                updateWindowTitle: updateWindowTitle
            ))
            .modifier(MainWindowNotificationReceivers(
                tabManager: tabManager,
                showSidebar: $showSidebar,
                useGFM: $useGFM,
                openFolder: openFolder,
                openFolderPanel: openFolderPanel,
                openDocumentPanel: openDocumentPanel,
                saveActiveDocument: saveActiveDocument,
                saveActiveDocumentAs: saveActiveDocumentAs,
                exportPDF: exportPDF,
                exportHTML: exportHTML
            ))
            .modifier(MainWindowAlerts(
                tabManager: tabManager,
                showConflictAlert: $showConflictAlert,
                showDeletedAlert: $showDeletedAlert,
                pendingExternalContent: $pendingExternalContent
            ))
            .modifier(MainWindowToolbar(
                tabManager: tabManager,
                useGFM: $useGFM
            ))
    }

    // MARK: - Main Layout

    private var mainSplitView: some View {
        HSplitView {
            if showSidebar {
                SidebarView(
                    treeModel: fileTreeModel,
                    selectedFileURL: $sidebarSelectedURL
                )
            }
            tabContentArea
                .frame(minWidth: 400)
                .layoutPriority(1)
        }
    }

    private var tabContentArea: some View {
        VStack(spacing: 0) {
            if tabManager.tabs.count > 1 || tabManager.tabs.first?.fileURL != nil {
                TabBarView(tabManager: tabManager)
                Divider()
            }

            if let activeTab = tabManager.activeTab {
                ContentView(
                    tab: activeTab,
                    useGFM: $useGFM
                )
                .id(activeTab.id)
            }
        }
    }

    // MARK: - Window Title

    private func updateWindowTitle() {
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow {
                window.title = tabManager.activeTab?.title ?? "On Your Marks"
                window.isDocumentEdited = tabManager.activeTab?.document.isDirty ?? false
            }
        }
    }

    // MARK: - Folder Management

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(url)
    }

    private func openFolder(_ url: URL) {
        saveBookmark(for: url)
        fileTreeModel.scan(rootURL: url)
        showSidebar = true
        UserDefaults.standard.set(true, forKey: "showSidebar")
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
        ), !isStale, url.startAccessingSecurityScopedResource() else {
            UserDefaults.standard.removeObject(forKey: "sidebarFolderBookmark")
            return
        }
        fileTreeModel.scan(rootURL: url)
        showSidebar = true
    }

    // MARK: - Document Actions

    private func openDocumentPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        panel.message = "Choose a Markdown file to open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        tabManager.openFile(url)
    }

    private func saveActiveDocument() {
        guard let tab = tabManager.activeTab else { return }
        if tab.fileURL != nil {
            tabManager.saveActiveTab()
            updateWindowTitle()
        } else {
            saveActiveDocumentAs()
        }
    }

    private func saveActiveDocumentAs() {
        guard let tab = tabManager.activeTab else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = tab.title.hasSuffix(".md") ? tab.title : "Untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        tabManager.saveActiveTabAs(url)
        updateWindowTitle()
    }

    // MARK: - Export

    private func exportPDF() {
        guard let tab = tabManager.activeTab else { return }
        let html = renderHTML(for: tab)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let baseName = tab.title.replacingOccurrences(of: ".md", with: "")
        panel.nameFieldStringValue = baseName + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Render HTML in a temporary WKWebView and print to PDF
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = Bundle.module
        #else
        bundle = Bundle.main
        #endif
        let baseURL = tab.fileURL?.deletingLastPathComponent() ?? bundle.resourceURL
        webView.loadHTMLString(html, baseURL: baseURL)

        // Wait for load, then create PDF
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let config = WKPDFConfiguration()
            config.rect = NSRect(x: 0, y: 0, width: 612, height: 792) // US Letter
            webView.createPDF(configuration: config) { result in
                if case .success(let data) = result {
                    try? data.write(to: url)
                }
            }
        }
    }

    private func exportHTML() {
        guard let tab = tabManager.activeTab else { return }
        let html = renderHTML(for: tab)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        let baseName = tab.title.replacingOccurrences(of: ".md", with: "")
        panel.nameFieldStringValue = baseName + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? html.write(to: url, atomically: true, encoding: .utf8)
    }

    private func renderHTML(for tab: TabItem) -> String {
        let parser = MarkdownParser(useGFM: useGFM)
        let doc = parser.parse(tab.document.text)
        var renderer = HTMLRenderer(useGFM: useGFM)
        let body = renderer.render(doc)

        let css = loadResource("preview", ext: "css")
        let highlightCSS = loadResource("highlight-theme", ext: "css")
        let highlightJS = loadResource("highlight.min", ext: "js")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(tab.title)</title>
            <style>\(css)</style>
            <style>\(highlightCSS)</style>
            <script>\(highlightJS)</script>
        </head>
        <body>
            <article id="content">
                \(body)
            </article>
            <script>hljs.highlightAll();</script>
        </body>
        </html>
        """
    }

    private func loadResource(_ name: String, ext: String) -> String {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = Bundle.module
        #else
        bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }
}

// MARK: - Lifecycle ViewModifier

struct MainWindowLifecycle: ViewModifier {
    @ObservedObject var tabManager: TabDocumentManager
    @Binding var sidebarSelectedURL: URL?
    @Binding var useGFM: Bool
    let restoreSavedFolder: () -> Void
    let updateWindowTitle: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                restoreSavedFolder()
            }
            .onChange(of: sidebarSelectedURL) { _, newURL in
                guard let url = newURL else { return }
                tabManager.openFile(url)
            }
            .onChange(of: tabManager.activeTabIndex) { _, _ in
                sidebarSelectedURL = tabManager.activeTab?.fileURL
                updateWindowTitle()
            }
            .onChange(of: useGFM) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "useGFM")
            }
    }
}

// MARK: - Alert ViewModifier

struct MainWindowAlerts: ViewModifier {
    @ObservedObject var tabManager: TabDocumentManager
    @Binding var showConflictAlert: Bool
    @Binding var showDeletedAlert: Bool
    @Binding var pendingExternalContent: String

    func body(content: Content) -> some View {
        content
            .alert("File Changed on Disk", isPresented: $showConflictAlert) {
                Button("Reload") {
                    if let tab = tabManager.activeTab {
                        tab.document.text = pendingExternalContent
                        tab.document.didLoad()
                        tab.fileWatcher?.updateKnownHash(tab.document.contentHash)
                    }
                }
                Button("Keep Mine", role: .cancel) {
                    if let tab = tabManager.activeTab,
                       let url = tab.fileURL,
                       let hash = FileWatcher.sha256(of: url) {
                        tab.fileWatcher?.updateKnownHash(hash)
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
    }
}

// MARK: - Toolbar ViewModifier

struct MainWindowToolbar: ViewModifier {
    @ObservedObject var tabManager: TabDocumentManager
    @Binding var useGFM: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    modePicker
                }

                ToolbarItem {
                    splitToggle
                }

                ToolbarItem {
                    gfmToggle
                }

                ToolbarItem {
                    tocMenu
                }
            }
    }

    private var tocMenu: some View {
        Menu {
            let headings = extractHeadings(from: tabManager.activeTab?.document.text ?? "")
            if headings.isEmpty {
                Text("No headings")
            } else {
                ForEach(Array(headings.enumerated()), id: \.offset) { _, heading in
                    Button(action: {
                        NotificationCenter.default.post(
                            name: .scrollToHeading,
                            object: nil,
                            userInfo: ["heading": heading.text, "line": heading.line]
                        )
                    }) {
                        HStack {
                            Text(String(repeating: "  ", count: heading.level - 1) + heading.text)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet.indent")
        }
        .help("Table of Contents")
        .accessibilityLabel("Table of contents")
    }

    private struct Heading {
        let level: Int
        let text: String
        let line: Int
    }

    private func extractHeadings(from text: String) -> [Heading] {
        var headings: [Heading] = []
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            var level = 0
            for char in trimmed {
                if char == "#" { level += 1 } else { break }
            }
            guard level >= 1, level <= 6 else { continue }
            let headingText = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
            guard !headingText.isEmpty else { continue }
            headings.append(Heading(level: level, text: headingText, line: index))
        }
        return headings
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: {
                // When split is active, highlight Raw Editor (split = Raw + Preview)
                if tabManager.activeTab?.isSplitView == true {
                    return ViewMode.editor
                }
                return tabManager.activeTab?.viewMode ?? .preview
            },
            set: { newValue in
                tabManager.activeTab?.viewMode = newValue
                // Selecting any mode exits split view
                tabManager.activeTab?.isSplitView = false
            }
        )) {
            Text("Preview").tag(ViewMode.preview)
            Text("Rich Editor").tag(ViewMode.wysiwyg)
            Text("Raw Editor").tag(ViewMode.editor)
        }
        .pickerStyle(.segmented)
        .frame(width: 300)
        .accessibilityLabel("View mode")
    }

    private var splitToggle: some View {
        Toggle(isOn: Binding(
            get: { tabManager.activeTab?.isSplitView ?? false },
            set: { newValue in
                guard tabManager.activeTab?.viewMode != .wysiwyg else { return }
                tabManager.activeTab?.isSplitView = newValue
            }
        )) {
            Image(systemName: "rectangle.split.2x1")
        }
        .disabled(tabManager.activeTab?.viewMode == .wysiwyg)
        .help("Toggle Split View")
        .accessibilityLabel("Toggle split view")
    }

    private var gfmToggle: some View {
        Toggle(isOn: $useGFM) {
            Text("GFM")
        }
        .toggleStyle(.checkbox)
        .help("GitHub Flavored Markdown")
        .accessibilityLabel("Toggle GitHub Flavored Markdown")
    }
}

// MARK: - Notification Receivers

struct MainWindowNotificationReceivers: ViewModifier {
    @ObservedObject var tabManager: TabDocumentManager
    @Binding var showSidebar: Bool
    @Binding var useGFM: Bool
    let openFolder: (URL) -> Void
    let openFolderPanel: () -> Void
    let openDocumentPanel: () -> Void
    let saveActiveDocument: () -> Void
    let saveActiveDocumentAs: () -> Void
    let exportPDF: () -> Void
    let exportHTML: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(SidebarAndViewModeReceivers(
                tabManager: tabManager,
                showSidebar: $showSidebar,
                useGFM: $useGFM,
                openFolder: openFolder,
                openFolderPanel: openFolderPanel
            ))
            .modifier(TabAndDocumentReceivers(
                tabManager: tabManager,
                openDocumentPanel: openDocumentPanel,
                saveActiveDocument: saveActiveDocument,
                saveActiveDocumentAs: saveActiveDocumentAs,
                exportPDF: exportPDF,
                exportHTML: exportHTML
            ))
    }
}

struct SidebarAndViewModeReceivers: ViewModifier {
    @ObservedObject var tabManager: TabDocumentManager
    @Binding var showSidebar: Bool
    @Binding var useGFM: Bool
    let openFolder: (URL) -> Void
    let openFolderPanel: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openFolder)) { notification in
                if let url = notification.object as? URL {
                    openFolder(url)
                } else {
                    openFolderPanel()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                showSidebar.toggle()
                UserDefaults.standard.set(showSidebar, forKey: "showSidebar")
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToPreview)) { _ in
                tabManager.activeTab?.viewMode = .preview
                tabManager.activeTab?.isSplitView = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToEditor)) { _ in
                tabManager.activeTab?.viewMode = .editor
                tabManager.activeTab?.isSplitView = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToWYSIWYG)) { _ in
                tabManager.activeTab?.viewMode = .wysiwyg
                tabManager.activeTab?.isSplitView = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSplit)) { _ in
                guard tabManager.activeTab?.viewMode != .wysiwyg else { return }
                tabManager.activeTab?.isSplitView.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleGFM)) { _ in
                useGFM.toggle()
            }
    }
}

struct TabAndDocumentReceivers: ViewModifier {
    @ObservedObject var tabManager: TabDocumentManager
    let openDocumentPanel: () -> Void
    let saveActiveDocument: () -> Void
    let saveActiveDocumentAs: () -> Void
    let exportPDF: () -> Void
    let exportHTML: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                tabManager.newTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                tabManager.closeActiveTabWithPrompt()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextTab)) { _ in
                tabManager.nextTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .previousTab)) { _ in
                tabManager.previousTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDocument)) { _ in
                openDocumentPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveDocument)) { _ in
                saveActiveDocument()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveDocumentAs)) { _ in
                saveActiveDocumentAs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
                exportPDF()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportHTML)) { _ in
                exportHTML()
            }
    }
}
