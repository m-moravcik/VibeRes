# VibeRes — display arrangement spike

Date: 2026-08-01
Commit at time of spike: `4fc49a772917e656e2f28fbebbc2a099c9e5ec51` (`Prepare 0.8.6`, after `v0.8.5`)
Status: **spike complete, feature not implemented**
Relates to: `BACKLOG.md` → *Display arrangement preservation*

## Why this exists

A user asked for MultiMonitorTool-style saved layouts — where each display sits
relative to the others, and which one is main. `BACKLOG.md` already carried this
as deferred, on the assumption that it was a large, uncertain piece of work.

This document records what was measured rather than assumed, because the central
assumption in the deferral turned out to be wrong in a way that changes the
design.

## What the request actually asks for

macOS already persists arrangement per display set, so "restore my layout after
reconnect" is mostly solved by the OS. Two things are not:

1. **Several different arrangements for the same set of monitors** — docked left
   vs docked right, presentation vs desk. macOS has no concept of this.
2. **Which display is main** (hosts the menu bar) as part of a saved setup.

Both are what VibeRes profiles are already shaped like. Evidence of demand is
thin (one detailed request; the repo had 6 stars, 0 issues and roughly 200
release downloads at the time of writing), so the scoping below is deliberately
conservative.

## Method

Throwaway Swift binaries built with `swiftc`, run against the live WindowServer.
Nothing in the app or the repo was modified.

- Host: macOS 26.5.2 (build 25F84), Apple Silicon, Swift 6.3.2
- Displays: 3 active
  - `id=1` built-in, main, origin `(0,0)`, 1800×1169 pt
  - `id=2` external, origin `(1074,-1080)`, 1920×1080
  - `id=3` external, origin `(-1486,-1440)`, 2560×1440

A non-trivial layout with vertical offsets and negative coordinates was
deliberately used, since an all-on-one-row arrangement would have hidden the
snapping behaviour described below.

Every mutation used `CGCompleteDisplayConfiguration` with `.forAppOnly` plus an
explicit restore transaction, and each restore was verified against a snapshot
taken before the change.

## Findings

### F1 — A partial origin change is silently mangled

Requesting only the target's origin, expecting the window server to rearrange
the rest:

```
>>> CGConfigureDisplayOrigin(display 2 -> (0,0)), scope=.forAppOnly
  ✓ committed
AFTER:
    id=1 origin=(    0,    0)  [builtin] <MAIN>
    id=2 origin=( 1800,    0)  [external]
    id=3 origin=(-1486,-1440)  [external]

main moved:      1 -> 1  => NO
menu bar moved:  1 -> 1  => NO
topology:        before 2:(1074,-1080)   after 2:(1800,0)   => NOT PRESERVED
```

The transaction **succeeded**. The main display did not change, and display 2
landed at neither the requested origin nor its previous one — its vertical
offset was destroyed.

Display 1 stayed pinned at `(0,0)`, so the window server resolved the conflict
by pushing display 2 aside to the nearest non-overlapping slot.

`CGConfigureDisplayOrigin` is not "move this display". It is a statement about
the desired final arrangement, and an incomplete statement gets completed for
you — badly.

### F2 — A complete arrangement change is exact, and does move the menu bar

Same goal, but every active display's origin is renormalised so the target sits
at `(0,0)`, all in one transaction:

```
    plan: id=1 -> (-1074,1080)
    plan: id=2 -> (0,0)
    plan: id=3 -> (-2560,-360)
  ✓ committed
AFTER:
    id=1 origin=(-1074, 1080)  [builtin]
    id=2 origin=(    0,    0)  [external] <MAIN>
    id=3 origin=(-2560, -360)  [external]

main moved:      1 -> 2  => YES
menu bar moved:  1 -> 2  => YES
all origins:     EXACT (no snapping)
topology:        PRESERVED
```

No snapping whatsoever, including negative coordinates. Topology is preserved
because the caller computed it, not because the window server inferred it.

**Rule: any apply that touches origins must specify an origin for every active
display — not merely for the displays named in the profile.**

### F3 — Mode and origin commit together, resolved against the new geometry

