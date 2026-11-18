import MlisbKit
import SwiftUI

/// A line-by-line comparison of an older text against a newer one, with long unchanged runs collapsed.
enum Compare {
    struct Row: Equatable {
        enum Kind { case same, added, removed, gap }
        let kind: Kind
        let text: String
    }

    static func rows(from old: String, to new: String, context: Int = 2) -> [Row] {
        func lines(_ s: String, _ kind: Row.Kind) -> [Row] {
            var parts = s.components(separatedBy: "\n")
            if parts.last == "" { parts.removeLast() }
            return parts.map { Row(kind: kind, text: $0) }
        }
        let ns = new as NSString
        var all: [Row] = []
        var pos = 0
        for c in TextDiff.changes(from: old, to: new) {
            all += lines(ns.substring(with: NSRange(location: pos, length: c.range.location - pos)), .same)
            all += lines(c.oldText, .removed)
            all += lines(ns.substring(with: c.range), .added)
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
        .frame(width: 820, height: 520)
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
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Text(row.text.isEmpty ? " " : row.text)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(row.kind == .gap ? .secondary : .primary)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(row.kind == .added ? Color.green.opacity(0.2)
                                        : row.kind == .removed ? Color.red.opacity(0.2) : .clear)
                    }
                }
                .padding(8)
            }
        }
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
