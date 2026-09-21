# VibeRes — Product Requirements

A menu-bar resolution switcher for macOS. Open source, native Swift, one
third-party dependency.

This document describes what VibeRes is meant to do and why it is built the way
it is. It is maintained: when a decision here stops matching the code, one of
the two is wrong and the discrepancy is a bug in its own right.

It replaces the original pre-implementation plan, which had drifted far enough
to be misleading — it still specified macOS 13, an `NSStatusItem` + `NSPopover`
shell explicitly instead of `MenuBarExtra`, and no package dependencies, none of
which survived contact with the implementation. The reasoning that was worth
keeping — the competitive gap, the CoreGraphics pitfalls, the App Store
decision — is carried forward below. The original is in git history.

- **Current version:** 0.9.0
- **Status of this document:** current as of 2026-09-21

---

## 1. What it is, and who it is for

Someone with a Mac and at least one display who changes resolution more than
once a month: a laptop that docks to a desk, a presenter plugging into whatever
projector the room has, anyone who wants 120 Hz for scrolling and native pixels
for pixel work.

The whole interaction is meant to take about three seconds. Click the menu-bar
icon, see every connected display and what it is doing, click a size, done.
Everything else in the product exists to make that three seconds shorter or
safer, or to let it happen without the popover at all.

### Why it exists

[EasyRes](http://easyres.softwar.io/) (Chris Miles, bundle id
`info.chrismiles.easyres`) was the only free menu-bar switcher with **preview**
of what a resolution change would do. Last release 1.1.4, around 2017; gone from
the Mac App Store; no Apple silicon, no macOS 14+. The alternatives each miss
something:

| Tool | Type | Price | What is missing |
|---|---|---|---|
| **SwitchResX** | GUI + menu bar | ~$16 | The most capable, and paid, and feature-overloaded |
| **Resolutionator** | menu bar | $3 | Works, closed source, no preview |
| **QuickRes** | menu bar | $7 | Toggles between two modes, not a full picker |
| **BetterDisplay** | GUI + menu bar | free/paid | Excellent, but a different product — DDC, virtual displays, HiDPI override |
| **displaymodemenu** (peaz) | menu bar | free (Apache 2.0) | Closest to this. No preview, drier UX |
| **ResolutionMenu** (robbertkl) | menu bar | free (MIT) | ObjC, last updated Jan 2023, uses private APIs |
| **displayplacer** (jakehilborn) | CLI | free (MIT) | CLI only — but a good reference implementation |

VibeRes is the `displaymodemenu` niche with a preview, multi-display profiles,
and a CLI that links the same code as the app.

### Principles

1. **The popover is the product.** Anything that pulls the user out of it — a
   separate window, a system alert, a modal — needs a reason. Confirmations are
   inline for this reason.
2. **Never strand the user.** A resolution change can make the screen
   unreadable, and the button that would undo it is on that screen. Every
   destructive or risky path has a way back that does not require seeing
   anything (see §4.6).
3. **Say what actually happened.** If a display fell back to a different refresh
   rate, or was skipped, or the arrangement was adjusted by macOS, the user is
   told — in their own language.
4. **No telemetry.** Not anonymised, not opt-in-with-a-nudge. An app that reads
   display hardware has no business phoning home, and "used by 2,400 people"
   is not worth the trade.

---

## 2. Non-goals

These are deliberate. See [BACKLOG.md](BACKLOG.md) for the ones that have been
argued through, and why.

- **Not a display configuration manager.** Mirroring, DDC, brightness, colour
  profiles, virtual displays: BetterDisplay territory. Resolution, refresh rate
  and which display is main is the whole scope.
- **Not on the Mac App Store.** The sandbox forbids
  `kCGDisplayShowDuplicateLowResolutionModes`, which is exactly what lets
  VibeRes list the modes System Settings lists. Sandboxing the app would
  remove the feature it exists for. Distribution is Developer ID signed,
  notarized builds through GitHub Releases and Homebrew.
- **No global hotkeys of its own.** Shortcuts.app already does this, VibeRes
  exposes App Intents, and a Shortcut can be bound to any key the user likes —
  including from Stream Deck, BetterTouchTool and Loupedeck, which all trigger
  Shortcuts.
- **No full arrangement storage.** A profile pins *which display is main*
  (§4.5) but stores no geometry. Stage 2 remains deferred.

---

## 3. Platform and stack

