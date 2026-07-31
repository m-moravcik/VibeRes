# Release process

VibeRes ships releases automatically through the
[`release.yml`](workflows/release.yml) workflow. A tag push (`vX.Y.Z`) drives
end-to-end publication.

Releases are **signed with a Developer ID certificate and notarized by Apple**.
Without that, macOS quarantines the downloaded ZIP and users get "VibeRes is
damaged and can't be opened" — the Gatekeeper error that actually means
"unsigned". See [Signing and notarization](#signing-and-notarization-one-time-setup)
below for the one-time setup.

## Prerequisites (one-time setup)

To enable cross-repo sync of the Homebrew formula + cask, the workflow needs
a Personal Access Token with write access to
[`m-moravcik/homebrew-viberes`](https://github.com/m-moravcik/homebrew-viberes).

1. Create a [fine-grained PAT](https://github.com/settings/tokens?type=beta).
   - **Repository access**: only `m-moravcik/homebrew-viberes`.
   - **Permissions**: `Contents: Read and write`.
   - **Expiration**: anything reasonable. The action runs ~once per release;
     a 1-year token is fine.
2. Save the PAT as a repo secret on `m-moravcik/VibeRes`:
   - Settings → Secrets and variables → Actions → **New repository secret**.
   - Name: `TAP_PUSH_TOKEN`.
   - Value: the PAT.

If the secret is missing, the release itself still publishes — only the tap
sync step is skipped (with `continue-on-error: true`). You'd then run the
sync manually.

## Signing and notarization (one-time setup)

Two independent things, both required:

- **Code signing** with a *Developer ID Application* certificate proves the
  bundle came from this team and hasn't been modified since.
- **Notarization** uploads the signed bundle to Apple, which scans it and
  issues a *ticket*. `stapler` embeds that ticket into the bundle so Gatekeeper
  can verify it without network access.

Signing alone is not enough on macOS 10.15+: an app that is signed but not
notarized still gets blocked on first launch.

### 1. Developer ID Application certificate

Requires the **Account Holder** or **Admin** role on the Apple Developer team.

1. Xcode → Settings → Accounts → select the account → **Manage Certificates**.
2. `+` → **Developer ID Application**.
3. Verify it landed in the keychain:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
   The Team ID is the 10-character string in parentheses at the end of the
   certificate name. `scripts/release-signed.sh` reads it from there, so it is
   not configured anywhere.

You do **not** need *Developer ID Installer* (that signs `.pkg` files) or a
provisioning profile (VibeRes claims no restricted entitlements).

Apple allows a limited number of Developer ID certificates per account, and
the private key exists only on the Mac that created it. **Back up the `.p12`
export from step 3 somewhere safe** — losing it means revoking and reissuing.

### 2. App Store Connect API key for notarytool

An API key is preferable to an Apple ID + app-specific password: it is scoped,
revocable, and does not carry your account credentials into CI.

1. [App Store Connect](https://appstoreconnect.apple.com) → Users and Access →
   Integrations → **App Store Connect API** → Team Keys → `+`.
2. Role: **Developer** is sufficient for notarization.
3. Download the `AuthKey_XXXXXXXX.p8`. **It can only be downloaded once.**
4. Note the **Key ID** (in the row) and the **Issuer ID** (above the table).

Store it locally as a notarytool keychain profile so you never have to pass the
file around:

```bash
xcrun notarytool store-credentials viberes-notary \
  --key ~/path/to/AuthKey_XXXXXXXX.p8 \
  --key-id XXXXXXXX \
  --issuer 12345678-90ab-cdef-1234-567890abcdef
```

### 3. Verify locally before touching CI

Signing-only dry run — no Apple round-trip, fails fast if the certificate is
wrong:

```bash
make signed-app-dry
```

Then the real thing (build → sign → notarize → staple → ZIP into `artifacts/`):

```bash
make signed-app
```

The script fails loudly if the hardened runtime flag, the secure timestamp, or
the Team ID is missing from the resulting signature, and it dumps the Apple
notarization log automatically when a submission is rejected.

Sanity-check the artifact the way a user's Mac would:

```bash
xcrun stapler validate build/Build/Products/Release/VibeRes.app
spctl --assess --type exec --verbose=4 build/Build/Products/Release/VibeRes.app
```

### 4. GitHub Actions secrets

Export the signing identity as a `.p12` first — Keychain Access → My
Certificates → right-click *Developer ID Application: …* → **Export** →
`.p12`, set a password. Then:

```bash
base64 -i DeveloperID.p12          | pbcopy   # -> MACOS_CERT_P12_BASE64
base64 -i AuthKey_XXXXXXXX.p8      | pbcopy   # -> AC_API_KEY_P8_BASE64
```

Settings → Secrets and variables → Actions → New repository secret, six of
them:

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | base64 of the exported `.p12` |
| `MACOS_CERT_PASSWORD` | password you set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | any random string; secures the throwaway keychain |
| `AC_API_KEY_P8_BASE64` | base64 of the `AuthKey_XXXXXXXX.p8` |
| `AC_API_KEY_ID` | the key's ID |
| `AC_API_ISSUER_ID` | issuer UUID from App Store Connect |

`base64` on macOS emits a single line, which is what the workflow expects. If
you produce the value some other way, make sure it has no wrapped newlines.

The workflow imports the certificate into a keychain scoped to that run only
and deletes both the keychain and the `.p8` in an `if: always()` step, so a
failed build does not leave the private key on the runner.

The release will **fail** rather than silently publish an unsigned build if any
of these secrets is missing.

### What is not signed

`Formula/viberes.rb` builds the `viberes` CLI from source on the user's own
machine, so it needs no notarization. If the CLI is ever shipped as a
pre-built binary, it needs its own Developer ID signature — and
`ENABLE_HARDENED_RUNTIME` is currently `NO` for that target in `project.yml`.

## Cutting a release

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml`.
2. Bump `version` and `tag:` in `Formula/viberes.rb`.
3. Add a new section in `CHANGELOG.md` titled `## [X.Y.Z] — YYYY-MM-DD` with
   the user-visible changes.
4. Commit and push to `main`.
5. Tag and push:
   ```bash
   git tag vX.Y.Z
   git push --tags
   ```
6. Watch [Actions](https://github.com/m-moravcik/VibeRes/actions). The
   `Release` workflow will:
   - Verify the tag matches `MARKETING_VERSION`.
   - Run the test suite.
   - Import the Developer ID certificate into a run-scoped keychain.
   - Build, sign, **notarize** and **staple** VibeRes.app, then package the
     stapled bundle as `VibeRes-X.Y.Z.zip` and compute its SHA256
     (`scripts/release-signed.sh`).
   - Extract the matching `## [X.Y.Z]` section from `CHANGELOG.md` as release
     notes.
   - Create the GitHub Release with the ZIP attached.
   - Update `Formula/viberes.rb` and `Casks/viberes-app.rb` in the tap, then
     commit and push.

If something fails midway, fix the cause and re-run via Actions →
**Release** → **Run workflow** with the tag name as input. Notarization is
idempotent — resubmitting the same bundle is fine.

## Manual fallback (no Action)

```bash
# 1. Build + sign + notarize + staple + ZIP into ./artifacts
#    Prints the SHA256 you need for the cask.
make signed-app

# 2. Tag + GitHub Release
git tag "v${VERSION}" && git push --tags
gh release create "v${VERSION}" "artifacts/VibeRes-${VERSION}.zip" \
  --title "VibeRes ${VERSION}" --notes-file CHANGELOG.md

# 3. Sync tap
git clone https://github.com/m-moravcik/homebrew-viberes /tmp/tap
cp Formula/viberes.rb /tmp/tap/Formula/viberes.rb
# (manually update version + sha256 in /tmp/tap/Casks/viberes-app.rb)
cd /tmp/tap && git add -A && git commit -m "viberes ${VERSION}" && git push
```
