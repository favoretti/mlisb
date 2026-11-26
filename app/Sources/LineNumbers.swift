import MarkdownEngine
import SwiftUI

/// Line numbers in the editor's left margin, counted as `mlisb file.md:N` counts lines.
enum LineNumbers {
    /// Space between the numbers and the review bar.
    static let gap: CGFloat = 4

    /// UTF-16 offset where each line starts; a trailing newline starts no line, as in `LineRequest`.
    static func starts(in text: String) -> [Int] {
        let ns = text as NSString
        var starts = [0]
        while true {
            let end = NSMaxRange(ns.lineRange(for: NSRange(location: starts[starts.count - 1], length: 0)))
            if end >= ns.length { break }
            starts.append(end)
        }
        return starts
    }

    /// Line starts of the editor's text, which shows a paragraph's lines joined at the file's offsets.
    static func starts(displayed: String) -> [Int] { starts(in: SoftBreaks.storage(displayed)) }

    static func digits(lines: Int) -> Int { String(max(lines, 1)).count }

    static func font(forText size: CGFloat) -> NSFont {
        .monospacedDigitSystemFont(ofSize: max(9, (size * 0.75).rounded()), weight: .regular)
    }

    /// Room the left margin keeps beyond its padding for numbers of `digits` digits.
    static func gutterWidth(digits: Int, textSize: CGFloat) -> CGFloat {
        let digit = ("0" as NSString).size(withAttributes: [.font: font(forText: textSize)]).width
        return ceil(digit * CGFloat(digits)) + gap
    }
}

/// Keeps a line-number overlay on the editor's text view while it is shown.
struct LineNumberHost: NSViewRepresentable {
    let textSize: CGFloat
    /// Told the digit count of the last line number whenever it changes.
    let digits: @MainActor (Int) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> LineNumberOverlay { LineNumberOverlay() }

    func updateNSView(_ view: NSView, context: Context) {
        let overlay = context.coordinator
        overlay.fontSize = textSize
        overlay.onDigits = digits
        overlay.attach(from: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: LineNumberOverlay) { coordinator.detach() }
}

final class LineNumberOverlay: EditorOverlay {
    struct Label {
        let number: Int
        let frame: CGRect
    }

    var fontSize = CGFloat(ReadingSettings.defaultSize) { didSet { if fontSize != oldValue { needsDisplay = true } } }
    var onDigits: (@MainActor (Int) -> Void)?
    private var cached: [Int]?
    private var digits = 0

    private var starts: [Int] {
        if let cached { return cached }
        let starts = LineNumbers.starts(displayed: textView?.string ?? "")
        cached = starts
        return starts
    }

    override func textDidChange() {
        cached = nil
        let now = LineNumbers.digits(lines: starts.count)
        guard now != digits else { return }
        digits = now
        Task { [weak self] in self?.onDigits?(now) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: LineNumbers.font(forText: fontSize), .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for label in labels(in: dirtyRect) {
            ("\(label.number)" as NSString).draw(at: label.frame.origin, withAttributes: attributes)
        }
    }

    /// The numbers to draw in `rect`, each inside the screen line where its line starts. A line on the
    /// screen line of the one before it (joined), or on one too low to hold a number (folded), shows none.
    func labels(in rect: NSRect) -> [Label] {
        guard let textView, let layout = textView.textLayoutManager, let content = layout.textContentManager else { return [] }
        let origin = textView.textContainerOrigin
        let font = LineNumbers.font(forText: fontSize)
        let height = ceil(font.ascender - font.descender + font.leading)
        let right = ReviewOverlay.barX(origin) - LineNumbers.gap
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        func label(_ number: Int, top: CGFloat) -> Label {
            let width = ceil(("\(number)" as NSString).size(withAttributes: attributes).width)
            return Label(number: number, frame: CGRect(x: right - width, y: top, width: width, height: height))
        }
        guard !textView.string.isEmpty else {
            let only = label(1, top: origin.y)
            return only.frame.intersects(rect) ? [only] : []
        }

        func line(at offset: Int) -> (top: CGFloat, baseline: CGFloat, height: CGFloat)? {
            guard let location = content.location(content.documentRange.location, offsetBy: offset),
                  let fragment = layout.textLayoutFragment(for: location) else { return nil }
            if fragment.state != .layoutAvailable { layout.ensureLayout(for: fragment.rangeInElement) }
            let inFragment = content.offset(from: fragment.rangeInElement.location, to: location)
            let lines = fragment.textLineFragments
            guard let line = lines.first(where: { NSLocationInRange(inFragment, $0.characterRange) }) ?? lines.first
            else { return nil }
            let top = origin.y + fragment.layoutFragmentFrame.minY + line.typographicBounds.minY
            return (top, top + line.glyphOrigin.y, line.typographicBounds.height)
        }

        let starts = self.starts
        // Start a line above the rect, to know whether its first line shares a screen line.
        var index = 0
        if let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: max(0, rect.minY - origin.y))) {
            let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let after = starts.partitioningIndex { $0 > offset }
            index = max(0, after - 2)
        }
        // Top of the last screen line that is not folded.
        var previousTop: CGFloat?
        for back in stride(from: index - 1, through: 0, by: -1) {
            if let line = line(at: starts[back]), line.height >= height {
                previousTop = line.top
                break
            }
        }
        var out: [Label] = []
        while index < starts.count {
            defer { index += 1 }
            guard let line = line(at: starts[index]) else { continue }
            if line.top > rect.maxY { break }
            if line.height < height { continue }
            defer { previousTop = line.top }
            if let previousTop, abs(line.top - previousTop) < 0.5 { continue }
            // Level with the line's text and inside its screen line; a tall one (image, diagram) gets it at the top.
            let top = line.height > 3 * fontSize
                ? line.top : min(max(line.top, line.baseline - font.ascender), line.top + line.height - height)
            let next = label(index + 1, top: top)
            if next.frame.intersects(rect) { out.append(next) }
        }
        return out
    }
}

private extension Array where Element == Int {
    /// The first index whose element satisfies `predicate`, for a predicate that is false then true.
    func partitioningIndex(where predicate: (Int) -> Bool) -> Int {
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            if predicate(self[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}
