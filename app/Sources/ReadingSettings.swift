import CoreGraphics

/// Reader preferences, stored in UserDefaults as `textSize` (Int), `lineWidth` (raw value) and `showLineNumbers` (Bool).
enum ReadingSettings {
    static let sizes = 12...24
    static let defaultSize = 16
    static let sidePadding: CGFloat = 28

    static func clamp(_ size: Int) -> Int { min(max(size, sizes.lowerBound), sizes.upperBound) }
    static func step(_ size: Int, by delta: Int) -> Int { clamp(size + delta) }

    /// Space on each side of a column of `width` in a pane of `paneWidth`, keeping `gutter` beyond
    /// the padding for line numbers.
    static func sideInset(paneWidth: CGFloat, width: LineWidth, gutter: CGFloat = 0) -> CGFloat {
        guard let points = width.points else { return sidePadding + gutter }
        return max(sidePadding + gutter, (paneWidth - points) / 2)
    }

    /// Room wide blocks reach past the column's right edge, out to the side padding; the gutter is on the left.
    static func wideOverflow(inset: CGFloat) -> CGFloat { inset - sidePadding }
}

enum LineWidth: String, CaseIterable, Identifiable {
    case narrow, medium, wide, full

    var id: Self { self }
    var points: CGFloat? { [.narrow: 600, .medium: 760, .wide: 920][self] }
    var label: String { self == .full ? "Full width" : rawValue.capitalized }
}
