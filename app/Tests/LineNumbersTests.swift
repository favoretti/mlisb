import AppKit
import XCTest
@testable import mlisb

@MainActor final class LineNumbersTests: XCTestCase {
    func testLineStartsWithLF() {
        XCTAssertEqual(LineNumbers.starts(in: "one\ntwo\nthree"), [0, 4, 8])
    }

    func testLineStartsWithCRLF() {
        XCTAssertEqual(LineNumbers.starts(in: "one\r\ntwo\r\nthree"), [0, 5, 10])
    }

    func testTrailingNewlineStartsNoLine() {
        XCTAssertEqual(LineNumbers.starts(in: "a\nb\n"), [0, 2])
    }

    func testEmptyTextHasOneLine() {
        XCTAssertEqual(LineNumbers.starts(in: ""), [0])
    }

    /// Number N is the line `mlisb file.md:N` opens.
    func testStartsAgreeWithLineRequests() {
        let text = "one\ntwo\r\nthree 😀\n\nfive\n"
        let starts = LineNumbers.starts(in: text)
        for (index, start) in starts.enumerated() {
            XCTAssertEqual(LineRequest.offset(ofLine: index + 1, in: text), start)
        }
    }

    /// The editor shows a paragraph's lines joined, at the same offsets as the file's.
    func testSoftBreakJoinedTextKeepsTheFileLines() {
        XCTAssertEqual(LineNumbers.starts(displayed: "one\u{2005}two\nthree"), [0, 4, 8])
        XCTAssertEqual(LineNumbers.starts(displayed: "one\u{FE03}\u{2005}two"), [0, 5])
        XCTAssertEqual(LineNumbers.starts(displayed: "- item\u{2005}\u{FE00}\u{FE00}more\nnext"), [0, 7, 14])
    }

    func testGutterGrowsWithDigits() {
        XCTAssertEqual(LineNumbers.digits(lines: 0), 1)
        XCTAssertEqual(LineNumbers.digits(lines: 999), 3)
        XCTAssertEqual(LineNumbers.digits(lines: 1000), 4)
        XCTAssertGreaterThan(LineNumbers.gutterWidth(digits: 4, textSize: 16), LineNumbers.gutterWidth(digits: 3, textSize: 16))
        XCTAssertLessThan(LineNumbers.font(forText: 16).pointSize, 16)
    }

    func testSideInsetMakesRoomForTheGutter() {
        XCTAssertEqual(ReadingSettings.sideInset(paneWidth: 1000, width: .full, gutter: 30), 58)
        XCTAssertEqual(ReadingSettings.sideInset(paneWidth: 1000, width: .medium, gutter: 30), 120)
        XCTAssertEqual(ReadingSettings.sideInset(paneWidth: 500, width: .wide, gutter: 30), 58)
    }

    // MARK: Overlay

    private func overlay(_ text: NSAttributedString, inset: CGFloat = 120) -> LineNumberOverlay {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 100_000)
        textView.textContainerInset = NSSize(width: inset, height: 12)
        textView.textStorage?.setAttributedString(text)
        let layout = textView.textLayoutManager!
        layout.ensureLayout(for: layout.documentRange)
        let overlay = LineNumberOverlay()
        overlay.fontSize = 16
        overlay.textView = textView
        textView.addSubview(overlay)
        return overlay
    }

    private func plain(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 16)])
    }

    private func assertNoOverlap(_ labels: [LineNumberOverlay.Label], file: StaticString = #filePath, line: UInt = #line) {
        for (a, b) in zip(labels, labels.dropFirst()) {
            XCTAssertLessThanOrEqual(a.frame.maxY, b.frame.minY, "\(a.number) and \(b.number)", file: file, line: line)
        }
    }

    func testEachLineGetsItsNumberInOrder() {
        let labels = overlay(plain("one\ntwo\n\nfour")).labels(in: NSRect(x: 0, y: 0, width: 800, height: 2000))
        XCTAssertEqual(labels.map(\.number), [1, 2, 3, 4])
        assertNoOverlap(labels)
    }

    func testJoinedLinesShowOneNumberPerScreenLine() {
        let labels = overlay(plain("one\u{2005}two\nthree")).labels(in: NSRect(x: 0, y: 0, width: 800, height: 2000))
        XCTAssertEqual(labels.map(\.number), [1, 3])
    }

    /// Folded lines (diagram source, hidden HTML tags) are laid out one point high, as the engine does.
    func testFoldedLinesDoNotOverlap() {
        let folded = NSMutableParagraphStyle()
        folded.maximumLineHeight = 1
        let text = NSMutableAttributedString(attributedString: plain("before\n"))
        text.append(NSAttributedString(string: "```mermaid\nA-->B\nB-->C\n```\n",
                                       attributes: [.font: NSFont.systemFont(ofSize: 0.1), .paragraphStyle: folded]))
        text.append(plain("after"))
        let labels = overlay(text).labels(in: NSRect(x: 0, y: 0, width: 800, height: 2000))
        XCTAssertEqual(labels.first?.number, 1)
        XCTAssertTrue(labels.map(\.number).contains(2))
        assertNoOverlap(labels)
    }

    func testThousandLinesAtFullWidthStayLeftOfTheReviewBar() {
        let lines = 1200
        let text = (1...lines).map { "Line \($0) of a long file" }.joined(separator: "\n")
        let gutter = LineNumbers.gutterWidth(digits: LineNumbers.digits(lines: lines), textSize: 16)
        let inset = ReadingSettings.sideInset(paneWidth: 800, width: .full, gutter: gutter)
        let overlay = overlay(plain(text), inset: inset)
        let origin = overlay.textView!.textContainerOrigin
        let bar = ReviewOverlay.barX(origin)
        for rect in [NSRect(x: 0, y: 0, width: 800, height: 1500), NSRect(x: 0, y: 20_000, width: 800, height: 1500)] {
            let labels = overlay.labels(in: rect)
            XCTAssertFalse(labels.isEmpty)
            assertNoOverlap(labels)
            for label in labels {
                XCTAssertLessThanOrEqual(label.frame.maxX, bar - LineNumbers.gap, "\(label.number)")
                XCTAssertGreaterThanOrEqual(label.frame.minX, 16, "\(label.number)")
            }
        }
        let last = overlay.labels(in: NSRect(x: 0, y: 0, width: 800, height: 100_000)).last
        XCTAssertEqual(last?.number, lines)
    }
}
