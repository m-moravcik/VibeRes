import Foundation
import SwiftUI

/// The single note shown under the profile pills after a profile is applied,
/// aggregated from one outcome per display.
///
/// Lives in the UI layer on purpose. `ProfileStore.ApplyOutcome.summary` stays
/// an English string because `VibeRes/Core` is also compiled into the
/// `viberes` command-line tool, which prints it verbatim and has no bundle to
/// resolve a String Catalog against. Localisable copy therefore belongs here,
/// built from the outcome's structured fields rather than from `summary`.
struct ApplyOutcomeNote: Equatable {
    enum Tone: Equatable, Comparable {
        case info
        case fallback
        case problem
    }

    /// One line of the note. Carries values, not prose, so the view can render
    /// it through a String Catalog entry in any language.
    enum Detail: Equatable {
        case applied(display: String, width: Int, height: Int, hz: Int?)
        case fallback(
            display: String,
            wantedWidth: Int, wantedHeight: Int, wantedHz: Int?,
            usedWidth: Int, usedHeight: Int, usedHz: Int?
        )
        case notConnected(display: String)
        case noExternalConnected
        case noUsableMode(display: String, width: Int, height: Int)
        case failed(display: String, message: String)

        case mainChanged(display: String)
        case mainAdjusted(display: String)
        case mainNotConnected
        case mainAmbiguous(count: Int)
        case mainMirrored
        case mainFailed(message: String)
    }

    enum Content: Equatable {
        case problems([Detail])
        case fallbacks([Detail])
        case applied(Detail, extraCount: Int)
        case alreadyAtSavedSettings
    }

    let tone: Tone
    let content: Content
    /// The main-display line, rendered after the per-display content. Kept
    /// separate from Content so the aggregation precedence above stays about
    /// modes only.
    let mainDetail: Detail?

    init(tone: Tone, content: Content, mainDetail: Detail? = nil) {
        self.tone = tone
        self.content = content
        self.mainDetail = mainDetail
    }

    static func make(
        from outcomes: [ProfileStore.ApplyOutcome],
        mainChange: ProfileStore.MainChangeOutcome? = nil
    ) -> ApplyOutcomeNote? {
        let base = modeNote(from: outcomes)
        guard let (detail, mainTone) = resolveMainDetail(for: mainChange) else { return base }
        // The main line rides on whatever the modes produced; when the modes
        // produced nothing (rare mixed statuses), it still deserves a note.
        let content = base?.content ?? .alreadyAtSavedSettings
        return ApplyOutcomeNote(
            tone: max(base?.tone ?? .info, mainTone),
            content: content,
            mainDetail: detail
        )
    }

    private static func resolveMainDetail(
        for change: ProfileStore.MainChangeOutcome?
    ) -> (Detail, Tone)? {
        switch change {
        case nil, .alreadyMain:
            return nil
        case .changed(let name):
            return (.mainChanged(display: name), .info)
        case .changedButAdjusted(let name):
            return (.mainAdjusted(display: name), .fallback)
        case .skippedNoMatch:
            return (.mainNotConnected, .fallback)
        case .skippedAmbiguous(let count):
            return (.mainAmbiguous(count: count), .fallback)
        case .skippedMirrored:
            return (.mainMirrored, .fallback)
        case .failed(let message):
            return (.mainFailed(message: message), .problem)
        }
    }

