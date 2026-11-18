#if canImport(Sparkle)
import XCTest
@testable import mlisb

final class UpdaterTests: XCTestCase {
    func testConfiguredNeedsFeedAndKey() {
        let feed = "https://example.com/appcast.xml"
        XCTAssertTrue(UpdaterModel.isConfigured(info: ["SUFeedURL": feed, "SUPublicEDKey": "k"]))
        XCTAssertFalse(UpdaterModel.isConfigured(info: ["SUFeedURL": feed]))
        XCTAssertFalse(UpdaterModel.isConfigured(info: ["SUPublicEDKey": "k"]))
        XCTAssertFalse(UpdaterModel.isConfigured(info: ["SUFeedURL": "  ", "SUPublicEDKey": "k"]))
        XCTAssertFalse(UpdaterModel.isConfigured(info: [:]))
    }
}
#endif