| Decision | Value | Why |
|---|---|---|
| Language | Swift 6.0, `SWIFT_STRICT_CONCURRENCY: complete` on **every** target | The app drives WindowServer from several event sources — timers, CG callbacks, wake notifications. Data races here corrupt display state |
| Deployment target | macOS 26.0 | The code leans on `@Observable`, `MenuBarExtra(.window)`, `NavigationStack`, `SMAppService`, App Intents and ScreenCaptureKit at once. See §7 for what a backport costs |
| UI | SwiftUI in `MenuBarExtra(.window)` | The original plan specified `NSStatusItem` + `NSPopover` and rejected `MenuBarExtra`. `MenuBarExtra` won on the amount of AppKit it removes; the cost is its cached panel geometry, which the app works around explicitly (`DisplayStore.dismissStaleMenuBarPopover`) |
| Architecture | `VibeRes/Core` is Foundation + CoreGraphics only, with no AppKit and no bundle assumptions | It is compiled into the `viberes` CLI target verbatim. This is why user-facing copy in Core stays English and is localised in `VibeRes/UI` — see §4.11 |
| Dependencies | Sparkle, pinned by exact version. Nothing else | An updater is the one dependency whose compromise is arbitrary code execution, so it is pinned and watched (§8) |
| Project file | `project.yml` via XcodeGen; `*.xcodeproj` is generated and gitignored | One reviewable source of truth for build settings |
| Binary | Universal (arm64 + x86_64) | macOS 26 still supports a handful of Intel Macs, and the slice costs nothing but download size |
| Distribution | Developer ID signed, notarized, stapled; GitHub Releases, Homebrew cask and formula, Sparkle feed | See §2 for why not the App Store |
| Licence | MIT | |

---

## 4. Requirements

Each requirement is a statement about behaviour that should be checkable
against the code. "Evidence" names where it lives.

### 4.1 Display enumeration

- Every active display is listed with its name as System Settings shows it, its
  current mode, and whether it hosts the menu bar.
- The mode list includes scaled HiDPI modes, which the default CoreGraphics
  call omits.
- Modes not usable for the desktop are filtered out.
- NTSC drop-frame refresh rates (59.94, 47.95) are deduplicated against their
  integer counterparts, preferring whichever is closer to a whole number.
- Enumeration is bounded: at most 32 active displays.

*Evidence:* `Core/DisplayManager.swift`, `Core/ResolutionGroup.swift`,
`Core/DisplayNamer.swift`.

### 4.2 Switching

- One click applies a mode. The reconfiguration is one
  Begin/Configure/Complete transaction whatever the number of displays.
- A mode the display refuses is dropped before the commit; the displays that
  would have worked still change. A failed commit changes nothing.
- Failures are explained in plain language with the numeric CoreGraphics code
  kept for bug reports, and are shown where the action happened.

*Evidence:* `Core/ResolutionSwitcher.swift`, `Core/UserFacingProblem.swift`,
`UI/ProblemCopy.swift`.

### 4.3 Reading the list

- Sizes are one row each; refresh rates are a segmented control on the row.
- **Simple Mode** (default) hides the per-rate control: a click takes the
  highest rate available for that size.
- Sizes below 60% of the widest are collapsed behind a disclosure, except the
  current one, which is never hidden.
- **Every row is a button.** Applying a resolution must be reachable by
  keyboard and must be announced as an action by VoiceOver. This is a hard
  requirement, not a nicety: Simple Mode is the default, and in Simple Mode the
  row is the only control.

*Evidence:* `UI/MenuContent.swift`, `Core/ResolutionListPartition.swift`.

### 4.4 Preview

- Hovering a row that is not the current one shows the proposed mode as a
  filled rectangle inside an outline of the current one, both at the same
  scale, in a fixed corner of the list.
- The tooltip carries what a rectangle cannot: mode family, true pixel count,
  and the change in screen space.
- **Live preview** (off by default) fills the inner rectangle with a real
  screenshot cropped to the proposed aspect ratio, so the user sees which part
  of their desktop survives the switch.
- Live preview is frugal with the Screen Recording permission: one still per
  display view, never a capture stream, cached while the popover is open,
  dropped when it closes, rendered on device and never transmitted. The
  permission is requested on the **first hover**, which is the point of use —
  not on opening a display.

*Evidence:* `UI/PreviewBox.swift`, `Core/DesktopCapture.swift`.

### 4.5 Profiles

- A profile is a named multi-display preset: per display, a target mode and how
  the entry binds to hardware.
- Binding is either **specific** (locked to one physical monitor by EDID,
  surviving reboots and reconnects) or **any external** (bound by role, so the
  profile travels to whatever projector is in the room). Built-in is always
  specific. Unlisted displays are left untouched.
- At most one "any external" entry per profile: more than one would have every
  entry match every external, and the last would win after blinking through the
  others.
- A profile can pin which display becomes main. The default is "don't change".
  The change is applied as a full-coverage translation of the live arrangement
  and verified by reading the arrangement back — a successful commit is not
  evidence that the request was honoured.
- **Profile names are unique**, case-insensitively. They are the handle the CLI,
  Shortcuts and any script address a profile by, so a name has to identify one
  profile. A catalog written by an older version may contain duplicates; those
  are reported, never guessed between.
