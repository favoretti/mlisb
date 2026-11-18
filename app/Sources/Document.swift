import Foundation
import MlisbKit
import Observation

/// One open markdown file. `text` is exactly the file's contents; bytes the user
/// didn't touch are written back unchanged.
@MainActor @Observable final class Document {
    let url: URL
    var text: String {
        didSet {
            guard text != oldValue else { return }
            if !loadingFromDisk {
                let e = Self.edit(oldValue, text)
                review.localEdit(range: e.range, replacement: e.replacement)
            }
            scheduleSave()
        }
    }
    /// What changed since the reader last marked the file reviewed.
    private(set) var review = ChangeReview(baseline: "", current: "")
    /// The change the reader last stepped to; a removed one has no text to select, so the bar quotes it.
    var current: TextChange?
    var showingHistory = false
    let history: HistoryStore
    /// Set when the file changed on disk while there were unsaved edits.
    private(set) var conflictingDiskText: String?
    private(set) var error: String?

    /// What we last read from or wrote to disk.
    private var diskText: String
    private var saveTask: Task<Void, Never>?
    private var watcher: FileWatcher?
    private var loadingFromDisk = false

    /// Shared by all documents; pruned once per launch, off the main thread.
    static let sharedHistory: HistoryStore = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let store = HistoryStore(directory: base.appendingPathComponent("History"))
        Task.detached(priority: .utility) { try? store.prune() }
        return store
    }()

    init(url: URL, history: HistoryStore = Document.sharedHistory) {
        self.url = url
        self.history = history
        text = ""
        diskText = ""
        reload()
    }

    var isReadOnly: Bool { error != nil || isBundled }
    /// The built-in help: shown, never edited or tracked.
    private var isBundled: Bool { FS.under(url, Bundle.main.bundleURL) }
    /// The sandbox has no access to this file (e.g. a link target outside what was opened).
    private(set) var needsAccess = false

    func reload() {
        do {
            let loaded = try Self.read(url)
            error = nil
            needsAccess = false
            diskText = loaded
            setFromDisk(loaded)
            if !isBundled { try? history.record(loaded, for: url, origin: .opened) }
            var baseline = isBundled ? loaded : history.reviewedBaseline(for: url)
            if baseline == nil {
                baseline = loaded
                try? history.setReviewedBaseline(loaded, for: url)
            }
            review = ChangeReview(baseline: baseline!, current: loaded)
            watcher = FileWatcher(url: url) { [weak self] in self?.diskChanged() }
        } catch {
            needsAccess = (error as? CocoaError)?.code == .fileReadNoPermission
            self.error = error.localizedDescription
        }
    }

    private static func read(_ url: URL) throws -> String {
        // Strict decoding: a lossy one would corrupt the file on the next save.
        guard let text = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [
                NSLocalizedDescriptionKey: "This file isn’t UTF-8 text, so it’s shown empty and can’t be edited."])
        }
        return text
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { self?.save() }
        }
    }

    func save() {
        saveTask?.cancel()
        guard !isReadOnly, conflictingDiskText == nil, text != diskText else { return }
        // The watcher can lag behind a write; never save over a change we haven't seen.
        if let onDisk = try? Self.read(url), onDisk != diskText { return diskChanged() }
        do {
            // Written in place (not atomically) to keep the inode, permissions and
            // symlinks, and because a single-file sandbox grant can't create a sibling.
            try Data(text.utf8).write(to: url)
            diskText = text
            try? history.record(text, for: url, origin: .saved)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func diskChanged() {
        guard let onDisk = try? Self.read(url), onDisk != diskText else { return }
        if text == diskText {
            diskText = onDisk
            externalChange(onDisk)
        } else if onDisk != text {
            conflictingDiskText = onDisk
        } else {
            diskText = onDisk
        }
    }

    func resolveConflict(keepMine: Bool) {
        guard let onDisk = conflictingDiskText else { return }
        conflictingDiskText = nil
        diskText = onDisk
        if keepMine { save() } else { externalChange(onDisk) }
    }

    private func setFromDisk(_ new: String) {
        loadingFromDisk = true
        text = new
        loadingFromDisk = false
    }

    private func externalChange(_ new: String) {
        setFromDisk(new)
        try? history.record(new, for: url, origin: .external)
        review.externalChange(current: new)
        current = nil
    }

    func markReviewed() {
        review.markReviewed(current: text)
        try? history.setReviewedBaseline(text, for: url)
        current = nil
    }

    /// Keeps the replaced text in history, then makes `version` the text as an ordinary edit.
    func restore(_ version: HistoryStore.Version) throws {
        guard conflictingDiskText == nil, !isReadOnly else { return }
        let old = try history.text(of: version)
        try history.record(text, for: url, origin: .saved)
        text = old
    }

    /// The smallest UTF-16 range of `old` whose replacement turns it into `new`.
    nonisolated static func edit(_ old: String, _ new: String) -> (range: NSRange, replacement: String) {
        let a = Array(old.utf16), b = Array(new.utf16)
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        if p > 0, UTF16.isLeadSurrogate(a[p - 1]) { p -= 1 }
        var s = 0
        while s < a.count - p, s < b.count - p, a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        if s > 0, UTF16.isTrailSurrogate(a[a.count - s]) { s -= 1 }
        return (NSRange(location: p, length: a.count - p - s),
                String(decoding: b[p..<b.count - s], as: UTF16.self))
    }
}
