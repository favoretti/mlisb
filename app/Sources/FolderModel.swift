import Foundation
import Observation

struct Entry: Hashable { let url: URL; let isDir: Bool }

/// File-system helpers behind the sidebar.
enum FS {
    static let markdown: Set<String> = ["md", "markdown", "mdown"]
    static let previewable: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "pdf"]

    static func isDir(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    static func under(_ url: URL, _ dir: URL) -> Bool {
        url.path == dir.path || url.path.hasPrefix(dir.path + "/")
    }

    /// Visible subfolders, markdown and previewable files; folders first.
    static func list(_ dir: URL) -> [Entry] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return urls
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { Entry(url: $0, isDir: isDir($0)) }
            .filter { $0.isDir || markdown.union(previewable).contains($0.url.pathExtension.lowercased()) }
            .sorted {
                if $0.isDir != $1.isDir { return $0.isDir }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
    }

    static func uniqueURL(in dir: URL, name: String, ext: String = "") -> URL {
        func candidate(_ n: Int) -> URL {
            let base = n == 1 ? name : "\(name) \(n)"
            return dir.appending(component: ext.isEmpty ? base : "\(base).\(ext)")
        }
        return (1...).lazy.map(candidate).first { !FileManager.default.fileExists(atPath: $0.path) }!
    }

    /// Moves or renames `src` to `dst`, never overwriting and never into itself.
    static func move(_ src: URL, to dst: URL) throws {
        guard !FileManager.default.fileExists(atPath: dst.path), !under(dst, src) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [
                NSLocalizedDescriptionKey: "“\(dst.lastPathComponent)” can’t be created there: the name is taken or the folder is inside itself."])
        }
        try FileManager.default.moveItem(at: src, to: dst)
    }
}

@MainActor @Observable final class FolderModel {
    let root: URL
    private(set) var children: [URL: [Entry]] = [:]
    private(set) var expanded: Set<URL> = []
    private(set) var document: Document?
    private(set) var preview: URL?
    var renaming: URL?
    var error: String?
    var selection: URL? { didSet { if let selection, selection != oldValue { open(selection) } } }
    private var watchers: [URL: FileWatcher] = [:]

    init(root: URL) {
        self.root = root
        load(root)
        selectInitial()
    }

    private func selectInitial() {
        let md = (children[root] ?? []).filter { !$0.isDir && FS.markdown.contains($0.url.pathExtension.lowercased()) }
        selection = (md.first { $0.url.lastPathComponent.lowercased() == "readme.md" } ?? md.first)?.url
    }

    private func load(_ dir: URL) {
        children[dir] = FS.list(dir)
        if watchers[dir] == nil { watchers[dir] = FileWatcher(url: dir) { [weak self] in self?.load(dir) } }
    }

    private func reloadAll() {
        children = [:]
        watchers = [:]
        for dir in [root] + expanded { load(dir) }
    }

    func isExpanded(_ dir: URL) -> Bool { expanded.contains(dir) }

    func setExpanded(_ dir: URL, _ on: Bool) {
        if on {
            expanded.insert(dir)
            load(dir)
        } else {
            expanded.remove(dir)
            watchers[dir] = nil
        }
    }

    private func open(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard url != document?.url, url != preview else { return }
        if FS.markdown.contains(ext) {
            document?.save()
            document = Document(url: url)
            preview = nil
        } else if FS.previewable.contains(ext) {
            document?.save()
            document = nil
            preview = url
        }
    }

    /// Selects a file that lives in this folder; false if it doesn't.
    func show(_ url: URL) -> Bool {
        let known = FS.markdown.union(FS.previewable).contains(url.pathExtension.lowercased())
        guard known, FS.under(url, root), FileManager.default.fileExists(atPath: url.path) else { return false }
        selection = url
        return true
    }

    func create(in dir: URL, folder: Bool) {
        if dir != root { setExpanded(dir, true) }
        let url = folder ? FS.uniqueURL(in: dir, name: "Untitled Folder") : FS.uniqueURL(in: dir, name: "Untitled", ext: "md")
        do {
            if folder { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
            else { try Data().write(to: url) }
        } catch { return self.error = error.localizedDescription }
        load(dir)
        selection = url
        renaming = url
    }

    func rename(_ url: URL, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), name != url.lastPathComponent else { return }
        move(url, to: url.deletingLastPathComponent().appending(component: name))
    }

    func move(_ urls: [URL], into dir: URL) {
        for url in urls where FS.under(url, root) && url.deletingLastPathComponent().path != dir.path {
            move(url, to: dir.appending(component: url.lastPathComponent))
        }
    }

    private func move(_ old: URL, to new: URL) {
        document?.save()
        do { try FS.move(old, to: new) } catch { return self.error = error.localizedDescription }
        func remap(_ u: URL) -> URL {
            FS.under(u, old) ? new.appending(path: String(u.path.dropFirst(old.path.count))) : u
        }
        expanded = Set(expanded.map(remap))
        if let u = document?.url ?? preview { open(remap(u)) }
        if let s = selection { selection = remap(s) }
        reloadAll()
    }

    func trash(_ url: URL) {
        document?.save()
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { return self.error = error.localizedDescription }
        if let s = selection, FS.under(s, url) { selection = nil }
        if let u = document?.url ?? preview, FS.under(u, url) { document = nil; preview = nil }
        expanded = expanded.filter { !FS.under($0, url) }
        reloadAll()
    }
}
