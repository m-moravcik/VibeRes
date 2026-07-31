#!/usr/bin/env bash
#
# Build, sign, notarize and staple VibeRes.app, then package the *stapled*
# bundle as the release ZIP.
#
# This is deliberately a separate path from `make app`. The ad-hoc signed build
# stays the default for development and for CI runs that have no access to the
# Developer ID private key (pull requests from forks, for example). Only
# releases go through here.
#
# ---------------------------------------------------------------------------
# Required: a "Developer ID Application" certificate in the keychain.
#   Xcode -> Settings -> Accounts -> Manage Certificates -> + -> Developer ID
#   Application. Requires the Account Holder or Admin role on the team.
#
# Notarization credentials — supply exactly one of:
#
#   A) App Store Connect API key (what CI uses):
#        AC_API_KEY_PATH      path to the AuthKey_XXXXXXXX.p8 file
#        AC_API_KEY_ID        the key ID (the XXXXXXXX part)
#        AC_API_ISSUER_ID     the issuer UUID from App Store Connect
#
#   B) A stored notarytool keychain profile (convenient locally):
#        NOTARY_PROFILE       profile name, defaults to "viberes-notary"
#      Create it once with:
#        xcrun notarytool store-credentials viberes-notary \
#          --key ~/Downloads/AuthKey_XXXXXXXX.p8 \
#          --key-id XXXXXXXX --issuer <issuer-uuid>
#
# Optional environment:
#   DEVELOPMENT_TEAM   Team ID. Auto-derived from the certificate when unset.
#   SIGN_IDENTITY      Defaults to "Developer ID Application", which codesign
#                      resolves against the keychain. Set the full name or the
#                      SHA-1 hash when more than one such certificate exists.
#   SKIP_NOTARIZE=1    Sign and verify only — no Apple round-trip. Use this to
#                      confirm the certificate works before burning a
#                      submission.
#   OUTPUT_DIR         Where the ZIP lands. Defaults to ./artifacts.
#   DERIVED_DATA       Build directory. Defaults to ./build.
#
# Signing requires network access: --timestamp contacts Apple's timestamp
# authority, and a signature without a secure timestamp fails notarization.
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Local convenience: keep the non-secret notarization identifiers (key path,
# key ID, issuer ID) in a gitignored file so `make signed-app` needs no
# ceremony. CI sets the same variables from secrets instead, so both paths run
# identical code. Values already in the environment win.
if [ -f "$REPO_ROOT/.release.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.release.env"
  set +a
fi

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-viberes-notary}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/artifacts}"
# Apple's notary service is usually under five minutes but has no SLA; queues of
# an hour do happen. Wait long rather than fail a release on their backlog.
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-90m}"
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/build}"
BUNDLE_ID="sk.moravcik.VibeRes"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Preflight — fail before spending a build on a broken configuration.
# ---------------------------------------------------------------------------
step "Preflight"

command -v xcodegen >/dev/null || die "xcodegen not found. brew install xcodegen"

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
[ -n "$VERSION" ] || die "could not read MARKETING_VERSION from project.yml"
echo "Version: $VERSION"

# Resolve the signing certificate up front. An ambiguous identity makes
# xcodebuild fail deep inside the build log, which is a miserable place to
# discover you have two certificates installed.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
MATCHES="$(printf '%s\n' "$IDENTITIES" | grep -c "Developer ID Application" || true)"
if [ "$MATCHES" -eq 0 ]; then
  printf '%s\n' "$IDENTITIES" >&2
  die "no 'Developer ID Application' certificate in the keychain.
  Create one: Xcode -> Settings -> Accounts -> Manage Certificates -> + ->
  Developer ID Application."
fi
if [ "$MATCHES" -gt 1 ] && [ "$SIGN_IDENTITY" = "Developer ID Application" ]; then
  printf '%s\n' "$IDENTITIES" >&2
  die "$MATCHES Developer ID Application certificates found — the identity is
  ambiguous. Set SIGN_IDENTITY to the full name or SHA-1 hash from the list above."
fi

CERT_LINE="$(printf '%s\n' "$IDENTITIES" | grep "Developer ID Application" | head -1)"
echo "Certificate: ${CERT_LINE#*\"}"

# The Team ID is the parenthesised suffix of the certificate common name, e.g.
# "Developer ID Application: Michal Moravcik (ABCDE12345)". Deriving it removes
# one thing to configure (and one thing to get wrong) in CI.
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  DEVELOPMENT_TEAM="$(printf '%s\n' "$CERT_LINE" \
    | sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p')"
  [ -n "$DEVELOPMENT_TEAM" ] || die "could not derive Team ID from the certificate name.
  Set DEVELOPMENT_TEAM explicitly (10 characters, from developer.apple.com -> Membership)."
  echo "Team ID (derived): $DEVELOPMENT_TEAM"