Changing a display's mode changes its size in points, so the arrangement maths
depends on which geometry the window server uses. Both in one transaction:

```
>>> display 2 mode 1920x1080 -> 1280x720 + all origins, one transaction
    plan: id=2 -> (-1280,0)
  ✓ committed
    id=2 requested (-1280,0) actual (-1280,0) EXACT
    mode applied: 1280x720 => YES
```

`-1280` is only the correct "immediately left of main" position under the *new*
width, so origins are resolved post-change. No two-pass apply is needed.

### F4 — `.forAppOnly` reverts modes and origins on process exit

After exiting without an explicit restore, the full original state returned —
both the mode change and all three origins.

Useful for spikes, **not usable as the app's safety net**: it reverts when the
process exits, and a menu-bar app does not exit. The equivalent for VibeRes is
`.forSession` (or `.permanently`) plus a timed explicit revert. Explicit restore
was verified byte-exact on every run, so a "Keep this arrangement? 15s" countdown
is implementable.

### F5 — Success from the API does not mean the request was honoured

With a single active display, requesting origin `(500,300)`:

```
  ✓ committed (CGError 0)
  requested (500,300) -> actual (0,0): SNAPPED
```

Read back `CGDisplayBounds` after the commit and compare. The return code is not
evidence. (The single-display case forces `(0,0)`, but F1 shows the same
success-with-different-result on multi-display.)

### F6 — A display that was live earlier this session fails at commit, not at staging

Two runs, and the difference between them is the finding.

While displays 2 and 3 were disconnected, probing `id=2` — an id CoreGraphics had
seen live earlier in the same session:

```
bogus-id         id=999: begin=0 configure=1001 complete=0
plausible-absent id=2:   begin=0 configure=0    complete=1001
```

Re-run with all three displays active, probing `id=4`, which has never existed:

```
bogus-id         id=999: configure=kCGErrorIllegalArgument
plausible-absent id=4:   configure=kCGErrorIllegalArgument
```

So the split is not "implausible vs plausible id". A **never-known** id is
rejected at staging, where it is harmless. An id that **was active earlier and no
longer is** passes `CGConfigureDisplayOrigin` as success and takes the whole
transaction down at `CGCompleteDisplayConfiguration` with
`kCGErrorIllegalArgument`.

The second case is the dangerous one, because it is the exact shape of a monitor
unplugged between building the plan and committing it.

Note for anyone re-running this: `./spike errors` reproduces only the second
block. Reproducing the first needs a display that was connected and then removed
during the same session.

This matters for `ResolutionSwitcher.applyBatch`, which currently tolerates
per-display staging rejections and carries on. That tolerance works for modes.
It cannot work for origins: skipping a rejected display's origin turns a complete
arrangement into a partial one, which is F1. **Modes degrade gracefully; origins
must be all-or-nothing.**

### F7 — Asleep and clamshell displays are online but not active

With the lid closed:

```
CGGetActiveDisplayList  err=0 count=0
CGGetOnlineDisplayList  err=0 count=1
AppleClamshellState = Yes
```

Configuring a display in that state produced an undocumented `CGError 1014`.
Any arrangement apply must gate on `CGGetActiveDisplayList`, and wake-triggered
auto-apply can land in a window where displays are online but not yet active.

### F8 — `.forSession` origins behave like `.permanently` within the session, and survive process exit

Measured 2026-08-01 on the same 3-display setup (`./spike mainfull session`,
then `./spike mainfull session norestore`):

```
>>> renormalise ALL origins so display 2 is at (0,0), scope=session
  ✓ committed
  all origins EXACT, main 1 -> 2, menu bar 1 -> 2, topology PRESERVED
  explicit restore verify: main=OK bounds=OK

>>> same, norestore, then probe after process exit:
[STATE] CGMainDisplayID=2   id=2 origin=(0,0) <MAIN>   — change SURVIVED exit
  recovered with ./spike setall 1:0:0 2:1074:-1080 3:-1486:-1440  ✓ byte-exact
```

