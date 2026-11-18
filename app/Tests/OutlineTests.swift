import XCTest
@testable import mlisb

final class OutlineTests: XCTestCase {
    func testHeadingsSkipFencesAndKeepRanges() {
        let text = """
        # Title
        text #not a heading
        ## Sub ##
        ```sh
        # comment in code
        ```
        ~~~
        ## also code
        ~~~
        ####### seven hashes
        #NoSpace
          ### Indented
        """
        let headings = Outline.headings(in: text)
        XCTAssertEqual(headings.map(\.level), [1, 2, 3])
        XCTAssertEqual(headings.map(\.title), ["Title", "Sub", "Indented"])
        XCTAssertEqual((text as NSString).substring(with: headings[1].range), "## Sub ##")
    }
}
