import Foundation

public enum FuzzyMatch {
    /// nil when `query` is not a subsequence of `candidate` (case-insensitive). Higher is better.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let q = query.map { $0.lowercased() }
        let c = Array(candidate)
        let lower = c.map { $0.lowercased() }
        if q.isEmpty { return 0 }
        guard q.count <= c.count else { return nil }

        func bonus(_ j: Int) -> Int {
            if j == 0 { return 30 }
            let p = c[j - 1]
            return "/-_. ".contains(p) || (p.isLowercase && c[j].isUppercase) ? 20 : 0
        }

        // best[j]: top score with the current query character matched at candidate index j.
        var best: [Int?] = (0..<c.count).map { lower[$0] == q[0] ? 10 + bonus($0) : nil }
        for i in 1..<q.count {
            var next = [Int?](repeating: nil, count: c.count)
            for j in i..<c.count where lower[j] == q[i] {
                var top: Int?
                for k in (i - 1)..<j {
                    guard let b = best[k] else { continue }
                    let s = b + (k == j - 1 ? 15 : -2 * (j - k - 1))
                    if top == nil || s > top! { top = s }
                }
                if let top { next[j] = top + 10 + bonus(j) }
            }
            best = next
        }
        guard let m = best.compactMap({ $0 }).max() else { return nil }
        return m - c.count
    }

    /// Candidates that match, best first; ties keep the input order. An empty query returns all, in order.
    public static func rank<T>(_ items: [T], query: String, by text: (T) -> String) -> [T] {
        if query.isEmpty { return items }
        let scored = items.enumerated().compactMap { i, item in
            score(query, in: text(item)).map { (item, $0, i) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }.map { $0.0 }
    }
}
