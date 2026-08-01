#!/usr/bin/env bash
#
# Builds and signs the Sparkle appcast for a release.
#
# The feed lives at a stable path in the repo — `appcast.xml` on `main`, served
# by raw.githubusercontent.com — rather than as a release asset. A
# `releases/latest/download/appcast.xml` URL 404s for *every* client, permanently,
# the moment one release is published without that asset attached, and no
# per-release check can prevent a future release from omitting it.
#
# Usage: scripts/make-appcast.sh <notarized-zip> [output]
#
# Environment:
#   SPARKLE_EDDSA_PRIVATE_KEY_PATH  file holding the base64 Ed25519 seed.
#                                   Falls back to the keychain if unset, which
#                                   only works interactively.
#   DERIVED_DATA                    where SwiftPM put Sparkle's tools.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ZIP="${1:?usage: make-appcast.sh <notarized-zip> [output]}"
OUT="${2:-$REPO_ROOT/appcast.xml}"
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/build}"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$ZIP" ] || die "no such archive: $ZIP"

# Sparkle ships its tools inside the SwiftPM artifact bundle, so there is no
# separate download to pin or checksum. Homebrew is not an option: the `sparkle`
# cask is deprecated for failing Gatekeeper and is disabled from 2026-09-01.
SIGN_UPDATE="$(find "$DERIVED_DATA/SourcePackages/artifacts" -name sign_update -type f -perm +111 2>/dev/null | head -1)"
[ -n "$SIGN_UPDATE" ] || die "sign_update not found under $DERIVED_DATA — build the app first"

SIGN_ARGS=()
if [ -n "${SPARKLE_EDDSA_PRIVATE_KEY_PATH:-}" ]; then
  [ -f "$SPARKLE_EDDSA_PRIVATE_KEY_PATH" ] || die "key file missing: $SPARKLE_EDDSA_PRIVATE_KEY_PATH"
  SIGN_ARGS=(-f "$SPARKLE_EDDSA_PRIVATE_KEY_PATH")
fi

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
BUILD="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)"
MIN_OS="$(awk -F'"' '/MACOSX_DEPLOYMENT_TARGET:/ {print $2; exit}' project.yml)"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || die "could not read version numbers from project.yml"

# Sparkle compares sparkle:version, which is CFBundleVersion — the build number,
# not the marketing version. Getting this wrong makes every client see "no
# update" with nothing logged anywhere.
LENGTH="$(stat -f%z "$ZIP")"
SIGNATURE="$("$SIGN_UPDATE" "${SIGN_ARGS[@]}" -p "$ZIP")" || die "sign_update failed"
[ -n "$SIGNATURE" ] || die "sign_update produced no signature"

# Release notes: the matching CHANGELOG section, as HTML so Sparkle renders
# bullets rather than raw markdown.
NOTES="$(awk -v ver="## [$VERSION]" '
  index($0, ver) == 1 { found=1; next }
  found && /^## \[/ { exit }
  found { print }
' CHANGELOG.md)"

HTML="$(printf '%s\n' "$NOTES" | python3 -c '
import html, re, sys

# Markdown wraps at 80 columns, so a bullet or paragraph usually spans several
# lines. Join continuations first, or every wrapped line becomes its own
# paragraph and sentences read as if they were cut in half.
blocks, current = [], None
for line in sys.stdin.read().splitlines():
    stripped = line.strip()
    if not stripped:
        if current: blocks.append(current); current = None
        continue
    if stripped.startswith(("- ", "### ", "## ", "> ")):
        if current: blocks.append(current)
        current = stripped
    elif current is not None:
        current += " " + stripped
    else:
        current = stripped
if current: blocks.append(current)

def inline(text):
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return text

out, in_list = [], False
for block in blocks:
    if block.startswith("### ") or block.startswith("## "):
        if in_list: out.append("</ul>"); in_list = False
        out.append("<h3>" + inline(block.lstrip("# ").strip()) + "</h3>")
    elif block.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        out.append("<li>" + inline(block[2:]) + "</li>")
    else:
        if in_list: out.append("</ul>"); in_list = False
        out.append("<p>" + inline(block.lstrip("> ")) + "</p>")
if in_list: out.append("</ul>")
print("\n".join(out))
')"

URL="https://github.com/m-moravcik/VibeRes/releases/download/v${VERSION}/VibeRes-${VERSION}.zip"
DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>VibeRes</title>
    <link>https://raw.githubusercontent.com/m-moravcik/VibeRes/main/appcast.xml</link>
    <description>Updates for VibeRes</description>
    <language>en</language>
    <item>
      <title>${VERSION}</title>
      <pubDate>${DATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
      <description><![CDATA[
${HTML}
      ]]></description>
      <enclosure url="${URL}"
                 sparkle:edSignature="${SIGNATURE}"
                 length="${LENGTH}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

# Sign the feed itself. Without this, someone able to substitute the feed cannot
# ship a malicious build — the enclosure signature stops that — but can pin every
# client to an older, validly signed release.
"$SIGN_UPDATE" "${SIGN_ARGS[@]}" --disable-signing-warning "$OUT" >/dev/null \
  || die "failed to sign the appcast feed"

grep -q 'sparkle:edSignature' "$OUT" || die "appcast has no enclosure signature"
echo "appcast: $OUT"
echo "  version ${VERSION} (build ${BUILD}), ${LENGTH} bytes"
echo "  feed signed; SURequireSignedFeed in Info.plist makes clients demand it"
