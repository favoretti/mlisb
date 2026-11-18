import XCTest
@testable import mlisb

final class LinkTargetTests: XCTestCase {
    private let doc = URL(fileURLWithPath: "/repo/docs/guide.md")

    func testClassification() {
        XCTAssertEqual(LinkTarget("#Setup-Notes", from: doc), .anchor("setup-notes"))
        XCTAssertEqual(LinkTarget("https://example.com/a?b=1", from: doc), .url(URL(string: "https://example.com/a?b=1")!))
        XCTAssertEqual(LinkTarget("MAILTO:a@b.c", from: doc), .url(URL(string: "MAILTO:a@b.c")!))
        XCTAssertEqual(LinkTarget("vscode://file/x", from: doc), .url(URL(string: "vscode://file/x")!))
        XCTAssertEqual(LinkTarget("javascript:alert(1)", from: doc), .url(URL(string: "javascript:alert(1)")!))
    }

    func testLocalFilesResolveAgainstTheDocument() {
        XCTAssertEqual(LinkTarget("other.md", from: doc), .file(URL(fileURLWithPath: "/repo/docs/other.md")))
        XCTAssertEqual(LinkTarget("./sub/My%20Note.md#part", from: doc), .file(URL(fileURLWithPath: "/repo/docs/sub/My Note.md")))
        XCTAssertEqual(LinkTarget("../README.md", from: doc), .file(URL(fileURLWithPath: "/repo/README.md")))
        XCTAssertEqual(LinkTarget("/abs/x.md", from: doc), .file(URL(fileURLWithPath: "/abs/x.md")))
        XCTAssertEqual(LinkTarget("file:///abs/run.command", from: doc), .file(URL(fileURLWithPath: "/abs/run.command")))
    }

    func testHeadingSlug() {
        XCTAssertEqual(Heading(level: 2, title: "What's new: v2.0 (beta)", range: NSRange()).slug, "whats-new-v20-beta")
    }
}
