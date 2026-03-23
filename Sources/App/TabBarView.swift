// Sources/App/TabBarView.swift
import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabManager: TabDocumentManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                TabButton(
                    title: tab.title,
                    isActive: index == tabManager.activeTabIndex,
                    isDirty: tab.document.isDirty,
                    onSelect: { tabManager.switchToTab(at: index) },
                    onClose: { tabManager.closeTabWithPrompt(at: index) }
                )
            }

            // New tab button
            Button(action: { tabManager.newTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.bar)
    }
}

struct TabButton: View {
    let title: String
    let isActive: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            if isDirty {
                Circle()
                    .fill(.primary)
                    .frame(width: 6, height: 6)
            }

            Text(title)
                .font(.system(size: 11))
                .lineLimit(1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isActive ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.15) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }
}
