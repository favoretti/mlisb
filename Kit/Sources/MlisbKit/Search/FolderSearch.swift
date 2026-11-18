import Foundation

public struct SearchOptions: Sendable {
    public var caseSensitive = false
    public var wholeWord = false
    public var regex = false
    public init() {}
}

public struct SearchMatch: Equatable, Sendable {
    public let line: Int
    public let lineText: String
    public let range: NSRange
}

public struct FileMatches: Equatable, Sendable {
    public let url: URL
    public let matches: [SearchMatch]
}

public struct SearchError: LocalizedError, Sendable {
    public let errorDescription: String?
}

public enum FolderSearch {
    /// The one list of markdown extensions; bin/mlisb and app/project.yml repeat it (a test keeps them equal).
    public static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdx", "qmd", "rmd", "mdc"]
    static let skipped: Set<String> = ["node_modules", "build", "DerivedData", "Pods", "vendor", "dist", "target"]

    /// Markdown files under `root` (see `extensions`), sorted by path. At most `limit`.
    public static func markdownFiles(in root: URL, limit: Int = 5000) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        // The enumerator never descends into symlinked directories.
        while let url = walker.nextObject() as? URL {
            let v = try? url.resourceValues(forKeys: keys)
            if v?.isDirectory == true {
                if skipped.contains(url.lastPathComponent) { walker.skipDescendants() }
            } else if extensions.contains(url.pathExtension.lowercased()), (v?.fileSize ?? 0) <= 5_000_000 {
                files.append(url)
            }
        }
        return Array(files.sorted { $0.path < $1.path }.prefix(limit))
    }

    /// Text search across those files. Checks `Task.isCancelled` between files and returns what it has.
    public static func search(_ query: String, in root: URL, options: SearchOptions = SearchOptions(), maxMatches: Int = 2000) async throws -> [FileMatches] {
        guard !query.isEmpty else { return [] }
        var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord { pattern = "\\b(?:\(pattern))\\b" }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options.caseSensitive ? [] : [.caseInsensitive])
        } catch {
            throw SearchError(errorDescription: "Invalid regular expression: \(error.localizedDescription)")
        }
        let task = Task.detached {
            var results: [FileMatches] = []
            var total = 0
            for url in markdownFiles(in: root) where total < maxMatches && !Task.isCancelled {
                guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { continue }
                let found = matches(of: regex, in: text as NSString, limit: maxMatches - total)
                if !found.isEmpty {
                    results.append(FileMatches(url: url, matches: found))
                    total += found.count
                }
            }
            return results
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private static func matches(of regex: NSRegularExpression, in ns: NSString, limit: Int) -> [SearchMatch] {
        var out: [SearchMatch] = []
        var line = 1
        var scanned = 0
        for m in regex.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)) where m.range.length > 0 {
            if out.count == limit { break }
            // Count line breaks since the previous match; \r\n counts once.
            for i in scanned..<m.range.location {
                let u = ns.character(at: i)
                if u == 10 || (u == 13 && !(i + 1 < ns.length && ns.character(at: i + 1) == 10)) { line += 1 }
            }
            scanned = m.range.location
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: m.range.location, length: 0))
            var shown = NSRange(location: start, length: contentsEnd - start)
            if shown.length > 300 {
                let from = min(max(start, m.range.location - 100), contentsEnd - 300)
                shown = ns.rangeOfComposedCharacterSequences(for: NSRange(location: from, length: 300))
            }
            out.append(SearchMatch(line: line, lineText: ns.substring(with: shown), range: m.range))
        }
        return out
    }
}
