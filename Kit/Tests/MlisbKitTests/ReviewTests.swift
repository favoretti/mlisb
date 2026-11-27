import Foundation
import Testing
@testable import MlisbKit

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func nsr(_ l: Int, _ n: Int) -> NSRange { NSRange(location: l, length: n) }

struct TextDiffTests {
    @Test func identical() {
        #expect(TextDiff.changes(from: "a\nb\n", to: "a\nb\n").isEmpty)
        #expect(TextDiff.changes(from: "", to: "").isEmpty)
    }

    @Test func added() {
        let c = TextDiff.changes(from: "a\nb\n", to: "a\nx\nb\n")
        #expect(c == [TextChange(kind: .added, range: nsr(2, 2), wordRanges: [], oldText: "")])
    }

    @Test func removed() {
        let c = TextDiff.changes(from: "a\nx\nb\n", to: "a\nb\n")
        #expect(c == [TextChange(kind: .removed, range: nsr(2, 0), wordRanges: [], oldText: "x\n")])
    }

    @Test func modified() {
        let c = TextDiff.changes(from: "a\nb\nc\n", to: "a\nB\nc\n")
        #expect(c == [TextChange(kind: .modified, range: nsr(2, 2), wordRanges: [nsr(2, 1)], oldText: "b\n")])
    }

    @Test func wholeFileFromEmpty() {
        let c = TextDiff.changes(from: "", to: "a\nb\n")
        #expect(c == [TextChange(kind: .added, range: nsr(0, 4), wordRanges: [], oldText: "")])
    }

    @Test func crlfIsADifference() {
        let c = TextDiff.changes(from: "a\r\nb\r\n", to: "a\nb\n")
        #expect(c.count == 1 && c[0].kind == .modified && c[0].range == nsr(0, 4))
        #expect(c[0].oldText == "a\r\nb\r\n")
    }

    @Test func missingFinalNewline() {
        let c = TextDiff.changes(from: "a\nb", to: "a\nb\n")
        #expect(c.count == 1 && c[0].kind == .modified && c[0].range == nsr(2, 2) && c[0].oldText == "b")
        #expect(TextDiff.changes(from: "a\nb\n", to: "a\nb").first?.range == nsr(2, 1))
    }

    @Test func wordRangesSeparateAndMerged() {
        let sep = TextDiff.changes(from: "alpha beta gamma delta epsilon\n", to: "alpha BETA GAMMA delta epsilon\n")
        #expect(sep[0].wordRanges == [nsr(6, 4), nsr(11, 5)])
        let merged = TextDiff.changes(from: "keep one two keep keep keep\n", to: "keep x-y keep keep keep\n")
        #expect(merged[0].wordRanges == [nsr(5, 3)])
    }

    @Test func sixtyPercentRule() {
        #expect(TextDiff.changes(from: "one", to: "two")[0].wordRanges.isEmpty)
        #expect(TextDiff.changes(from: "one two three four\n", to: "one 2 three four\n")[0].wordRanges == [nsr(4, 1)])
    }

    @Test func unicodeRangesAreUTF16() {
        let c = TextDiff.changes(from: "h\u{E9}llo 😀 world\n", to: "h\u{E9}llo 😀 there\n")
        #expect(c[0].wordRanges == [nsr(9, 5)])
        let m = TextDiff.changes(from: "cafe\u{301} x\n", to: "cafe\u{301} y\n")
        #expect(m[0].wordRanges == [nsr(6, 1)])
        let e = TextDiff.changes(from: "😀\nb\n", to: "😀\nB\n")
        #expect(e[0].range == nsr(3, 2))
    }

    @Test func randomOutputSortedAndDisjoint() {
        var rng = SeededRNG(state: 7)
        for _ in 0..<200 {
            func text() -> String { (0..<Int.random(in: 0..<30, using: &rng)).map { _ in "l\(Int.random(in: 0..<6, using: &rng))\n" }.joined() }
            let new = text(), len = new.utf16.count
            var end = 0
            for c in TextDiff.changes(from: text(), to: new) {
                #expect(c.range.location >= end && NSMaxRange(c.range) <= len)
                end = NSMaxRange(c.range)
            }
        }
    }

    @Test func fastOnLargeDocuments() {
        let lines = (0..<10_000).map { "line number \($0) of the document\n" }
        var edited = lines
        for i in [100, 2500, 2501, 7000, 9990] { edited[i] = "changed \(i)\n" }
        edited.remove(at: 5000)
        let (a, b) = (lines.joined(), edited.joined())
        let clock = ContinuousClock()
        var result: [TextChange] = []
        let few = clock.measure { result = TextDiff.changes(from: a, to: b) }
        #expect(result.count == 5)
        // Loose on purpose: shared CI machines are several times slower. This only catches a quadratic blow-up.
        #expect(few < .seconds(5))

        let other = (0..<10_000).map { "unrelated \($0) text\n" }.joined()
        var unrelated: [TextChange] = []
        let worst = clock.measure { unrelated = TextDiff.changes(from: a, to: other) }
        #expect(unrelated.count == 1 && unrelated[0].kind == .modified)
        #expect(worst < .seconds(10))
        print("diff timings: scattered edits \(few), unrelated \(worst)")
    }
}

