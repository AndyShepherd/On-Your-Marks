// Sources/App/ContentView.swift
import SwiftUI

enum ViewMode: Int, CaseIterable {
    case preview = 0
    case editor = 1
}

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var viewMode: ViewMode = .preview
    @State private var isSplitView = false
    @State private var scrollPercentage: Double = 0
    @State private var useGFM = UserDefaults.standard.bool(forKey: "useGFM")
    @State private var renderedHTML: String = ""
    @State private var renderTask: Task<Void, Never>?

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
        document.fileURL?.deletingLastPathComponent()
    }

    var body: some View {
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
        .frame(minWidth: 800, minHeight: 500)
        .onAppear { scheduleRender() }
        .onChange(of: document.text) { _, _ in scheduleRender() }
        .onChange(of: useGFM) { _, _ in scheduleRender() }
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

    private var previewPanel: some View {
        MarkdownPreviewView(
            htmlContent: renderedHTML,
            baseURL: baseURL,
            scrollPercentage: $scrollPercentage
        )
    }

    @ViewBuilder
    private var editorPanel: some View {
        // Placeholder until Task 10 (STTextView integration)
        TextEditor(text: $document.text)
            .font(.system(.body, design: .monospaced))
    }
}
