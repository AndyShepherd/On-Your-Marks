// Sources/Editor/EditorKeyCommands.swift
import Foundation

enum EditorKeyCommands {

    static func bold(text: inout String, selectedRange: inout NSRange) {
        wrap(text: &text, selectedRange: &selectedRange, prefix: "**", suffix: "**")
    }

    static func italic(text: inout String, selectedRange: inout NSRange) {
        wrap(text: &text, selectedRange: &selectedRange, prefix: "*", suffix: "*")
    }

    static func inlineCode(text: inout String, selectedRange: inout NSRange) {
        wrap(text: &text, selectedRange: &selectedRange, prefix: "`", suffix: "`")
    }

    static func link(text: inout String, selectedRange: inout NSRange) {
        let nsText = text as NSString
        if selectedRange.length > 0 {
            let selected = nsText.substring(with: selectedRange)
            let replacement = "[\(selected)](url)"
            text = nsText.replacingCharacters(in: selectedRange, with: replacement)
            selectedRange = NSRange(location: selectedRange.location + selected.count + 3, length: 3)
        } else {
            let insertion = "[](url)"
            text = nsText.replacingCharacters(in: NSRange(location: selectedRange.location, length: 0), with: insertion)
            selectedRange = NSRange(location: selectedRange.location + 1, length: 0)
        }
    }

    static func image(text: inout String, selectedRange: inout NSRange) {
        let nsText = text as NSString
        if selectedRange.length > 0 {
            let selected = nsText.substring(with: selectedRange)
            let replacement = "![\(selected)](url)"
            text = nsText.replacingCharacters(in: selectedRange, with: replacement)
            selectedRange = NSRange(location: selectedRange.location + selected.count + 4, length: 3)
        } else {
            let insertion = "![](url)"
            text = nsText.replacingCharacters(in: NSRange(location: selectedRange.location, length: 0), with: insertion)
            selectedRange = NSRange(location: selectedRange.location + 2, length: 0)
        }
    }

    static func codeBlock(text: inout String, selectedRange: inout NSRange) {
        let insertion = "```\n\n```"
        let nsText = text as NSString
        text = nsText.replacingCharacters(in: NSRange(location: selectedRange.location, length: 0), with: insertion)
        selectedRange = NSRange(location: selectedRange.location + 4, length: 0)
    }

    static func horizontalRule(text: inout String, selectedRange: inout NSRange) {
        let insertion = "\n---\n"
        let nsText = text as NSString
        text = nsText.replacingCharacters(in: NSRange(location: selectedRange.location, length: 0), with: insertion)
        selectedRange = NSRange(location: selectedRange.location + insertion.count, length: 0)
    }

    static func increaseHeading(text: inout String, selectedRange: inout NSRange) {
        let lines = text.components(separatedBy: "\n")
        let (lineIndex, _) = lineAndOffset(for: selectedRange.location, in: text)
        guard lineIndex < lines.count else { return }

        var line = lines[lineIndex]
        let currentLevel = line.prefix(while: { $0 == "#" }).count
        guard currentLevel < 6 else { return }

        if currentLevel == 0 {
            line = "# " + line
        } else {
            line = "#" + line
        }

        var newLines = lines
        newLines[lineIndex] = line
        text = newLines.joined(separator: "\n")
        selectedRange = NSRange(location: selectedRange.location + 1, length: selectedRange.length)
    }

    static func decreaseHeading(text: inout String, selectedRange: inout NSRange) {
        let lines = text.components(separatedBy: "\n")
        let (lineIndex, _) = lineAndOffset(for: selectedRange.location, in: text)
        guard lineIndex < lines.count else { return }

        var line = lines[lineIndex]
        let currentLevel = line.prefix(while: { $0 == "#" }).count
        guard currentLevel > 0 else { return }

        if currentLevel == 1 {
            line = String(line.dropFirst(2)) // Remove "# "
        } else {
            line = String(line.dropFirst(1)) // Remove one "#"
        }

        var newLines = lines
        newLines[lineIndex] = line
        text = newLines.joined(separator: "\n")
        let offset = currentLevel == 1 ? 2 : 1
        selectedRange = NSRange(location: max(0, selectedRange.location - offset), length: selectedRange.length)
    }

    // MARK: - Helpers

    private static func wrap(text: inout String, selectedRange: inout NSRange, prefix: String, suffix: String) {
        let nsText = text as NSString
        if selectedRange.length > 0 {
            let selected = nsText.substring(with: selectedRange)
            let replacement = "\(prefix)\(selected)\(suffix)"
            text = nsText.replacingCharacters(in: selectedRange, with: replacement)
            selectedRange = NSRange(location: selectedRange.location + prefix.count, length: selected.count)
        } else {
            let insertion = "\(prefix)\(suffix)"
            text = nsText.replacingCharacters(in: NSRange(location: selectedRange.location, length: 0), with: insertion)
            selectedRange = NSRange(location: selectedRange.location + prefix.count, length: 0)
        }
    }

    private static func lineAndOffset(for charOffset: Int, in text: String) -> (line: Int, column: Int) {
        var line = 0
        var col = 0
        for (i, char) in text.enumerated() {
            if i == charOffset { break }
            if char == "\n" {
                line += 1
                col = 0
            } else {
                col += 1
            }
        }
        return (line, col)
    }
}
