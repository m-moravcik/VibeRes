# Backlog

Product decisions and ideas for future releases, with planned and deferred
work identified in each entry. Deferred ideas may never ship. Tracked so we
don't keep re-deciding the same questions every few weeks.

## Considered

### Mirror display support

Add the ability to save a profile that mirrors one display to another (e.g.
laptop's built-in screen mirrored onto a connected projector during a
presentation).

**Why it would help**
- Strongest concrete use case: plug projector → switch profile → present.
  Currently the user has to open System Settings → Displays → Arrange to
  enable mirroring manually, breaking the menubar flow.
- EasyRes (the discontinued tool VibeRes succeeds) had a mirror toggle, so
  there's existing user expectation.
- One CG API call: `CGConfigureDisplayMirrorOfDisplay(config, slave, master)`.
  Drops into the existing apply transaction cleanly.

**Why it was deferred**
- Profile semantics were unclear when `.anyExternal` matched multiple
  displays. Resolved by the source/target rule in the agreed spec below.

**Decided 2026-11-13: planned as its own release after 1.0.** Mirroring alone
fits the "plug in the projector, click a profile" story, so it moves out of
the non-goals. Not bolted onto a patch, and 1.0 does not wait for it.

**Agreed spec**
- `Profile.mirror` is tri-state: `nil` leaves mirroring alone (every
  existing profile decodes as this), `.off` turns mirroring off, and
  `.on(source)` mirrors one source to every other display in the profile.
  The source must be a specific display entry. An `.anyExternal` entry can
  only be a target: every external display it matches mirrors the source.
- The source's resolution wins. Mirroring forces one mode, so the target
  entries' resolution and refresh rate are hidden in the form, not edited.
- Saving a new profile captures the current mirror state.
- Apply sets mirroring in the same CG configuration transaction as the
  resolution, then verifies the result with `CGDisplayMirrorsDisplay`, the
  way main-display placement is verified.
- Revert undoes mirroring along with the resolution.
- UI: one "Mirroring" row in the Save / Edit form (off, or mirror from a
  chosen specific display entry). Sketch the form before code and keep it
  compact.
- PRD §2 lists mirroring as planned; the release moves it into §4.

### Display arrangement preservation

Save and restore the spatial layout of displays (which monitor is left of
which, which one is primary / hosts the menu bar) as part of a profile.

**Spiked 2026-08-01** — measurements and a staged plan in
[docs/display-arrangement-spike-2026-08-01.md](docs/display-arrangement-spike-2026-08-01.md).
API risk is lower than the deferral below assumes: origins apply exactly, and
mode plus origin commit in one transaction. But the implied "one
`CGConfigureDisplayOrigin` call" model is wrong — a partial origin change
silently mangles the layout and still returns success, so any apply touching
origins must specify one for *every* active display.

**Stage 1 shipped in 0.9.0** — a profile can pin which display is main
(`Profile.mainDisplay`), applied as a full-coverage origin translation with
post-commit verification and Revert support. Stage 2 (full stored geometry)
remains deferred; see
[the implementation plan](docs/superpowers/plans/2026-08-01-main-display-in-profile.md).

**Why it would help**
- macOS occasionally reshuffles arrangement after a mode change, especially
  when applying a resolution that doesn't fit the existing geometry.
  Currently the user has to fix the layout manually in System Settings.
- Completes the "save my whole desk setup" mental model. Today VibeRes
  saves *what* mode each monitor is in but not *where* the monitor sits.

**Why it's deferred**
- Bigger surface area than mirror. Requires:
  - New `Profile.Entry` field for `(x, y)` origin
  - Migration path for existing JSON profiles (default `origin: nil`)
  - Save form UI with thumbnail arrangement preview
  - Edge case handling (monitor disconnected since save)
  - `CGConfigureDisplayOrigin` integration into apply transaction
- ~2–3 days of work, multiple test surfaces.
- Niche need — most users don't reshuffle arrangement often enough to
  warrant the complexity.

**Reconfirmed 2026-11-13: Stage 2 stays deferred.** The mirroring release
(above) ships without it.

