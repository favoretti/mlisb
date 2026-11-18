import Foundation
import Testing
@testable import MlisbKit

struct LintTests {
    func kinds(_ text: String, file: URL? = nil) -> [LintIssue.Kind] {
        DocumentLint.issues(in: text, fileURL: file).map(\.kind)
    }

    @Test func slugs() {
        #expect(Slug.github("Hello, World! v2.0") == "hello-world-v20")
        #expect(Slug.github("snake_case - dash") == "snake_case---dash")
    }

    @Test func duplicateAnchors() {
        let issues = DocumentLint.issues(in: "# Intro\n\n## Setup\n\n## Setup\n\n[a](#setup-1) [b](#setup)")
        #expect(issues.map(\.kind) == [.duplicateAnchor])
        #expect(issues[0].line == 5)
        #expect(issues[0].range == NSRange(location: 19, length: 8))
    }

    @Test func skippedLevels() {
        #expect(kinds("# A\n### B") == [.skippedHeadingLevel])
        #expect(kinds("# A\n## B\n### C\n# D") == [])
        #expect(kinds("### First\n## Second") == [])
    }

    @Test func references() {
        #expect(kinds("see [text][nope] and [other][]") == [.undefinedReference, .undefinedReference])
        #expect(kinds("see [text][Ref]\n\n[ref]: https://example.com") == [])
        #expect(kinds("- [ ] todo\n- [x] done\nnote[^1]\n\n> [!NOTE]\n> hi\n\n[^1]: foot") == [])
        #expect(kinds("matrix[i][j]") == [])
    }

    @Test func fences() {
        let issues = DocumentLint.issues(in: "text\n\n```swift\ncode")
        #expect(issues.map(\.kind) == [.unclosedFence])
        #expect(issues[0].line == 3)
        #expect(kinds("```\ncode\n```\n") == [])
        #expect(kinds("~~~\ncode\n~~~\n") == [])
        #expect(kinds("````\n```\n````\n") == [])
    }

    @Test func anchorLinks() {
        #expect(kinds("# Design Guide\n[ok](#design-guide) [bad](#nope)") == [.brokenAnchor])
        #expect(kinds("[x](#a)") == [.brokenAnchor])
    }

    @Test func ignoresCode() {
        let md = """
        ```
        # Skipped
        ### Deeper
        [a][nope] [b](#nope) [c](missing.md)
        | a | b |
        |---|---|
        | 1 |
        ```

        Inline `[a][nope] [b](#nope)` too.
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("x.md")
        #expect(kinds(md, file: url) == [])
    }

    @Test func relativeLinks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mlisb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("my file.md"), atomically: true, encoding: .utf8)
        let doc = dir.appendingPathComponent("doc.md")
        let md = "[ok](my%20file.md#top) ![img](pic.png) [web](https://example.com/x) [abs](/x) [mail](mailto:a@b.c)"
        let issues = DocumentLint.issues(in: md, fileURL: doc)
        #expect(issues.map(\.kind) == [.brokenLink])
        #expect(issues[0].message.contains("pic.png"))
        #expect(kinds(md) == [])
    }

    @Test func tables() {
        #expect(kinds("| a | b |\n|---|---|\n| 1 | 2 |\n| 3 |\n| 4 | 5 | 6 |") == [.tableColumnMismatch, .tableColumnMismatch])
        #expect(kinds("a | b\n--|--\n1 | 2") == [])
        #expect(kinds("| a | b |\n|---|---|\n| x \\| y | 2 |\n\nplain | text") == [])
    }

    @Test func sortedByLine() {
        let lines = DocumentLint.issues(in: "# A\n### B\n[a][y]\n```").map(\.line)
        #expect(lines == [2, 3, 4])
    }
}
