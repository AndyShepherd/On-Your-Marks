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
    @State private var cursorOffset: Int = 0
    @State private var editorScrollOffset: Int = 0
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
        mainContent
            .frame(minWidth: 800, minHeight: 500)
            .onAppear { scheduleRender() }
            .onChange(of: document.text) { _, _ in scheduleRender() }
            .onChange(of: useGFM) { _, _ in scheduleRender() }
            .modifier(ViewModeReceivers(viewMode: $viewMode, isSplitView: $isSplitView, useGFM: $useGFM))
            .modifier(FormatCommandReceivers(applyFormatCommand: applyFormatCommand))
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
