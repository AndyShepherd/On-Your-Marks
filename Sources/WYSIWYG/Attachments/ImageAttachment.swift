// Sources/WYSIWYG/Attachments/ImageAttachment.swift
import AppKit

final class ImageAttachment: NSTextAttachment, MarkdownBlockAttachment {

    let source: String
    let altText: String

    private static let maxWidth: CGFloat = 400
    private static let padding: CGFloat = 10
    private static let iconSize: CGFloat = 40
    private static let captionHeight: CGFloat = 18
    private static let cornerRadius: CGFloat = 6
    private nonisolated(unsafe) static let captionFont: NSFont = .systemFont(ofSize: 11, weight: .regular)

    init(source: String, altText: String) {
        self.source = source
        self.altText = altText
        super.init(data: nil, ofType: nil)
        let img = Self.makeImage(source: source, altText: altText)
        self.image = img
        self.bounds = CGRect(x: 0, y: -4, width: img.size.width, height: img.size.height)
    }

    required init?(coder: NSCoder) {
        self.source = (coder.decodeObject(forKey: "source") as? String) ?? ""
        self.altText = (coder.decodeObject(forKey: "altText") as? String) ?? ""
        super.init(coder: coder)
        let img = Self.makeImage(source: self.source, altText: self.altText)
        self.image = img
        self.bounds = CGRect(x: 0, y: -4, width: img.size.width, height: img.size.height)
    }

    nonisolated func serializeToMarkdown() -> String {
        "![\(altText)](\(source))\n"
    }

    // MARK: - Private

    private static func canvasHeight(altText: String, width: CGFloat) -> CGFloat {
        let captionAreaWidth = width - padding * 2
        let hasCaption = !altText.isEmpty
        let captionExtra: CGFloat
        if hasCaption {
            let captionSize = (altText as NSString).boundingRect(
                with: NSSize(width: captionAreaWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: captionFont]
            )
            captionExtra = ceil(captionSize.height) + padding / 2
        } else {
            captionExtra = 0
        }
        return padding + iconSize + captionExtra + padding
    }

    private static func makeImage(source: String, altText: String) -> NSImage {
        let width = maxWidth
        let height = canvasHeight(altText: altText, width: width)
        let size = CGSize(width: width, height: height)
        let image = NSImage(size: size)

        image.lockFocus()

        // Background with rounded corners
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

        // Photo SF Symbol icon centered horizontally
        let iconConfig = NSImage.SymbolConfiguration(pointSize: iconSize * 0.6, weight: .regular)
        let iconImage = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)

        let iconX = (width - iconSize) / 2
        // NSImage draws from bottom-left; icon sits above caption area
        let captionAreaHeight: CGFloat
        if !altText.isEmpty {
            let captionSize = (altText as NSString).boundingRect(
                with: NSSize(width: width - padding * 2, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: captionFont]
            )
            captionAreaHeight = ceil(captionSize.height) + padding / 2
        } else {
            captionAreaHeight = 0
        }
        let iconY = padding + captionAreaHeight

        if let iconImage {
            iconImage.draw(
                in: CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 0.4
            )
        }

        // Source path label — small, centered, just above the icon
        if !source.isEmpty {
            let sourceAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let sourceStr = source as NSString
            let sourceSize = sourceStr.size(withAttributes: sourceAttrs)
            let truncated = sourceSize.width > width - padding * 2
            let drawStr: NSString = truncated ? "…\(source)" as NSString : sourceStr
            let drawSize = (drawStr as NSString).size(withAttributes: sourceAttrs)
            let sourceX = (width - min(drawSize.width, width - padding * 2)) / 2
            let sourceY = iconY + iconSize + 4
            drawStr.draw(at: NSPoint(x: sourceX, y: sourceY), withAttributes: sourceAttrs)
        }

        // Alt text caption — bottom of the block
        if !altText.isEmpty {
            let captionAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let captionRect = CGRect(
                x: padding,
                y: padding / 2,
                width: width - padding * 2,
                height: captionAreaHeight
            )
            (altText as NSString).draw(
                with: captionRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: captionAttrs
            )
        }

        image.unlockFocus()
        return image
    }
}