else
  echo "Team ID: $DEVELOPMENT_TEAM"
fi

# Decide how we will talk to the notary service, before building.
NOTARY_ARGS=()
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "Notarization: SKIPPED (SKIP_NOTARIZE=1)"
elif [ -n "${AC_API_KEY_PATH:-}" ]; then
  [ -f "$AC_API_KEY_PATH" ] || die "AC_API_KEY_PATH does not exist: $AC_API_KEY_PATH"
  [ -n "${AC_API_KEY_ID:-}" ] || die "AC_API_KEY_PATH is set but AC_API_KEY_ID is not"
  [ -n "${AC_API_ISSUER_ID:-}" ] || die "AC_API_KEY_PATH is set but AC_API_ISSUER_ID is not"
  NOTARY_ARGS=(--key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID")
  echo "Notarization: App Store Connect API key ($AC_API_KEY_ID)"
else
  # Fallback only. store-credentials cannot reliably *overwrite* an existing
  # profile from a non-interactive shell — the keychain ACL prompt has nobody
  # to answer it, so the old item is removed, the new one is never written, and
  # the command still exits 0. Prefer AC_API_KEY_PATH.
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "no usable notarization credentials.
  Preferred: put AC_API_KEY_PATH / AC_API_KEY_ID / AC_API_ISSUER_ID in
  .release.env (see that file for the format).
  Alternatively store a keychain profile — interactively, in Terminal:
    xcrun notarytool store-credentials $NOTARY_PROFILE \\
      --key AuthKey_XXXXXXXX.p8 --key-id XXXXXXXX --issuer <issuer-uuid>"
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  echo "Notarization: keychain profile '$NOTARY_PROFILE'"
fi

# ---------------------------------------------------------------------------
# 2. Build with the real identity.
#
# Signing during the build rather than re-signing afterwards means the
# signature can never go stale relative to the binary. --timestamp and the
# hardened runtime (ENABLE_HARDENED_RUNTIME in project.yml) are both hard
# requirements for notarization.
#
# CODE_SIGN_STYLE=Manual with no provisioning profile is correct here: a
# Developer ID app that claims no restricted entitlements does not need one.
# ---------------------------------------------------------------------------
step "Build (Release, Developer ID)"

xcodegen generate

BUILD_ARGS=(
  -project VibeRes.xcodeproj
  -scheme VibeRes
  -configuration Release
  -destination 'platform=macOS'
  -derivedDataPath "$DERIVED_DATA"
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
  PROVISIONING_PROFILE_SPECIFIER=""
  CODE_SIGNING_REQUIRED=YES
  CODE_SIGNING_ALLOWED=YES
  ENABLE_HARDENED_RUNTIME=YES
  OTHER_CODE_SIGN_FLAGS="--timestamp"
  # Both of these are also pinned in project.yml's Release config. They are
  # repeated here so a release can never be instrumented or carry debug
  # entitlements even if the spec drifts: coverage instrumentation pulls in
  # com.apple.security.get-task-allow, and notarization rejects that outright.
  ENABLE_CODE_COVERAGE=NO
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
)

if command -v xcbeautify >/dev/null; then
  BEAUTIFY=(xcbeautify)
  # Surface build failures as GitHub annotations when running in Actions.
  [ -n "${GITHUB_ACTIONS:-}" ] && BEAUTIFY+=(--renderer github-actions)
  xcodebuild "${BUILD_ARGS[@]}" clean build | "${BEAUTIFY[@]}"
else
  xcodebuild "${BUILD_ARGS[@]}" clean build
fi

APP="$DERIVED_DATA/Build/Products/Release/VibeRes.app"
[ -d "$APP" ] || die "build reported success but $APP does not exist"

# ---------------------------------------------------------------------------
# 3. Verify the signature locally. Catching a bad signature here costs seconds;
#    catching it via a rejected notarization costs minutes.
# ---------------------------------------------------------------------------
step "Verify signature"

codesign --verify --deep --strict --verbose=2 "$APP" \
  || die "codesign verification failed"

# Confirm the three properties notarization actually checks for. Grepping the
# human-readable output is ugly but it is the only place codesign reports the
# runtime flag and the timestamp together.
SIG_INFO="$(codesign --display --verbose=4 "$APP" 2>&1)"
printf '%s\n' "$SIG_INFO" | grep -q "flags=.*runtime" \
  || die "hardened runtime is not enabled on the signed bundle"
printf '%s\n' "$SIG_INFO" | grep -q "^Timestamp=" \
  || die "signature has no secure timestamp — notarization would reject it"
printf '%s\n' "$SIG_INFO" | grep -q "^TeamIdentifier=$DEVELOPMENT_TEAM" \
  || die "signed with an unexpected team: $(printf '%s\n' "$SIG_INFO" | grep '^TeamIdentifier=')"
printf '%s\n' "$SIG_INFO" | grep -E "^(Authority|TeamIdentifier|Timestamp)=" | head -5
echo "Hardened runtime + secure timestamp + team: OK"

# Debug entitlements are a hard notarization rejection, and the failure arrives
# minutes later from Apple with no local trace. Check here instead.
# get-task-allow lets a debugger attach to the signed app and read its memory;
# it is injected by coverage-instrumented and development-signed builds.
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
for forbidden in \
  com.apple.security.get-task-allow \
  com.apple.security.cs.disable-library-validation \
  com.apple.security.cs.allow-dyld-environment-variables
do
  if printf '%s' "$ENTS" | grep -q "$forbidden"; then
    printf '%s' "$ENTS" | plutil -p - >&2 2>/dev/null || printf '%s\n' "$ENTS" >&2
    die "the signed bundle requests '$forbidden'.
  Notarization rejects this. Check ENABLE_CODE_COVERAGE and
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS for the Release configuration."
  fi
done
echo "Entitlements: no debug/relaxation entitlements present"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  step "Done (signed, not notarized)"
  echo "App: $APP"
  echo "Re-run without SKIP_NOTARIZE=1 to notarize and package."
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Notarize.
#
# notarytool takes a ZIP (or DMG/PKG) for submission, but the ticket is stapled
# to the .app — a ZIP cannot hold one. Hence: zip for submission, staple the
# app, then zip *again* for distribution. Shipping the submission ZIP is the
# classic mistake; it is byte-identical to an un-stapled build and users behind
# a captive portal get a Gatekeeper error.
#
# ditto, not zip: it preserves symlinks and resource forks inside the bundle,
# which /usr/bin/zip mangles.
# ---------------------------------------------------------------------------
step "Notarize"

mkdir -p "$OUTPUT_DIR"
SUBMIT_ZIP="$DERIVED_DATA/VibeRes-submit.zip"
rm -f "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
[ -f "$SUBMIT_ZIP" ] || die "failed to create submission archive"

set +e
SUBMIT_JSON="$(xcrun notarytool submit "$SUBMIT_ZIP" \
  "${NOTARY_ARGS[@]}" --wait --timeout "$NOTARY_TIMEOUT" --output-format json 2>&1)"
SUBMIT_RC=$?
set -e
printf '%s\n' "$SUBMIT_JSON"

SUBMISSION_ID="$(printf '%s' "$SUBMIT_JSON" \
  | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | cut -d'"' -f4)"

# notarytool exits 0 for a *completed* submission even when the verdict is
# Invalid — the exit code reports whether the round-trip worked, not whether
# Apple accepted the bundle. Both have to be checked, or a rejected build
# sails through to stapling and fails there with an unrelated CloudKit error.
SUBMIT_STATUS="$(printf '%s' "$SUBMIT_JSON" \
  | grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | cut -d'"' -f4)"

if [ "$SUBMIT_RC" -ne 0 ] || [ "$SUBMIT_STATUS" != "Accepted" ]; then
  if [ -n "$SUBMISSION_ID" ]; then
    echo
    echo "--- notarization log for $SUBMISSION_ID ---" >&2
    xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_ARGS[@]}" >&2 || true
  fi
  die "notarization was not accepted (status=${SUBMIT_STATUS:-unknown}, exit $SUBMIT_RC)"
