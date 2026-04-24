// Sources/App/OnYourMarksApp.swift
import SwiftUI
import AppKit

enum AppearancePreference: String, CaseIterable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static var current: AppearancePreference {
        let raw = UserDefaults.standard.string(forKey: "appearancePreference") ?? ""
        return AppearancePreference(rawValue: raw) ?? .system
    }

    @MainActor
    static func apply(_ pref: AppearancePreference) {
        UserDefaults.standard.set(pref.rawValue, forKey: "appearancePreference")
        NSApp.appearance = pref.nsAppearance
    }
}

@main
struct OnYourMarksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appearancePreference") private var appearanceRaw: String = AppearancePreference.system.rawValue

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView()
                .task {
                    AppDelegate.openWindowAction = { [openWindow] in
                        openWindow(id: "main")
                    }
                }
        }
        .commands {
            // Replace default New/Open with our own
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    postEnsureWindow(.newTab)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Open...") {
                    postEnsureWindow(.openDocument)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Folder...") {
                    postEnsureWindow(.openFolder)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            // Replace default Save
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveDocument, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As...") {
                    NotificationCenter.default.post(name: .saveDocumentAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Export as PDF...") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Export as HTML...") {
                    NotificationCenter.default.post(name: .exportHTML, object: nil)
                }
            }

            // Replace system Print with our own
            CommandGroup(replacing: .printItem) {
                Button("Print...") {
                    NotificationCenter.default.post(name: .printDocument, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            // View menu — Toggle Sidebar
            CommandGroup(before: .toolbar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("Next Tab") {
                    NotificationCenter.default.post(name: .nextTab, object: nil)
                }
                .keyboardShortcut("}", modifiers: .command)

                Button("Previous Tab") {
                    NotificationCenter.default.post(name: .previousTab, object: nil)
                }
                .keyboardShortcut("{", modifiers: .command)

                Divider()
            }

            // View menu — mode switching
            CommandGroup(after: .toolbar) {
                Button("Preview") {
                    NotificationCenter.default.post(name: .switchToPreview, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Rich Editor") {
                    NotificationCenter.default.post(name: .switchToWYSIWYG, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Raw Editor") {
                    NotificationCenter.default.post(name: .switchToEditor, object: nil)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Toggle Split View") {
                    NotificationCenter.default.post(name: .toggleSplit, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Divider()

                Button("Toggle GFM") {
                    NotificationCenter.default.post(name: .toggleGFM, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Divider()

                Menu("Appearance") {
                    ForEach(AppearancePreference.allCases, id: \.self) { pref in
                        Button {
                            AppearancePreference.apply(pref)
                            appearanceRaw = pref.rawValue
                        } label: {
                            let active = AppearancePreference(rawValue: appearanceRaw) == pref
                            Text((active ? "✓ " : "  ") + pref.displayName)
                        }
                    }
                }
            }

            // Format menu
            CommandMenu("Format") {
                Button("Bold") {
                    NotificationCenter.default.post(name: .formatBold, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Italic") {
                    NotificationCenter.default.post(name: .formatItalic, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Inline Code") {
                    NotificationCenter.default.post(name: .formatCode, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Strikethrough") {
                    NotificationCenter.default.post(name: .formatStrikethrough, object: nil)
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])

                Button("Code Block") {
                    NotificationCenter.default.post(name: .formatCodeBlock, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Link") {
                    NotificationCenter.default.post(name: .formatLink, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Image") {
                    NotificationCenter.default.post(name: .formatImage, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Menu("Heading") {
                    ForEach(1...6, id: \.self) { level in
                        Button("H\(level)") {
                            NotificationCenter.default.post(name: .formatHeading, object: level)
                        }
                    }
                }

                Button("Increase Heading Level") {
                    NotificationCenter.default.post(name: .formatHeadingIncrease, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Decrease Heading Level") {
                    NotificationCenter.default.post(name: .formatHeadingDecrease, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Divider()

                Button("Horizontal Rule") {
                    NotificationCenter.default.post(name: .formatHorizontalRule, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
private func hasVisibleWindow() -> Bool {
    NSApp.windows.contains(where: { $0.canBecomeMain && $0.isVisible })
}

/// Posts a notification, creating a window first if none exists.
@MainActor
private func postEnsureWindow(_ name: Notification.Name) {
    if hasVisibleWindow() {
        NotificationCenter.default.post(name: name, object: nil)
    } else {
        // No window — ask AppDelegate to open one, then post notification
        AppDelegate.requestNewWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Stored action to open a new window — set from SwiftUI's Environment
    @MainActor static var openWindowAction: (() -> Void)?

    /// Request a new window from anywhere in the app
    @MainActor static func requestNewWindow() {
        if let action = openWindowAction {
            action()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }

        // Check for miniaturized windows first
        if let miniaturized = sender.windows.first(where: { $0.isMiniaturized && $0.canBecomeMain }) {
            miniaturized.deminiaturize(self)
            return false
        }

        // Try to bring forward any existing but hidden window
        if let existing = sender.windows.first(where: { $0.canBecomeMain }) {
            existing.makeKeyAndOrderFront(self)
            return false
        }

        // Window was destroyed (red X on WindowGroup). Return true so
        // SwiftUI creates a fresh window automatically.
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearancePreference.apply(AppearancePreference.current)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "p" {
                NotificationCenter.default.post(name: .printDocument, object: nil)
                return nil
            }
            return event
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let mdURLs = urls.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "md" || ext == "markdown"
        }
        guard !mdURLs.isEmpty else { return }

        Task { @MainActor in
            if !hasVisibleWindow() {
                Self.requestNewWindow()
                try? await Task.sleep(for: .milliseconds(500))
            }
            for url in mdURLs {
                NotificationCenter.default.post(
                    name: .openFileFromFinder,
                    object: url
                )
            }
        }
    }
}
