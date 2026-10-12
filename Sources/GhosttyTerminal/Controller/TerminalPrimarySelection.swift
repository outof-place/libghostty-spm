import Foundation

/// The selection clipboard (X11's primary selection): what `copy-on-select`
/// last selected, pasted by a middle click. Ghostty's own macOS app keeps it
/// on a private pasteboard; here it lives in this process, one per host
/// pasteboard name, so the user's clipboard never sees it.
enum TerminalPrimarySelection {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var texts: [String: String] = [:]

    static func text(for name: String) -> String? {
        lock.withLock { texts[name] }
    }

    static func set(_ text: String?, for name: String) {
        lock.withLock { texts[name] = text }
    }
}
