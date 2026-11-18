import Foundation
import Testing
@testable import MlisbKit

struct HistoryTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mlisb-history-\(UUID().uuidString)")
    var store: HistoryStore { HistoryStore(directory: dir) }
    let file = URL(fileURLWithPath: "/tmp/mlisb-test/doc.md")
    let day: TimeInterval = 86400

    func files(_ sub: String) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent(sub), includingPropertiesForKeys: nil)) ?? []
    }

    /// Makes a stored blob look `bytes` big without writing them.
    func inflate(_ v: HistoryStore.Version, to bytes: UInt64) throws {
        let h = try FileHandle(forWritingTo: dir.appendingPathComponent("blobs/\(v.id)"))
        try h.truncate(atOffset: bytes)
        try h.close()
    }

    @Test func dedupeAndOrder() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date(timeIntervalSince1970: 1000)
        #expect(try store.record("a", for: file, origin: .opened, date: t0) != nil)
        #expect(try store.record("a", for: file, origin: .saved) == nil)
        try store.record("b", for: file, origin: .external, date: t0 + 1)
        try store.record("a", for: file, origin: .saved, date: t0 + 2)
        let v = store.versions(for: file)
        #expect(v.map(\.origin) == [.saved, .external, .opened])
        #expect(v.map(\.byteCount) == [1, 1, 1])
        #expect(try store.text(of: v[1]) == "b")
        #expect(store.versions(for: URL(fileURLWithPath: "/tmp/other.md")).isEmpty)
    }

    @Test func roundTripAwkwardText() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        for text in ["a\r\nb\r\n", "\u{FEFF}bom", "no trailing newline", "", "emoji 😀 e\u{301}", "\n"] {
            let v = try #require(try store.record(text, for: file, origin: .saved))
            #expect(try store.text(of: v) == text)
            #expect(Array(try store.text(of: v).utf8) == Array(text.utf8))
        }
    }

    @Test func baselinePersistsAcrossInstances() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.reviewedBaseline(for: file) == nil)
        try store.setReviewedBaseline("reviewed\r\n", for: file)
        try store.record("later", for: file, origin: .opened)
        #expect(HistoryStore(directory: dir).reviewedBaseline(for: file) == "reviewed\r\n")
        #expect(HistoryStore(directory: dir).versions(for: file).count == 1)
    }

    @Test func corruptBlobThrows() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let v = try #require(try store.record("hello", for: file, origin: .saved))
        let blob = dir.appendingPathComponent("blobs/\(v.id)")
        try Data("garbage".utf8).write(to: blob)
        #expect(throws: HistoryError.self) { try store.text(of: v) }
        // Valid compressed data whose content does not match the hash.
        try ((Data("other".utf8) as NSData).compressed(using: .zlib) as Data).write(to: blob)
        #expect(throws: HistoryError.self) { try store.text(of: v) }
        try FileManager.default.removeItem(at: blob)
        #expect(throws: HistoryError.self) { try store.text(of: v) }
        // Recording the same text again repairs the blob.
        try store.record("x", for: file, origin: .saved)
        try store.record("hello", for: file, origin: .saved)
        #expect(try store.text(of: v) == "hello")
    }

    @Test func corruptIndexIsAbsent() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.record("a", for: file, origin: .saved)
        try store.setReviewedBaseline("a", for: file)
        let index = try #require(files("index").first)
        try Data("{not json".utf8).write(to: index)
        #expect(store.versions(for: file).isEmpty)
        #expect(store.reviewedBaseline(for: file) == nil)
        #expect(try store.record("a", for: file, origin: .saved) != nil)
        #expect(store.versions(for: file).count == 1)
    }

    @Test func pruneDropsOldButKeepsNewest() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        try store.record("a", for: file, origin: .saved, date: now - 40 * day)
        try store.record("b", for: file, origin: .saved, date: now - 10 * day)
        try store.record("c", for: file, origin: .saved, date: now - 1 * day)
        try store.prune(now: now)
        #expect(store.versions(for: file).count == 2)

        let lone = URL(fileURLWithPath: "/tmp/mlisb-test/lone.md")
        let v = try #require(try store.record("old", for: lone, origin: .saved, date: now - 90 * day))
        try store.prune(now: now)
        #expect(try store.text(of: v) == "old")
    }

    @Test func pruneKeepsBaseline() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        try store.setReviewedBaseline("baseline text", for: file)
        try store.record("baseline text", for: file, origin: .opened, date: now - 60 * day)
        try store.record("newer", for: file, origin: .saved, date: now)
        try store.prune(now: now)
        #expect(store.reviewedBaseline(for: file) == "baseline text")
        #expect(store.versions(for: file).count == 1)
    }

    @Test func prunePerFileSize() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let a = try #require(try store.record("a", for: file, origin: .saved, date: now - 3 * day))
        let b = try #require(try store.record("b", for: file, origin: .saved, date: now - 2 * day))
        try store.record("c", for: file, origin: .saved, date: now - 1 * day)
        try inflate(a, to: 13 << 20)
        try inflate(b, to: 13 << 20)
        try store.prune(now: now)
        #expect(store.versions(for: file).count == 2)
        #expect(store.versions(for: file).last == b)
    }

    @Test func pruneTotalSize() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        var urls: [URL] = []
        for i in 0..<11 {
            let f = URL(fileURLWithPath: "/tmp/mlisb-test/f\(i).md")
            urls.append(f)
            let old = try #require(try store.record("old \(i)", for: f, origin: .saved, date: now - Double(i + 1) * day))
            try store.record("new \(i)", for: f, origin: .saved, date: now)
            try inflate(old, to: 24 << 20)
        }
        try store.prune(now: now)
        #expect(urls.map { store.versions(for: $0).count } == Array(repeating: 2, count: 10) + [1])
    }

    @Test func pruneRemovesUnreferencedBlobsOnly() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let other = URL(fileURLWithPath: "/tmp/mlisb-test/other.md")
        let dead = try #require(try store.record("dead", for: file, origin: .saved, date: now - 50 * day))
        let shared = try #require(try store.record("shared", for: file, origin: .saved, date: now - 40 * day))
        try store.record("shared", for: other, origin: .saved, date: now)
        try store.record("keep", for: file, origin: .saved, date: now)
        try Data("x".utf8).write(to: dir.appendingPathComponent("blobs/stray"))
        try store.prune(now: now)
        let names = Set(files("blobs").map(\.lastPathComponent))
        #expect(names.contains(shared.id))
        #expect(!names.contains(dead.id) && !names.contains("stray"))
        #expect(names.count == 2)
    }
}