fi
[ -n "$SUBMISSION_ID" ] || die "notarytool succeeded but returned no submission id"
echo "Status: $SUBMIT_STATUS ($SUBMISSION_ID)"

# ---------------------------------------------------------------------------
# 5. Staple and package.
# ---------------------------------------------------------------------------
step "Staple"

xcrun stapler staple "$APP" || die "stapling failed"
xcrun stapler validate "$APP" || die "stapler validate failed after stapling"

# The real end-to-end check: this is what Gatekeeper does when the user
# double-clicks a freshly downloaded app.
spctl --assess --type exec --verbose=4 "$APP" || die "Gatekeeper assessment failed"

step "Package"

FINAL_ZIP="$OUTPUT_DIR/VibeRes-$VERSION.zip"
rm -f "$FINAL_ZIP"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"
[ -f "$FINAL_ZIP" ] || die "failed to create $FINAL_ZIP"

SHA="$(shasum -a 256 "$FINAL_ZIP" | awk '{print $1}')"

step "Done"
printf 'Artifact : %s\n' "$FINAL_ZIP"
printf 'Size     : %s\n' "$(du -h "$FINAL_ZIP" | awk '{print $1}')"
printf 'SHA256   : %s\n' "$SHA"
printf 'Submission: %s\n' "$SUBMISSION_ID"

# Expose values to GitHub Actions when running there, so release.yml does not
# have to recompute them.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "zip=$FINAL_ZIP"
    echo "sha256=$SHA"
    echo "version=$VERSION"
  } >> "$GITHUB_OUTPUT"
fi
