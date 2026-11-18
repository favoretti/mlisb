import MlisbKit
import SwiftUI

@MainActor @Observable final class SearchModel {
    let root: URL
    var query = "" { didSet { schedule() } }
    var options = SearchOptions() { didSet { schedule() } }
    private(set) var results: [FileMatches] = []
    private(set) var error: String?
    private(set) var searching = false
    private var task: Task<Void, Never>?

    init(root: URL) { self.root = root }

    /// Runs the search 250 ms after the last change; a newer one cancels the older.
    private func schedule() {
        task?.cancel()
        guard !query.isEmpty else { results = []; error = nil; searching = false; return }
        searching = true
        let (query, options, root) = (query, options, root)
        task = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found: [FileMatches]
            var message: String?
            do { found = try await FolderSearch.search(query, in: root, options: options) } catch { found = []; message = error.localizedDescription }
            guard !Task.isCancelled else { return }
            results = found
            error = message
            searching = false
        }
    }

    /// For emphasising matches in the shown line; nil if the pattern is invalid.
    var highlighter: NSRegularExpression? {
        var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord { pattern = "\\b(?:\(pattern))\\b" }
        return try? NSRegularExpression(pattern: pattern, options: options.caseSensitive ? [] : [.caseInsensitive])
    }
}

struct SidebarSearchField: View {
    @Bindable var search: SearchModel
    let nav: NavState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $search.query)
                    .textFieldStyle(.plain).focused($focused)
                    .onExitCommand { search.query = "" }
                if !search.query.isEmpty {
                    Button { search.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Menu {
                Toggle("Match Case", isOn: $search.options.caseSensitive)
                Toggle("Whole Word", isOn: $search.options.wholeWord)
                Toggle("Regular Expression", isOn: $search.options.regex)
            } label: { Image(systemName: "slider.horizontal.3") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(8)
        .onChange(of: nav.searchRequest) { focused = true }
    }
}

struct SearchResultsView: View {
    let search: SearchModel
    let open: (URL, NSRange) -> Void

    private var total: Int { search.results.reduce(0) { $0 + $1.matches.count } }

    var body: some View {
        if let error = search.error {
            ContentUnavailableView("Invalid search", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            List {
                Text(search.searching && search.results.isEmpty ? "Searching…"
                     : total == 0 ? "No results" : "\(total) results in \(search.results.count) files")
                    .foregroundStyle(.secondary)
                ForEach(search.results, id: \.url) { file in
                    Section {
                        ForEach(Array(file.matches.enumerated()), id: \.offset) { _, match in
                            Button { open(file.url, match.range) } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(emphasised(match.lineText)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(match.line)").foregroundStyle(.secondary).monospacedDigit()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        VStack(alignment: .leading) {
                            Text(file.url.lastPathComponent).font(.headline)
                            let folder = QuickOpen.relativePath(file.url.deletingLastPathComponent(), in: search.root)
                            if folder != search.root.lastPathComponent { Text(folder).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }

    private func emphasised(_ line: String) -> AttributedString {
        let text = line.trimmingCharacters(in: .whitespaces)
        var out = AttributedString(text)
        let ns = text as NSString
        for m in search.highlighter?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [] {
            if let r = Range(m.range, in: text), let a = AttributedString.Index(r.lowerBound, within: out),
               let b = AttributedString.Index(r.upperBound, within: out) {
                out[a..<b].font = .body.bold()
                out[a..<b].backgroundColor = .yellow.opacity(0.35)
            }
        }
        return out
    }
}
