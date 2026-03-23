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
        updateBounds()
    }

    func updateBounds() {
        let totalRows = 1 + rows.count
        let height = CGFloat(totalRows) * TableAttachmentView.tableRowHeight
            + TableAttachmentView.tableGridLine * CGFloat(totalRows + 1)
        self.bounds = CGRect(x: 0, y: 0, width: TableAttachmentView.tableWidth, height: height)
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
        let width = TableAttachmentView.tableWidth
        let totalRows = 1 + attachment.rows.count
        let height = CGFloat(totalRows) * TableAttachmentView.tableRowHeight
            + TableAttachmentView.tableGridLine * CGFloat(totalRows + 1)
        // loadView is always called on the main thread by TextKit.
        // Use nonisolated(unsafe) to bridge the concurrency boundary.
        nonisolated(unsafe) let att = attachment
        nonisolated(unsafe) let selfRef = self
        MainActor.assumeIsolated {
            let tableView = TableAttachmentView(attachment: att)
            tableView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
            selfRef.view = tableView
        }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        guard let attachment = self.textAttachment as? TableAttachment else {
            return .zero
        }
        let rows = attachment.rows.count
        let width = min(TableAttachmentView.tableWidth, proposedLineFragment.width)
        let totalRows = 1 + rows
        let height = CGFloat(totalRows) * TableAttachmentView.tableRowHeight
            + TableAttachmentView.tableGridLine * CGFloat(totalRows + 1)
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

// MARK: - Interactive Table View

final class TableAttachmentView: NSView, NSTextFieldDelegate {

    private nonisolated(unsafe) var attachment: TableAttachment?
    private var cellFields: [[NSTextField]] = []

    private static let cornerRadius: CGFloat = 6
    static nonisolated let tableWidth: CGFloat = 520
    static nonisolated let tableRowHeight: CGFloat = 32
    private static let cellHPadding: CGFloat = 8
    static nonisolated let tableGridLine: CGFloat = 1
    private nonisolated(unsafe) static let headerFont: NSFont = .systemFont(ofSize: 13, weight: .semibold)
    private nonisolated(unsafe) static let cellFont: NSFont = .systemFont(ofSize: 13, weight: .regular)

    // Use flipped coordinates so top-down layout works naturally
    override var isFlipped: Bool { true }

    // Ensure mouse events reach buttons and text fields inside the attachment
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Check subviews first (buttons, text fields)
        for subview in subviews.reversed() {
            let converted = subview.convert(point, from: self)
            if let hit = subview.hitTest(converted) {
                return hit
            }
        }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let target = hitTest(point), target !== self {
            target.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    private static let buttonSize: CGFloat = 24

    init(attachment: TableAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.cornerRadius = Self.cornerRadius
        self.layer?.masksToBounds = true
        self.buildGrid()
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

    private var totalGridRows: Int { 1 + rowCount }

    private func gridHeight() -> CGFloat {
        CGFloat(totalGridRows) * Self.tableRowHeight + Self.tableGridLine * CGFloat(totalGridRows + 1)
    }

    private func computeHeight() -> CGFloat {
        gridHeight()
    }

    // MARK: - Intrinsic Content Size

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.tableWidth, height: computeHeight())
    }

    // MARK: - Draw grid lines and backgrounds

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let totalWidth = bounds.width
        let colWidth = totalWidth / CGFloat(columnCount)
        let gw = Self.tableGridLine

        // Outer border
        let borderPath = NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSColor.separatorColor.setStroke()
        borderPath.lineWidth = gw
        borderPath.stroke()

        // Header background
        let headerRect = NSRect(x: 0, y: 0, width: totalWidth, height: Self.tableRowHeight + gw)
        NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(rect: headerRect).fill()

        // Horizontal grid lines
        NSColor.separatorColor.setStroke()
        for gridRow in 1...totalGridRows {
            let y = CGFloat(gridRow) * Self.tableRowHeight + gw * CGFloat(gridRow)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: y))
            line.line(to: NSPoint(x: totalWidth, y: y))
            line.lineWidth = gw
            line.stroke()
        }

        // Vertical grid lines (between columns)
        for col in 1..<columnCount {
            let x = CGFloat(col) * colWidth
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: 0))
            line.line(to: NSPoint(x: x, y: bounds.height))
            line.lineWidth = gw
            line.stroke()
        }
    }

    // MARK: - Build Grid

    private func buildGrid() {
        subviews.forEach { $0.removeFromSuperview() }
        cellFields = []

        guard let attachment else { return }

        let colWidth = Self.tableWidth / CGFloat(columnCount)
        let gw = Self.tableGridLine

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

            field.frame = NSRect(
                x: CGFloat(col) * colWidth + Self.cellHPadding,
                y: gw,
                width: colWidth - Self.cellHPadding * 2,
                height: Self.tableRowHeight
            )
        }
        cellFields.append(headerFields)

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

                let y = CGFloat(row + 1) * Self.tableRowHeight + gw * CGFloat(row + 2)
                field.frame = NSRect(
                    x: CGFloat(col) * colWidth + Self.cellHPadding,
                    y: y,
                    width: colWidth - Self.cellHPadding * 2,
                    height: Self.tableRowHeight
                )
            }
            cellFields.append(rowFields)
        }

        invalidateIntrinsicContentSize()
        setNeedsDisplay(bounds)
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
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        field.placeholderString = row == -1 ? "Header" : ""
        let gridRow = row + 1
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

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

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
        // Flipped coordinates — y=0 is top
        let gw = Self.tableGridLine
        let headerBottom = Self.tableRowHeight + gw * 2
        guard point.y > headerBottom else { return nil }
        let offsetFromHeaderBottom = point.y - headerBottom
        let row = Int(offsetFromHeaderBottom / (Self.tableRowHeight + gw))
        guard row >= 0 && row < rowCount else { return nil }
        return row
    }

    private func columnIndex(at point: NSPoint) -> Int? {
        let colWidth = Self.tableWidth / CGFloat(columnCount)
        let col = Int(point.x / colWidth)
        guard col >= 0 && col < columnCount else { return nil }
        return col
    }

    // MARK: - Context Menu Actions

    @objc private func contextAddRow(_ sender: Any) {
        attachment?.addRow()
        rebuildAndInvalidate()
    }

    @objc private func contextRemoveRow(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        attachment?.removeRow(at: row)
        rebuildAndInvalidate()
    }

    @objc private func contextAddColumn(_ sender: Any) {
        attachment?.addColumn()
        rebuildAndInvalidate()
    }

    @objc private func contextRemoveColumn(_ sender: NSMenuItem) {
        guard let col = sender.representedObject as? Int else { return }
        attachment?.removeColumn(at: col)
        rebuildAndInvalidate()
    }

    @objc private func removeLastRow(_ sender: Any) {
        guard let attachment, attachment.rows.count > 1 else { return }
        attachment.removeRow(at: attachment.rows.count - 1)
        rebuildAndInvalidate()
    }

    @objc private func removeLastColumn(_ sender: Any) {
        guard let attachment, attachment.headers.count > 1 else { return }
        attachment.removeColumn(at: attachment.headers.count - 1)
        rebuildAndInvalidate()
    }

    private func rebuildAndInvalidate() {
        // Trigger a full document re-render by posting a textDidChange-like
        // notification. The WYSIWYG coordinator will serialize → re-parse → re-render,
        // which recreates the table attachment at the correct size.
        if let textView = findParentTextView() {
            // Mark the text storage as edited so the coordinator picks it up
            NotificationCenter.default.post(
                name: NSText.didChangeNotification,
                object: textView
            )
        }
    }

    private func findParentTextView() -> NSTextView? {
        var current: NSView? = superview
        while let view = current {
            if let textView = view as? NSTextView { return textView }
            current = view.superview
        }
        return nil
    }
}
