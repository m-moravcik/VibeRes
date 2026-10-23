#!/usr/bin/env bash
#
# Fails when the app emits a localisable string that Localizable.xcstrings does
# not carry, or when any catalog entry (Localizable.xcstrings and
# InfoPlist.xcstrings) lacks or leaves empty a translation in one of the six
# languages of the app family: en, sk, cs, de, es, fr.
#
# This lives in a script rather than a unit test because the input is a build
# artifact: the Swift compiler writes one `.stringsdata` per source file listing
# every literal it extracted. A unit test cannot reliably find those — they sit
# in whichever derived-data path the build happened to use.
#
# It exists because the catalog silently drifted 76 strings behind the UI while
# CHANGELOG.md advertised "full localisation (en/sk/de)". Nothing was watching.
#
# Usage: scripts/check-localisation.sh [derived-data-path]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DERIVED="${1:-$REPO_ROOT/build-localisation}"
CATALOG="VibeRes/Resources/Localizable.xcstrings"
INFOPLIST_CATALOG="VibeRes/Resources/InfoPlist.xcstrings"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$CATALOG" ] || die "no catalog at $CATALOG"
[ -f "$INFOPLIST_CATALOG" ] || die "no catalog at $INFOPLIST_CATALOG"

command -v xcodegen >/dev/null || die "xcodegen not found"
xcodegen generate >/dev/null

# A Debug build is enough; string extraction is not configuration-specific.
xcodebuild build \
  -project VibeRes.xcodeproj \
  -scheme VibeRes \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO >/dev/null

python3 - "$DERIVED" "$CATALOG" "$INFOPLIST_CATALOG" <<'PY'
import glob, json, re, sys

derived, catalog, infoplist_catalog = sys.argv[1], sys.argv[2], sys.argv[3]
LANGUAGES = ['en', 'sk', 'cs', 'de', 'es', 'fr']

emitted = set()
files = glob.glob(derived + '/**/*.stringsdata', recursive=True)
if not files:
    sys.exit("error: no .stringsdata produced — is SWIFT_EMIT_LOC_STRINGS still YES?")

for path in files:
    for entries in json.load(open(path)).get('tables', {}).values():
        for entry in entries:
            key = entry.get('key', '')
            if key.strip():
                emitted.add(key)

have = set(json.load(open(catalog))['strings'])
missing = sorted(emitted - have)

# Bare units, separators and format-only strings carry no words to translate.
ignorable = re.compile(r'^(Hz|%lld Hz|%lld|%@|·|—|✱|✱ flex)$')
missing = [k for k in missing if not ignorable.match(k)]

print(f"emitted {len(emitted)} keys, catalog has {len(have)}")
if missing:
    print(f"\nmissing from {catalog}:")
    for k in missing:
        print("  " + repr(k))
    sys.exit(f"\nerror: {len(missing)} localisable string(s) not in the catalog")


def leaves(localization):
    """Every translated string in one language: a plain string unit, each
    plural/device variation, and each substitution's variations."""
    if 'stringUnit' in localization:
        yield localization['stringUnit']
    for variation in localization.get('variations', {}).values():
        for branch in variation.values():
            yield from leaves(branch)
    for substitution in localization.get('substitutions', {}).values():
        yield from leaves(substitution)


# Every key needs a non-empty translation in every language. Being present in
# the catalog is not enough: a key with only some languages filled in would
# silently fall back to English for the rest.
incomplete = []
for path in (catalog, infoplist_catalog):
    strings = json.load(open(path))['strings']
    for key, entry in sorted(strings.items()):
        if ignorable.match(key):
            continue
        localizations = entry.get('localizations', {})
        for lang in LANGUAGES:
            found = list(leaves(localizations.get(lang, {})))
            if not found or any(not (u.get('value') or '').strip() for u in found):
                incomplete.append((path, key, lang))
            elif any(u.get('state') not in (None, 'translated') for u in found):
                incomplete.append((path, key, lang + ' (not marked translated)'))

if incomplete:
    print("\nmissing, empty or untranslated entries:")
    for path, key, lang in incomplete:
        print(f"  [{lang}] {key!r} in {path}")
    sys.exit(f"\nerror: {len(incomplete)} translation(s) missing across {', '.join(LANGUAGES)}")
print(f"all keys translated in {', '.join(LANGUAGES)}")
print("localisation coverage: OK")
PY
