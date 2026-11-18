import Foundation
import XCTest
@testable import MlisbKit

/// bin/mlisb and app/project.yml repeat FolderSearch.extensions; they must not drift.
final class ExtensionListTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func lists(in file: String, pattern: String) throws -> [Set<String>] {
        let text = try String(contentsOf: root.appending(path: file), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            Set(text[Range($0.range(at: 1), in: text)!].split(whereSeparator: { "|, *.".contains($0) }).map(String.init))
        }
    }

    func testLauncherMatches() throws {
        let found = try lists(in: "bin/mlisb", pattern: #"(\*\.\w+(?:\|\*\.\w+)+)\)"#)
        XCTAssertEqual(found.count, 2)
        for list in found { XCTAssertEqual(list, FolderSearch.extensions) }
    }

    func testProjectMatches() throws {
        let found = try lists(in: "app/project.yml", pattern: #"public\.filename-extension: \[([^\]]+)\]"#)
        XCTAssertEqual(found.count, 1)
        // The system's markdown type already claims these three.
        XCTAssertEqual(found[0].union(["md", "markdown", "mdown"]), FolderSearch.extensions)
    }
}
