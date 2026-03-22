import Foundation

class TabItem: Identifiable, ObservableObject {
    let id = UUID()
    @Published var document: MarkdownDocument
    @Published var fileURL: URL?
    @Published var viewMode: ViewMode = .preview
    @Published var isSplitView: Bool = false
    @Published var scrollPercentage: Double = 0
    @Published var cursorOffset: Int = 0
    @Published var editorScrollOffset: Int = 0
    var fileWatcher: FileWatcher?

    var title: String {
        if let url = fileURL {
            return url.lastPathComponent
        }
        return "Untitled"
    }

    init(document: MarkdownDocument = MarkdownDocument(), fileURL: URL? = nil) {
        self.document = document
        self.fileURL = fileURL
    }

    func startWatching(onConflict: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        fileWatcher?.stop()
        guard let url = fileURL else { return }

        fileWatcher = FileWatcher(url: url, knownHash: document.contentHash) { [weak self] newContent in
            guard let self else { return }
            if newContent.isEmpty {
                onDelete()
            } else if document.isDirty {
                onConflict(newContent)
            } else {
                document.text = newContent
                document.didLoad()
            }
        }
        fileWatcher?.start()
    }

    func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    deinit {
        stopWatching()
    }
}
