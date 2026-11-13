import AppKit
import SwiftUI
import Testing
@testable import VibeRes

@Suite("Shortcut row layout", .serialized)
@MainActor
struct ShortcutRowLayoutTests {
    // The Settings contract requires the controls to stay beside the title.
    // Measure the real accessory in its shared baseline-aligned control group:
    // automatic vertical fallback must not move it when a refusal appears.
    @Test("A refusal does not move Revert's controls below its title",
          arguments: ["en", "de", "fr"], [ColorScheme.light, .dark])
    func revertWithAccessory(language: String, scheme: ColorScheme) throws {
        let idle = try accessoryFrame(problem: nil, language: language, scheme: scheme)
        let refused = try accessoryFrame(problem: .needsModifiers, language: language, scheme: scheme)
        #expect(abs(idle.minX - refused.minX) < 1)
        #expect(abs(idle.minY - refused.minY) < 1)
    }

    private func accessoryFrame(problem: HotkeyProblem?, language: String, scheme: ColorScheme) throws -> CGRect {
        let probe = FrameProbe()
        let hotkeys = HotkeyCenter(registrar: CarbonHotkeyRegistrar())
        let view = Form {
            Section {
                ShortcutRecorder(
                    owner: .revert, combo: .constant(nil), savedCombo: nil,
                    title: Text("Revert last change"), initialProblem: problem
                ) {
                    Button("Use \(Text(verbatim: KeyCombo.suggestedRevert.localizedDisplayString()))") {}
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe.frame = $0 }
                }
            } header: {
                Text("Revert")
            }
        }
        .formStyle(.grouped)
        .frame(width: 470, height: 400)
        .environment(hotkeys)
        .environment(\.locale, Locale(identifier: language))
        .environment(\.colorScheme, scheme)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 470, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        for _ in 0..<3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            hosting.layoutSubtreeIfNeeded()
        }
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        Attachment.record(png, named: "revert-\(language)-\(scheme)-\(problem == nil ? "idle" : "refused").png")
        return try #require(probe.frame)
    }
}

@MainActor
private final class FrameProbe {
    var frame: CGRect?
}
