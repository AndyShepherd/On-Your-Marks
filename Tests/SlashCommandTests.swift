// Tests/SlashCommandTests.swift
import Testing
@testable import OnYourMarks

@Suite("SlashCommandMenu")
struct SlashCommandTests {
    @Test("All commands are present")
    func allCommandsPresent() {
        let names = SlashCommandMenu.allCommands.map(\.name)
        #expect(names.contains("heading"))
        #expect(names.contains("bullet"))
        #expect(names.contains("numbered"))
        #expect(names.contains("task"))
        #expect(names.contains("quote"))
        #expect(names.contains("code"))
        #expect(names.contains("table"))
        #expect(names.contains("image"))
        #expect(names.contains("divider"))
    }

    @Test("Filter narrows results")
    func filterNarrows() {
        let filtered = SlashCommandMenu.allCommands.filter { $0.name.hasPrefix("he") }
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "heading")
    }

    @Test("Empty filter returns all")
    func emptyFilter() {
        let filtered = SlashCommandMenu.allCommands.filter { $0.name.hasPrefix("") }
        #expect(filtered.count == SlashCommandMenu.allCommands.count)
    }
}
