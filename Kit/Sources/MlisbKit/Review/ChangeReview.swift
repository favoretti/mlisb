import Foundation

public struct ChangeReview: Sendable {
    public private(set) var baseline: String
    public private(set) var changes: [TextChange]

    public init(baseline: String, current: String) {
        self.baseline = baseline
        changes = TextDiff.changes(from: baseline, to: current)
    }

    /// The file was changed by another program: recompute against the baseline.
    public mutating func externalChange(current: String) {
        changes = TextDiff.changes(from: baseline, to: current)
    }

    /// Everything has been reviewed: the baseline becomes `current`, no changes remain.
    public mutating func markReviewed(current: String) {
        baseline = current
        changes = []
    }

    /// The reader typed: `range` (UTF-16, in the text before the edit) was replaced by `replacement`.
    public mutating func localEdit(range: NSRange, replacement: String) {
        let delta = replacement.utf16.count - range.length
        let end = NSMaxRange(range)
        // nets[i]: current length minus baseline length over the changes before change i.
        var nets = [0]
        for c in changes { nets.append(nets.last! + c.range.length - c.oldText.utf16.count) }
        // Touching is closed on both ends, so an adjacent edit joins the change instead of merging two blocks.
        let first = changes.firstIndex { NSMaxRange($0.range) >= range.location } ?? changes.count
        let last = changes.lastIndex { $0.range.location <= end } ?? -1

        if first > last {
            let r = NSRange(location: range.location - nets[first], length: range.length)
            baseline = (baseline as NSString).replacingCharacters(in: r, with: replacement)
            shift(from: first, by: delta)
            return
        }

        let start = min(changes[first].range.location, range.location)
        let oldEnd = max(NSMaxRange(changes[last].range), end)
        let baseStart = start - nets[first]
        let old = (baseline as NSString).substring(
            with: NSRange(location: baseStart, length: oldEnd - nets[last + 1] - baseStart))
        let merged = NSRange(location: start, length: oldEnd + delta - start)
        shift(from: last + 1, by: delta)
        let change = TextChange(kind: merged.length == 0 ? .removed : old.isEmpty ? .added : .modified,
                                range: merged, wordRanges: [], oldText: old)
        changes.replaceSubrange(first...last, with: merged.length == 0 && old.isEmpty ? [] : [change])
    }

    private mutating func shift(from i: Int, by delta: Int) {
        for j in i..<changes.count {
            changes[j].range.location += delta
            changes[j].wordRanges = changes[j].wordRanges.map { NSRange(location: $0.location + delta, length: $0.length) }
        }
    }

    public func next(after location: Int) -> TextChange? {
        changes.first { $0.range.location > location } ?? changes.first
    }

    public func previous(before location: Int) -> TextChange? {
        changes.last { $0.range.location < location } ?? changes.last
    }

    public var counts: (added: Int, modified: Int, removed: Int) {
        (changes.filter { $0.kind == .added }.count,
         changes.filter { $0.kind == .modified }.count,
         changes.filter { $0.kind == .removed }.count)
    }
}
