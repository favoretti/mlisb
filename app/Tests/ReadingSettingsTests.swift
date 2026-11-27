import XCTest
@testable import mlisb

final class ReadingSettingsTests: XCTestCase {
    func testClampStaysInRange() {
        XCTAssertEqual(ReadingSettings.clamp(5), 12)
        XCTAssertEqual(ReadingSettings.clamp(16), 16)
        XCTAssertEqual(ReadingSettings.clamp(99), 24)
    }

    func testStepStopsAtLimits() {
        XCTAssertEqual(ReadingSettings.step(16, by: 1), 17)
        XCTAssertEqual(ReadingSettings.step(24, by: 1), 24)
        XCTAssertEqual(ReadingSettings.step(12, by: -1), 12)
        XCTAssertEqual(ReadingSettings.step(13, by: -1), 12)
    }

    func testSideInset() {
        XCTAssertEqual(ReadingSettings.sideInset(paneWidth: 1000, width: .medium), 120)
        XCTAssertEqual(ReadingSettings.sideInset(paneWidth: 1000, width: .narrow), 200)
        XCTAssertEqual(ReadingSettings.sideInset(paneWidth: 1000, width: .wide), 40)
        XCTAssertEqual(ReadingSettings.sideInset(paneWidth: 1000, width: .full), 28)
        // A pane narrower than the column keeps only the padding.
        XCTAssertEqual(ReadingSettings.sideInset(paneWidth: 500, width: .wide), 28)
    }

    func testLineNumbersLeaveWideBlocksInPlaceWhenTheColumnStays() {
        let off = ReadingSettings.sideInset(paneWidth: 1400, width: .medium, gutter: 0)
        let on = ReadingSettings.sideInset(paneWidth: 1400, width: .medium, gutter: 20)
        XCTAssertEqual(off, on)
        XCTAssertEqual(ReadingSettings.wideOverflow(inset: off), ReadingSettings.wideOverflow(inset: on))
    }

    func testWideBlocksReachThePaddingAtFullWidthWithLineNumbers() {
        for gutter: CGFloat in [0, 20] {
            let inset = ReadingSettings.sideInset(paneWidth: 1000, width: .full, gutter: gutter)
            XCTAssertEqual(1000 - inset + ReadingSettings.wideOverflow(inset: inset), 1000 - ReadingSettings.sidePadding)
        }
    }
}
