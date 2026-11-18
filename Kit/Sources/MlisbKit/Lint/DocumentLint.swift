import Foundation

public struct LintIssue: Equatable, Sendable {
    public enum Kind: String, Sendable { case duplicateAnchor, skippedHeadingLevel, undefinedReference, unclosedFence, brokenAnchor, brokenLink, tableColumnMismatch }
    public let kind: Kind
    public let message: String
    public let line: Int
    public let range: NSRange
}

public enum Slug {
    /// The anchor github.com generates for a heading: lowercased, punctuation removed (letters, digits, `-`, `_` and spaces kept), spaces to `-`.
    public static func github(_ heading: String) -> String {
        String(heading.lowercased().filter { $0.isLetter || $0.isNumber || "-_ ".contains($0) }.map { $0 == " " ? "-" : $0 })
    }
}

public enum DocumentLint {
    /// `fileURL` enables the checks that look at the file system (relative links and images).
    public static func issues(in text: String, fileURL: URL? = nil) -> [LintIssue] {
        func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
        func groups(_ r: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
            r.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
        }
        func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String {
            m.range(at: i).location == NSNotFound ? "" : (s as NSString).substring(with: m.range(at: i))
        }

        let ns = text as NSString
        var lines: [(text: String, range: NSRange)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { s, r, _, _ in
            lines.append((s ?? "", r))
        }

        var issues: [LintIssue] = []
        func add(_ kind: LintIssue.Kind, _ message: String, _ i: Int, _ range: NSRange? = nil) {
            issues.append(LintIssue(kind: kind, message: message, line: i + 1, range: range ?? lines[i].range))
        }
        func at(_ i: Int, _ r: NSRange) -> NSRange { NSRange(location: lines[i].range.location + r.location, length: r.length) }

        // Pass 1: find fenced code; blank out inline code spans in the other lines.
        let fenceOpen = rx("^[ \\t]*(`{3,}|~{3,})(.*)$")
        let codeSpan = rx("(?<!`)(`+)(?!`).+?(?<!`)\\1(?!`)")
        var code = [Bool](repeating: false, count: lines.count)
        var masked = lines.map(\.text)
        var fence: (ch: Character, len: Int, line: Int)?
        for (i, l) in lines.enumerated() {
            if let f = fence {
                code[i] = true
                let t = l.text.trimmingCharacters(in: .whitespaces)
                if t.count >= f.len && t.allSatisfy({ $0 == f.ch }) { fence = nil }
            } else if let m = groups(fenceOpen, l.text).first {
                let marker = group(m, 1, l.text)
                if marker.first == "`" && group(m, 2, l.text).contains("`") { masked[i] = l.text; continue }
                fence = (marker.first!, marker.count, i)
                code[i] = true
            } else {
                let out = NSMutableString(string: l.text)
                for s in groups(codeSpan, l.text) {
                    out.replaceCharacters(in: s.range, with: String(repeating: " ", count: s.range.length))
                }
                masked[i] = out as String
            }
        }
        if let f = fence { add(.unclosedFence, "This code fence is never closed.", f.line) }

        // Pass 2: headings, anchors, reference definitions.
        let heading = rx("^ {0,3}(#{1,6})(?:[ \\t]+(.*?))?(?:[ \\t]+#+)?[ \\t]*$")
        let definition = rx("^ {0,3}\\[([^\\]^][^\\]]*)\\]:")
        func label(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() }
        var anchors = Set<String>()
        var seen: [String: Int] = [:]
        var defined = Set<String>()
        var previousLevel: Int?
        for i in lines.indices where !code[i] {
            if let m = groups(definition, masked[i]).first { defined.insert(label(group(m, 1, masked[i]))) }
            guard let m = groups(heading, lines[i].text).first else { continue }
            let level = m.range(at: 1).length
            if let p = previousLevel, level > p + 1 {
                add(.skippedHeadingLevel, "Heading level jumps from H\(p) to H\(level); add an H\(p + 1) in between.", i)
            }
            previousLevel = level
            let title = group(m, 2, lines[i].text)
            let base = Slug.github(title)
            let n = seen[base, default: 0]
            seen[base] = n + 1
            anchors.insert(n == 0 ? base : "\(base)-\(n)")
            if n > 0 && !base.isEmpty {
                add(.duplicateAnchor, "Heading \"\(title)\" has the same anchor as an earlier heading; link to it as #\(base)-\(n).", i)
            }
        }

        // Pass 3: references, links, tables.
        let reference = rx("(?<![\\p{L}\\p{N}_\\]])\\[([^\\]]+)\\]\\[([^\\]]*)\\]")
        let link = rx("\\]\\(\\s*<?([^)\\s>]+)")
        let scheme = rx("^[A-Za-z][A-Za-z0-9+.-]*:")
        let delimiter = rx("^[ \\t]*\\|?[ \\t]*:?-+:?[ \\t]*(\\|[ \\t]*:?-+:?[ \\t]*)*\\|?[ \\t]*$")
        func cells(_ s: String) -> Int {
            var parts = 1, escaped = false
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
            for ch in t {
                if ch == "|" && !escaped { parts += 1 }
                escaped = ch == "\\" && !escaped
            }
            return parts
        }
        var tableCells: Int?
        for i in lines.indices where !code[i] {
            for m in groups(reference, masked[i]) {
                let first = group(m, 1, masked[i])
                let l = label(group(m, 2, masked[i]).isEmpty ? first : group(m, 2, masked[i]))
                if [" ", "x"].contains(first.lowercased()) || "^!".contains(l.first ?? "a") || defined.contains(l) { continue }
                add(.undefinedReference, "No link definition found for [\(l)].", i, at(i, m.range))
            }
            for m in groups(link, masked[i]) {
                let target = group(m, 1, masked[i])
                let r = at(i, m.range(at: 1))
                if target.hasPrefix("#") {
                    let anchor = (String(target.dropFirst()).removingPercentEncoding ?? "").lowercased()
                    if !anchor.isEmpty && !anchors.contains(anchor) {
                        add(.brokenAnchor, "No heading matches the link #\(anchor).", i, r)
                    }
                } else if let fileURL, !target.hasPrefix("/"), groups(scheme, target).isEmpty {
                    let path = (target.split(separator: "#", omittingEmptySubsequences: false).first.map(String.init) ?? "").removingPercentEncoding ?? ""
                    let file = fileURL.deletingLastPathComponent().appendingPathComponent(path).path
                    if !path.isEmpty && !FileManager.default.fileExists(atPath: file) {
                        add(.brokenLink, "The file \(path) does not exist.", i, r)
                    }
                }
            }
            // Cells are counted on the raw line: GitHub splits on pipes inside code spans too.
            let raw = lines[i].text
            if let header = tableCells {
                if raw.contains("|") {
                    let n = cells(raw)
                    if n != header { add(.tableColumnMismatch, "This table row has \(n) cells but the header has \(header).", i) }
                    continue
                }
                tableCells = nil
            }
            if i > 0, !code[i - 1], lines[i - 1].text.contains("|"), raw.contains("-"), !groups(delimiter, raw).isEmpty {
                let header = cells(lines[i - 1].text)
                tableCells = header
                let n = cells(raw)
                if n != header { add(.tableColumnMismatch, "This table row has \(n) cells but the header has \(header).", i) }
            }
        }
        return issues.sorted { ($0.line, $0.range.location) < ($1.line, $1.range.location) }
    }
}
