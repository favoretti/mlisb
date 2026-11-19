import XCTest
@testable import mlisb

@MainActor final class HelpTests: XCTestCase {
    func testBuiltInHelpOpensReadOnly() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "mlisb Help", withExtension: "md"))
        let document = Document(url: url)
        XCTAssertTrue(document.text.hasPrefix("# mlisb Help"))
        XCTAssertNil(document.error)
        XCTAssertTrue(document.isReadOnly)
    }

    func testThirdPartyNoticesOpenReadOnlyWithEveryBundledLicense() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Third-Party Notices", withExtension: "md"))
        let document = Document(url: url)
        XCTAssertTrue(document.text.hasPrefix("# Third-party notices"))
        XCTAssertTrue(document.isReadOnly)
        for section in ["## MarkdownEngine", "## Sparkle", "## JavaScript packages in the diagram page", "### mermaid "] {
            XCTAssertTrue(document.text.contains(section), section)
        }
        // Every license text sits in a fence that closes, so it reads as a block and wraps.
        let fences = document.text.split(separator: "\n").filter { $0.hasPrefix("```") }
        XCTAssertEqual(fences.count % 2, 0)
    }
}
