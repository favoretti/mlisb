import Foundation
import Observation

/// One open markdown file. `text` is exactly the file's contents; bytes the user
/// didn't touch are written back unchanged.
@MainActor @Observable final class Document {
    let url: URL
    var text: String { didSet { if text != oldValue { scheduleSave() } } }
    /// Set when the file changed on disk while there were unsaved edits.
    private(set) var conflictingDiskText: String?
    private(set) var error: String?

    /// What we last read from or wrote to disk.
    private var diskText: String
    private var saveTask: Task<Void, Never>?
    private var watcher: FileWatcher?

    init(url: URL) {
        self.url = url
        text = ""
        diskText = ""
        reload()
    }

    var isReadOnly: Bool { error != nil }
    /// The sandbox has no access to this file (e.g. a link target outside what was opened).
    private(set) var needsAccess = false

    func reload() {
        do {
            let loaded = try Self.read(url)
            error = nil
            needsAccess = false
            diskText = loaded
            text = loaded
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
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func diskChanged() {
        guard let onDisk = try? Self.read(url), onDisk != diskText else { return }
        if text == diskText {
            diskText = onDisk
            text = onDisk
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
        if keepMine { save() } else { text = onDisk }
    }
}
