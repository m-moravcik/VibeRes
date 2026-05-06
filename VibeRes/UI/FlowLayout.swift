import SwiftUI

/// A simple wrapping flow layout for the profile pill bar. Lays children left-to-right;
/// when the next child wouldn't fit on the current line, drops to the next row instead
/// of overflowing horizontally. Works inside a fixed-width MenuBarExtra popover where
/// horizontal scroll feels wrong.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    struct Cache {
        var lines: [[Int]] = []      // row → indices into subviews
        var lineHeights: [CGFloat] = []
        var totalHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { /* recomputed in layout */ }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? .infinity
        layoutLines(width: width, subviews: subviews, cache: &cache)
        return CGSize(width: width.isFinite ? width : cache.measuredWidth, height: cache.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        layoutLines(width: bounds.width, subviews: subviews, cache: &cache)

        var y = bounds.minY
        for (rowIndex, row) in cache.lines.enumerated() {
            var x = bounds.minX
            let lineHeight = cache.lineHeights[rowIndex]
            for index in row {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += lineHeight + lineSpacing
        }
    }

    private func layoutLines(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        cache.lines = []
        cache.lineHeights = []
        cache.totalHeight = 0
        cache.measuredWidth = 0

        var currentRow: [Int] = []
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var maxWidthSeen: CGFloat = 0

        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = currentRow.isEmpty ? size.width : currentRowWidth + spacing + size.width

            if !currentRow.isEmpty && needed > width {
                cache.lines.append(currentRow)
                cache.lineHeights.append(currentRowHeight)
                cache.totalHeight += currentRowHeight + lineSpacing
                maxWidthSeen = max(maxWidthSeen, currentRowWidth)
                currentRow = []
                currentRowWidth = 0
                currentRowHeight = 0
            }

            currentRow.append(i)
            currentRowWidth = currentRow.count == 1 ? size.width : currentRowWidth + spacing + size.width
            currentRowHeight = max(currentRowHeight, size.height)
        }

        if !currentRow.isEmpty {
            cache.lines.append(currentRow)
            cache.lineHeights.append(currentRowHeight)
            cache.totalHeight += currentRowHeight
            maxWidthSeen = max(maxWidthSeen, currentRowWidth)
        }
        cache.measuredWidth = maxWidthSeen
    }
}