struct ChangeReviewTests {
    @Test func externalChangeShowsAndRecomputes() {
        var r = ChangeReview(baseline: "a\nb\nc\n", current: "a\nb\nc\n")
        #expect(r.changes.isEmpty)
        r.externalChange(current: "a\nB\nc\nd\n")
        #expect(r.counts == (added: 1, modified: 1, removed: 0))
        r.externalChange(current: "a\nc\n")
        #expect(r.counts == (added: 0, modified: 0, removed: 1))
        #expect(r.baseline == "a\nb\nc\n")
    }

    @Test func randomEditsOutsideChangesKeepInvariant() {
        var rng = SeededRNG(state: 42)
        var lines = (0..<40).map { "line \($0) has some words\n" }
        let baseline = lines.joined()
        lines[5] = "line 5 was rewritten\n"
        lines.remove(at: 12)
        lines.insert("brand new line\n", at: 20)
        lines[30] = "line 30 also changed\n"
        var text = lines.joined()
        var review = ChangeReview(baseline: baseline, current: text)
        #expect(review.changes.count == 4)

        var applied = 0
        for _ in 0..<300 {
            let ns = text as NSString
            let starts = (0..<ns.length).filter { $0 == 0 || ns.character(at: $0 - 1) == 10 }
            let ls = starts.randomElement(using: &rng)!
            let content = ns.lineRange(for: nsr(ls, 0)).length - 1
            let loc = ls + Int.random(in: 0...content, using: &rng)
            let len = Int.random(in: 0...min(3, ls + content - loc), using: &rng)
            let edit = nsr(loc, len)
            if review.changes.contains(where: { NSMaxRange($0.range) >= edit.location && $0.range.location <= NSMaxRange(edit) }) { continue }
            let word = String((0..<Int.random(in: 0...4, using: &rng)).map { _ in "abcxyz".randomElement(using: &rng)! })
            review.localEdit(range: edit, replacement: word)
            text = ns.replacingCharacters(in: edit, with: word)
            applied += 1

            let expected = TextDiff.changes(from: review.baseline, to: text)
            #expect(expected.map { "\($0.kind) \($0.range)" } == review.changes.map { "\($0.kind) \($0.range)" })
        }
        #expect(applied > 100)
    }

    @Test func editInsideChangeGrowsIt() {
        var r = ChangeReview(baseline: "a\nb\nc\nd\ne\n", current: "a\nB\nc\nD\ne\n")
        r.localEdit(range: nsr(3, 0), replacement: "zz")
        #expect(r.baseline == "a\nb\nc\nd\ne\n")
        #expect(r.changes[0].range == nsr(2, 4) && r.changes[0].wordRanges.isEmpty && r.changes[0].oldText == "b\n")
        #expect(r.changes[1].range == nsr(8, 2) && r.changes[1].wordRanges == [nsr(8, 1)])
        r.localEdit(range: nsr(2, 3), replacement: "")
        #expect(r.changes[0].range == nsr(2, 1))
        #expect(r.changes[1].range == nsr(5, 2))
    }

    @Test func editAdjacentOrOverlappingStaysInChange() {
        var r = ChangeReview(baseline: "a\nb\nc\n", current: "a\nB\nc\n")
        r.localEdit(range: nsr(4, 0), replacement: "tail\n")
        #expect(r.changes.count == 1 && r.changes[0].range == nsr(2, 7) && r.changes[0].oldText == "b\n")
        #expect(r.baseline == "a\nb\nc\n")
    }

    @Test func deletingAnAddedBlockDropsIt() {
        var r = ChangeReview(baseline: "a\n", current: "a\nx\n")
        r.localEdit(range: nsr(2, 2), replacement: "")
        #expect(r.changes.isEmpty && r.baseline == "a\n")
    }

    @Test func markReviewed() {
        var r = ChangeReview(baseline: "a\n", current: "b\n")
        r.markReviewed(current: "b\n")
        #expect(r.baseline == "b\n" && r.changes.isEmpty)
    }

    @Test func markOneReviewedLeavesTheOthers() {
        let current = "a\nB\nc\nnew\nd\n"
        var r = ChangeReview(baseline: "a\nb\nc\nd\ne\n", current: current)
        #expect(r.counts == (added: 1, modified: 1, removed: 1))
        // Each step: the remaining changes are exactly what a fresh diff against the new baseline gives.
        for kind in [TextChange.Kind.added, .removed, .modified] {
            let change = r.changes.first { $0.kind == kind }!
            r.markReviewed(change, current: current)
            #expect(!r.changes.contains(change))
            #expect(TextDiff.changes(from: r.baseline, to: current) == r.changes)
        }
        #expect(r.baseline == current && r.changes.isEmpty)
    }

    @Test func markReviewedIgnoresAStaleChange() {
        var r = ChangeReview(baseline: "a\n", current: "b\n")
        r.markReviewed(TextChange(kind: .added, range: nsr(0, 0), wordRanges: [], oldText: ""), current: "b\n")
        #expect(r.baseline == "a\n" && r.changes.count == 1)
    }

    @Test func nextPreviousWrap() throws {
        let r = ChangeReview(baseline: "1\n2\n3\n4\n5\n", current: "1\nX\n3\nY\n5\n")
        #expect(r.next(after: 0)?.range.location == 2)
        #expect(r.next(after: 2)?.range.location == 6)
        #expect(r.next(after: 6)?.range.location == 2)
        #expect(r.previous(before: 10)?.range.location == 6)
        #expect(r.previous(before: 6)?.range.location == 2)
        #expect(r.previous(before: 2)?.range.location == 6)
        #expect(ChangeReview(baseline: "a", current: "a").next(after: 0) == nil)
    }
}