- Applying a profile reports per display what happened: exact match, closest
  available, not connected, no usable mode, or failed.
- A profile whose displays do not exactly match what is connected routes
  through an inline confirmation showing what will be skipped and what will be
  left alone.
- Deleting a profile asks first. There is no undo for it.

*Evidence:* `Core/Profile.swift`, `Core/ProfileStore.swift`,
`Core/DisplaySetClassifier.swift`, `UI/ProfilesSection.swift`.

### 4.6 Not stranding the user

This is principle 2 made concrete, and it is the requirement with the least
room to negotiate.

- **Revert** (`⌘Z`, or the footer row) undoes the last action — one display or
  a whole profile, including the main-display change. A revert that fails keeps
  the entry so it can be tried again, and reports only what actually came back.
- **Confirm resolution changes** (opt-in) applies for the session only and
  undoes it after 12 seconds unless confirmed. The *timeout* is the safety net,
  not the button: someone looking at a black screen cannot click anything.
- Revert history is dropped when it would reference a display that is no longer
  attached.

*Evidence:* `Core/RevertHistory.swift`, `Core/RevertCountdown.swift`,
`DisplayStore.performRevert`.

### 4.7 Auto-apply

- When a monitor is plugged in or unplugged, the saved profile that exactly
  matches the new set is applied silently.
- "Exactly" means every entry binds to something live and every live display is
  covered. Where several profiles match, the more specific wins (EDID beats
  built-in beats any-external), and a tie goes to the more recently saved.
- A resolution change on its own never triggers it: the app must not fight a
  user who just picked a mode by hand.
- Nothing is announced when nothing actually changed.

*Evidence:* `ProfileStore.profileMatchingExactly`,
`DisplayStore.applyRefresh`, `ProfilesSection.autoApplyMatchingProfile`.

### 4.8 Waking and racing

- After wake, and at launch via Launch-at-Login, WindowServer can briefly
  report an empty or partial display list. The app samples until two
  consecutive samples agree, and commits only then — with a 3.75 s ceiling.
- A settled wake where the same monitors came back at different modes
  re-triggers auto-apply.

*Evidence:* `DisplayStore.scheduleWakeRefresh`, `DisplayStore.wakeSettled`.

### 4.9 Command line

- `viberes` links the same Core code as the app: same profile store, same
  CoreGraphics calls, same scoring. It is not a reimplementation.
- Commands: `list`, `modes`, `current`, `set`, and `profile
  list|show|save|apply|update|flex|rename|delete`.
- A display is addressed by a case-insensitive substring of its name or its
  numeric id; a profile by name or by the id `profile list` prints.
- Exit code 0 on full success, 2 when anything fell back or was skipped, 1 on
  a usage or lookup error. Errors go to stderr.
- `VIBERES_PROFILE_DIR` relocates the catalog, so the CLI can be scripted — and
  tested — against a throwaway set.
- A refused operation exits non-zero. It must never print success over a
  no-op.

*Evidence:* `VibeResCLI/main.swift`.

### 4.10 Shortcuts and Siri

- **Set Display Resolution** and **Get Current Resolution** register as App
  Intents, reachable from Shortcuts, Spotlight and Siri.
- Parameters are validated at the boundary with the same bounds as the CLI
  (1–16384 points, 1–1000 Hz) and refused per parameter, not silently
  best-matched. Scoring is overflow-safe regardless, as a second line.

*Evidence:* `Shortcuts/SetResolutionIntent.swift`, `Core/ModeScoring.swift`.

### 4.11 Language

- The interface ships in English, Slovak and German, from a String Catalog.
- User-facing copy produced in `VibeRes/Core` stays English, because Core is
  compiled into the bundle-less CLI. Anything the *app* shows is rendered in
  `VibeRes/UI` from structured values, never from a pre-formatted English
  sentence.
- The catalog's coverage is enforced in CI (§8). It is not enough for the
  catalog to be internally complete — it has to cover what the app emits.

*Evidence:* `Resources/Localizable.xcstrings`, `UI/ApplyOutcomeNote.swift`,
`UI/ProblemCopy.swift`, `UI/ProfilePreviewCopy.swift`,
`scripts/check-localisation.sh`.

### 4.12 Updates

- Sparkle, with the appcast served from a stable path in the repository and a
  signed feed (`SURequireSignedFeed` + `SUVerifyUpdateBeforeExtraction`).
- Updates download in the background; the popover offers a restart. **The app
  never restarts itself.**
- A build that is not Developer ID signed by this project's team, or that
  Homebrew installed, does not self-update and says which it is. Downloading
  and executing a binary from the internet is the one operation where the app
  checks who it is before acting.

