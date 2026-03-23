// Sources/WYSIWYG/Attachments/TableAttachment.swift
import AppKit

enum ColumnAlignment: Equatable, Sendable {
    case left, center, right
}

final class TableAttachment: NSTextAttachment, MarkdownBlockAttachment {

    var headers: [String]
    var rows: [[String]]
    var alignments: [ColumnAlignment]

    init(headers: [String], rows: [[String]], alignments: [ColumnAlignment]) {
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
        super.init(data: nil, ofType: nil)
        self.allowsTextAttachmentView = true
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
        self.allowsTextAttachmentView = true
    }

    // MARK: - View Provider

    override func viewProvider(
        for parentView: NSView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = TableAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        return provider
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
}

// MARK: - View Provider

final class TableAttachmentViewProvider: NSTextAttachmentViewProvider {

    override func loadView() {
        guard let attachment = self.textAttachment as? TableAttachment else { return }
        // loadView is always called on the main thread by AppKit
        let tableView = TableAttachmentView(attachment: attachment)
        self.view = tableView
    }
}

// MARK: - Interactive Table View

final class TableAttachmentView: NSView, NSTextFieldDelegate {

    private nonisolated(unsafe) weak var attachment: TableAttachment?
    private var cellFields: [[NSTextField]] = []

    private static let padding: CGFloat = 10
    private static let cellPadding: CGFloat = 4
    private static let cornerRadius: CGFloat = 6
    private static let maxWidth: CGFloat = 600
    private static let rowHeight: CGFloat = 28
    private static let separatorHeight: CGFloat = 1
    private nonisolated(unsafe) static let headerFont: NSFont = .systemFont(ofSize: 13, weight: .bold)
    private nonisolated(unsafe) static let cellFont: NSFont = .systemFont(ofSize: 13, weight: .regular)

    nonisolated init(attachment: TableAttachment) {
        self.attachment = attachment
        // loadView() is always called on the main thread by AppKit's text system
        super.init(frame: .zero)
        MainActor.assumeIsolated {
            self.wantsLayer = true
            self.layer?.cornerRadius = Self.cornerRadius
            self.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            self.layer?.borderColor = NSColor.separatorColor.cgColor
            self.layer?.borderWidth = 1
            self.buildGrid()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout Constants

    private var columnCount: Int {
        max(attachment?.headers.count ?? 1, 1)
    }

    private var rowCount: Int {
        attachment?.rows.count ?? 0
    }

    private func computeHeight() -> CGFloat {
        // padding + header row + separator + data rows + padding
        let totalRows = 1 + rowCount
        return Self.padding * 2
            + CGFloat(totalRows) * Self.rowHeight
            + Self.separatorHeight
    }

    // MARK: - Intrinsic Content Size

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.maxWidth, height: computeHeight())
    }

    // MARK: - Build Grid

