// Sources/WYSIWYG/Attachments/TableAttachment.swift
import AppKit

enum ColumnAlignment: Equatable, Sendable {
    case left, center, right
}

final class TableAttachment: NSTextAttachment, MarkdownBlockAttachment {

    var headers: [String]
    var rows: [[String]]
    var alignments: [ColumnAlignment]

    private static let padding: CGFloat = 10
    private static let cellPadding: CGFloat = 6
    private static let cornerRadius: CGFloat = 6
    private static let canvasWidth: CGFloat = 600
    private static let rowHeight: CGFloat = 24
    private nonisolated(unsafe) static let headerFont: NSFont = .systemFont(ofSize: 13, weight: .bold)
    private nonisolated(unsafe) static let cellFont: NSFont = .systemFont(ofSize: 13, weight: .regular)

    init(headers: [String], rows: [[String]], alignments: [ColumnAlignment]) {
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
        super.init(data: nil, ofType: nil)
        let img = Self.makeImage(headers: headers, rows: rows, alignments: alignments)
        self.image = img
        self.bounds = CGRect(x: 0, y: -4, width: img.size.width, height: img.size.height)
    }

    required init?(coder: NSCoder) {
        self.headers = (coder.decodeObject(forKey: "headers") as? [String]) ?? []
        self.rows = (coder.decodeObject(forKey: "rows") as? [[String]]) ?? []
        // Decode alignments as raw ints
        if let rawAlignments = coder.decodeObject(forKey: "alignments") as? [Int] {
            self.alignments = rawAlignments.map { raw in
                switch raw {
                case 1: return .center
                case 2: return .right
                default: return .left
                }
            }
        } else {
            self.alignments = Array(repeating: .left, count: headers.count)
        }
        super.init(coder: coder)
        let img = Self.makeImage(headers: self.headers, rows: self.rows, alignments: self.alignments)
        self.image = img
        self.bounds = CGRect(x: 0, y: -4, width: img.size.width, height: img.size.height)
    }

    // MARK: - Mutation

    func addRow() {
        let emptyRow = Array(repeating: "", count: headers.count)
        rows.append(emptyRow)
    }

    func removeRow(at index: Int) {
        rows.remove(at: index)
    }

    func addColumn() {
        headers.append("")
        for i in rows.indices {
            rows[i].append("")
        }
        alignments.append(.left)
    }

    func removeColumn(at index: Int) {
        headers.remove(at: index)
        for i in rows.indices {
            rows[i].remove(at: index)
        }
        alignments.remove(at: index)
    }

    // MARK: - Serialization

    nonisolated func serializeToMarkdown() -> String {
        var lines: [String] = []

        // Header row
        let headerLine = "| " + headers.joined(separator: " | ") + " |"
        lines.append(headerLine)

        // Alignment row
        let alignmentCells = alignments.map { alignment -> String in
            switch alignment {
            case .left:   return ":---"
            case .center: return ":---:"
            case .right:  return "---:"
            }
        }
        let alignmentLine = "| " + alignmentCells.joined(separator: " | ") + " |"
        lines.append(alignmentLine)

        // Data rows
        for row in rows {
            let rowLine = "| " + row.joined(separator: " | ") + " |"
            lines.append(rowLine)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Rendering

    private static func canvasHeight(rowCount: Int) -> CGFloat {
        // header + separator line + data rows
        let totalRows = CGFloat(1 + rowCount)
        return padding * 2 + totalRows * rowHeight + 1 // +1 for separator line
    }

    private static func makeImage(headers: [String], rows: [[String]], alignments: [ColumnAlignment]) -> NSImage {
        let width = canvasWidth
        let height = canvasHeight(rowCount: rows.count)
        let size = CGSize(width: width, height: height)
        let image = NSImage(size: size)

        image.lockFocus()

        // Background
        let backgroundPath = NSBezierPath(
            roundedRect: CGRect(origin: .zero, size: size),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        NSColor.controlBackgroundColor.setFill()
        backgroundPath.fill()

        // Border
        NSColor.separatorColor.setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        let columnCount = max(headers.count, 1)
        let tableWidth = width - padding * 2
        let columnWidth = tableWidth / CGFloat(columnCount)

        // Draw header row (from top, but NSImage is bottom-left origin)
        let headerY = height - padding - rowHeight
        for (col, header) in headers.enumerated() {
            let cellX = padding + CGFloat(col) * columnWidth + cellPadding
            let cellWidth = columnWidth - cellPadding * 2
            let alignment = col < alignments.count ? alignments[col] : .left

            let paragraphStyle = NSMutableParagraphStyle()
            switch alignment {
            case .left:   paragraphStyle.alignment = .left
            case .center: paragraphStyle.alignment = .center
            case .right:  paragraphStyle.alignment = .right
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ]
            let rect = CGRect(x: cellX, y: headerY, width: cellWidth, height: rowHeight)
            (header as NSString).draw(
                with: rect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attrs
            )
        }

        // Draw separator line
        let separatorY = headerY - 1
        NSColor.separatorColor.setFill()
        NSBezierPath(rect: CGRect(x: padding, y: separatorY, width: tableWidth, height: 1)).fill()

        // Draw data rows
        for (rowIdx, row) in rows.enumerated() {
            let rowY = separatorY - CGFloat(rowIdx + 1) * rowHeight
            for (col, cell) in row.enumerated() {
                let cellX = padding + CGFloat(col) * columnWidth + cellPadding
                let cellWidth = columnWidth - cellPadding * 2
                let alignment = col < alignments.count ? alignments[col] : .left

                let paragraphStyle = NSMutableParagraphStyle()
                switch alignment {
                case .left:   paragraphStyle.alignment = .left
                case .center: paragraphStyle.alignment = .center
                case .right:  paragraphStyle.alignment = .right
                }

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraphStyle,
                ]
                let rect = CGRect(x: cellX, y: rowY, width: cellWidth, height: rowHeight)
                (cell as NSString).draw(
                    with: rect,
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: attrs
                )
            }
        }

        image.unlockFocus()
        return image
    }
}
