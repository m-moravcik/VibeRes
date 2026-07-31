import Foundation

/// Splits a display's point sizes into the ones worth showing immediately and a
/// collapsible tail.
///
/// A 5K panel reports 14–20 point sizes, trailing off into 1280×720 and
/// 1024×576 — options that exist because the hardware allows them, not because
/// anyone picks them. Every extra row costs reading time on a decision the user
/// makes in a second or two, so the small end goes behind a disclosure.
enum ResolutionListPartition {
    struct Split: Equatable {
        let primary: [Int]
        let collapsed: [Int]
    }

    /// Sizes at least this fraction of the widest size stay visible.
    ///
    /// Compared on width rather than area because "at least 60% as wide as the
    /// biggest option" is something a person can check by eye; the equivalent
    /// area threshold (~36%) is not.
    private static let widthThreshold = 0.6

    /// - Parameters:
    ///   - sizes: point sizes in the order they will be rendered.
    ///   - currentIndex: the display's active size, never collapsed — hiding
    ///     where the user already is would be worse than a long list.
    static func split(
        sizes: [(width: Int, height: Int)],
        currentIndex: Int?
    ) -> Split {
        guard let widest = sizes.map(\.width).max(), widest > 0 else {
            return Split(primary: [], collapsed: [])
        }

        var primary: [Int] = []
        var collapsed: [Int] = []
        for (index, size) in sizes.enumerated() {
            let keep = Double(size.width) / Double(widest) >= widthThreshold
                || index == currentIndex
            if keep {
                primary.append(index)
            } else {
                collapsed.append(index)
            }
        }
        // Both lists come out ascending, so rows never reorder when the current
        // mode changes.
        return Split(primary: primary, collapsed: collapsed)
    }
}
