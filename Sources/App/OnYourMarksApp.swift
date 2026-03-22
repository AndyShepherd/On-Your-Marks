// Sources/App/OnYourMarksApp.swift
import SwiftUI
import AppKit

@main
struct OnYourMarksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            // View menu
            CommandGroup(after: .toolbar) {
                Button("Preview") {
                    NotificationCenter.default.post(name: .switchToPreview, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Editor") {
                    NotificationCenter.default.post(name: .switchToEditor, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Toggle Split View") {
                    NotificationCenter.default.post(name: .toggleSplit, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Divider()

                Button("Toggle GFM") {
                    NotificationCenter.default.post(name: .toggleGFM, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

            }

            // File menu — Open Folder
            CommandGroup(after: .newItem) {
                Button("Open Folder...") {
                    // If no window exists, create one first
                    if NSApp.windows.filter({ $0.isVisible }).isEmpty {
                        NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil)
                        // Small delay to let the window appear before posting the notification
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .openFolder, object: nil)
                        }
                    } else {
                        NotificationCenter.default.post(name: .openFolder, object: nil)
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            // View menu — Toggle Sidebar
            CommandGroup(before: .toolbar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()
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

class AppDelegate: NSObject, NSApplicationDelegate {
    // Ensures the app stays running even when all windows are closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
