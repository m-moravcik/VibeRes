# Backlog

Product decisions and ideas for future releases, with planned and deferred
work identified in each entry. Deferred ideas may never ship. Tracked so we
don't keep re-deciding the same questions every few weeks.

## 1.0 (decided 2026-11-14)

0.12.0 shipped what was built so far (shortcuts, the first profile in the
tour, confirmation on by default, the one-line Revert row) so it gets real
use first. 1.0 is the polished core that says what happened, not more
features. It ships these, then one break-it QA pass over the whole app and
fresh README screenshots. The list and the QA fixes shipped as 0.13.0
(2026-11-15) for about a week of real use; 1.0 follows with the fresh
screenshots:

1. The safety countdown drains (motion audit item 2). Confirmation is on by
   default now, so every new user sees it.
2. VoiceOver hears a shortcut's result (product suggestions below).
3. A hint for a profile that can never apply here (product suggestions).
4. Report a problem with a prefilled bug report (follows from VISION.md).
5. The shortcut recorder shows its state (motion audit item 3).
6. One small polish batch: the hover preview morphs between sizes, the
   onboarding checkmark bounces, "Copied" swaps in place (motion audit items
   1, 5 and 6).

After 1.0: the menu bar glyph's "no" moment (item 4, needs new frames), bring
windows back on screen (a new permission flow), HDR (API not known yet, may
need a private symbol), then mirroring as its own release. Arrangement Stage
2 stays deferred.

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

**Why it was deferred** (kept as history; how the spec answers each)
- Scope creep risk: mirror would pull arrangement, primary swap and
  rotation after it, and the resolution switcher would become a display
  configuration manager (BetterDisplay territory). Main-display selection
  (primary swap) already shipped in 0.9.0. Mirroring alone is now admitted;
  full arrangement geometry (Stage 2) stays deferred and rotation stays out
  (PRD §2).
- UI complexity: the Save / Edit forms are dense. Answered by a single
  "Mirroring" row and hiding the targets' resolution instead of adding a
  per-entry axis.
- Profile semantics were unclear when `.anyExternal` matched multiple
  displays. Answered by the source/target rule below.
- macOS already has mirroring in System Settings. True, but reaching it
  breaks the menu bar flow, which is the use case above.

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

**Decided 2026-11-13: off mission (VISION.md).** The open question is
answered: VibeRes does not switch modes on triggers other than the display
set. Switching by the app in front or the time of day belongs to Shortcuts
automations through the App Intents.

### Hotkey per profile

Bind global keyboard shortcuts to apply a specific profile (e.g.
⌥⌘1 = Work, ⌥⌘2 = Presentation), and one to Revert.

**Why it was deferred**
- Already addressable via Shortcuts.app (the App Intents integration): a
  keyboard shortcut can run a Shortcut that applies a profile.
  *Corrected 2026-11-15: this was never true. The App Intents are Set
  Resolution and Get Resolution; applying a profile from Shortcuts needs the
  Apply Profile intent listed under the break-it QA findings below.*

**Decided 2026-11-13: build it, next after the first-profile onboarding.**
The Shortcuts route needs one hand-built Shortcut per profile; a shortcut
field next to the profile is one step, in the place the user already is.
The App Intents stay for Stream Deck, automations and scripting.

