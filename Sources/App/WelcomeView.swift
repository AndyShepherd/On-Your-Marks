// Sources/App/WelcomeView.swift
import SwiftUI

struct WelcomeView: View {
    let onNewFile: () -> Void
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void

    private let accentColor = Color.purple

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // App icon and title
                VStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 128, height: 128)

                    Text("On Your Marks")
                        .font(.system(size: 36, weight: .bold))

                    Text("A Markdown editor for macOS")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Action buttons
                VStack(spacing: 14) {
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
                .frame(width: 340)

                // Keyboard hints
                HStack(spacing: 20) {
                    hintLabel("⌘N", "New")
                    hintLabel("⌘O", "Open")
                    hintLabel("⇧⌘O", "Folder")
                }
                .font(.callout)
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
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(accentColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
