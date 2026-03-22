// Sources/App/Notifications.swift
import Foundation

extension Notification.Name {
    static let switchToPreview = Notification.Name("switchToPreview")
    static let switchToEditor = Notification.Name("switchToEditor")
    static let toggleSplit = Notification.Name("toggleSplit")
    static let toggleGFM = Notification.Name("toggleGFM")
    static let formatBold = Notification.Name("formatBold")
    static let formatItalic = Notification.Name("formatItalic")
    static let formatCode = Notification.Name("formatCode")
    static let formatCodeBlock = Notification.Name("formatCodeBlock")
    static let formatLink = Notification.Name("formatLink")
    static let formatImage = Notification.Name("formatImage")
    static let formatHeading = Notification.Name("formatHeading")
    static let formatHeadingIncrease = Notification.Name("formatHeadingIncrease")
    static let formatHeadingDecrease = Notification.Name("formatHeadingDecrease")
    static let formatHorizontalRule = Notification.Name("formatHorizontalRule")
}