So `.forSession` commits origins exactly like `.permanently` (F2 shape), and
unlike `.forAppOnly` (F4) it does **not** revert when the process exits — per
the scope's documentation it reverts at logout/restart, which was not tested
(it would kill the session doing it). This makes `.forSession` usable as the
backstop layer of a future "Keep this arrangement? 15 s" countdown: the
countdown's revert is still an explicit re-apply, `.forSession` only bounds
the damage if the app dies before confirming.

Not instrumented: how visible an origin-only reconfiguration is (blank vs
fade). Record the observation during the 0.9.0 manual checklist run.

## What this invalidates

- **The cheap single-call main-display swap does not exist.** Setting main
  requires computing and committing origins for every active display (F1, F2).
- `BACKLOG.md`'s "~2–3 days" for full arrangement is optimistic for the product
  surface, though the API risk is now much lower than the entry assumes.
- The batch transaction is not a neutral refactor — it trades the current
  per-display graceful degradation for atomicity (F6).

## What is still unknown

Not tested, and each would need its own check before relying on it:

- Whether `.permanently` origins survive a reboot
- Arrangement behaviour with mirrored displays, or with rotation
- A display disconnecting mid-transaction
- HiDPI/scaled modes combined with origin changes — F3 used a native
  `1280×720` mode (`pixelWidth == width`)
- Whether the applied arrangement survives sleep/wake unchanged

## Implementation plan

### Stage 1 — main display in a profile

Cheap not because it is one API call (it is not), but because it stores no
geometry: the origin plan is derived from live state at apply time, so relative
topology is preserved by leaving it alone.

- `Profile.mainDisplay: DisplayMatcher?` — one optional field; the existing
  decoder pattern (`decodeIfPresent`, as used for `matcher`) covers migration
- Extend `ResolutionSwitcher.applyBatch` with an optional origin plan that, when
  present, **must cover every active display**, and is dropped in full if it
  cannot (F1, F6)
- Build the plan at apply time: read live `CGDisplayBounds`, subtract the
  target's origin from all of them
- Verify after commit by re-reading `CGDisplayBounds`; do not trust the return
  code (F5)
- `RevertHistory.Entry` gains `beforeOrigin`, and the history gains the previous
  main display id
- UI: a single picker in the Save/Edit form, default "leave unchanged"

Guards: the matcher must resolve to exactly one active display, and every target
must be present in `CGGetActiveDisplayList` immediately before
`CGBeginDisplayConfiguration` (F7).

Estimate: 1.5–2 days including tests. The plan builder, renormalisation and
guard conditions are pure functions and fit the existing unit-test style; the CG
call itself does not and needs a manual multi-monitor check.

### Stage 2 — full arrangement (conditional)

Only if Stage 1 ships without reports of scattered windows. Remaining cost is
product, not API: stored geometry against a different resolution, `.anyExternal`
matchers with absolute origins, a saved monitor that is no longer connected, and
the Save/Edit UI. Capture-only — arrange in System Settings, snapshot in VibeRes.
No drag-and-drop editor.

### Do not

- Pair this with the mirror feature. Doubling the scope of a release that
  already carries an irreversible failure mode is a bad trade.
- Enable arrangement by default for existing profiles.

## Reproducing

Source: `scripts/display-arrangement-spike.swift`. It is not in any build target
— `project.yml` scopes sources to `VibeRes/`, `VibeRes/Core/`, `VibeResCLI/` and
`VibeResTests/`, and nothing in the Makefile or CI globs `.swift` — so it is
inert where it sits.

```
swiftc -O -o spike scripts/display-arrangement-spike.swift \
    -framework AppKit -framework CoreGraphics

./spike state                      # report displays, exit 1 if fewer than 2 active
./spike main                       # F1: partial origin change
./spike mainfull app               # F2: full renormalised arrangement
./spike combo norestore            # F3: mode + origins, .forAppOnly revert (F4)
./spike origin 1 500 300           # F5: success with a different result
./spike errors                     # F6: staging vs commit rejection
./spike setall 1:0:0 2:1074:-1080  # recovery hatch, .permanently
```

Requires at least two awake displays; a closed lid alone is enough to make the
spike abort (F7). Every mutating mode restores the previous arrangement and
verifies it; `setall` is there for the case where a run is interrupted before
the restore.
