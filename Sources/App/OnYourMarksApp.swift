// Sources/App/OnYourMarksApp.swift
import SwiftUI
import AppKit

@main
struct OnYourMarksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .commands {
            // Replace default New/Open with our own
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Open...") {
                    NotificationCenter.default.post(name: .openDocument, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Folder...") {
                    NotificationCenter.default.post(name: .openFolder, object: nil)
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
