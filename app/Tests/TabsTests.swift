import XCTest
@testable import mlisb

@MainActor final class TabsTests: XCTestCase {
    func testTheStripFollowsAndDrivesTheWindowTabs() {
        func window(_ title: String) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = title
            return window
        }
        let (a, b) = (window("a.md"), window("b.md"))
        defer { a.close() }
        let tabs = WindowTabs()
        tabs.window = a

        tabs.refresh()
        XCTAssertEqual(tabs.tabs.map(\.title), ["a.md"])
        // Looking at a window without tabs must not give it a tab group of its own.
        XCTAssertNil(a.tabbedWindows)

        a.orderFront(nil)
        a.addTabbedWindow(b, ordered: .above)
        tabs.refresh()
        XCTAssertEqual(tabs.tabs.map(\.title), ["a.md", "b.md"])
        XCTAssertEqual(tabs.selected, ObjectIdentifier(a))

        tabs.select(ObjectIdentifier(b))
        XCTAssertTrue(a.tabGroup?.selectedWindow === b)
        tabs.refresh()
        XCTAssertEqual(tabs.selected, ObjectIdentifier(b))

        tabs.close(ObjectIdentifier(b))
        tabs.refresh()
        XCTAssertEqual(tabs.tabs.map(\.title), ["a.md"])
    }
}
