// Tests/TableAttachmentTests.swift
import Testing
import AppKit
@testable import OnYourMarks

@Suite("TableAttachment")
struct TableAttachmentTests {

    @Test("Basic table serializes to GFM pipe syntax")
    func basicTableSerialization() {
        let attachment = TableAttachment(
            headers: ["A", "B"],
            rows: [["1", "2"], ["3", "4"]],
            alignments: [.left, .left]
        )
        let result = attachment.serializeToMarkdown()
        #expect(result.contains("| A | B |"))
        #expect(result.contains("| :--- | :--- |"))
        #expect(result.contains("| 1 | 2 |"))
        #expect(result.contains("| 3 | 4 |"))
    }

    @Test("Center alignment marker")
    func centerAlignment() {
        let attachment = TableAttachment(
            headers: ["X"],
            rows: [["1"]],
            alignments: [.center]
        )
        let result = attachment.serializeToMarkdown()
        #expect(result.contains(":---:"))
    }

    @Test("Right alignment marker")
    func rightAlignment() {
        let attachment = TableAttachment(
            headers: ["X"],
            rows: [["1"]],
            alignments: [.right]
        )
        let result = attachment.serializeToMarkdown()
        #expect(result.contains("---:"))
    }

    @Test("Add row appends empty row")
    func addRow() {
        let attachment = TableAttachment(headers: ["A"], rows: [["1"]], alignments: [.left])
        attachment.addRow()
        #expect(attachment.rows.count == 2)
        #expect(attachment.rows[1] == [""])
    }

    @Test("Add column extends headers and all rows")
    func addColumn() {
        let attachment = TableAttachment(headers: ["A"], rows: [["1"]], alignments: [.left])
        attachment.addColumn()
        #expect(attachment.headers == ["A", ""])
        #expect(attachment.rows[0] == ["1", ""])
        #expect(attachment.alignments.count == 2)
    }

    @Test("Remove row")
    func removeRow() {
        let attachment = TableAttachment(headers: ["A"], rows: [["1"], ["2"]], alignments: [.left])
        attachment.removeRow(at: 0)
        #expect(attachment.rows.count == 1)
        #expect(attachment.rows[0] == ["2"])
    }

    @Test("Remove column")
    func removeColumn() {
        let attachment = TableAttachment(headers: ["A", "B"], rows: [["1", "2"]], alignments: [.left, .right])
        attachment.removeColumn(at: 0)
        #expect(attachment.headers == ["B"])
        #expect(attachment.rows[0] == ["2"])
        #expect(attachment.alignments == [.right])
    }
}
