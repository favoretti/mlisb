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
}
