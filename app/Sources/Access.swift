import AppKit
import Observation

/// Keeps sandbox access to opened files and folders across launches, and the recents list.
@MainActor @Observable final class Access {
    static let shared = Access()

    private(set) var recents = NSDocumentController.shared.recentDocumentURLs

    /// Call when a window gets its root. A restored window has no sandbox access
    /// until the bookmark saved on an earlier open is resolved.
    func begin(_ url: URL) {
        if FS.under(url, Bundle.main.bundleURL) { return }   // the built-in help needs no access and is not a recent document
        // shortcut: bookmarks are never pruned; cap the dictionary if it grows large.
        var saved = UserDefaults.standard.dictionary(forKey: "bookmarks") as? [String: Data] ?? [:]
        var stale = false
        var resolved: URL?
        if let data = saved[url.path] {
            resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            _ = resolved?.startAccessingSecurityScopedResource()
        }
        if resolved == nil || stale, let data = try? url.bookmarkData(options: .withSecurityScope) {
            saved[url.path] = data
            UserDefaults.standard.set(saved, forKey: "bookmarks")
        }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        // Reading the list back waits on another process; every restored window would pay for it.
        let limit = NSDocumentController.shared.maximumRecentDocumentCount
        recents = Array(([url] + recents.filter { $0.standardizedFileURL != url.standardizedFileURL }).prefix(limit))
    }

    func clearRecents() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        recents = []
    }
}
