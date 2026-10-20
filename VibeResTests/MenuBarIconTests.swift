import AppKit
import Testing
@testable import VibeRes

/// The menu bar label is drawn in code, so nothing but these checks stops a
/// change from shipping an icon the menu bar cannot tint (a non-template image
/// stays black on a dark bar) or one MenuBarExtra shrinks (taller than 16 pt).
@Suite("Menu bar icon")
@MainActor
struct MenuBarIconTests {
    @Test func isATemplateImage() {
        #expect(MenuBarIcon.image.isTemplate)
    }

    @Test func everyAnimationFrameIsATemplateThatFits() {
        for phase in stride(from: 0.0, through: MenuBarIcon.duration, by: MenuBarIconAnimator.frameInterval) {
            let frame = MenuBarIcon.image(at: phase)
            #expect(frame.isTemplate, "frame at \(phase) s")
            #expect(frame.size == MenuBarIcon.size, "frame at \(phase) s")
        }
    }

    /// The window springs out past full size and is back in its corner
    /// before the animation stops, so stopping never shows a jump.
    @Test func animationOvershootsAndEndsAtRest() {
        let samples = stride(from: 0.0, through: MenuBarIcon.duration, by: 0.01).map { MenuBarIcon.growth(at: $0) }
        #expect((samples.max() ?? 0) > 1, "a small overshoot")
        #expect(MenuBarIcon.growth(at: MenuBarIcon.duration) == 0)
        #expect(MenuBarIcon.growth(at: nil) == 0)
        #expect(MenuBarIcon.duration <= 2.5)
    }

    @Test func fitsTheMenuBar() {
        #expect(MenuBarIcon.image.size.height <= 16)
        #expect(MenuBarIcon.image.size.width <= 22)
    }

    /// The ink, not the canvas, is what has to match the neighbours: a regular
    /// SF Symbol at 15 pt is 25 to 29 px tall at 2x.
    @Test func inkHeightMatchesTheNeighboursAt2x() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 32,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = MenuBarIcon.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        MenuBarIcon.image.draw(in: NSRect(origin: .zero, size: MenuBarIcon.size))
        NSGraphicsContext.restoreGraphicsState()

        let inkRows = (0..<rep.pixelsHigh).filter { y in
            (0..<rep.pixelsWide).contains { x in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.16 }
        }
        let height = (inkRows.last ?? 0) - (inkRows.first ?? 0) + 1
        #expect((25...29).contains(height), "ink is \(height) px tall at 2x")
    }
}