**Built 2026-11-13, for the next release.** The maintained contract and
accepted Carbon limitations are in [PRD §4.11](PRD.md#411-global-shortcuts);
setup and everyday use are in the [user guide](README.md#keyboard-shortcuts).
The separate Settings tab was chosen because recording in a normal window
is sturdier than in the popover and one list shows every shortcut.

## Follows from VISION.md (2026-11-13)

Changes the approved vision asks for that the app does not do yet. None is
built; each still needs its own design before it ships.

### Confirm resolution changes on by default
**Built 2026-11-13.** On for a fresh install (no welcome tour finished yet),
with the switch in the tour's last step and in Settings → Display; skipping
the tour keeps it on. An install from before keeps what it had, which is off
for anyone who never touched it. Guards a size or rate picked by hand only.

### HDR as an advanced profile setting
VISION.md: HDR is the one colour setting in reach, as an advanced control
that Simple mode keeps out of sight. A profile saved with HDR restores it in
Simple mode too, and the outcome says HDR changed. Open: which API reads and
sets HDR per display, and whether it needs a private symbol (allowed only
behind a fallback that keeps the previous behaviour).

### Bring windows back on screen after a mode change
VISION.md: an opt-in that asks for the Accessibility permission only when it
is switched on. Moves windows a mode change left off-screen or under the menu
bar back into view. Off by default; without the permission it stays off and
says why.

### Report a problem with a prefilled bug report
VISION.md: diagnostics leave the Mac only when the user sends them, for
example as a prefilled bug report the user reads before submitting. A button
in Settings -> Debug opens a new GitHub issue with the diagnostics in its
body. Open: URL length limits for the log lines, and falling back to copying
when the report is too long.
**Built 2026-11-14:** "Report a problem…" next to Copy diagnostics opens
the bug report form with the diagnostics in its field (`BugReport`). Links
stay under 5,500 characters (signed out, GitHub keeps the prefill through
login only up to about 6,000 and answers HTTP 500 from about 6,950): the
oldest log lines are left out first and the report says how many; if even
that is too long, the form opens empty and the full report goes on the
clipboard, which the Debug tab says.

### Revert after the CLI and the Set Resolution intent
VISION.md: a shortcut or script applies like the CLI, and Revert takes it
back. Profiles, shortcuts and auto-apply record Revert; the `viberes` CLI
(a separate process) and the Set Resolution App Intent (which calls the
switcher directly) still record none, so Revert afterwards offers the
action before them. Open: how the CLI hands its change to the running app,
and whether the intent should go through `DisplayStore` instead.

## Break-it QA findings, deferred (2026-11-15)

Found in the 1.0 QA pass and left for later on purpose. The pass fixed the
safety nets, the profile catalog, and Settings, shortcuts and copy; these did
not make that cut.

### Apply Profile App Intent
VISION.md and the README imply a Shortcut can apply a profile, but the App
Intents are only Set Resolution and Get Resolution. An Apply Profile intent
(with the profile as an `AppEntity`) would close that. Open question for
1.0: build it as its own change, or document the gap.

### Identical twin monitors saved at different modes
Two monitors that report the same vendor, model and serial bind to both
`.edid` entries of a profile, so applying stages the same display twice and
both rows of the outcome report success (`ProfileStore.applyDetailed`). The
save already warns that such displays cannot be told apart; apply should say
so too, or bind entries to displays one to one.

### More than 200 profiles
`ProfileStore.capped` keeps the first 200 profiles of a hand-edited or
merged catalog, and the next save writes only those. Since the catalog fix,
a file the app could not fully read is copied aside before it is replaced,
but the cap does not count as "could not read" yet, so the profiles past 200
are lost without a copy or a note.

### Duplicate profile ids in a hand-edited file
Two profiles with the same id: delete removes both, and the profile list's
`ForEach` gets non-unique ids. Decoding could give the second a new id, or
keep only the first and report the drop like any unreadable item.

### A shortcut that fails at launch is easy to miss
A saved shortcut that cannot be registered at launch is reported in Settings
→ Shortcuts and in the profile's Edit form, nowhere else. VISION.md wants
problems "reported, never hidden"; a quiet note in the popover would be
enough. (Falling back quietly when a shortcut is pressed while the action
cannot run is accepted in PRD §4.11.)

## Motion and polish audit (2026-11-13)

A pass over the whole app with the motion-polish checklist. The popover
already moves with a job per animation (`Design.Motion`, popover motion v2):
press feedback, rows making room, notes, rolling numbers, the changed-glow,
the travelling MAIN badge and rate highlight, the pill checkmark bounce, the
menu bar glyph moment, Reduce Motion handled throughout. What is left sits
around it: the hover preview, the safety countdown, the global shortcuts that
run with the popover closed, and the Settings window. Ranked by value for
effort; each item says when it was built.

### 1. Hover preview morphs between sizes
- **Moment:** moving the pointer down the size list in a display's detail.
  The proposed rectangle in the preview box jumps from size to size, and the
  box itself pops in and out.
- **Job:** connect. The eye should see "bigger" or "smaller" as a change, on
  the feature VibeRes has that the alternatives do not.
- **Technique:** the proposed rectangle springs to its new frame
  (`.animation(Design.Motion.chip, value: proposed size)`), and the box fades
  and scales in from 0.96 on first hover (`rowIn` timing), out with `rowOut`.
- **Reduce Motion:** the rectangle crossfades (`quick`); the box fades only.
- **Effort:** S. `PreviewBox.swift`, `DisplayDetailView` overlay.
- **Built 2026-11-14:** as above, except the box appears with `quick` at
  once rather than `rowIn`: a hover preview answers the pointer, and the
  0.2 s delay made it lag behind it.

### 2. The safety countdown drains
- **Moment:** "Keep this resolution? Reverting in 12s" with Confirm
  resolution changes on.
- **Job:** progress. A draining bar reads at a glance on a screen that may be
  barely legible; the rolling seconds need reading.
- **Technique:** a thin bar along the row's bottom edge in the warning tint,
  `ProgressView(timerInterval:)` or a width driven by `TimelineView`, linear
  over the window.
- **Reduce Motion:** the bar steps once a second with the digits instead of
  sliding.
- **Effort:** S. `MenuContent.swift` countdown row.
- **Built 2026-11-14:** a 2 pt bar in the warning tint along the bottom of
  `ConfirmationRow`, driven by `TimelineView(.animation)` from the
  countdown's deadline; under Reduce Motion it steps with the seconds. The
  clock symbol takes the same tint, as the palette says warning notes do.

### 3. The shortcut recorder shows its state
- **Moment:** recording a shortcut in Settings or the Edit form.
- **Jobs:** progress (listening), confirm (accepted), and a clear "no".
- **Technique:** while listening the field carries an accent border that
  breathes (opacity loop, period ~1.2 s, stops when recording stops); an
  accepted combination lands with the existing `changedGlow`; a refusal gives
  one short horizontal shake (~0.3 s, three small offsets, `keyframeAnimator`).
- **Reduce Motion:** the border is static; no shake, the border turns orange
  for the refusal instead. The reason text stays the real signal.
- **Effort:** S. `ShortcutRecorder.swift`.
- **Built 2026-11-14:** `recorderState` on the recorder field: a 2 pt accent
  border breathing between full and 0.3 opacity (`phaseAnimator`, 1.2 s a
  breath) while listening, the changed-glow on an accepted combination, a
  0.3 s shake (-5, 4, -2, 0 pt) on a refusal. Reduce Motion: the border holds
  still and turns orange while the refusal stands.

### 4. The menu bar glyph answers a missed shortcut
- **Moment:** a global shortcut pressed with the popover closed that did
  nothing (no profile display connected, nothing to revert, a failed switch).
  Today the only answer is the alert sound, which is off for anyone with
  muted alerts.
- **Job:** confirm, negatively. Success already answers: the displays change
  and the glyph plays its switch moment.
- **Technique:** a short "no" moment on the status glyph, a small horizontal
  shake of the window glyph (~0.5 s), drawn through `MenuBarIconAnimator`
  frames per the motion-polish skill's `status-glyphs.md`.
- **Reduce Motion:** a brief dim of the glyph instead of the shake.
- **Effort:** M. Needs glyph frames and their size tests.

### 5. Onboarding marks the first saved profile
- **Moment:** the welcome tour's profile step after **Save profile**. The
  confirmation crossfades in.
- **Job:** celebrate, quietly. The first profile is the one milestone in the
  app; the pill checkmark already bounces once on activation, so the same
  system bounce on the confirmation's checkmark ties the two together.
- **Technique:** `.symbolEffect(.bounce, value: savedName)` on the
  confirmation symbol. No confetti.
- **Reduce Motion:** no bounce, the crossfade stays.
- **Effort:** XS. `OnboardingView.swift`.
- **Built 2026-11-14.** The confirmation is now one view that shows rather
  than a branch that appears, so the bounce sees the name change.

### 6. "Copied" in Settings swaps in place
- **Moment:** Settings → Debug → Copy diagnostics.
- **Job:** confirm.
- **Technique:** `.contentTransition(.symbolEffect(.replace))` on the label so
  the checkmark replaces the text instead of cutting.
- **Reduce Motion:** crossfade.
- **Effort:** XS. `SettingsView.swift`.
- **Built 2026-11-14:** one label, "Copy diagnostics" with a copy symbol
  that swaps to "Copied" with a checkmark.

### Product suggestions (not motion)
- **The Revert row wraps onto two lines.** "Revert Built-in Retina Display →
  1512×982" is too long for the popover footer and breaks the menu-like row.
  Shorter label ("Revert to 1512×982"), the display name in the tooltip and
  the accessibility label. A UI defect, worth fixing before the motion items.
  **Built 2026-11-14:** "Revert to 1512×982", or "Revert size and main
  display" when the menu bar moves back too (the size does not fit there in
  every language) and "Revert 2 displays"; the whole sentence with display
  names is the tooltip and what VoiceOver reads. Footer rows are one line.
- **VoiceOver hears a shortcut's result.** With the popover closed a profile
  or Revert shortcut is silent for a screen reader user. Post an
  accessibility announcement ("Applied Work", "Nothing to revert") through
  `NSAccessibility.post(element:notification: .announcementRequested)`.
  **Built 2026-11-14:** a profile shortcut says the profile's name and the
  note the popover would show ("Desk: Already at the saved settings."),
  or that none of its displays is connected; Revert says it reverted, that
  there was nothing to revert, or what could not be reverted. The alert
  sound stays for a miss. `ShortcutAnnouncement`, posted 0.6 s later so the
  mode switch does not swallow it.
- **A hint for a profile that can never apply here.** A pill whose displays
  are all missing applies nothing; its tooltip could say which monitor it is
  waiting for, as the confirmation panel already does.
  **Built 2026-11-14:** the pill dims and its tooltip (and VoiceOver value)
  says "Waiting for LG UltraFine", then the panel's reason. The pill
  tooltip and the apply confirmation were English in every language; they
  are in the catalog now, and the panel names the missing or extra
  displays instead of counting them with "(s)".
- **No new sounds.** macOS has no silent mode to respect and the menu bar
  utility should stay quiet; the alert sound for a missed shortcut is the
  one sound worth having.

## Shipped, kept here so they are not re-proposed

### One format for sizes and refresh rates — shipped in 0.14.0

Cards, both profile forms, apply notes, the hover preview, the confirmation
rows and Revert notes wrote three dialects ("2 560 × 1 440 · 60 Hz",
"2560×1440 · 60 Hz", "2560×1440 @75Hz"). `ModeFormat` now writes all of them
as "2 560 × 1 440 · 60 Hz" (narrow no-break space between digit groups, "Hz"
and "VRR" as symbols), the same in en, sk, cs, de, es and fr.

### Sparkle in-app updates — shipped in 0.8.2

Deferred here until "monthly non-brew downloads pass ~100"; shipped earlier
because the manual "download the ZIP and replace the .app" step was the only
update path for anyone not using Homebrew. EdDSA signing, a signed feed, and a
gate that refuses to self-update anything not Developer ID signed by this
project. See `PRD.md` §4.13.

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