    private static func modeNote(from outcomes: [ProfileStore.ApplyOutcome]) -> ApplyOutcomeNote? {
        guard !outcomes.isEmpty else { return nil }

        // Precedence is deliberate: one broken display matters more than three
        // working ones, so the worst status in the batch sets the tone. Every
        // problem is carried, because "Dell not connected" and "LG failed" are
        // different actions for the user.
        let problems = outcomes.filter {
            switch $0.status {
            case .skippedNoMatch, .skippedNoMode, .failed: return true
            case .applied, .alreadyApplied, .appliedWithFallback: return false
            }
        }
        if !problems.isEmpty {
            return ApplyOutcomeNote(tone: .problem, content: .problems(problems.map(detail(for:))))
        }

        let fallbacks = outcomes.filter {
            if case .appliedWithFallback = $0.status { return true }
            return false
        }
        if !fallbacks.isEmpty {
            return ApplyOutcomeNote(tone: .fallback, content: .fallbacks(fallbacks.map(detail(for:))))
        }

        if let first = outcomes.first(where: {
            if case .applied = $0.status { return true }
            return false
        }) {
            return ApplyOutcomeNote(
                tone: .info,
                content: .applied(detail(for: first), extraCount: outcomes.count - 1)
            )
        }

        // Manual apply against an identical state: confirm the click registered
        // without pretending anything changed.
        if outcomes.allSatisfy({
            if case .alreadyApplied = $0.status { return true }
            return false
        }) {
            return ApplyOutcomeNote(tone: .info, content: .alreadyAtSavedSettings)
        }

        return nil
    }

    /// A display mode rendered as digits only, for use as an argument inside a
    /// localised sentence. Deliberately free of words so no translation of it
    /// is ever needed.
    static func modeString(width: Int, height: Int, hz: Int?) -> String {
        let size = "\(width)×\(height)"
        guard let hz else { return size }
        return "\(size) @\(hz)Hz"
    }

    private static func detail(for outcome: ProfileStore.ApplyOutcome) -> Detail {
        // `appliedSize` is nil for statuses that never reached a mode change;
        // falling back to the request keeps the numbers meaningful.
        let size = outcome.appliedSize ?? outcome.requestedSize

        switch outcome.status {
        case .applied, .alreadyApplied:
            return .applied(
                display: outcome.displayName,
                width: size.0,
                height: size.1,
                hz: outcome.appliedHz
            )
        case .appliedWithFallback:
            return .fallback(
                display: outcome.displayName,
                wantedWidth: outcome.requestedSize.0,
                wantedHeight: outcome.requestedSize.1,
                wantedHz: outcome.requestedHz,
                usedWidth: size.0,
                usedHeight: size.1,
                usedHz: outcome.appliedHz
            )
        case .skippedNoMatch:
            // A flexible profile that found no external monitor must not name
            // the saved label — "Desk monitor not connected" would be a lie
            // about a profile that matches any external.
            switch outcome.matcherKind {
            case .anyExternal: return .noExternalConnected
            case .specific: return .notConnected(display: outcome.displayName)
            }
        case .skippedNoMode:
            return .noUsableMode(
                display: outcome.displayName,
                width: outcome.requestedSize.0,
                height: outcome.requestedSize.1
            )
        case .failed(let message):
            return .failed(display: outcome.displayName, message: message)
        }
    }
}

// MARK: - Localised rendering
//
// View glue, deliberately not unit-tested: the repo does not test views, and
// asserting on rendered output would test Foundation's formatter rather than
// our logic. What is testable — the aggregation rules and the numeric mode
// formatting — is covered in ApplyOutcomeNoteTests.
//
// Explicit dot-notation keys, matching the convention already used by
// OnboardingView, rather than letting the compiler derive keys like
// "%@ \u{2192} %@" from the literal. A translator sees a name and a comment
// instead of a puzzle. Numbers arrive pre-formatted via `modeString`, so no
// language has to reassemble "2560\u{00D7}1440 @60Hz".