    private func buildGrid() {
        // Remove old subviews
        subviews.forEach { $0.removeFromSuperview() }
        cellFields = []

        guard let attachment else { return }

        // Separator line between header and data rows
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let totalWidth = Self.maxWidth - Self.padding * 2
        let colWidth = totalWidth / CGFloat(columnCount)

        // Header row
        var headerFields: [NSTextField] = []
        for col in 0..<columnCount {
            let field = makeTextField(
                text: col < attachment.headers.count ? attachment.headers[col] : "",
                font: Self.headerFont,
                alignment: textAlignment(for: col),
                row: -1,
                col: col
            )
            addSubview(field)
            headerFields.append(field)

            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: Self.padding + CGFloat(col) * colWidth + Self.cellPadding
                ),
                field.widthAnchor.constraint(equalToConstant: colWidth - Self.cellPadding * 2),
                field.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
                field.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            ])
        }
        cellFields.append(headerFields)

        // Separator constraints
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),
            separator.topAnchor.constraint(
                equalTo: topAnchor,
                constant: Self.padding + Self.rowHeight
            ),
            separator.heightAnchor.constraint(equalToConstant: Self.separatorHeight),
        ])

        // Data rows
        for row in 0..<rowCount {
            var rowFields: [NSTextField] = []
            for col in 0..<columnCount {
                let cellValue: String
                if row < attachment.rows.count && col < attachment.rows[row].count {
                    cellValue = attachment.rows[row][col]
                } else {
                    cellValue = ""
                }

                let field = makeTextField(
                    text: cellValue,
                    font: Self.cellFont,
                    alignment: textAlignment(for: col),
                    row: row,
                    col: col
                )
                addSubview(field)
                rowFields.append(field)

                let topOffset = Self.padding
                    + Self.rowHeight  // header
                    + Self.separatorHeight
                    + CGFloat(row) * Self.rowHeight

                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(
                        equalTo: leadingAnchor,
                        constant: Self.padding + CGFloat(col) * colWidth + Self.cellPadding
                    ),
                    field.widthAnchor.constraint(equalToConstant: colWidth - Self.cellPadding * 2),
                    field.topAnchor.constraint(equalTo: topAnchor, constant: topOffset),
                    field.heightAnchor.constraint(equalToConstant: Self.rowHeight),
                ])
            }
            cellFields.append(rowFields)
        }

        invalidateIntrinsicContentSize()
    }

    // MARK: - Text Field Factory

    private func makeTextField(
        text: String,
        font: NSFont,
        alignment: NSTextAlignment,
        row: Int,
        col: Int
    ) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.font = font
        field.alignment = alignment
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .exterior
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.delegate = self
        // Store cell coordinates in tag: encode row+1 (header is row 0) and col
        // Tag encoding: (gridRow * 1000) + col where gridRow 0 = header, 1.. = data rows
        let gridRow = row + 1  // -1 becomes 0 (header), 0 becomes 1, etc.
        field.tag = gridRow * 1000 + col
        return field
    }

    private func textAlignment(for col: Int) -> NSTextAlignment {
        guard let attachment, col < attachment.alignments.count else { return .left }
        switch attachment.alignments[col] {
        case .left:   return .left
        case .center: return .center
        case .right:  return .right
        }
    }

    // MARK: - Cell Coordinate Decoding

    private func gridRow(for tag: Int) -> Int { tag / 1000 }
    private func gridCol(for tag: Int) -> Int { tag % 1000 }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let attachment else { return }

        let gRow = gridRow(for: field.tag)
        let col = gridCol(for: field.tag)
        let value = field.stringValue

        if gRow == 0 {
            // Header
            if col < attachment.headers.count {
                attachment.headers[col] = value
            }
        } else {
            // Data row (gRow is 1-based)
            let dataRow = gRow - 1
            if dataRow < attachment.rows.count && col < attachment.rows[dataRow].count {
                attachment.rows[dataRow][col] = value
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            selectNextCell(from: control as! NSTextField, forward: true)
            return true
        } else if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            selectNextCell(from: control as! NSTextField, forward: false)
            return true
        }
        return false
    }

    // MARK: - Tab Navigation

    private func selectNextCell(from field: NSTextField, forward: Bool) {
        let gRow = gridRow(for: field.tag)
        let col = gridCol(for: field.tag)

        // Flatten cell grid to find next/previous
        let totalCols = columnCount
        var flatIndex = gRow * totalCols + col

        if forward {
            flatIndex += 1
        } else {
            flatIndex -= 1
        }

        let totalCells = cellFields.count * totalCols
        if totalCells == 0 { return }

        // Wrap around
        flatIndex = ((flatIndex % totalCells) + totalCells) % totalCells

        let nextRow = flatIndex / totalCols
        let nextCol = flatIndex % totalCols

        if nextRow < cellFields.count && nextCol < cellFields[nextRow].count {
            window?.makeFirstResponder(cellFields[nextRow][nextCol])
        }
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        // Determine which data row was clicked (if any)
        let locationInView = convert(event.locationInWindow, from: nil)
        let clickedDataRow = dataRowIndex(at: locationInView)

        let addRowItem = NSMenuItem(title: "Add Row Below", action: #selector(contextAddRow(_:)), keyEquivalent: "")
        addRowItem.target = self
        addRowItem.representedObject = clickedDataRow
        menu.addItem(addRowItem)

        if clickedDataRow != nil && (attachment?.rows.count ?? 0) > 1 {
            let removeRowItem = NSMenuItem(title: "Remove Row", action: #selector(contextRemoveRow(_:)), keyEquivalent: "")
            removeRowItem.target = self
            removeRowItem.representedObject = clickedDataRow
            menu.addItem(removeRowItem)
        }

        menu.addItem(.separator())

        let addColItem = NSMenuItem(title: "Add Column", action: #selector(contextAddColumn(_:)), keyEquivalent: "")
        addColItem.target = self
        menu.addItem(addColItem)

        if columnCount > 1 {
            let clickedCol = columnIndex(at: locationInView)
            let removeColItem = NSMenuItem(title: "Remove Column", action: #selector(contextRemoveColumn(_:)), keyEquivalent: "")
            removeColItem.target = self
            removeColItem.representedObject = clickedCol
            menu.addItem(removeColItem)
        }

        return menu
    }

    private func dataRowIndex(at point: NSPoint) -> Int? {
        // Point is in flipped coordinates (NSView is not flipped by default)
        // topAnchor-based layout: header starts at padding from top
        let headerBottom = Self.padding + Self.rowHeight + Self.separatorHeight
        guard point.y < frame.height - headerBottom else { return nil }
        let offsetFromHeaderBottom = (frame.height - headerBottom) - point.y
        let row = Int(offsetFromHeaderBottom / Self.rowHeight)
        guard row >= 0 && row < rowCount else { return nil }
        return row
    }

    private func columnIndex(at point: NSPoint) -> Int? {
        let totalWidth = Self.maxWidth - Self.padding * 2
        let colWidth = totalWidth / CGFloat(columnCount)
        let offsetX = point.x - Self.padding
        guard offsetX >= 0 else { return nil }
        let col = Int(offsetX / colWidth)
        guard col >= 0 && col < columnCount else { return nil }
        return col
    }

    // MARK: - Context Menu Actions

    @objc private func contextAddRow(_ sender: NSMenuItem) {
        attachment?.addRow()
        rebuildAndInvalidate()
    }

    @objc private func contextRemoveRow(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        attachment?.removeRow(at: row)
        rebuildAndInvalidate()
    }

    @objc private func contextAddColumn(_ sender: NSMenuItem) {
        attachment?.addColumn()
        rebuildAndInvalidate()
    }

    @objc private func contextRemoveColumn(_ sender: NSMenuItem) {
        guard let col = sender.representedObject as? Int else { return }
        attachment?.removeColumn(at: col)
        rebuildAndInvalidate()
    }

    private func rebuildAndInvalidate() {
        buildGrid()
    }
}
