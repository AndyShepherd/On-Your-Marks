// Sources/App/MainWindowView.swift
import SwiftUI
import AppKit

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
                saveActiveDocumentAs: saveActiveDocumentAs
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
            }
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { tabManager.activeTab?.isSplitView == true ? nil : tabManager.activeTab?.viewMode ?? .preview },
            set: { newValue in
                if let mode = newValue {
                    tabManager.activeTab?.viewMode = mode
                    tabManager.activeTab?.isSplitView = false
                }
            }
        )) {
            Text("Preview").tag(ViewMode?.some(.preview))
            Text("Rich Editor").tag(ViewMode?.some(.wysiwyg))
            Text("Raw Editor").tag(ViewMode?.some(.editor))
        }
        .pickerStyle(.segmented)
        .frame(width: 300)
        .accessibilityLabel("View mode")
    }

    private var splitToggle: some View {
        Toggle(isOn: Binding(
            get: { tabManager.activeTab?.isSplitView ?? false },
            set: { tabManager.activeTab?.isSplitView = $0 }
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
                saveActiveDocumentAs: saveActiveDocumentAs
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
    }
}
