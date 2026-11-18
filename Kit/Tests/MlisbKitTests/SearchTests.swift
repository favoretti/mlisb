import Foundation
import Testing
@testable import MlisbKit

struct SearchTests {
    @Test func fuzzyRanking() {
        let r1 = FuzzyMatch.rank(["random-notes/draft.md", "README.md"], query: "rdm") { $0 }
        #expect(r1.first == "README.md")
        let r2 = FuzzyMatch.rank(["docs/explanation.md", "PLAN.md"], query: "plan") { $0 }
        #expect(r2.first == "PLAN.md")
        #expect(FuzzyMatch.score("dsg", in: "docs/design-guide.md") != nil)
        #expect(FuzzyMatch.score("zzz", in: "README.md") == nil)
        #expect(FuzzyMatch.score("MD", in: "readme.md") != nil)
    }

    @Test func fuzzyTiesAndEmptyQuery() {
        #expect(FuzzyMatch.rank(["b", "a", "c"], query: "") { $0 } == ["b", "a", "c"])
        #expect(FuzzyMatch.rank(["ab1", "ab2"], query: "ab") { $0 } == ["ab1", "ab2"])
        #expect(FuzzyMatch.score("a", in: "a") ?? 0 > FuzzyMatch.score("a", in: "abc") ?? 0)
    }

    func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mlisb-\(UUID().uuidString)")
        let fm = FileManager.default
        for d in ["docs", "node_modules/x", ".hidden", "build"] {
            try fm.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        let files: [String: Data] = [
            "a.md": Data("Hello World\nsecond hello line\r\nthird".utf8),
            "docs/b.markdown": Data("nothing\nHELLO again".utf8),
            "docs/c.txt": Data("hello".utf8),
            "node_modules/x/d.md": Data("hello".utf8),
            ".hidden/e.md": Data("hello".utf8),
            "build/f.md": Data("hello".utf8),
            "bad.md": Data([0xFF, 0xFE, 0x68, 0x65, 0x6C, 0x6C, 0x6F]),
        ]
        for (name, data) in files { try data.write(to: root.appendingPathComponent(name)) }
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("node_modules"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("docslink"), withDestinationURL: root.appendingPathComponent("docs"))
        return root
    }

    @Test func listsMarkdownFiles() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.resolvingSymlinksInPath().path + "/"
        let names = FolderSearch.markdownFiles(in: root).map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "") }
        #expect(names == ["a.md", "bad.md", "docs/b.markdown"])
        #expect(FolderSearch.markdownFiles(in: root, limit: 1).count == 1)
    }

    @Test func searchesCaseInsensitively() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await FolderSearch.search("hello", in: root)
        #expect(result.map { $0.url.lastPathComponent } == ["a.md", "b.markdown"])
        let a = result[0].matches
        #expect(a.map(\.line) == [1, 2])
        #expect(a[0].lineText == "Hello World")
        #expect(a[1].lineText == "second hello line")
        #expect(a[0].range == NSRange(location: 0, length: 5))
    }

    @Test func optionsAndErrors() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var o = SearchOptions()
        o.caseSensitive = true
        #expect(try await FolderSearch.search("hello", in: root, options: o).first?.matches.count == 1)
        o = SearchOptions()
        o.wholeWord = true
        #expect(try await FolderSearch.search("hell", in: root, options: o).isEmpty)
        o = SearchOptions()
        o.regex = true
        #expect(try await FolderSearch.search("h.llo\\s+w", in: root, options: o).count == 1)
        #expect(try await FolderSearch.search("", in: root).isEmpty)
        do {
            _ = try await FolderSearch.search("(", in: root, options: o)
            Issue.record("expected an error")
        } catch {
            #expect(error.localizedDescription.contains("regular expression"))
        }
        #expect(try await FolderSearch.search("hello", in: root, maxMatches: 1).flatMap(\.matches).count == 1)
    }

    @Test func truncatesLongLines() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mlisb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let line = String(repeating: "x", count: 1000) + "needle" + String(repeating: "y", count: 1000)
        try line.write(to: root.appendingPathComponent("long.md"), atomically: true, encoding: .utf8)
        let m = try await FolderSearch.search("needle", in: root)[0].matches[0]
        #expect(m.lineText.count == 300 && m.lineText.contains("needle"))
        #expect(m.range == NSRange(location: 1000, length: 6))
    }
}
