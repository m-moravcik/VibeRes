#!/bin/bash
# Render the README hero animation from the app itself and encode it.
# See VibeRes/Preview/MotionDemo.swift.
#
#   scripts/motion-demo.sh [output-dir]     # default build/motion
#
# Writes, per appearance (light, then dark with a -dark suffix):
#   hero.gif     8 s seamless loop, 960 px wide, 30 fps
# The intermediate PNG frames go to the Trash afterwards.
# The frames come from this Mac's built-in display's list of sizes, so the lid
# must be open and the screen awake. Nothing is switched (the harness rigs the
# apply path to abort), and live preview is forced off, so no desktop is
# captured.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-$PWD/build/motion}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
DERIVED="${VIBERES_MOTION_DERIVED:-build/motion-dd}"
APP="$DERIVED/Build/Products/Debug/VibeRes.app"
WIDTH=960
FPS=30

xcodegen generate >/dev/null
xcodebuild -project VibeRes.xcodeproj -scheme VibeRes -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -quiet build

# Stale frames from an earlier take would end up in the GIF.
for scheme in light dark; do
    if [ -d "$OUT/frames-$scheme" ]; then
        osascript -e "tell application \"Finder\" to delete POSIX file \"$OUT/frames-$scheme\"" >/dev/null
    fi
done

# Preferences come from launch arguments (argument domain, nothing written).
VIBERES_MOTION_DEMO="$OUT" "$APP/Contents/MacOS/VibeRes" \
    -AppleLanguages "(en)" \
    -VibeRes.OnboardingShown YES \
    -VibeRes.SimpleMode YES \
    -VibeRes.LivePreviewEnabled NO \
    -VibeRes.LivePreviewHintDismissed YES \
    -VibeRes.ConfirmDisplayChanges NO

for scheme in light dark; do
    frames="$OUT/frames-$scheme/frame_%04d.png"
    suffix=""; [ "$scheme" = dark ] && suffix="-dark"
    palette="$OUT/frames-$scheme/palette.png"

    ffmpeg -v error -y -framerate $FPS -i "$frames" \
        -vf "scale=$WIDTH:-1:flags=lanczos,palettegen=stats_mode=diff" "$palette"
    ffmpeg -v error -y -framerate $FPS -i "$frames" -i "$palette" \
        -lavfi "scale=$WIDTH:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
        -loop 0 "$OUT/hero$suffix.gif"
done

# The frames are ~350 MB per appearance; keep them with VIBERES_MOTION_KEEP_FRAMES=1.
if [ "${VIBERES_MOTION_KEEP_FRAMES:-0}" != 1 ]; then
    for scheme in light dark; do
        osascript -e "tell application \"Finder\" to delete POSIX file \"$OUT/frames-$scheme\"" >/dev/null
    done
fi

ls -l "$OUT"/hero*.gif
