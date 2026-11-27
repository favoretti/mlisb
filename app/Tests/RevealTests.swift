import MlisbKit
import SwiftUI
import XCTest
@testable import mlisb

/// `reveal` backs Next/Previous Change, Contents jumps and `mlisb file.md:N`; it has to move the real editor.
@MainActor final class RevealTests: XCTestCase {
    private func editor(_ text: String) async throws -> (NSTextView, NSClipView, NSWindow) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reveal-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("long.md")
        try Data(text.utf8).write(to: file)
        let document = Document(url: file, history: HistoryStore(directory: dir.appendingPathComponent("History")))
        let window = NSWindow(contentViewController: NSHostingController(rootView: EditorPane(document: document)))
        window.setContentSize(NSSize(width: 800, height: 500))
        window.orderFront(nil)
        try await Task.sleep(for: .seconds(2))
        let textView = try XCTUnwrap(window.contentView?.editorTextView())
        return (textView, try XCTUnwrap(textView.enclosingScrollView?.contentView), window)
    }

    private func isVisible(_ range: NSRange, in textView: NSTextView, clip: NSClipView) -> Bool {
        guard let rect = textView.firstRect(of: range, clip: clip) else { return false }
        return clip.bounds.contains(rect)
    }

    func testRevealScrollsToTextFarDownAndBack() async throws {
        let text = (0..<300).map { "Paragraph \($0) with some words.\n\n" }.joined()
        let (textView, clip, window) = try await editor(text)
        defer { window.close() }
        let far = (text as NSString).range(of: "Paragraph 280 ")
        textView.reveal(far)
        XCTAssertGreaterThan(clip.bounds.minY, 0)
        XCTAssertTrue(isVisible(far, in: textView, clip: clip))
        textView.reveal(NSRange(location: 0, length: 0))
        XCTAssertEqual(clip.bounds.minY, 0)
    }

    func testRevealFindsALineInsideOneLongParagraph() async throws {
        // Single newlines join into one paragraph: its layout fragment starts at the top of the file.
        let text = (0..<300).map { "Line \($0) of one long paragraph.\n" }.joined()
        let (textView, clip, window) = try await editor(text)
        defer { window.close() }
        let far = (text as NSString).range(of: "Line 250 ")
        textView.reveal(far)
        XCTAssertTrue(isVisible(far, in: textView, clip: clip))
    }
}

private extension NSTextView {
    func firstRect(of range: NSRange, clip: NSClipView) -> CGRect? {
        guard let tlm = textLayoutManager,
              let start = tlm.location(tlm.documentRange.location, offsetBy: range.location),
              let end = tlm.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }
        var rect: CGRect?
        tlm.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            rect = frame
            return false
        }
        return rect.map { convert($0.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y), to: clip) }
    }
}