extension ApplyOutcomeNote.Detail {
    var localizedDescription: String {
        switch self {
        case let .applied(display, width, height, hz):
            let mode = ApplyOutcomeNote.modeString(width: width, height: height, hz: hz)
            return String(localized: LocalizedStringResource(
                "note.detail.applied",
                defaultValue: "\(display) \u{2192} \(mode)",
                comment: "Display was set to a mode. 1: display name, 2: mode e.g. 2560x1440 @60Hz"
            ))

        case let .fallback(display, wantedWidth, wantedHeight, wantedHz, usedWidth, usedHeight, usedHz):
            let wanted = ApplyOutcomeNote.modeString(width: wantedWidth, height: wantedHeight, hz: wantedHz)
            let used = ApplyOutcomeNote.modeString(width: usedWidth, height: usedHeight, hz: usedHz)
            return String(localized: LocalizedStringResource(
                "note.detail.fallback",
                defaultValue: "\(display): wanted \(wanted), used \(used) (closest available)",
                comment: "Requested mode was unavailable. 1: display, 2: requested mode, 3: mode actually used"
            ))

        case let .notConnected(display):
            return String(localized: LocalizedStringResource(
                "note.detail.notConnected",
                defaultValue: "\(display) not connected",
                comment: "A profile names this display but it is not attached. 1: display name"
            ))

        case .noExternalConnected:
            return String(localized: LocalizedStringResource(
                "note.detail.noExternalConnected",
                defaultValue: "No external monitor connected",
                comment: "A flexible profile matches any external monitor, but none is attached"
            ))

        case let .noUsableMode(display, width, height):
            let mode = ApplyOutcomeNote.modeString(width: width, height: height, hz: nil)
            return String(localized: LocalizedStringResource(
                "note.detail.noUsableMode",
                defaultValue: "\(display): no usable mode for \(mode)",
                comment: "Display matched but offers no mode close to the saved one. 1: display, 2: saved mode"
            ))

        case let .failed(display, message):
            return String(localized: LocalizedStringResource(
                "note.detail.failed",
                defaultValue: "\(display): \(message)",
                comment: "Applying a mode failed. 1: display name, 2: system error text"
            ))

        case let .mainChanged(display):
            return String(localized: LocalizedStringResource(
                "note.detail.mainChanged",
                defaultValue: "Main display \u{2192} \(display)",
                comment: "The menu bar moved to this display. 1: display name"
            ))

        case let .mainAdjusted(display):
            return String(localized: LocalizedStringResource(
                "note.detail.mainAdjusted",
                defaultValue: "Main display \u{2192} \(display), but macOS adjusted the arrangement",
                comment: "Main display was set but the layout differs from what was requested. 1: display name"
            ))

        case .mainNotConnected:
            return String(localized: LocalizedStringResource(
                "note.detail.mainNotConnected",
                defaultValue: "Main display unchanged — the saved display is not connected",
                comment: "The profile's main display is not attached"
            ))

        case let .mainAmbiguous(count):
            return String(localized: LocalizedStringResource(
                "note.detail.mainAmbiguous",
                defaultValue: "Main display unchanged — \(count) connected displays match",
                comment: "Several displays match the saved main. 1: how many"
            ))

        case .mainMirrored:
            return String(localized: LocalizedStringResource(
                "note.detail.mainMirrored",
                defaultValue: "Main display unchanged — displays are mirrored",
                comment: "Arrangement is not touched while mirroring is on"
            ))

        case let .mainFailed(message):
            return String(localized: LocalizedStringResource(
                "note.detail.mainFailed",
                defaultValue: "Main display unchanged: \(message)",
                comment: "Setting the main display failed. 1: system error text"
            ))
        }
    }
}

extension ApplyOutcomeNote {
    /// The whole note as one resolved string.
    ///
    /// Resolved rather than composed from `Text` values because concatenating
    /// `Text` with `+` is deprecated on macOS 26, and interpolating one `Text`
    /// into another would put an opaque `%@` in the middle of a translatable
    /// sentence.
    var localizedDescription: String {
        let base: String
        switch content {
        case let .problems(details):
            base = Self.joined(details)

        case let .fallbacks(details):
            base = Self.joined(details)

        case let .applied(detail, extraCount):
            if extraCount > 0 {
                let more = String(localized: LocalizedStringResource(
                    "note.moreDisplays",
                    defaultValue: " (+\(extraCount) more)",
                    comment: "Appended when a profile also applied to further displays. 1: how many others"
                ))
                base = detail.localizedDescription + more
            } else {
                base = detail.localizedDescription
            }

        case .alreadyAtSavedSettings:
            base = String(localized: LocalizedStringResource(
                "note.alreadyAtSavedSettings",
                defaultValue: "Already at the saved settings.",
                comment: "The profile was applied but nothing needed changing"
            ))
        }
        guard let mainDetail else { return base }
        return base + "; " + mainDetail.localizedDescription
    }

    private static func joined(_ details: [Detail]) -> String {
        details.map(\.localizedDescription).joined(separator: "; ")
    }
}
