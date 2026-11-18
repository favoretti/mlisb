import AppKit
import MlisbKit
import XCTest
@testable import mlisb

@MainActor
final class NavigationTests: XCTestCase {
    private func menu(_ spec: [(String, [String])]) -> NSMenu {
        let main = NSMenu()
        main.autoenablesItems = false
        for (title, items) in spec {
            let sub = NSMenu(title: title)
            sub.autoenablesItems = false
            for t in items { sub.addItem(t == "-" ? .separator() : NSMenuItem(title: t, action: nil, keyEquivalent: "")) }
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            top.submenu = sub
            main.addItem(top)
        }
        return main
    }

    func testCommandsSkipExcludedItems() {
        let main = menu([("File", ["New", "-", "Open Quickly…", "Print"]), ("Edit", ["Copy", "Services"])])
        let services = main.items[1].submenu!.items[1]
        services.submenu = NSMenu(title: "Services")
        services.submenu!.addItem(NSMenuItem(title: "Send", action: nil, keyEquivalent: ""))
        main.items[0].submenu!.items[3].isEnabled = false
        let window = NSMenuItem(title: "Notes", action: #selector(NSWindow.makeKeyAndOrderFront(_:)), keyEquivalent: "")
        main.items[1].submenu!.addItem(window)
        let titles = QuickOpen.commands(in: main, services: services.submenu).map(\.title)
        XCTAssertEqual(titles, ["File ▸ New", "Edit ▸ Copy"])
    }

    func testShortcutText() {
        let item = NSMenuItem(title: "x", action: nil, keyEquivalent: "o")
        item.keyEquivalentModifierMask = [.command, .shift]
        XCTAssertEqual(QuickOpen.shortcut(item), "⇧⌘O")
    }

    private let root = URL(fileURLWithPath: "/w")
    private func file(_ p: String, _ t: Double) -> (url: URL, modified: Date) { (root.appending(path: p), Date(timeIntervalSince1970: t)) }
    private func entries(_ query: String, files: [(url: URL, modified: Date)]) -> [QuickEntry] {
        let item = NSMenuItem(title: "Bold", action: nil, keyEquivalent: "b")
        return QuickOpen.entries(
            files: files, root: root, headings: Outline.headings(in: "# Intro\n## Setup steps\n"),
            commands: [MenuCommand(title: "Format ▸ Bold", shortcut: "⌘B", item: item)], query: query)
    }

    func testEmptyQueryOrderAndRelativePaths() {
        let list = entries("", files: [file("a.md", 1), file("docs/b.md", 3), file("c.md", 2)])
        XCTAssertEqual(list.map(\.title), ["docs/b.md", "c.md", "a.md", "Intro", "Setup steps", "Format ▸ Bold"])
        XCTAssertEqual(list.map(\.indent), [0, 0, 0, 0, 1, 0])
        XCTAssertEqual(list.last?.detail, "⌘B")
    }

    func testEmptyQueryCapsFiles() {
        let many = (0..<80).map { file("f\($0).md", Double($0)) }
        XCTAssertEqual(entries("", files: many).filter { if case .file = $0.kind { true } else { false } }.count, 50)
    }

    func testRankingAcrossKinds() {
        let list = entries("setup", files: [file("setup.md", 1), file("other/readme.md", 2)])
        XCTAssertEqual(list.map(\.title), ["setup.md", "Setup steps"])
        XCTAssertEqual(entries("bold", files: []).first?.title, "Format ▸ Bold")
    }

    func testLineRequestSelection() {
        let url = URL(fileURLWithPath: "/a.md")
        XCTAssertEqual(LineRequest(file: url, range: NSRange(location: 2, length: 3)).selection(in: "abcdefg"), NSRange(location: 2, length: 3))
        XCTAssertEqual(LineRequest(file: url, range: NSRange(location: 5, length: 9)).selection(in: "abcdefg"), NSRange(location: 5, length: 2))
        XCTAssertEqual(LineRequest(file: url, range: NSRange(location: 50, length: 1)).selection(in: "abc"), NSRange(location: 3, length: 0))
    }

    func testLintURLNeedsReadableFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNotNil(InspectorView.lintURL(dir.appending(path: "a.md")))
        XCTAssertNil(InspectorView.lintURL(dir.appending(path: "missing/a.md")))
    }
}
