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
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
    }

    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        let tab = tabs[index]
        tab.stopWatching()

        // Auto-save if dirty and has a file
        if tab.document.isDirty, let url = tab.fileURL {
            try? tab.document.data().write(to: url, options: .atomic)
        }

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
        // If index == activeTabIndex, the new tab at that index becomes active
    }

    func closeActiveTab() {
        closeTab(at: activeTabIndex)
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
