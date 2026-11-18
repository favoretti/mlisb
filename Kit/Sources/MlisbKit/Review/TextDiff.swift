import Foundation

public struct TextChange: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case added, modified, removed }
    public let kind: Kind
    /// UTF-16 range in the NEW text. For `.removed`, a zero-length range where the text used to be.
    public var range: NSRange
    /// For `.modified`: UTF-16 ranges in the new text of the words that differ. Empty otherwise.
    public var wordRanges: [NSRange]
    /// For `.modified` and `.removed`: the old text that was replaced or removed. Empty for `.added`.
    public let oldText: String
}

public enum TextDiff {
    // shortcut: past this many edits the search gives up and reports one block; raise if real documents hit it.
    private static let cap = 1000

    public static func changes(from old: String, to new: String) -> [TextChange] {
        let a = Array(old.utf16), b = Array(new.utf16)
        let aStarts = lineStarts(a), bStarts = lineStarts(b)
        var ids: [ArraySlice<UInt16>: Int] = [:]
        func lineIDs(_ u: [UInt16], _ s: [Int]) -> [Int] {
            (0..<s.count - 1).map { i in
                let key = u[s[i]..<s[i + 1]]
                if let id = ids[key] { return id }
                ids[key] = ids.count
                return ids.count - 1
            }
        }
        let x = lineIDs(a, aStarts), y = lineIDs(b, bStarts)

        var p = 0
        while p < x.count, p < y.count, x[p] == y[p] { p += 1 }
        var q = 0
        while q < x.count - p, q < y.count - p, x[x.count - 1 - q] == y[y.count - 1 - q] { q += 1 }
        let ma = Array(x[p..<x.count - q]), mb = Array(y[p..<y.count - q])
        let matches = (ma.isEmpty || mb.isEmpty) ? [] : myers(ma, mb) ?? []

        var hunks: [(a: Range<Int>, b: Range<Int>)] = []
        var ai = 0, bi = 0
        for (i, j) in matches + [(ma.count, mb.count)] {
            if i > ai || j > bi { hunks.append((p + ai..<p + i, p + bi..<p + j)) }
            ai = i + 1
            bi = j + 1
        }

        return hunks.map { h in
            let (os, oe) = (aStarts[h.a.lowerBound], aStarts[h.a.upperBound])
            let (ns, ne) = (bStarts[h.b.lowerBound], bStarts[h.b.upperBound])
            let oldText = String(decoding: a[os..<oe], as: UTF16.self)
            let range = NSRange(location: ns, length: ne - ns)
            if h.a.isEmpty { return TextChange(kind: .added, range: range, wordRanges: [], oldText: "") }
            if h.b.isEmpty { return TextChange(kind: .removed, range: range, wordRanges: [], oldText: oldText) }
            let words = wordRanges(old: oldText, new: String(decoding: b[ns..<ne], as: UTF16.self), at: ns)
            return TextChange(kind: .modified, range: range, wordRanges: words, oldText: oldText)
        }
    }

    /// Offsets where each line starts (terminator attached to its line), plus the end offset.
    private static func lineStarts(_ u: [UInt16]) -> [Int] {
        var s = [0]
        for (i, c) in u.enumerated() where c == 10 { s.append(i + 1) }
        if s.last! != u.count { s.append(u.count) }
        return s
    }

    private static func tokens(_ s: String, at base: Int) -> [(text: String, range: NSRange)] {
        let marks: [Unicode.GeneralCategory] = [.nonspacingMark, .spacingMark, .enclosingMark]
        var out: [(text: String, range: NSRange)] = []
        var inWord = false, loc = base
        for sc in s.unicodeScalars {
            let n = sc.utf16.count
            let word = sc == "_" || sc.properties.isAlphabetic || sc.properties.numericType != nil
                || marks.contains(sc.properties.generalCategory)
            if word && inWord {
                out[out.count - 1].text.unicodeScalars.append(sc)
                out[out.count - 1].range.length += n
            } else {
                out.append((String(sc), NSRange(location: loc, length: n)))
            }
            inWord = word
            loc += n
        }
        return out
    }

    private static func wordRanges(old: String, new: String, at base: Int) -> [NSRange] {
        let o = tokens(old, at: 0), t = tokens(new, at: base)
        var ids: [String: Int] = [:]
        func id(_ s: String) -> Int {
            if let i = ids[s] { return i }
            ids[s] = ids.count
            return ids.count - 1
        }
        let oi = o.map { id($0.text) }, ni = t.map { id($0.text) }
        guard let m = myers(oi, ni) else { return [] }
        let same = Set(m.map { $0.1 })
        let differing = t.indices.filter { !same.contains($0) }
        guard Double(differing.count) <= 0.6 * Double(t.count) else { return [] }
        var out: [NSRange] = []
        for i in differing {
            let r = t[i].range
            if let l = out.last, NSMaxRange(l) == r.location {
                out[out.count - 1].length += r.length
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// Matched index pairs (in a, in b) of a minimal edit script, or nil if it needs more than `cap` edits.
    private static func myers(_ a: [Int], _ b: [Int]) -> [(Int, Int)]? {
        let n = a.count, m = b.count, maxD = min(n + m, cap), off = maxD + 1
        var v = [Int](repeating: 0, count: 2 * maxD + 3)
        var trace: [[Int]] = []
        for d in 0...maxD {
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                var x = (k == -d || (k != d && v[off + k - 1] < v[off + k + 1])) ? v[off + k + 1] : v[off + k - 1] + 1
                var y = x - k
                while x < n, y < m, a[x] == b[y] { x += 1; y += 1 }
                v[off + k] = x
                if x >= n && y >= m {
                    var out: [(Int, Int)] = []
                    x = n
                    y = m
                    for dd in stride(from: d, through: 0, by: -1) {
                        let pv = trace[dd], pk0 = x - y
                        let pk = (pk0 == -dd || (pk0 != dd && pv[off + pk0 - 1] < pv[off + pk0 + 1])) ? pk0 + 1 : pk0 - 1
                        let px = pv[off + pk], py = px - pk
                        while x > px && y > py { x -= 1; y -= 1; out.append((x, y)) }
                        x = px
                        y = py
                    }
                    return Array(out.reversed())
                }
            }
        }
        return nil
    }
}
