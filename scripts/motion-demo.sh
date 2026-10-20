#!/bin/bash
# Render the README hero animation from the app itself and encode it.
# See VibeRes/Preview/MotionDemo.swift.
#
#   scripts/motion-demo.sh [output-dir]     # default build/motion
#
# Writes, per appearance (light, then dark with a -dark suffix):
#   hero.gif     8 s seamless loop, 960 px wide, 30 fps
#   hero.mp4     the same take, H.264 yuv420p, faststart
#   poster.png   the first frame
#   _sheet.png   six key frames for review
# The frames come from this Mac's built-in display's list of sizes; nothing is
# switched (the harness rigs the apply path to abort), and live preview is
# forced off, so no desktop is captured.
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
    ffmpeg -v error -y -framerate $FPS -i "$frames" \
        -vf "scale=$WIDTH:-2:flags=lanczos" -c:v libx264 -preset slow -crf 20 \
        -pix_fmt yuv420p -movflags +faststart "$OUT/hero$suffix.mp4"
    ffmpeg -v error -y -i "$OUT/frames-$scheme/frame_0000.png" \
        -vf "scale=$WIDTH:-1:flags=lanczos" "$OUT/poster$suffix.png"
    # Rest, hover with preview, dark, icon fully grown, the way back, settled.
    ffmpeg -v error -y -framerate $FPS -i "$frames" \
        -vf "select='eq(n\,0)+eq(n\,30)+eq(n\,45)+eq(n\,70)+eq(n\,148)+eq(n\,200)',scale=480:-1:flags=lanczos,tile=3x2:padding=8:color=white" \
        -frames:v 1 -fps_mode vfr "$OUT/_sheet$suffix.png"
done

ls -l "$OUT"/hero* "$OUT"/poster* "$OUT"/_sheet*
