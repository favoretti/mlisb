import CoreGraphics

/// Reader preferences, stored in UserDefaults as `textSize` (Int) and `lineWidth` (raw value).
enum ReadingSettings {
    static let sizes = 12...24
    static let defaultSize = 16
    static let sidePadding: CGFloat = 28

    static func clamp(_ size: Int) -> Int { min(max(size, sizes.lowerBound), sizes.upperBound) }
    static func step(_ size: Int, by delta: Int) -> Int { clamp(size + delta) }

    /// Space on each side of a column of `width` in a pane of `paneWidth`.
    static func sideInset(paneWidth: CGFloat, width: LineWidth) -> CGFloat {
        guard let points = width.points else { return sidePadding }
        return max(sidePadding, (paneWidth - points) / 2)
    }
}

enum LineWidth: String, CaseIterable, Identifiable {
    case narrow, medium, wide, full

    var id: Self { self }
    var points: CGFloat? { [.narrow: 600, .medium: 760, .wide: 920][self] }
    var label: String { self == .full ? "Full width" : rawValue.capitalized }
}
