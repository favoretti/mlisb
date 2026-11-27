import MlisbKit
import XCTest
@testable import mlisb

@MainActor final class ReviewTests: XCTestCase {
    private var dir: URL!
    private var store: HistoryStore!
    private var file: URL { dir.appendingPathComponent("a.md") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("review-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = HistoryStore(directory: dir.appendingPathComponent("History"))
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func write(_ s: String) throws { try Data(s.utf8).write(to: file) }
    private func open() -> Document { Document(url: file, history: store) }
    private func external(_ d: Document, _ s: String) async throws {
        try write(s)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(d.text, s)
    }

    func testExternalChangeShowsAndTypingDoesNot() async throws {
        try write("one\ntwo\nthree\n")
        let d = open()
        XCTAssertTrue(d.review.changes.isEmpty)
        d.text += "typed\n"
        XCTAssertTrue(d.review.changes.isEmpty)

        d.save()
        try await external(d, "one\nTWO\nthree\ntyped\n")
        XCTAssertEqual(d.review.changes.map(\.kind), [.modified])
    }

    func testTypingInsideAndOutsideAChangeKeepsMarksConsistent() async throws {
        try write("one\ntwo\nthree\n")
        let d = open()
        try await external(d, "one\nTWO\nthree\n")
        d.text = "zero\n" + d.text            // outside, before: the mark moves
        XCTAssertEqual(d.review.changes.first?.range, NSRange(location: 9, length: 4))
        d.text = d.text.replacingOccurrences(of: "TWO", with: "TWOx")  // inside: still one change
        XCTAssertEqual(d.review.changes.count, 1)
        XCTAssertEqual((d.text as NSString).substring(with: d.review.changes[0].range), "TWOx\n")
        d.text += "end\n"                       // outside, after
        XCTAssertEqual(d.review.changes.count, 1)
        XCTAssertEqual(d.review.changes[0].range, NSRange(location: 9, length: 5))
    }

    func testMarkReviewedClearsAndSurvivesANewDocument() async throws {
        try write("a\nb\n")
        let d = open()
        try await external(d, "a\nc\n")
        XCTAssertFalse(d.review.changes.isEmpty)
        d.markReviewed()
        XCTAssertTrue(d.review.changes.isEmpty)
        XCTAssertTrue(open().review.changes.isEmpty)
    }

    func testFileChangedWhileClosedShowsOnReopen() throws {
        try write("a\nb\n")
        _ = open()
        try write("a\nb\nnew\n")
        let d = open()
        XCTAssertEqual(d.review.changes.map(\.kind), [.added])
        XCTAssertEqual(d.text, "a\nb\nnew\n")
    }

    func testVersionsAreRecordedOnceEach() async throws {
        try write("a\n")
        let d = open()
        XCTAssertEqual(store.versions(for: file).map(\.origin), [.opened])
        d.text = "b\n"
        d.save()
        XCTAssertEqual(store.versions(for: file).map(\.origin), [.saved, .opened])
        d.save()
        try await external(d, "c\n")
        XCTAssertEqual(store.versions(for: file).map(\.origin), [.external, .saved, .opened])
        XCTAssertEqual(open().text, "c\n")
        XCTAssertEqual(store.versions(for: file).count, 3)
    }

    func testRestoreBringsBackOldTextAndKeepsTheReplacedOne() throws {
        try write("old\n")
        let d = open()
        let first = try XCTUnwrap(store.versions(for: file).first)
        d.text = "newer\n"
        try d.restore(first)
        XCTAssertEqual(d.text, "old\n")
        let texts = try store.versions(for: file).map { try store.text(of: $0) }
        XCTAssertTrue(texts.contains("newer\n"))
        d.save()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "old\n")
    }

    func testSubtitleNamesOnlyTheKindsThereAre() {
        XCTAssertEqual(reviewSubtitle((added: 2, modified: 8, removed: 0)), "2 added · 8 changed")
        XCTAssertEqual(reviewSubtitle((added: 0, modified: 0, removed: 1)), "1 removed")
        XCTAssertEqual(reviewSubtitle((added: 0, modified: 0, removed: 0)), "")
    }

    func testEditRangeDoesNotSplitSurrogatePairs() {
        let e = Document.edit("a😀b", "a😁b")
        XCTAssertEqual(e.range, NSRange(location: 1, length: 2))
        XCTAssertEqual(e.replacement, "😁")
    }

    func testCompareRowsCollapseLongUnchangedRuns() {
        let old = (1...10).map(String.init).joined(separator: "\n") + "\n"
        let new = old.replacingOccurrences(of: "\n5\n", with: "\nfive\n")
        let rows = Compare.rows(from: old, to: new).map { "\($0.kind) \($0.text)" }
        XCTAssertEqual(rows, ["gap … 2 unchanged lines …", "same 3", "same 4", "removed 5", "added five", "same 6", "same 7",
                              "gap … 3 unchanged lines …"])
    }

    func testCompareRowsMarkTheChangedWordsOfALine() {
        let old = "intro\nmodified: 2026-11-19T16:52:29Z\nend\n"
        let new = "intro\nmodified: 2026-11-19T20:10:31Z\nend\n"
        let rows = Compare.rows(from: old, to: new)
        func marked(_ row: Compare.Row) -> [String] { row.words.map { (row.text as NSString).substring(with: $0) } }
        let removed = rows.first { $0.kind == .removed }!, added = rows.first { $0.kind == .added }!
        XCTAssertEqual(marked(removed), ["19T16", "52", "29Z"])
        XCTAssertEqual(marked(added), ["19T20", "10", "31Z"])
    }
}
