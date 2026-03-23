// Sources/WYSIWYG/WYSIWYGToolbarView.swift
import SwiftUI

struct WYSIWYGToolbarView: View {
    let onBold: () -> Void
    let onItalic: () -> Void
    let onStrikethrough: () -> Void
    let onCode: () -> Void
    let onLink: () -> Void
    let onImage: () -> Void
    let onBulletList: () -> Void
    let onNumberedList: () -> Void
    let onTaskList: () -> Void
    let onBlockquote: () -> Void
    let onHorizontalRule: () -> Void
    let onTable: () -> Void
    let onHeading: (Int) -> Void

    var isBold: Bool = false
    var isItalic: Bool = false
    var isStrikethrough: Bool = false
    var isCode: Bool = false
    var isBlockquote: Bool = false
    var headingLevel: Int = 0
    var body: some View {
        HStack(spacing: 2) {
            headingMenu

            toolbarDivider

            formatGroup

            toolbarDivider

            insertGroup

            toolbarDivider

            blockGroup

            toolbarDivider

            structureGroup

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Heading Menu

    private var headingMenu: some View {
        Menu {
            Button("Paragraph") { onHeading(0) }
            Divider()
            ForEach(1...6, id: \.self) { level in
                Button("Heading \(level)") { onHeading(level) }
            }
        } label: {
            Label("Heading", systemImage: "textformat.size")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 32)
        .accessibilityLabel("Heading level")
    }

    // MARK: - Inline Format Group

    private var formatGroup: some View {
        HStack(spacing: 2) {
            toolbarButton(
                symbol: "bold",
                label: "Bold",
                isActive: isBold,
                action: onBold
            )
            toolbarButton(
                symbol: "italic",
                label: "Italic",
                isActive: isItalic,
                action: onItalic
            )
            toolbarButton(
                symbol: "strikethrough",
                label: "Strikethrough",
                isActive: isStrikethrough,
                action: onStrikethrough
            )
            toolbarButton(
                symbol: "chevron.left.forwardslash.chevron.right",
                label: "Inline code",
                isActive: isCode,
                action: onCode
            )
        }
    }

    // MARK: - Insert Group

    private var insertGroup: some View {
        HStack(spacing: 2) {
            toolbarButton(
                symbol: "link",
                label: "Link",
                isActive: false,
                action: onLink
            )
            toolbarButton(
                symbol: "photo",
                label: "Image",
                isActive: false,
                action: onImage
            )
        }
    }

    // MARK: - Block Group

    private var blockGroup: some View {
        HStack(spacing: 2) {
            toolbarButton(
                symbol: "list.bullet",
                label: "Bullet list",
                isActive: false,
                action: onBulletList
            )
            toolbarButton(
                symbol: "list.number",
                label: "Numbered list",
                isActive: false,
                action: onNumberedList
            )
            toolbarButton(
                symbol: "checklist",
                label: "Task list",
                isActive: false,
                action: onTaskList
            )
            toolbarButton(
                symbol: "text.quote",
                label: "Blockquote",
                isActive: isBlockquote,
                action: onBlockquote
            )
        }
    }

    // MARK: - Structure Group

    private var structureGroup: some View {
        HStack(spacing: 2) {
            toolbarButton(
                symbol: "minus",
                label: "Horizontal rule",
                isActive: false,
                action: onHorizontalRule
            )
            toolbarButton(
                symbol: "tablecells",
                label: "Table",
                isActive: false,
                action: onTable
            )
        }
    }

    // MARK: - Helpers

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 4)
    }

    private func toolbarButton(
        symbol: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel(label)
    }
}
