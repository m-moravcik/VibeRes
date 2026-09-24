#!/bin/bash
# Render the README screenshots, the app icon and the portfolio banner from the
# app itself. See VibeRes/Preview/ScreenshotHarness.swift.
#
#   scripts/screenshots.sh        # English, into build/screenshots/en
#   scripts/screenshots.sh sk     # Slovak, for the web.pexelo portfolio
#
# Writes root, detail, save, revert, hero (popover under the menu bar, README) and
# banner (1920x1080) in -light and -dark, plus icon.png. The displays are this
# Mac's; the profiles are invented. Copy what you need into docs/screenshots.
#
# The preferences are passed as launch arguments. UserDefaults serves those
# from the argument domain and writes nothing, so the result does not depend on
# whatever the Debug build (sk.moravcik.VibeRes.debug) last had set.
set -euo pipefail
cd "$(dirname "$0")/.."

LANG_CODE="${1:-en}"
OUT="$PWD/build/screenshots/$LANG_CODE"
DERIVED="build/screenshots-dd"
APP="$DERIVED/Build/Products/Debug/VibeRes.app"

xcodegen generate >/dev/null
xcodebuild -project VibeRes.xcodeproj -scheme VibeRes -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -quiet build

VIBERES_SCREENSHOTS="$OUT" "$APP/Contents/MacOS/VibeRes" \
    -AppleLanguages "($LANG_CODE)" \
    -VibeRes.OnboardingShown YES \
    -VibeRes.SimpleMode NO \
    -VibeRes.LivePreviewEnabled NO \
    -VibeRes.LivePreviewHintDismissed YES \
    -VibeRes.ConfirmDisplayChanges NO
