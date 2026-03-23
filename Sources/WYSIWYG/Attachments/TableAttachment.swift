// Sources/WYSIWYG/Attachments/TableAttachment.swift
import AppKit

enum ColumnAlignment: Equatable, Sendable {
    case left, center, right
}

final class TableAttachment: NSTextAttachment, MarkdownBlockAttachment {

    var headers: [String]
    var rows: [[String]]
    var alignments: [ColumnAlignment]

    // MARK: - Static Image Constants

    private static let tableWidth: CGFloat = 520
    private static let rowHeight: CGFloat = 28
    private static let cornerRadius: CGFloat = 6
    private static let gridLine: CGFloat = 1
    private static let cellHPadding: CGFloat = 8
    private static let hintHeight: CGFloat = 20
    private static nonisolated(unsafe) let headerFont: NSFont = .systemFont(ofSize: 12, weight: .semibold)
    private static nonisolated(unsafe) let cellFont: NSFont = .systemFont(ofSize: 12, weight: .regular)
    private static nonisolated(unsafe) let hintFont: NSFont = .systemFont(ofSize: 10, weight: .regular)

    init(headers: [String], rows: [[String]], alignments: [ColumnAlignment]) {
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
        super.init(data: nil, ofType: nil)
        refreshImage()
    }

    required init?(coder: NSCoder) {
        self.headers = (coder.decodeObject(forKey: "headers") as? [String]) ?? []
        self.rows = (coder.decodeObject(forKey: "rows") as? [[String]]) ?? []
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
        refreshImage()
    }

    // MARK: - Static Image Rendering

    func refreshImage() {
        let columnCount = max(headers.count, 1)
        let totalDataRows = 1 + rows.count
        let gridHeight = CGFloat(totalDataRows) * Self.rowHeight
            + Self.gridLine * CGFloat(totalDataRows + 1)
        let totalHeight = gridHeight + Self.hintHeight
        let size = NSSize(width: Self.tableWidth, height: totalHeight)

        let img = NSImage(size: size, flipped: false) { rect in
            let colWidth = rect.width / CGFloat(columnCount)

            // Background rounded rect
            let bgPath = NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
            NSColor.controlBackgroundColor.setFill()
            bgPath.fill()

            // In non-flipped coordinates: y=0 is bottom, y=max is top
            // Layout: hint at bottom, then data rows going up, header at top

            // Header background at top
            let headerY = rect.height - Self.hintHeight - Self.rowHeight - Self.gridLine
            let headerBgRect = NSRect(x: 0, y: headerY, width: rect.width, height: Self.rowHeight + Self.gridLine)
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            bgPath.addClip()
            NSBezierPath(rect: headerBgRect).fill()

            // Reset clipping
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()

            // Outer border
            let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                          xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
            NSColor.separatorColor.setStroke()
            borderPath.lineWidth = Self.gridLine
            borderPath.stroke()

            // Hint text at very bottom
            let hintAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.hintFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let hint = "[Double-click to edit]"
            let hintRect = NSRect(
                x: Self.cellHPadding,
                y: 2,
                width: rect.width - Self.cellHPadding * 2,
                height: Self.hintHeight
            )
            (hint as NSString).draw(in: hintRect, withAttributes: hintAttrs)

            // Draw header text at top
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.headerFont,
                .foregroundColor: NSColor.labelColor,
            ]
            for col in 0..<columnCount {
                let text = col < self.headers.count ? self.headers[col] : ""
                let cellRect = NSRect(
                    x: CGFloat(col) * colWidth + Self.cellHPadding,
                    y: headerY + 4,
                    width: colWidth - Self.cellHPadding * 2,
                    height: Self.rowHeight - 4
                )
                (text as NSString).draw(in: cellRect, withAttributes: headerAttrs)
            }

            // Separator below header
            NSColor.separatorColor.setStroke()
            let sepY = headerY
            let sep = NSBezierPath()
            sep.move(to: NSPoint(x: 0, y: sepY))
            sep.line(to: NSPoint(x: rect.width, y: sepY))
            sep.lineWidth = Self.gridLine
            sep.stroke()

            // Data rows (going down from header)
            let cellAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.cellFont,
                .foregroundColor: NSColor.labelColor,
            ]
            for row in 0..<self.rows.count {
                let rowY = headerY - CGFloat(row + 1) * Self.rowHeight - Self.gridLine
                for col in 0..<columnCount {
                    let text: String
                    if col < self.rows[row].count {
                        text = self.rows[row][col]
                    } else {
                        text = ""
                    }
                    let cellRect = NSRect(
                        x: CGFloat(col) * colWidth + Self.cellHPadding,
                        y: rowY + 4,
                        width: colWidth - Self.cellHPadding * 2,
                        height: Self.rowHeight - 4
                    )
                    (text as NSString).draw(in: cellRect, withAttributes: cellAttrs)
                }

                // Row separator
                let rowSep = NSBezierPath()
                rowSep.move(to: NSPoint(x: 0, y: rowY))
                rowSep.line(to: NSPoint(x: rect.width, y: rowY))
                rowSep.lineWidth = Self.gridLine
                rowSep.stroke()
            }

