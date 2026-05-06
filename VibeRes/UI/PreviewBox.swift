import SwiftUI

/// Geometric preview: an outer frame at the current display's aspect+size, with an inner
/// frame showing the proposed mode at the same point-scale. Mirrors how System Settings →
/// Displays sketches relative arrangements.
struct PreviewBox: View {
    let currentWidth: Int
    let currentHeight: Int
    let proposedWidth: Int
    let proposedHeight: Int

    /// Maximum bounding box (in points) for the preview frame in the popover.
    let maxSize: CGFloat

    var body: some View {
        let cur = CGSize(width: max(1, currentWidth), height: max(1, currentHeight))
        let prop = CGSize(width: max(1, proposedWidth), height: max(1, proposedHeight))

        // Pick whichever is larger as the bounding rectangle so we can show shrinking
        // OR growing changes within the same coordinate space.
        let bound = CGSize(width: max(cur.width, prop.width), height: max(cur.height, prop.height))
        let scale = min(maxSize / bound.width, maxSize / bound.height)

        let curFrame = CGSize(width: cur.width * scale, height: cur.height * scale)
        let propFrame = CGSize(width: prop.width * scale, height: prop.height * scale)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1)
                .frame(width: curFrame.width, height: curFrame.height)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.accentColor.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1)
                )
                .frame(width: propFrame.width, height: propFrame.height)
        }
        .frame(width: max(curFrame.width, propFrame.width), height: max(curFrame.height, propFrame.height), alignment: .topLeading)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Compact change-indicator badge ("+12%", "−16%") relative to the current mode.
/// Helps the user see which way and how much the proposed mode shifts real estate
/// without needing the hover preview.
struct RealEstateBadge: View {
    let currentWidth: Int
    let currentHeight: Int
    let proposedWidth: Int
    let proposedHeight: Int

    var body: some View {
        guard let pct = changePercent, pct != 0 else { return AnyView(EmptyView()) }
        let isMore = pct > 0
        let text = "\(isMore ? "+" : "−")\(abs(pct))%"
        let color = isMore ? Color.green : Color.orange
        return AnyView(
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(color.opacity(0.16), in: Capsule())
        )
    }

    /// Percent change in screen real estate (point area). Returns nil if unchanged or
    /// either side has zero area; rounded to nearest int for compact rendering.
    private var changePercent: Int? {
        let curArea = Double(currentWidth) * Double(currentHeight)
        let propArea = Double(proposedWidth) * Double(proposedHeight)
        guard curArea > 0, propArea > 0 else { return nil }
        let delta = (propArea - curArea) / curArea * 100
        return Int(delta.rounded())
    }
}
