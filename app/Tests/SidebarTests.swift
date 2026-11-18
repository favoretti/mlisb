import XCTest
@testable import mlisb

@MainActor final class SidebarTests: XCTestCase {
    var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private func make(_ names: String...) throws {
        for n in names {
            let url = dir.appending(component: n)
            if n.hasSuffix("/") { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            else { try Data("x".utf8).write(to: url) }
        }
    }

    func testListFiltersAndSorts() throws {
        try make("b/", "a/", ".hidden/", ".x.md", "File 10.md", "File 2.md", "pic.PNG", "notes.txt", "doc.pdf", "z.markdown")
        XCTAssertEqual(FS.list(dir).map(\.url.lastPathComponent),
                       ["a", "b", "doc.pdf", "File 2.md", "File 10.md", "pic.PNG", "z.markdown"])
        XCTAssertEqual(FS.list(dir).map(\.isDir), [true, true] + Array(repeating: false, count: 5))
    }

    func testUniqueURL() throws {
        XCTAssertEqual(FS.uniqueURL(in: dir, name: "Untitled", ext: "md").lastPathComponent, "Untitled.md")
        try make("Untitled.md", "Untitled 2.md")
        XCTAssertEqual(FS.uniqueURL(in: dir, name: "Untitled", ext: "md").lastPathComponent, "Untitled 3.md")
        XCTAssertEqual(FS.uniqueURL(in: dir, name: "Untitled Folder").lastPathComponent, "Untitled Folder")
    }

    func testMoveRefusesToOverwriteOrEnterItself() throws {
        try make("a.md", "b.md", "d/")
        XCTAssertThrowsError(try FS.move(dir.appending(component: "a.md"), to: dir.appending(component: "b.md")))
        XCTAssertThrowsError(try FS.move(dir.appending(component: "d"), to: dir.appending(path: "d/d")))
        try FS.move(dir.appending(component: "a.md"), to: dir.appending(path: "d/a.md"))
        XCTAssertEqual(FS.list(dir.appending(component: "d")).map(\.url.lastPathComponent), ["a.md"])
    }

    func testInitialSelectionPrefersReadme() throws {
        try make("a.md", "ReadMe.MD", "z/")
        XCTAssertEqual(FolderModel(root: dir).selection?.lastPathComponent, "ReadMe.MD")
    }

    func testInitialSelectionFallsBackToFirstMarkdown() throws {
        try make("b.md", "a.md")
        XCTAssertEqual(FolderModel(root: dir).selection?.lastPathComponent, "a.md")
    }

    func testRenameAndMoveFollowOpenFile() throws {
        try make("README.md", "d/")
        let model = FolderModel(root: dir)
        model.rename(dir.appending(component: "README.md"), to: "Guide.md")
        XCTAssertEqual(model.selection?.lastPathComponent, "Guide.md")
        XCTAssertEqual(model.document?.url.lastPathComponent, "Guide.md")
        model.move([dir.appending(component: "Guide.md")], into: dir.appending(component: "d"))
        XCTAssertEqual(model.selection?.deletingLastPathComponent().lastPathComponent, "d")
        XCTAssertEqual(model.document?.url, model.selection)
        XCTAssertNil(model.error)
    }

    func testRenameOverExistingSetsErrorAndKeepsFile() throws {
        try make("README.md", "other.md")
        let model = FolderModel(root: dir)
        model.rename(dir.appending(component: "README.md"), to: "other.md")
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.selection?.lastPathComponent, "README.md")
    }

    func testTrashClearsSelection() throws {
        try make("README.md")
        let model = FolderModel(root: dir)
        model.trash(dir.appending(component: "README.md"))
        XCTAssertNil(model.error)
        XCTAssertNil(model.selection)
        XCTAssertNil(model.document)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(component: "README.md").path))
    }
}