*Evidence:* `UI/Updater.swift`, `UI/UpdaterGate.swift`, `appcast.xml`.

### 4.13 Everything else

- Launch at login via `SMAppService`, with the user's *intent* stored
  separately so a registration invalidated by an update or a move is
  re-registered rather than silently forgotten.
- A three-step welcome tour on first launch, replayable from Settings.
- Settings in a standard `⌘,` scene: General, Display, Updates.
- `⌘1`…`⌘9` apply the first nine profiles while the popover has focus.

*Evidence:* `Core/LoginItem.swift`, `Core/Preferences.swift`,
`UI/SettingsView.swift`, `UI/OnboardingView.swift`.

---

## 5. Platform constraints worth knowing

Hard-won, and easy to rediscover the expensive way.

1. **`CGDisplayCopyAllDisplayModes` returns an incomplete list** without
   `kCGDisplayShowDuplicateLowResolutionModes`. System Settings shows modes the
   default call does not.
2. **HiDPI is `pixelWidth > width`** — `width` is logical points, `pixelWidth`
   is the framebuffer.
3. **`isUsableForDesktopGUI()`** filters modes that exist for TV-out and
   similar internal uses.
4. **Identify displays by EDID**, never by index: `CGDisplayVendorNumber` +
   `CGDisplayModelNumber` + `CGDisplaySerialNumber`. Indices shift when modes
   change. Two identical monitors can still report the same identity, which no
   amount of care fixes — the app says so rather than guessing.
5. **Setting the main display is not an API call.** Whichever display sits at
   (0,0) is main. A *partial* origin change is silently mangled by the window
   server and still returns success, so any origin statement must cover every
   active display, and the result must be read back. Measured in
   `docs/display-arrangement-spike-2026-08-01.md`.
6. **Active is not online.** A sleeping or clamshell display is online but not
   active, and configuring one fails with undocumented errors.
7. **TCC keys Screen Recording grants by code-signature hash**, not bundle id.
   Ad-hoc signed builds lose the grant whenever the signature drifts, which is
   why released builds are Developer ID signed and why the app stops asking
   after two failed attempts.
8. **`MenuBarExtra(.window)` caches its panel geometry.** After a
   reconfiguration the popover can open offset, or on the wrong monitor, until
   the cached frame is reset.

---

## 6. Quality bar

- **Tests:** Swift Testing. Every pure decision — scoring, bucketing,
  matchers, planning, countdowns, revert, outcome aggregation, the updater
  gate, the screen-recording permission machine, store limits, name
  resolution, form validity — is covered. Anything that would reconfigure a
  real display is injected through a seam, so a test never changes the
  machine. Currently 299 tests in 47 suites.
- **The CLI is tested as a binary**, not as a copy of its logic: the tests run
  `viberes` with `VIBERES_PROFILE_DIR` pointed at a temporary directory and
  assert on exit codes and output.
- **Views are not unit-tested**, because asserting on rendered SwiftUI tests
  the framework. Behaviour that matters is pushed out of the view into
  something testable — form validity, picker contents and row copy all live on
  their state types. The one thing that cannot be: whether a control *is* a
  control. A small XCUITest suite drives the real app through the
  accessibility API for that, and it is verified to fail when the resolution
  row goes back to being a tap gesture.
- **CI gates on every push and PR:** tests, the UI suite in a job of its own,
  a Release app build, a Release CLI build with a smoke test, and localisation
  coverage. A red gate is a broken build, not a warning — 0.9.0 shipped with
  22 untranslated strings because a red localisation gate sat unattended for
  six weeks.
- **Weekly:** pinned dependency versions are checked against published security
  advisories (`scripts/check-dependency-advisories.py`).
- **Release:** `git tag vX.Y.Z && git push --tags`. The workflow refuses a tag
  that is not an ancestor of `main`, builds, signs, notarizes, staples,
  publishes, and syncs the Homebrew tap. One global concurrency group, because
  two concurrent runs once published an appcast signed for a different build.

---

## 7. Older macOS

Lowering the deployment target is mostly one line in `project.yml`:

- **macOS 15 Sequoia** — everything compiles.
- **macOS 14 Sonoma** — should work as-is.
- **macOS 13 Ventura** — needs ~30 lines: `@Observable` is macOS 14+, so
  `DisplayStore` and `ProfileStore` would fall back to `ObservableObject` +
  `@Published`.
- **macOS 12 Monterey and older** — a rewrite. `MenuBarExtra(.window)`,
  `NavigationStack`, `SMAppService.mainApp` and App Intents all arrived in 13.

---

## 8. Document history

| Date | Change |
|---|---|
| 2026-09-21 | Rewritten as a maintained PRD. The original pre-implementation plan is in git history |
| 2026-08-03 | 0.9.0: main display in profiles (Stage 1 of arrangement support) |
