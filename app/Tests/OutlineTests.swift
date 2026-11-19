import MarkdownEngine
import SwiftUI
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

    /// A heading far down a long document has no layout yet; jumping to it must still scroll there.
    @MainActor func testRevealScrollsToAHeadingFarDown() async throws {
        let text = "# Top\n\n" + (1...60).map { "## Section \($0)\n\n" + String(repeating: "Words in a paragraph. ", count: 30) + "\n" }.joined(separator: "\n")
        var stored = text
        let editor = NativeTextViewWrapper(text: Binding(get: { stored }, set: { stored = $0 }), configuration: .default)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: editor)
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        let textView = try XCTUnwrap(window.contentView?.editorTextView())
        let target = try XCTUnwrap(Outline.headings(in: textView.string).last)
        textView.reveal(NSRange(location: target.range.location, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        let tlm = try XCTUnwrap(textView.textLayoutManager)
        let location = try XCTUnwrap(tlm.location(tlm.documentRange.location, offsetBy: target.range.location))
        let frame = try XCTUnwrap(tlm.textLayoutFragment(for: location)).layoutFragmentFrame
        XCTAssertTrue(textView.visibleRect.intersects(frame), "visible \(textView.visibleRect) heading \(frame)")
        XCTAssertEqual(textView.selectedRange().location, target.range.location)
    }
}
