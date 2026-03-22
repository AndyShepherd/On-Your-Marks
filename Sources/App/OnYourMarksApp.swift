// Sources/App/OnYourMarksApp.swift
import SwiftUI

@main
struct OnYourMarksApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document)
        }
    }
}