            // Vertical grid lines between columns
            let gridBottom = Self.hintHeight
            let gridTop = rect.height - Self.hintHeight
            for col in 1..<columnCount {
                let x = CGFloat(col) * colWidth
                let vLine = NSBezierPath()
                vLine.move(to: NSPoint(x: x, y: gridBottom))
                vLine.line(to: NSPoint(x: x, y: gridTop))
                vLine.lineWidth = Self.gridLine
                vLine.stroke()
            }

            return true
        }

        self.image = img
        self.bounds = CGRect(origin: .zero, size: size)
    }

    // MARK: - Open Panel Editor

    @MainActor
    static func openEditor(for attachment: TableAttachment, in textView: NSTextView) {
        let panel = TableEditorPanel(attachment: attachment) {
            // Save position
            let savedSelection = textView.selectedRange()
            let savedScroll = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero

            // Refresh the static preview image
            attachment.refreshImage()

            // Invalidate layout so the new image is displayed
            if let storage = textView.textStorage {
                let fullRange = NSRange(location: 0, length: storage.length)
                storage.edited(.editedAttributes, range: fullRange, changeInLength: 0)
            }

            // Trigger serialization so document.text gets updated
            NotificationCenter.default.post(name: NSText.didChangeNotification, object: textView)

            // Restore position on next run loop tick (after layout completes)
            DispatchQueue.main.async {
                textView.setSelectedRange(savedSelection)
                textView.enclosingScrollView?.contentView.scroll(to: savedScroll)
                textView.enclosingScrollView?.reflectScrolledClipView(textView.enclosingScrollView!.contentView)
            }
        }
        panel.makeKeyAndOrderFront(nil)
        // Position near the text view's window
        if let parentWindow = textView.window {
            let parentFrame = parentWindow.frame
            let panelSize = panel.frame.size
            let x = parentFrame.midX - panelSize.width / 2
            let y = parentFrame.midY - panelSize.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
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

// MARK: - Table Editor Panel

@MainActor
final class TableEditorPanel: NSPanel, NSTextFieldDelegate {

    private let attachment: TableAttachment
    private let onClose: () -> Void
    private var gridContainer: NSView!
    private var scrollView: NSScrollView!
    /// Snapshot of the table data at open time, for dirty checking
    private var originalMarkdown: String = ""

    init(attachment: TableAttachment, onClose: @escaping () -> Void) {
        self.attachment = attachment
        self.onClose = onClose

        let contentRect = NSRect(x: 0, y: 0, width: 560, height: 400)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        self.title = "Edit Table"
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 360, height: 250)
        self.originalMarkdown = attachment.serializeToMarkdown()

        buildUI()
    }

    private var isDirty: Bool {
        commitCurrentField()
        return attachment.serializeToMarkdown() != originalMarkdown
    }

    override func close() {
        commitCurrentField()
        if attachment.serializeToMarkdown() != originalMarkdown {
            let alert = NSAlert()
            alert.messageText = "Save table changes?"
            alert.informativeText = "You have unsaved changes to this table."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Save
                onClose()
                super.close()
            case .alertSecondButtonReturn:
                // Discard — restore original data
                // Re-parse original markdown to restore attachment state
                // Simplest: just close without calling onClose
                super.close()
            default:
                // Cancel — don't close
                return
            }
        } else {
            super.close()
        }
    }

    /// Called by Done button — always saves
    private func saveAndClose() {
        commitCurrentField()
        onClose()
        // Skip the close() override prompt by calling super directly
        super.close()
    }

    // MARK: - Build UI

    private func buildUI() {
        let root = NSView(frame: contentView!.bounds)
        root.autoresizingMask = [.width, .height]

        // Scroll view for the table grid
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 44, width: root.bounds.width, height: root.bounds.height - 44))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder

        gridContainer = FlippedView()
        gridContainer.autoresizingMask = []
        scrollView.documentView = gridContainer
        root.addSubview(scrollView)

        // Button bar at bottom
        let buttonBar = NSView(frame: NSRect(x: 0, y: 0, width: root.bounds.width, height: 44))
        buttonBar.autoresizingMask = [.width]

        let addRowBtn = makeButton(title: "+ Row", action: #selector(addRowClicked))
        addRowBtn.frame.origin = NSPoint(x: 8, y: 8)
        buttonBar.addSubview(addRowBtn)

        let removeRowBtn = makeButton(title: "- Row", action: #selector(removeRowClicked))
        removeRowBtn.frame.origin = NSPoint(x: 78, y: 8)
        buttonBar.addSubview(removeRowBtn)

        let addColBtn = makeButton(title: "+ Column", action: #selector(addColumnClicked))
        addColBtn.frame.origin = NSPoint(x: 158, y: 8)
        buttonBar.addSubview(addColBtn)

        let removeColBtn = makeButton(title: "- Column", action: #selector(removeColumnClicked))
        removeColBtn.frame.origin = NSPoint(x: 248, y: 8)
        buttonBar.addSubview(removeColBtn)

        let doneBtn = makeButton(title: "Done", action: #selector(doneClicked))
        doneBtn.frame.origin = NSPoint(x: root.bounds.width - 78, y: 8)
        doneBtn.autoresizingMask = [.minXMargin]
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        buttonBar.addSubview(doneBtn)

        root.addSubview(buttonBar)
        contentView = root

        rebuildGrid()
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        btn.sizeToFit()
        return btn
    }

    // MARK: - Grid Layout

    private func rebuildGrid() {
        gridContainer.subviews.forEach { $0.removeFromSuperview() }

        let columnCount = max(attachment.headers.count, 1)
        let colWidth: CGFloat = 140
        let rowHeight: CGFloat = 28
        let totalWidth = CGFloat(columnCount) * colWidth
        let totalRows = 1 + attachment.rows.count
        let totalHeight = CGFloat(totalRows) * rowHeight

        gridContainer.frame = NSRect(x: 0, y: 0, width: max(totalWidth, scrollView.bounds.width), height: max(totalHeight, scrollView.bounds.height))

        // Header fields (y=0 is top in flipped view)
        for col in 0..<columnCount {
            let field = makeTextField(
                text: col < attachment.headers.count ? attachment.headers[col] : "",
                bold: true,
                tag: col  // tag encodes: row * 10000 + col, row 0 = header
            )
            field.frame = NSRect(
                x: CGFloat(col) * colWidth + 2,
                y: 0,
                width: colWidth - 4,
                height: rowHeight
            )
            gridContainer.addSubview(field)
        }

        // Data rows (top-down in flipped coordinates)
        for row in 0..<attachment.rows.count {
            for col in 0..<columnCount {
                let text: String
                if col < attachment.rows[row].count {
                    text = attachment.rows[row][col]
                } else {
                    text = ""
                }
                let field = makeTextField(
                    text: text,
                    bold: false,
                    tag: (row + 1) * 10000 + col
                )
                field.frame = NSRect(
                    x: CGFloat(col) * colWidth + 2,
                    y: CGFloat(row + 1) * rowHeight,
                    width: colWidth - 4,
                    height: rowHeight
                )
                gridContainer.addSubview(field)
            }
        }
    }

    private func makeTextField(text: String, bold: Bool, tag: Int) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.font = bold ? .systemFont(ofSize: 12, weight: .semibold) : .systemFont(ofSize: 12)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.tag = tag
        field.target = self
        field.action = #selector(cellEdited(_:))
        field.delegate = self
        return field
    }

    // MARK: - Tab / Return Navigation

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? NSTextField else { return false }
        let tag = field.tag
        let row = tag / 10000
        let col = tag % 10000
        let columnCount = max(attachment.headers.count, 1)
        let totalRows = 1 + attachment.rows.count

        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            // Tab: move to next cell (right, wrap to next row)
            cellEdited(field)
            let nextCol = col + 1
            if nextCol < columnCount {
                focusCell(row: row, col: nextCol)
            } else if row + 1 < totalRows {
                focusCell(row: row + 1, col: 0)
            } else {
                focusCell(row: 0, col: 0)
            }
            return true
        }

        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            // Shift+Tab: move to previous cell
            cellEdited(field)
            let prevCol = col - 1
            if prevCol >= 0 {
                focusCell(row: row, col: prevCol)
            } else if row > 0 {
                focusCell(row: row - 1, col: columnCount - 1)
            } else {
                focusCell(row: totalRows - 1, col: columnCount - 1)
            }
            return true
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Return: move to same column in next row
            cellEdited(field)
            let nextRow = row + 1
            if nextRow < totalRows {
                focusCell(row: nextRow, col: col)
            } else {
                focusCell(row: 0, col: col)
            }
            return true
        }

        return false
    }

    private func focusCell(row: Int, col: Int) {
        let targetTag = row * 10000 + col
        for subview in gridContainer.subviews {
            if let field = subview as? NSTextField, field.tag == targetTag {
                makeFirstResponder(field)
                return
            }
        }
    }

    // MARK: - Cell Editing

    @objc private func cellEdited(_ sender: NSTextField) {
        let tag = sender.tag
        let row = tag / 10000
        let col = tag % 10000

        if row == 0 {
            // Header
            if col < attachment.headers.count {
                attachment.headers[col] = sender.stringValue
            }
        } else {
            let dataRow = row - 1
            if dataRow < attachment.rows.count && col < attachment.rows[dataRow].count {
                attachment.rows[dataRow][col] = sender.stringValue
            }
        }
    }

    // MARK: - Button Actions

    @objc private func addRowClicked(_ sender: Any) {
        commitCurrentField()
        attachment.addRow()
        rebuildGrid()
    }

    @objc private func removeRowClicked(_ sender: Any) {
        commitCurrentField()
        guard attachment.rows.count > 1 else { return }
        attachment.removeRow(at: attachment.rows.count - 1)
        rebuildGrid()
    }

    @objc private func addColumnClicked(_ sender: Any) {
        commitCurrentField()
        attachment.addColumn()
        rebuildGrid()
    }

    @objc private func removeColumnClicked(_ sender: Any) {
        commitCurrentField()
        guard attachment.headers.count > 1 else { return }
        attachment.removeColumn(at: attachment.headers.count - 1)
        rebuildGrid()
    }

    @objc private func doneClicked(_ sender: Any) {
        saveAndClose()
    }

    /// Commit all field values back to the attachment data.
    private func commitCurrentField() {
        // End any active field editing
        makeFirstResponder(nil)
        // Walk all text fields and sync their values to the attachment
        for subview in gridContainer.subviews {
            guard let field = subview as? NSTextField else { continue }
            cellEdited(field)
        }
    }
}

// MARK: - Flipped NSView for top-down layout

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
