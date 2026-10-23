import Foundation
import Testing
@testable import VibeRes

/// How long the note under the profile pills stays on screen.
///
/// It used to stay for good: only an info note cleared itself, and the note
/// lives in view state that outlives a closed popover, so "GN246HL not
/// connected" from a click hours ago greeted every later open.
@Suite("Popover note lifetime")
struct PopoverNoteTests {
    @Test("Only a reassuring note clears itself on a timer")
    func onlyInfoExpires() {
        #expect(ApplyOutcomeNote.Tone.info.autoDismissDelay == .seconds(6))
        #expect(ApplyOutcomeNote.Tone.fallback.autoDismissDelay == nil)
        #expect(ApplyOutcomeNote.Tone.problem.autoDismissDelay == nil)
    }

    @Test("An expired timer clears the note it was started for")
    func expiryClearsItsOwnNote() {
        var slot = PopoverNote<String>()
        let generation = slot.show("Applied", tone: .info)

        slot.expire(generation)

        #expect(slot.current == nil)
    }

    @Test("A timer from an earlier note leaves a newer one alone")
    func staleExpiryKeepsNewerNote() {
        // The same words twice in a row are two notes. Matching on the
        // content, as the timer used to, let the first one's timer cut the
        // second short.
        var slot = PopoverNote<String>()
        let first = slot.show("Applied", tone: .info)
        _ = slot.show("Applied", tone: .info)

        slot.expire(first)

        #expect(slot.current?.body == "Applied")
    }

    @Test("Closing the popover clears every note, warnings included")
    func popoverCloseClearsWarnings() {
        var slot = PopoverNote<String>()
        _ = slot.show("Dell: no usable mode", tone: .problem)

        slot.dismiss()

        #expect(slot.current == nil)
    }

    @Test("A warning stays while the popover is open")
    func warningStaysUntilDismissed() {
        var slot = PopoverNote<String>()
        let generation = slot.show("LG fell back to 60 Hz", tone: .fallback)

        // No timer is started for it, but an unrelated expiry must not clear
        // it either.
        slot.expire(generation - 1)
        #expect(slot.current?.tone == .fallback)

        slot.dismiss()
        #expect(slot.current == nil)
    }
}

/// The "Applied ..." note after an auto-apply. The popover-close handler
/// clears the last open's note, and a MenuBarExtra holds updates back while
/// closed, so the close and a new auto-apply often reach the view in one
/// update. SwiftUI may run their handlers in either order; the note used to
/// be dismissed by the close handler when it ran second.
@Suite("Auto-apply note")
struct AutoApplyAnnouncementTests {
    /// The two handlers in `ProfilesSection`, on the real note and marker.
    struct Popover {
        var note = PopoverNote<String>()
        var announcement = AutoApplyAnnouncement()
        var lastAutoApply: ProfileStore.AutoApplyRecord?
        let now: Date

        mutating func autoApplyChanged() {
            announceFresh()
        }

        mutating func popoverClosed() {
            note.dismiss()
            announcement.reset()
            announceFresh()
        }

        private mutating func announceFresh() {
            guard let record = announcement.take(lastAutoApply, now: now) else { return }
            note.show("Applied \(record.profileName)", tone: .info)
        }
    }

    static let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    static let fresh = ProfileStore.AutoApplyRecord(profileName: "Presentation", date: now.addingTimeInterval(-5))

    @Test("A close and an auto-apply in one update show the note, close handler last")
    func closeHandlerLast() {
        var popover = Popover(lastAutoApply: Self.fresh, now: Self.now)
        popover.autoApplyChanged()
        popover.popoverClosed()
        #expect(popover.note.current?.body == "Applied Presentation")
    }

    @Test("A close and an auto-apply in one update show the note, close handler first")
    func closeHandlerFirst() {
        var popover = Popover(lastAutoApply: Self.fresh, now: Self.now)
        popover.popoverClosed()
        let generation = popover.note.current?.generation
        popover.autoApplyChanged()
        #expect(popover.note.current?.body == "Applied Presentation")
        // Announced once: the second handler does not replace it.
        #expect(popover.note.current?.generation == generation)
    }

    @Test("An auto-apply older than the freshness window is not announced")
    func staleRecordIsQuiet() {
        let stale = ProfileStore.AutoApplyRecord(
            profileName: "Presentation",
            date: Self.now.addingTimeInterval(-AutoApplyAnnouncement.freshness - 1))
        var popover = Popover(lastAutoApply: stale, now: Self.now)
        popover.autoApplyChanged()
        popover.popoverClosed()
        #expect(popover.note.current == nil)
    }

    @Test("No auto-apply, no note")
    func noRecordIsQuiet() {
        var popover = Popover(lastAutoApply: nil, now: Self.now)
        popover.popoverClosed()
        #expect(popover.note.current == nil)
    }

    @Test("A record is announced at most once per open")
    func oncePerOpen() {
        var announcement = AutoApplyAnnouncement()
        #expect(announcement.take(Self.fresh, now: Self.now) == Self.fresh)
        #expect(announcement.take(Self.fresh, now: Self.now) == nil)
        announcement.reset()
        #expect(announcement.take(Self.fresh, now: Self.now) == Self.fresh)
    }
}
