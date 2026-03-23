import Foundation
import SwiftUI

class TabDocumentManager: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var activeTabIndex: Int = 0

    var activeTab: TabItem? {
        guard activeTabIndex >= 0 && activeTabIndex < tabs.count else { return nil }
        return tabs[activeTabIndex]
    }

    init() {
        // Start with one empty tab
        tabs = [TabItem()]
    }

    func newTab() {
        let tab = TabItem()
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
    }

    /// Whether the current state is a single empty untitled tab
    var isSingleEmptyTab: Bool {
        tabs.count == 1
            && tabs[0].fileURL == nil
            && tabs[0].document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func openFile(_ url: URL) {
        // If already open, switch to it
        if let existingIndex = tabs.firstIndex(where: { $0.fileURL == url }) {
            activeTabIndex = existingIndex
            return
        }

        // Load file content
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let doc = MarkdownDocument(text: content)
        doc.didLoad()
        let tab = TabItem(document: doc, fileURL: url)

        // If the only tab is an empty untitled one, replace it
        if tabs.count == 1,
           tabs[0].fileURL == nil,
           tabs[0].document.text.isEmpty {
            tabs[0].stopWatching()
            tabs[0] = tab
            activeTabIndex = 0
        } else {
            tabs.append(tab)
            activeTabIndex = tabs.count - 1
        }
    }

    /// Close a tab without any prompt — called after user confirms or if not dirty.
    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        let tab = tabs[index]
        tab.stopWatching()

        tabs.remove(at: index)

        // Never have zero tabs
        if tabs.isEmpty {
            tabs = [TabItem()]
            activeTabIndex = 0
        } else if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        } else if index < activeTabIndex {
            activeTabIndex -= 1
        }
    }

    /// Close the active tab with prompt.
    @MainActor func closeActiveTabWithPrompt() {
        closeTabWithPrompt(at: activeTabIndex)
    }

    /// Close a tab with an unsaved-changes prompt if needed.
    @MainActor func closeTabWithPrompt(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        let tab = tabs[index]

        // Check both isDirty flag and content hash — the WYSIWYG editor
        // may have changed content without going through userDidEdit
        let hasUnsavedChanges = tab.document.isDirty || tab.document.contentHash != tab.document.lastKnownHash

        if hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "Save changes to \"\(tab.title)\"?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Save then close
                if let url = tab.fileURL {
                    try? tab.document.data().write(to: url, options: .atomic)
                    tab.document.didSave()
                    closeTab(at: index)
                } else {
                    // Untitled — need a save panel
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.plainText]
                    panel.nameFieldStringValue = "Untitled.md"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? tab.document.data().write(to: url, options: .atomic)
                        tab.document.didSave()
                        closeTab(at: index)
                    }
                }
            case .alertSecondButtonReturn:
                // Don't save — just close
                closeTab(at: index)
            default:
                break
            }
        } else {
            closeTab(at: index)
        }
    }

    func switchToTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        activeTabIndex = index
    }

    func nextTab() {
        guard tabs.count > 1 else { return }
        activeTabIndex = (activeTabIndex + 1) % tabs.count
    }

    func previousTab() {
        guard tabs.count > 1 else { return }
        activeTabIndex = (activeTabIndex - 1 + tabs.count) % tabs.count
    }

    func moveTab(from source: Int, to destination: Int) {
        guard source != destination else { return }
        let tab = tabs.remove(at: source)
        let adjustedDestination = destination > source ? destination - 1 : destination
        tabs.insert(tab, at: adjustedDestination)

        // Adjust activeTabIndex
        if activeTabIndex == source {
            activeTabIndex = adjustedDestination
        } else if source < activeTabIndex && adjustedDestination >= activeTabIndex {
            activeTabIndex -= 1
        } else if source > activeTabIndex && adjustedDestination <= activeTabIndex {
            activeTabIndex += 1
        }
    }

    func saveActiveTab() {
        guard let tab = activeTab else { return }
        if let url = tab.fileURL {
            try? tab.document.data().write(to: url, options: .atomic)
            tab.document.didSave()
            tab.fileWatcher?.updateKnownHash(tab.document.contentHash)
        }
        // If no fileURL, caller should show NSSavePanel
    }

    func saveActiveTabAs(_ url: URL) {
        guard let tab = activeTab else { return }
        try? tab.document.data().write(to: url, options: .atomic)
        tab.fileURL = url
        tab.document.didSave()
    }

    /// Find if a URL is already open and return its tab index
    func tabIndex(for url: URL) -> Int? {
        tabs.firstIndex(where: { $0.fileURL == url })
    }
}
