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