**If we revisit**
- Builds on the mirroring release: same per-display form rows and the same
  test pattern (CG configuration transaction with rollback).
- Dedicated release, UI exploration first.

### Per-app resolution profiles

Apply a profile automatically when a specific app becomes frontmost. E.g.
"Final Cut Pro → switch built-in to 2880×1620 native; Slack → switch back
to 1800×1169 HiDPI".

**Why it would help**
- Pro users (editors, designers) who need different DPI per app
- Power-user differentiator from EasyRes / BetterDisplay

**Why it's deferred**
- Niche audience. <5% of users probably want this.
- Requires `NSWorkspace.didActivateApplicationNotification` listener
  permanently running.
- Conflicts with manual user mode picks ("I switched manually, stop
  overriding me when Slack comes back").
- Needs a "pause auto-switch for N minutes" escape hatch.
- Privacy review may surface — listing frontmost apps could be flagged.

**If we revisit**
- Ship as an opt-in beta flag in Settings → Display, not on by default.
- Treat manual mode picks within 60s as "user override, suspend auto-apply
  for this app session" to avoid the fighting-the-user problem.

**Reconfirmed 2026-11-13: not now.** Open question for when it comes back:
whether people would rather set this up in VibeRes, in one place, than chain
it together through Shortcuts automations.

### Hotkey per profile

Bind global keyboard shortcuts to apply a specific profile (e.g.
⌥⌘1 = Work, ⌥⌘2 = Presentation), and one to Revert.

**Why it was deferred**
- Already addressable via Shortcuts.app (the App Intents integration): a
  keyboard shortcut can run a Shortcut that applies a profile.

**Decided 2026-11-13: build it, next after the first-profile onboarding.**
The Shortcuts route needs one hand-built Shortcut per profile; a shortcut
field next to the profile is one step, in the place the user already is.
The App Intents stay for Stream Deck, automations and scripting.

**Agreed spec**
- Optional and unset by default. Nothing is registered until the user sets
  a shortcut.
- Per-profile shortcut, set in the profile's Edit form.
- A global Revert shortcut. Settings offers a suggested combination that the
  user enables with one click; it is never enabled automatically.
- Registered with Carbon `RegisterEventHotKey`: no Accessibility permission
  and no new dependency.
- Taken or invalid combinations are refused inline when set, not discovered
  later.
- Replaces the PRD §2 non-goal "No global hotkeys of its own".

## Shipped, kept here so they are not re-proposed

### Sparkle in-app updates — shipped in 0.8.2

Deferred here until "monthly non-brew downloads pass ~100"; shipped earlier
because the manual "download the ZIP and replace the .app" step was the only
update path for anyone not using Homebrew. EdDSA signing, a signed feed, and a
gate that refuses to self-update anything not Developer ID signed by this
project. See `PRD.md` §4.12.

### Hover preview double-click — resolved by dropping the popover

The SwiftUI `.popover` used for the profile-pill preview spawned an NSPanel
that ate the first click on the pill. The preview is now a plain `.help(...)`
tooltip built from the same `ProfileApplyPreview` rows, so there is no panel to
intercept anything. The trade — no icons or colour in the tooltip — was
accepted and has not been complained about since.

## Known limitations (accepted, not deferred)

### Display arrangement reset by macOS on extreme resolution change

When applying a resolution that doesn't fit existing arrangement geometry
(e.g. 640×480 on a 4K monitor), macOS itself reshuffles monitors to
"reasonable" positions. The reshuffle is macOS behaviour, not a VibeRes
bug: the only arrangement change VibeRes makes is the deliberate,
full-coverage translation behind "main display" (0.9.0), and it verifies the
result by reading it back.

**Workaround**
- Open System Settings → Displays → Arrange and drag monitors back. macOS
  remembers per-resolution layout.

**When to revisit**
- Stage 1 ships main-display selection (0.9.0) but stores no geometry, so
  reshuffles are not prevented. Stage 2 (full arrangement storage and
  restoration) owns this limitation. Until then, documenting the workaround in
  the troubleshooting section is enough.
