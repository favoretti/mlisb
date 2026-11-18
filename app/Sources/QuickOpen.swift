import AppKit
import MlisbKit
import SwiftUI

struct MenuCommand {
    let title: String
    let shortcut: String
    let item: NSMenuItem
}

struct QuickEntry: Identifiable, Equatable {
    enum Kind: Equatable { case file(URL), heading(NSRange), command(NSMenuItem) }
    let kind: Kind
    let title: String
    let detail: String
    let indent: Int
    let id: String
}

enum QuickOpen {
    static let ownTitle = "Open Quickly…"

    static func excluded(_ item: NSMenuItem, services: NSMenu?) -> Bool {
        item.title == ownTitle || item.isAlternate
            || (item.submenu != nil && (item.submenu === services || item.title == "Services"))
            || item.target is NSWindow || item.action == #selector(NSWindow.makeKeyAndOrderFront(_:))
    }

    /// Enabled leaf items, depth first, titled "Menu ▸ Item".
    static func commands(in menu: NSMenu, services: NSMenu?) -> [MenuCommand] {
        var out: [MenuCommand] = []
        func walk(_ menu: NSMenu, _ path: [String]) {
            menu.update()
            for item in menu.items where !item.isSeparatorItem && !item.isHidden && !excluded(item, services: services) {
                if let sub = item.submenu {
                    walk(sub, path + [item.title.isEmpty ? sub.title : item.title])
                } else if item.isEnabled {
                    out.append(MenuCommand(title: (path + [item.title]).joined(separator: " ▸ "), shortcut: shortcut(item), item: item))
                }
            }
        }
        walk(menu, [])
        return out
    }

    static func shortcut(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let m = item.keyEquivalentModifierMask
        return (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
            + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "") + item.keyEquivalent.uppercased()
    }

    static func relativePath(_ url: URL, in root: URL) -> String {
        url.path.hasPrefix(root.path + "/") ? String(url.path.dropFirst(root.path.count + 1)) : url.lastPathComponent
    }

    /// Empty query: files (newest first, at most 50), headings, commands. Otherwise everything, fuzzy ranked.
    static func entries(files: [(url: URL, modified: Date)], root: URL?, headings: [Heading],
                        commands: [MenuCommand], query: String) -> [QuickEntry] {
        let recent = files.sorted { ($0.modified, $1.url.path) > ($1.modified, $0.url.path) }
        let fileEntries = recent.map { f in
            let path = root.map { relativePath(f.url, in: $0) } ?? f.url.lastPathComponent
            return QuickEntry(kind: .file(f.url), title: path, detail: "", indent: 0, id: "f:" + f.url.path)
        }
        let headingEntries = headings.map {
            QuickEntry(kind: .heading($0.range), title: $0.title, detail: "", indent: $0.level - 1, id: "h:\($0.range.location)")
        }
        let commandEntries = commands.enumerated().map { i, c in
            QuickEntry(kind: .command(c.item), title: c.title, detail: c.shortcut, indent: 0, id: "c:\(i)")
        }
        if query.isEmpty { return Array(fileEntries.prefix(50)) + headingEntries + commandEntries }
        return Array(FuzzyMatch.rank(fileEntries + headingEntries + commandEntries, query: query, by: \.title).prefix(100))
    }
}

struct QuickOpenView: View {
    let nav: NavState
    let root: URL?
    let headings: [Heading]
    let openFile: (URL) -> Void
    let goTo: (NSRange) -> Void
    @State private var query = ""
    @State private var selected = 0
    @State private var files: [(url: URL, modified: Date)] = []
    @State private var commands: [MenuCommand] = []
    @FocusState private var focused: Bool

    private var entries: [QuickEntry] {
        QuickOpen.entries(files: files, root: root, headings: headings, commands: commands, query: query)
    }

    var body: some View {
        let entries = entries
        ZStack(alignment: .top) {
            Color.black.opacity(0.001).onTapGesture { nav.quickOpen = false }
            VStack(spacing: 0) {
                TextField("Open Quickly", text: $query)
                    .textFieldStyle(.plain).font(.title3).padding(12)
                    .focused($focused)
                    .onSubmit { if entries.indices.contains(selected) { run(entries[selected]) } }
                    .onExitCommand { nav.quickOpen = false }
                    .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
                    .onKeyPress(.downArrow) { selected = max(min(selected + 1, entries.count - 1), 0); return .handled }
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                                Button { run(entry) } label: { row(entry, selected: i == selected) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: min(340, CGFloat(entries.count) * 26 + 12))
                    .onChange(of: selected) { if entries.indices.contains(selected) { proxy.scrollTo(entries[selected].id) } }
                }
            }
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
            .padding(.top, 40)
        }
        .onAppear {
            focused = true
            if let menu = NSApp.mainMenu { commands = QuickOpen.commands(in: menu, services: NSApp.servicesMenu) }
        }
        .task {
            guard let root else { return }
            files = await Task.detached {
                FolderSearch.markdownFiles(in: root).map {
                    ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }
            }.value
        }
        .onChange(of: query) { selected = 0 }
    }

    private func row(_ entry: QuickEntry, selected: Bool) -> some View {
        HStack {
            Image(systemName: icon(entry.kind)).foregroundStyle(.secondary).frame(width: 18)
            Text(entry.title).lineLimit(1).truncationMode(.middle).padding(.leading, CGFloat(entry.indent) * 12)
            Spacer()
            Text(entry.detail).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func icon(_ kind: QuickEntry.Kind) -> String {
        switch kind {
        case .file: "doc.text"
        case .heading: "number"
        case .command: "command"
        }
    }

    private func run(_ entry: QuickEntry) {
        nav.quickOpen = false
        switch entry.kind {
        case .file(let url): openFile(url)
        case .heading(let range): goTo(NSRange(location: range.location, length: 0))
        case .command(let item):
            // Through the menu, after the palette is gone, so validation and targets match a manual choice.
            Task { if let menu = item.menu { menu.performActionForItem(at: menu.index(of: item)) } }
        }
    }
}
