// Sources/WYSIWYG/Attachments/CodeBlockAttachment.swift
import AppKit

final class CodeBlockAttachment: NSTextAttachment, MarkdownBlockAttachment {

    let code: String
    let language: String

    private static let padding: CGFloat = 10
    private static let labelHeight: CGFloat = 18
    private static let cornerRadius: CGFloat = 6
    private nonisolated(unsafe) static let codeFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    private nonisolated(unsafe) static let labelFont: NSFont = .systemFont(ofSize: 11, weight: .regular)
    private static let canvasWidth: CGFloat = 600

    init(code: String, language: String) {
        self.code = code
        self.language = language
        super.init(data: nil, ofType: nil)
        self.image = Self.makeImage(code: code, language: language)
        self.bounds = CGRect(x: 0, y: -4, width: Self.canvasWidth, height: Self.canvasHeight(code: code, language: language, width: Self.canvasWidth))
    }

    required init?(coder: NSCoder) {
        self.code = (coder.decodeObject(forKey: "code") as? String) ?? ""
        self.language = (coder.decodeObject(forKey: "language") as? String) ?? ""
        super.init(coder: coder)
        self.image = Self.makeImage(code: self.code, language: self.language)
        self.bounds = CGRect(x: 0, y: -4, width: Self.canvasWidth, height: Self.canvasHeight(code: self.code, language: self.language, width: Self.canvasWidth))
    }

    nonisolated func serializeToMarkdown() -> String {
        "```\(language)\n\(code)```\n"
    }

    // MARK: - Private

    private static func canvasHeight(code: String, language: String, width: CGFloat) -> CGFloat {
        let codeAreaWidth = width - padding * 2
        let codeSize = (code as NSString).boundingRect(
            with: NSSize(width: codeAreaWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: codeFont]
        )
        let labelExtra: CGFloat = language.isEmpty ? 0 : labelHeight
        return ceil(codeSize.height) + padding * 2 + labelExtra
    }

    private static func makeImage(code: String, language: String) -> NSImage {
        let width = canvasWidth
        let height = canvasHeight(code: code, language: language, width: width)
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

        // Language label (top-right)
        var codeOriginY: CGFloat = padding

        if !language.isEmpty {
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let labelSize = (language as NSString).size(withAttributes: labelAttrs)
            let labelX = width - padding - labelSize.width
            let labelY = height - padding - labelHeight + (labelHeight - labelSize.height) / 2
            (language as NSString).draw(
                at: NSPoint(x: labelX, y: labelY),
                withAttributes: labelAttrs
            )
            codeOriginY += labelHeight
        }

        // Code text — AppKit draws from bottom in flipped coordinates;
        // NSImage uses a bottom-left origin, so we draw from codeOriginY up.
        let codeRect = CGRect(
            x: padding,
            y: codeOriginY,
            width: width - padding * 2,
            height: height - codeOriginY - padding
        )
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .foregroundColor: NSColor.labelColor,
        ]
        (code as NSString).draw(
            with: codeRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: codeAttrs
        )

        image.unlockFocus()
        return image
    }
}
