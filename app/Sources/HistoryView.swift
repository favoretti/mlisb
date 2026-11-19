import MlisbKit
import SwiftUI

/// A line-by-line comparison of an older text against a newer one, with long unchanged runs collapsed.
enum Compare {
    struct Row: Equatable {
        enum Kind { case same, added, removed, gap }
        let kind: Kind
        let text: String
        /// UTF-16 ranges in `text` of the words that changed, when only part of the line did.
        var words: [NSRange] = []
    }

    static func rows(from old: String, to new: String, context: Int = 2) -> [Row] {
        func lines(_ s: String, _ kind: Row.Kind, words: [NSRange] = []) -> [Row] {
            var parts = s.components(separatedBy: "\n")
            if parts.last == "" { parts.removeLast() }
            var start = 0
            return parts.map { part in
                let length = (part as NSString).length
                let line = NSRange(location: start, length: length)
                start += length + 1
                let inLine = words.compactMap { $0.intersection(line) }.filter { $0.length > 0 }
                return Row(kind: kind, text: part, words: inLine.map { NSRange(location: $0.location - line.location, length: $0.length) })
            }
        }
        let ns = new as NSString
        var all: [Row] = []
        var pos = 0
        for c in TextDiff.changes(from: old, to: new) {
            let added = ns.substring(with: c.range)
            all += lines(ns.substring(with: NSRange(location: pos, length: c.range.location - pos)), .same)
            // The diff marks words in the new text only; diffing back marks them in the old.
            let removedWords = c.kind == .modified ? TextDiff.changes(from: added, to: c.oldText).flatMap(\.wordRanges) : []
            all += lines(c.oldText, .removed, words: removedWords)
            all += lines(added, .added, words: c.wordRanges.map { NSRange(location: $0.location - c.range.location, length: $0.length) })
            pos = NSMaxRange(c.range)
        }
        all += lines(ns.substring(from: pos), .same)

        var out: [Row] = []
        var i = 0
        while i < all.count {
            guard all[i].kind == .same else { out.append(all[i]); i += 1; continue }
            var j = i
            while j < all.count, all[j].kind == .same { j += 1 }
            let before = i == 0 ? 0 : context, after = j == all.count ? 0 : context
            let hidden = j - i - before - after
            if hidden >= 2 {
                out += all[i..<i + before] + [Row(kind: .gap, text: "… \(hidden) unchanged lines …")] + all[j - after..<j]
            } else {
                out += all[i..<j]
            }
            i = j
        }
        return out
    }
}

struct HistoryView: View {
    let document: Document
    @State private var versions: [HistoryStore.Version] = []
    @State private var selection: String?
    @State private var rows: [Compare.Row] = []
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var selected: HistoryStore.Version? { versions.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            if versions.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Versions appear here as this file is opened, saved or changed by another app."))
            } else {
                HSplitView {
                    List(versions, selection: $selection) { version in
                        VStack(alignment: .leading) {
                            Text(version.date.formatted(.relative(presentation: .named)))
                            Text("\(label(version.origin)) · \(ByteCountFormatter.string(fromByteCount: Int64(version.byteCount), countStyle: .file))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                    comparison.frame(minWidth: 360)
                }
            }
            Divider()
            HStack {
                if let error { Text(error).foregroundStyle(.red).lineLimit(1) }
                Spacer()
                Button("Restore This Version") { restore() }
                    .disabled(selected == nil || document.conflictingDiskText != nil || document.isReadOnly)
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
        }
        .frame(minWidth: 700, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(ResizableSheet(key: "historySize", minimum: NSSize(width: 700, height: 420), initial: NSSize(width: 1000, height: 680)))
        .onAppear {
            versions = document.history.versions(for: document.url)
            selection = versions.first?.id
        }
        .onChange(of: selection) { load() }
        .onChange(of: document.text) { load() }
    }

    @ViewBuilder private var comparison: some View {
        if !rows.contains(where: { $0.kind == .added || $0.kind == .removed }) {
            Text(selected == nil ? "" : "Identical to the current text.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Text(text(of: row))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(row.kind == .gap ? .secondary : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .background(tint(row.kind).opacity(0.2))
                    }
                }
                .textSelection(.enabled)
                .padding(8)
            }
        }
    }

    private func tint(_ kind: Compare.Row.Kind) -> Color {
        kind == .added ? .green : kind == .removed ? .red : .clear
    }

    private func text(of row: Compare.Row) -> AttributedString {
        var line = AttributedString(row.text.isEmpty ? " " : row.text)
        for word in row.words {
            if let range = Range(word, in: line) { line[range].backgroundColor = tint(row.kind).opacity(0.45) }
        }
        return line
    }

    private func label(_ origin: HistoryStore.Origin) -> String {
        switch origin {
        case .opened: "Opened"
        case .saved: "Saved"
        case .external: "Changed by another app"
        }
    }

    private func load() {
        guard let selected, let old = try? document.history.text(of: selected) else { return rows = [] }
        rows = Compare.rows(from: old, to: document.text)
    }

    private func restore() {
        guard let selected else { return }
        do {
            try document.restore(selected)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// SwiftUI sheets have a fixed size; this gives the sheet's window a resize edge and remembers the size.
struct ResizableSheet: NSViewRepresentable {
    let key: String
    let minimum: NSSize
    let initial: NSSize

    func makeNSView(context: Context) -> Probe { Probe(self) }
    func updateNSView(_ view: Probe, context: Context) {}

    final class Probe: NSView {
        private let sheet: ResizableSheet
        private var configured = false

        init(_ sheet: ResizableSheet) {
            self.sheet = sheet
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            guard let window, !configured else { return }
            configured = true
            window.styleMask.insert(.resizable)
            window.contentMinSize = sheet.minimum
            let saved = UserDefaults.standard.string(forKey: sheet.key).map(NSSizeFromString) ?? sheet.initial
            let size = NSSize(width: max(saved.width, sheet.minimum.width), height: max(saved.height, sheet.minimum.height))
            // SwiftUI sizes the sheet to its minimum first; set the size after that.
            DispatchQueue.main.async { window.setContentSize(size) }
            NotificationCenter.default.addObserver(self, selector: #selector(resized), name: NSWindow.didEndLiveResizeNotification, object: window)
        }

        @objc private func resized(_ note: Notification) {
            guard let window = note.object as? NSWindow else { return }
            UserDefaults.standard.set(NSStringFromSize(window.contentLayoutRect.size), forKey: sheet.key)
        }
    }
}
