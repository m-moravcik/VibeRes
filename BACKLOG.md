# Backlog

Features and improvements that have been discussed but deferred from current
releases. Not a roadmap — entries here may never ship. Tracked so we don't
keep re-deciding the same questions every few weeks.

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

**Why it's deferred**
- Scope creep risk. Resolution + Hz is a clean narrative; mirror would
  pull arrangement next, then primary swap, then rotation. The menubar
  resolution switcher becomes a "display config manager", which is a
  different product (BetterDisplay territory).
- UI complexity. The Save / Edit forms are already dense — adding a
  third axis (resolution × refresh rate × mirror master) per entry needs
  a layout redesign before code, not after.
- Profile semantics get messy. `.anyExternal` + mirror raises questions:
  if the master is "any external" and you have two externals connected,
  which one is the mirror target? No clean answer yet.
- macOS already has mirror in System Settings. Parity with EasyRes, but
  not unique value VibeRes brings.

**If we revisit**
- Make it a dedicated v1.0.0 release with mirror as the single headline
  feature. Don't bolt it onto a patch. (0.9.0 went to main-display
  selection instead.)
- UI exploration first (Figma or whiteboard) for Save / Edit form before
  any code. Verify the form stays compact.
- Decide upfront: does mirror replace the slave's resolution in the
  profile, or coexist with it? (Likely replace — mirroring forces both
  displays to the same mode anyway.)

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

**If we revisit**
- Pair with the mirror release. Both fall under "save the full setup"
  story, share UI infrastructure (per-entry per-display config), and
  share the test pattern (CG configuration transaction with rollback).
- Same decision rule as mirror: dedicated release, UI exploration first.

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

### Hotkey per profile

Bind global keyboard shortcuts to apply a specific profile (e.g.
⌥⌘1 = Work, ⌥⌘2 = Presentation).

**Why it would help**
- Power-user feature. Some users live in the keyboard, never click
  menubar icons.

**Why it's deferred**
- Already addressable via macOS Shortcuts.app (the existing AppIntents
  integration). Users can build their own keyboard shortcut → Run
  Shortcut chain.
- Avoiding duplication of macOS-native functionality.

**If we revisit**
- Only if Shortcuts.app integration proves too cumbersome for end users
  (e.g. measured friction in feedback).

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
