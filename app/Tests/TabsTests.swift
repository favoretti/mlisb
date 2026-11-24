import SwiftUI
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

    func testTheTitleIsTheFullPathAndATabTheName() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.title = "~/notes/a.md"
        window.tab.title = "a.md"
        let tabs = WindowTabs()
        tabs.window = window
        tabs.refresh()
        XCTAssertEqual(tabs.tabs.map(\.title), ["a.md"])

        let home = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        XCTAssertEqual(URL(fileURLWithPath: home + "/notes/a.md").displayPath, "~/notes/a.md")
        XCTAssertEqual(URL(fileURLWithPath: "/usr/share/doc/x.md").displayPath, "/usr/share/doc/x.md")
        XCTAssertEqual(URL(fileURLWithPath: home + "other/x.md").displayPath, home + "other/x.md")
    }

    /// A tab in the background builds its editor only when it is shown.
    func testABackgroundTabBuildsItsEditorWhenSelected() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tabs-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func window(_ name: String) throws -> NSWindow {
            let url = dir.appendingPathComponent(name)
            try Data("# \(name)\n".utf8).write(to: url)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.tabbingMode = .preferred
            window.contentView = NSHostingView(rootView: WorkspaceView(root: .constant(url)))
            return window
        }
        let (a, b) = (try window("a.md"), try window("b.md"))
        defer { b.close(); a.close() }
        a.orderFront(nil)
        a.addTabbedWindow(b, ordered: .above)
        a.tabGroup?.selectedWindow = a
        func settle() async throws { for _ in 0..<20 { try await Task.sleep(for: .milliseconds(50)) } }
        try await settle()
        XCTAssertNotNil(a.contentView?.editorTextView())
        XCTAssertNil(b.contentView?.editorTextView(), "a background tab builds no editor")

        a.tabGroup?.selectedWindow = b
        try await settle()
        XCTAssertNotNil(b.contentView?.editorTextView(), "selecting the tab builds its editor")
    }

    /// Each tab knows the file its window shows, for Reveal in Finder and Copy Path.
    func testATabKnowsItsFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tabs-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try ["a.md", "b.md"].map { name in
            let url = dir.appendingPathComponent(name)
            try Data("# \(name)\n".utf8).write(to: url)
            return url
        }
        let windows = urls.map { url in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.tabbingMode = .preferred
            window.contentView = NSHostingView(rootView: WorkspaceView(root: .constant(url)))
            return window
        }
        defer { windows.reversed().forEach { $0.close() } }
        windows[0].orderFront(nil)
        windows[0].addTabbedWindow(windows[1], ordered: .above)
        for _ in 0..<20 { try await Task.sleep(for: .milliseconds(50)) }
        let tabs = WindowTabs()
        tabs.window = windows[0]
        tabs.refresh()
        XCTAssertEqual(tabs.tabs.map(\.url), urls)
    }
}
