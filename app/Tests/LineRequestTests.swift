import XCTest
@testable import mlisb

final class LineRequestTests: XCTestCase {
    private func parse(_ s: String) -> LineRequest? { URL(string: s).flatMap(LineRequest.init(url:)) }

    func testParsesFileAndLine() {
        let r = parse("mlisb://line?file=%2Ftmp%2Fmy%20notes%3A1.md&line=42")
        XCTAssertEqual(r?.file.path, "/tmp/my notes:1.md")
        XCTAssertEqual(r?.line, 42)
    }

    func testIgnoresBadRequests() {
        XCTAssertNil(parse("mlisb://line?file=%2Ftmp%2Fa.md"))
        XCTAssertNil(parse("mlisb://line?line=3"))
        XCTAssertNil(parse("mlisb://line?file=%2Ftmp%2Fa.md&line=x"))
        XCTAssertNil(parse("mlisb://line?file=%2Ftmp%2Fa.md&line=0"))
        XCTAssertNil(parse("mlisb://line?file=a.md&line=3"))
        XCTAssertNil(parse("mlisb://other?file=%2Ftmp%2Fa.md&line=3"))
        XCTAssertNil(parse("https://line?file=%2Ftmp%2Fa.md&line=3"))
    }

    func testOffsetOfLine() {
        let text = "one\ntwo\r\nthree 😀\nfour"
        XCTAssertEqual(LineRequest.offset(ofLine: 1, in: text), 0)
        XCTAssertEqual(LineRequest.offset(ofLine: 2, in: text), 4)
        XCTAssertEqual(LineRequest.offset(ofLine: 3, in: text), 9)
        XCTAssertEqual(LineRequest.offset(ofLine: 4, in: text), 18)
        XCTAssertEqual(LineRequest.offset(ofLine: 99, in: text), 18)
    }

    func testOffsetIgnoresTrailingNewlineAndEmptyText() {
        XCTAssertEqual(LineRequest.offset(ofLine: 9, in: "a\nb\n"), 2)
        XCTAssertEqual(LineRequest.offset(ofLine: 5, in: ""), 0)
    }
}
