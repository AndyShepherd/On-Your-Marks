# Appearance Setting & Light-Mode Printing

**Date:** 2026-04-24
**Status:** Approved

## Problem

1. Users have no in-app way to choose Light vs Dark — the app inherits system appearance and there is no override.
2. Printing and PDF export reproduce the on-screen dark rendering. `@media print` CSS is ignored because `WKWebView.createPDF()` snapshots the live view, not a print-paginated render. The result: dark backgrounds and pale text on paper.

## Goals

- Add an in-app appearance choice: **System**, **Light**, **Dark**.
- Force **Light** appearance for the offscreen `WKWebView` used for print and PDF export, regardless of the user's appearance choice or system setting.

## Non-goals

- Theming the live preview separately from the app. Live preview keeps following the chosen appearance.
- Custom themes / accent colours / per-document overrides.

## Design

### Appearance choice

- Persist a string preference `appearancePreference` in `UserDefaults` with values `"system"` (default) | `"light"` | `"dark"`.
- A small helper applies the preference by setting `NSApp.appearance`:
  - `"system"` → `nil` (follow system)
  - `"light"`  → `NSAppearance(named: .aqua)`
  - `"dark"`   → `NSAppearance(named: .darkAqua)`
- Apply once at launch from `AppDelegate.applicationDidFinishLaunching`.
- Re-apply whenever the preference changes.

### Menu

Add a submenu in `OnYourMarksApp.commands` under the existing View block:

```
View → Appearance →
   • System
   • Light
   • Dark
```

Each item shows a checkmark when active. Selecting one writes `UserDefaults` and re-applies via the helper.

### Print / Export light-mode lock

In both `printDocument()` and `exportPDF()` in `MainWindowView.swift`, immediately after constructing the offscreen `WKWebView`, force light:

```swift
webView.appearance = NSAppearance(named: .aqua)
```

This is enough on its own — `prefers-color-scheme` in CSS resolves against the view's effective appearance, so the existing `:root` light variables apply and the dark `@media (prefers-color-scheme: dark)` block is skipped. The PDF capture now reflects the light render.

The on-screen `MarkdownPreviewView` is untouched.

## Files touched

- `Sources/App/OnYourMarksApp.swift` — appearance helper, launch apply, View → Appearance submenu.
- `Sources/App/MainWindowView.swift` — set `webView.appearance` in `printDocument()` and `exportPDF()`.

## Testing

1. Set system to Dark. Launch app → app is dark (System default). Switch to Light via menu → app becomes light. Switch to Dark → dark. Quit and relaunch → preference persists.
2. With app in Dark mode, choose **Print…** → printed PDF preview is light-themed.
3. With app in Dark mode, choose **Export as PDF…** → saved PDF is light-themed.
4. With app in Light mode, print/export still produce light PDFs.
