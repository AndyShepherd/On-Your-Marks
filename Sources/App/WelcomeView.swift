// Sources/App/WelcomeView.swift
import SwiftUI

struct WelcomeView: View {
    let onNewFile: () -> Void
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // App icon and title
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)

                    Text("On Your Marks")
                        .font(.system(size: 28, weight: .semibold))

                    Text("A Markdown editor for macOS")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                // Action buttons
                VStack(spacing: 12) {
                    welcomeButton(
                        title: "New Document",
                        subtitle: "Start writing from scratch",
                        icon: "doc.badge.plus",
                        action: onNewFile
                    )

                    welcomeButton(
                        title: "Open File",
                        subtitle: "Open an existing Markdown file",
                        icon: "doc.text",
                        action: onOpenFile
                    )

                    welcomeButton(
                        title: "Open Folder",
                        subtitle: "Browse a folder of Markdown files",
                        icon: "folder",
                        action: onOpenFolder
                    )
                }
                .frame(width: 280)

                // Keyboard hints
                HStack(spacing: 16) {
                    hintLabel("⌘N", "New")
                    hintLabel("⌘O", "Open")
                    hintLabel("⇧⌘O", "Folder")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func welcomeButton(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func hintLabel(_ shortcut: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(shortcut)
                .fontDesign(.monospaced)
            Text(label)
        }
    }
}
