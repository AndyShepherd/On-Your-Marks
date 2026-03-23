// Sources/WYSIWYG/SlashCommandMenu.swift
import AppKit

// MARK: - SlashCommand

struct SlashCommand: Sendable {
    let name: String
    let label: String
    let icon: String  // SF Symbol name
}

// MARK: - SlashCommandMenu

@MainActor
final class SlashCommandMenu: NSObject {

    // MARK: Static command list

    nonisolated static let allCommands: [SlashCommand] = [
        SlashCommand(name: "heading",  label: "Heading",      icon: "textformat.size"),
        SlashCommand(name: "bullet",   label: "Bullet List",  icon: "list.bullet"),
        SlashCommand(name: "numbered", label: "Numbered List", icon: "list.number"),
        SlashCommand(name: "task",     label: "Task List",    icon: "checklist"),
        SlashCommand(name: "quote",    label: "Blockquote",   icon: "text.quote"),
        SlashCommand(name: "code",     label: "Code Block",   icon: "chevron.left.forwardslash.chevron.right"),
        SlashCommand(name: "table",    label: "Table",        icon: "tablecells"),
        SlashCommand(name: "image",    label: "Image",        icon: "photo"),
        SlashCommand(name: "divider",  label: "Divider",      icon: "minus"),
    ]

    // MARK: Private state

    private var popover: NSPopover?
    private var controller: SlashCommandViewController?
    private var onSelect: ((SlashCommand) -> Void)?

    // MARK: Public API

    var isShowing: Bool { popover?.isShown ?? false }

    /// Show the popover anchored to `rect` inside `view`.
    /// - Parameters:
    ///   - rect: The bounding rect of the cursor (in `view` coordinates).
    ///   - view: The view that owns the cursor.
    ///   - filter: Initial filter string (the text typed after `/`).
    ///   - onSelect: Called when the user picks a command.
    func show(relativeTo rect: NSRect,
              of view: NSView,
              filter: String,
              onSelect: @escaping (SlashCommand) -> Void) {
        self.onSelect = onSelect

        // Reuse existing popover if already visible
        if let existing = popover, existing.isShown {
            updateFilter(filter)
            return
        }

        let vc = SlashCommandViewController()
        vc.delegate = self
        self.controller = vc

        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.animates = false
        self.popover = pop

        vc.applyFilter(filter)

        pop.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    /// Update the filter string while the popover is visible.
    func updateFilter(_ filter: String) {
        controller?.applyFilter(filter)
    }

    /// Close the popover without selecting a command.
    func dismiss() {
        popover?.close()
        popover = nil
        controller = nil
        onSelect = nil
    }
}

// MARK: - SlashCommandMenuDelegate (internal)

extension SlashCommandMenu: SlashCommandViewControllerDelegate {
    func slashCommandViewController(_ vc: SlashCommandViewController,
                                    didSelect command: SlashCommand) {
        let handler = onSelect
        dismiss()
        handler?(command)
    }

    func slashCommandViewControllerDidCancel(_ vc: SlashCommandViewController) {
        dismiss()
    }
}

// MARK: - SlashCommandViewController

@MainActor
protocol SlashCommandViewControllerDelegate: AnyObject {
    func slashCommandViewController(_ vc: SlashCommandViewController,
                                    didSelect command: SlashCommand)
    func slashCommandViewControllerDidCancel(_ vc: SlashCommandViewController)
}

@MainActor
final class SlashCommandViewController: NSViewController {

    weak var delegate: SlashCommandViewControllerDelegate?

    private var filteredCommands: [SlashCommand] = SlashCommandMenu.allCommands
    private var selectedIndex: Int = 0

    // MARK: Views

    private let scrollView = NSScrollView()
    private let stackView: NSStackView = {
        let sv = NSStackView()
        sv.orientation = .vertical
        sv.spacing = 2
        sv.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        sv.alignment = .leading
        return sv
    }()

    // MARK: Lifecycle

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 280))
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        self.view = container

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let clipView = scrollView.contentView
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
        ])

        rebuildRows()
    }

    // MARK: Filtering

    func applyFilter(_ filter: String) {
        if filter.isEmpty {
            filteredCommands = SlashCommandMenu.allCommands
        } else {
            let lower = filter.lowercased()
            filteredCommands = SlashCommandMenu.allCommands.filter {
                $0.name.lowercased().hasPrefix(lower) ||
                $0.label.lowercased().hasPrefix(lower)
            }
        }
        selectedIndex = 0
        rebuildRows()
    }

    // MARK: Navigation

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: // Down arrow
            moveSelection(by: 1)
        case 126: // Up arrow
            moveSelection(by: -1)
        case 36, 76: // Return / Enter
            confirmSelection()
        case 53: // Escape
            delegate?.slashCommandViewControllerDidCancel(self)
        default:
            super.keyDown(with: event)
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filteredCommands.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + filteredCommands.count) % filteredCommands.count
        updateRowHighlights()
    }

    private func confirmSelection() {
        guard filteredCommands.indices.contains(selectedIndex) else { return }
        delegate?.slashCommandViewController(self, didSelect: filteredCommands[selectedIndex])
    }

    // MARK: Row building

    private func rebuildRows() {
        for sub in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        for (index, command) in filteredCommands.enumerated() {
            let row = makeRowView(for: command, index: index)
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -8).isActive = true
        }

        updateRowHighlights()
    }

    private func makeRowView(for command: SlashCommand, index: Int) -> NSView {
        let row = SlashCommandRowView(command: command, index: index, owner: self)
        return row
    }

    private func updateRowHighlights() {
        for (index, view) in stackView.arrangedSubviews.enumerated() {
            (view as? SlashCommandRowView)?.setHighlighted(index == selectedIndex)
        }
    }

    // MARK: Row tap

    fileprivate func rowTapped(at index: Int) {
        guard filteredCommands.indices.contains(index) else { return }
        selectedIndex = index
        confirmSelection()
    }
}

// MARK: - SlashCommandRowView

@MainActor
private final class SlashCommandRowView: NSView {

    private let command: SlashCommand
    private let index: Int
    private weak var owner: SlashCommandViewController?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let highlightLayer = CALayer()

    init(command: SlashCommand, index: Int, owner: SlashCommandViewController) {
        self.command = command
        self.index = index
        self.owner = owner
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true

        // Icon
        let image = NSImage(systemSymbolName: command.icon, accessibilityDescription: command.label)
        iconView.image = image
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = .labelColor
        addSubview(iconView)

        // Label
        label.stringValue = command.label
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Click gesture
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }

    func setHighlighted(_ highlighted: Bool) {
        layer?.backgroundColor = highlighted
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor
    }

    @objc private func handleClick() {
        owner?.rowTapped(at: index)
    }
}
