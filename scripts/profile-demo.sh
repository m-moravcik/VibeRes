#!/bin/bash
# Render the README hero loop (a profile clicked in the popover) from the app
# itself and encode it. See VibeRes/Preview/ProfileDemo.swift.
#
#   scripts/profile-demo.sh [output-dir] [lang]   # default build/profile-demo/<lang>, en
#
# Writes, per appearance (light, then dark with a -dark suffix):
#   hero.gif      9.2 s seamless loop, 960 px wide, 30 fps, for the README
#   hero.mp4      the same from the frames, 1440 px wide, for a website
#   poster.jpg    the first frame, at the MP4's size
#   contact.png   eight key frames, to review before publishing
#   frames-light/ frames-dark/   the 3x PNG frames
#
# The display cards are this Mac's displays, and the loop needs two: the
# built-in (lid open, screen awake) and an external. Nothing is switched: the
# harness rigs the apply paths to a demo display list. The profiles are
# invented and live in a scratch directory; preferences come from launch
# arguments (argument domain, nothing written).
#
# VIBERES_PROFILE_DEMO_KEEP_MAIN=1 leaves the main display where it is.
set -euo pipefail
cd "$(dirname "$0")/.."

LANG_CODE="${2:-en}"
OUT="${1:-$PWD/build/profile-demo/$LANG_CODE}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
DERIVED="${VIBERES_PROFILE_DEMO_DERIVED:-build/profile-demo-dd}"
APP="$PWD/$DERIVED/Build/Products/Debug/VibeRes.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
GIF_WIDTH=960
MP4_WIDTH=1440
FPS=30
GIF_LIMIT=$((5 * 1024 * 1024))

trash() {
    if [ -e "$1" ]; then
        osascript -e "tell application \"Finder\" to delete POSIX file \"$1\"" >/dev/null
    fi
}

xcodegen generate >/dev/null
xcodebuild -project VibeRes.xcodeproj -scheme VibeRes -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO -quiet build
# The build registers the Debug app with LaunchServices; take it back out
# whatever happens next, and let the display sleep again.
CAFFEINATE=""
cleanup() {
    "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" >/dev/null 2>&1 || true
    if [ -n "$CAFFEINATE" ]; then kill "$CAFFEINATE" 2>/dev/null || true; fi
}
trap cleanup EXIT

# Stale frames from an earlier take would end up in the loop.
for scheme in light dark; do
    trash "$OUT/frames-$scheme"
done

# The frames come from the popover while it animates, so the built-in display
# must stay awake for the whole take.
caffeinate -u -d -t 300 &
CAFFEINATE=$!
disown "$CAFFEINATE"
VIBERES_PROFILE_DEMO="$OUT" "$APP/Contents/MacOS/VibeRes" \
    -AppleLanguages "($LANG_CODE)" \
    -VibeRes.OnboardingShown YES \
    -VibeRes.SimpleMode YES \
    -VibeRes.LivePreviewEnabled NO \
    -VibeRes.LivePreviewHintDismissed YES \
    -VibeRes.ConfirmDisplayChanges NO \
    -VibeRes.AutoApplyOnDisplayChange NO

for scheme in light dark; do
    dir="$OUT/frames-$scheme"
    suffix=""; [ "$scheme" = dark ] && suffix="-dark"

    # Seam: the harness renders one frame past the end of the loop, which
    # must equal the first ("inf" is identical). It then leaves the frames,
    # so the loop does not hold on a duplicate.
    last=$(ls "$dir" | grep -c '^frame_')
    seam=$(printf "%s/frame_%04d.png" "$dir" $((last - 1)))
    echo "$scheme seam: $(ffmpeg -v info -i "$dir/frame_0000.png" -i "$seam" -lavfi psnr -f null - 2>&1 \
        | grep -o 'average:[^ ]*')"
    trash "$OUT/seam$suffix.png"
    mv "$seam" "$OUT/seam$suffix.png"

    frames="$dir/frame_%04d.png"
    palette="$OUT/palette$suffix.png"
    ffmpeg -v error -y -framerate $FPS -i "$frames" \
        -vf "scale=$GIF_WIDTH:-1:flags=lanczos,palettegen=stats_mode=diff" "$palette"
    ffmpeg -v error -y -framerate $FPS -i "$frames" -i "$palette" \
        -lavfi "scale=$GIF_WIDTH:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
        -loop 0 "$OUT/hero$suffix.gif"
    trash "$palette"

    ffmpeg -v error -y -framerate $FPS -i "$frames" \
        -vf "scale=$MP4_WIDTH:-2:flags=lanczos,format=yuv420p" \
        -c:v libx264 -preset veryslow -tune animation -crf 20 -movflags +faststart -an "$OUT/hero$suffix.mp4"
    ffmpeg -v error -y -i "$dir/frame_0000.png" -vf "scale=$MP4_WIDTH:-2:flags=lanczos" -q:v 2 \
        "$OUT/poster$suffix.jpg"

    # Key frames at the GIF's width: the start, the press on B, the note
    # dropping in, the checkmark's bounce, the icon's window springing out,
    # B settled, the press on A, A back.
    ffmpeg -v error -y -framerate $FPS -i "$frames" \
        -vf "select='eq(n\,0)+eq(n\,42)+eq(n\,58)+eq(n\,63)+eq(n\,70)+eq(n\,110)+eq(n\,180)+eq(n\,206)',scale=$GIF_WIDTH:-1:flags=lanczos,tile=4x2" \
        -frames:v 1 "$OUT/contact$suffix.png"

    size=$(stat -f %z "$OUT/hero$suffix.gif")
    if [ "$size" -gt "$GIF_LIMIT" ]; then
        echo "hero$suffix.gif is $size bytes, over the 5 MB README budget" >&2
        exit 1
    fi
done

ls -l "$OUT"/hero*.gif "$OUT"/hero*.mp4 "$OUT"/poster*.jpg "$OUT"/contact*.png
