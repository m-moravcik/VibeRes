# Vision

`VibeRes` exists so that changing what a Mac's displays show takes about three seconds and never leaves the user stuck.
It serves the person at the Mac who changes resolution more than once a month: a laptop that docks to a desk, a presenter on whatever projector the room has, someone who wants 120 Hz for scrolling and native pixels for pixel work.
It turns a click, a profile, a keyboard shortcut, a CLI line or a Shortcuts action into the display mode asked for, and says what actually happened.
It owns exactly one thing: the mode of each connected display, meaning its size, refresh rate, scaling, and which display is main.

## The popover is the product

Every feature makes the three-second interaction shorter or safer, or lets it happen without opening the popover.
Confirmations, errors and forms live inline in the popover; a separate window, alert or modal needs a stated reason.
Saving and editing a profile stay in the popover, where the setup being saved is in view; Settings may offer roomier editing alongside, never instead.
The popover keeps its controls under the pointer while it changes state: no step, message or note moves the thing the user is about to click.
The menu bar carries the drawn glyph only; the current mode is one click away, not text competing for menu bar space.
Motion has a job (confirm, locate, show progress, connect two states), uses the `Design.Motion` vocabulary, and becomes a crossfade or the end state under Reduce Motion.

## Never strand the user

A resolution change can make the screen unreadable, so every risky path has a way back that needs no sight: Revert, ⌘Z, the Revert shortcut, the confirmation timeout.
The confirmation timeout is on by default, so a black screen undoes itself even for someone who never opened Settings.
It guards a size picked by hand; a profile, a shortcut or auto-apply applies modes the user saved after seeing them work, and arms no countdown.
A newer action never lets an older safety net act on it, and a safety net is never dropped by an action that changed nothing.
Anything that claims a permission, a key combination or system-wide behaviour is off until the user turns it on.
Bringing back windows a mode change left off-screen belongs here too, as an opt-in that asks for the Accessibility permission only when it is switched on.
Auto-apply is the one automatic behaviour on by default, because a profile that waits for a click when its monitor connects defeats its purpose; it stays narrow instead: an exact match of the connected displays only, and a flexible profile never takes a monitor another profile names.

## Say what actually happened

A fallback rate, a skipped display, an arrangement macOS adjusted, or a shortcut that could not register is reported, never hidden.
A successful API call is not evidence: the result is read back from the system before it is reported as done.
Hardware that cannot be told apart is named as such rather than guessed between.
Every user-facing string ships in English, Slovak, Czech, German, Spanish and French, and accent text meets WCAG AA contrast.

## One core, every surface

The app, the `viberes` CLI and the App Intents share one Core and one binding of profiles to displays, so a profile does the same thing from every entry point.
A shortcut or script applies like the CLI: no confirmation, a clear outcome, and Revert takes it back.
Profiles live in a readable JSON file; a field the app cannot read is dropped, never the whole catalog, and files from older versions keep working.

## Native, private and small

VibeRes is built from the platform: SwiftUI, CoreGraphics, SF Symbols, App Intents and Carbon hotkeys.
It has one third-party dependency, Sparkle, pinned and watched; a feature VibeRes already does well is never swapped for a library, and a second dependency needs an explicit decision.
It sends nothing anywhere, not even opt-in telemetry: the update check is the only automatic network request.
Diagnostics leave the Mac only when the user sends them, for example as a prefilled bug report the user reads before submitting.
A private API is used only when it is the sole way to show what System Settings shows, behind a fallback that keeps the previous behaviour.
It is free and open source, with no paid tier, licence check or account.

## Scope

VibeRes is not a display configuration manager: brightness, DDC, colour profiles, rotation and virtual displays belong to tools like BetterDisplay.
HDR is the one colour setting in reach, as an advanced control that Simple mode keeps out of sight.
A profile saved with HDR restores it in Simple mode too: Simple mode hides the control, not the effect, and the outcome still says HDR changed.
It does not switch modes on triggers other than the display set, such as the app in front or the time of day; that automation belongs to Shortcuts through the App Intents.
It has no admin role, managed settings or fleet features; the person at the Mac decides.
It stores no window or display geometry beyond which display is main.
It is not on the Mac App Store, because the sandbox forbids listing every mode System Settings lists.
Mirroring is the one planned expansion, as its own release after 1.0.

A change aligns when it shortens or secures the click-to-mode path, reports its outcome honestly in all six languages, behaves the same from the popover, CLI, shortcuts and Shortcuts, and needs nothing new to permit or install.
A change should be resisted when it adds a control beyond display modes, turns on something intrusive by default, sends data off the Mac without the user sending it, adds a dependency or permission for convenience, moves the core loop out of the popover, or lets any path leave the user with an unreadable screen and no way back.
