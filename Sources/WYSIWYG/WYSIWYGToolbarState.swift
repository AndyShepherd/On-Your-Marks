// Sources/WYSIWYG/WYSIWYGToolbarState.swift
import SwiftUI

/// Observable object shared between the WYSIWYG toolbar and editor
/// to track which formatting attributes are active at the current selection.
@MainActor
final class WYSIWYGToolbarState: ObservableObject {
    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isStrikethrough: Bool = false
    @Published var isCode: Bool = false
    @Published var isBlockquote: Bool = false
    @Published var headingLevel: Int = 0
    @Published var isInTable: Bool = false
}
