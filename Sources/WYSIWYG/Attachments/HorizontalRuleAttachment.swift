// Sources/WYSIWYG/Attachments/HorizontalRuleAttachment.swift
import AppKit

final class HorizontalRuleAttachment: NSTextAttachment, MarkdownBlockAttachment {

    override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        self.image = HorizontalRuleAttachment.makeImage()
        self.bounds = CGRect(x: 0, y: -4, width: 0, height: 20)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.image = HorizontalRuleAttachment.makeImage()
        self.bounds = CGRect(x: 0, y: -4, width: 0, height: 20)
    }

    convenience init() {
        self.init(data: nil, ofType: nil)
    }

    func serializeToMarkdown() -> String { "---\n" }

    // MARK: - Private

    private static func makeImage() -> NSImage {
        // Draw a 1px separator line centered in a 600x20 canvas.
        // The width is notional; the text system stretches attachment images to fill the line width.
        let size = CGSize(width: 600, height: 20)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.separatorColor.setFill()
        let lineRect = CGRect(x: 0, y: (size.height - 1) / 2, width: size.width, height: 1)
        NSBezierPath(rect: lineRect).fill()
        image.unlockFocus()
        return image
    }
}
