// Sources/App/ContentView.swift
import SwiftUI
import AppKit

enum ViewMode: Int, CaseIterable {
    case preview = 0
    case editor = 1
    case wysiwyg = 2
}

struct ContentView: View {
    @ObservedObject var tab: TabItem
    @Binding var useGFM: Bool
    @State private var renderedHTML: String = ""
    @State private var renderTask: Task<Void, Never>?
    @StateObject private var wysiwygToolbarState = WYSIWYGToolbarState()

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let text = tab.document.text
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
        tab.fileURL?.deletingLastPathComponent()
    }

    var body: some View {
        mainContent
            .onAppear {
                scheduleRender()
                tab.startWatching(
                    onConflict: { _ in },
                    onDelete: { }
                )
            }
            .onDisappear {
                tab.stopWatching()
            }
            .onChange(of: tab.document.text) { _, _ in scheduleRender() }
            .onChange(of: useGFM) { _, _ in scheduleRender() }
            .modifier(FormatCommandReceivers(applyFormatCommand: applyFormatCommand))
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            Group {
                if tab.isSplitView {
                    HSplitView {
                        editorPanel
                        previewPanel
                    }
                } else {
                    switch tab.viewMode {
                    case .preview:
                        previewPanel
                    case .editor:
                        editorPanel
                    case .wysiwyg:
                        wysiwygPanel
                    }
                }
            }
            Divider()
            wordCountBar
        }
    }

    private var wordCountBar: some View {
        let text = tab.document.text
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let chars = text.count
        let lines = text.components(separatedBy: "\n").count

        return HStack {
            Text("\(words) words")
            Text("·")
                .foregroundStyle(.quaternary)
            Text("\(chars) characters")
            Text("·")
                .foregroundStyle(.quaternary)
            Text("\(lines) lines")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private var previewPanel: some View {
        MarkdownPreviewView(
            htmlContent: renderedHTML,
            baseURL: baseURL,
            scrollPercentage: Binding(
                get: { tab.scrollPercentage },
                set: { tab.scrollPercentage = $0 }
            )
        )
    }

    private var wysiwygPanel: some View {
        VStack(spacing: 0) {
            WYSIWYGToolbarView(
                onBold: { NotificationCenter.default.post(name: .formatBold, object: nil) },
                onItalic: { NotificationCenter.default.post(name: .formatItalic, object: nil) },
                onStrikethrough: { NotificationCenter.default.post(name: .formatStrikethrough, object: nil) },
                onCode: { NotificationCenter.default.post(name: .formatCode, object: nil) },
                onLink: { NotificationCenter.default.post(name: .formatLink, object: nil) },
                onImage: { NotificationCenter.default.post(name: .formatImage, object: nil) },
                onBulletList: { NotificationCenter.default.post(name: .formatBulletList, object: nil) },
                onNumberedList: { NotificationCenter.default.post(name: .formatNumberedList, object: nil) },
                onTaskList: { NotificationCenter.default.post(name: .formatTaskList, object: nil) },
                onBlockquote: { NotificationCenter.default.post(name: .formatBlockquote, object: nil) },
                onHorizontalRule: { NotificationCenter.default.post(name: .formatHorizontalRule, object: nil) },
                onTable: { NotificationCenter.default.post(name: .formatTable, object: nil) },
                onHeading: { level in
                    NotificationCenter.default.post(name: .formatHeading, object: nil, userInfo: ["level": level])
                },
                isBold: wysiwygToolbarState.isBold,
                isItalic: wysiwygToolbarState.isItalic,
                isStrikethrough: wysiwygToolbarState.isStrikethrough,
                isCode: wysiwygToolbarState.isCode,
                isBlockquote: wysiwygToolbarState.isBlockquote,
                headingLevel: wysiwygToolbarState.headingLevel
            )
            Divider()
            WYSIWYGEditorView(
                text: Binding(
                    get: { tab.document.text },
                    set: { tab.document.text = $0 }
                ),
                useGFM: useGFM,
                toolbarState: wysiwygToolbarState
            )
        }
    }

    private var editorPanel: some View {
        STTextViewEditor(
            text: Binding(
                get: { tab.document.text },
                set: { tab.document.text = $0 }
            ),
            cursorOffset: Binding(
                get: { tab.cursorOffset },
                set: { tab.cursorOffset = $0 }
            ),
            scrollOffset: Binding(
                get: { tab.editorScrollOffset },
                set: { tab.editorScrollOffset = $0 }
            )
        )
    }

    private func applyFormatCommand(_ command: (inout String, inout NSRange) -> Void) {
        guard tab.viewMode == .editor || tab.isSplitView else { return }
        var text = tab.document.text
        var range = NSRange(location: tab.cursorOffset, length: 0)
        command(&text, &range)
        tab.document.userDidEdit(text)
        tab.cursorOffset = range.location
    }
}

// MARK: - Format Command Receivers

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
            .onReceive(NotificationCenter.default.publisher(for: .formatStrikethrough)) { _ in
                applyFormatCommand { EditorKeyCommands.strikethrough(text: &$0, selectedRange: &$1) }
            }
    }
}
