# Release process

VibeRes ships releases automatically through the
[`release.yml`](workflows/release.yml) workflow. A tag push (`vX.Y.Z`) drives
end-to-end publication.

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
   - Build VibeRes.app in Release configuration.
   - Package as `VibeRes-X.Y.Z.zip`.
   - Compute its SHA256.
   - Extract the matching `## [X.Y.Z]` section from `CHANGELOG.md` as release
     notes.
   - Create the GitHub Release with the ZIP attached.
   - Update `Formula/viberes.rb` and `Casks/viberes-app.rb` in the tap, then
     commit and push.

If something fails midway, fix the cause and re-run via Actions →
**Release** → **Run workflow** with the tag name as input.

## Manual fallback (no Action)

```bash
# 1. Build + ZIP
xcodegen generate
xcodebuild -project VibeRes.xcodeproj -scheme VibeRes -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build
mkdir -p /tmp/viberes-release
cp -R build/Build/Products/Release/VibeRes.app /tmp/viberes-release/
(cd /tmp/viberes-release && zip -ry "VibeRes-${VERSION}.zip" VibeRes.app)

# 2. SHA256
shasum -a 256 "/tmp/viberes-release/VibeRes-${VERSION}.zip"

# 3. Tag + GitHub Release
git tag "v${VERSION}" && git push --tags
gh release create "v${VERSION}" "/tmp/viberes-release/VibeRes-${VERSION}.zip" \
  --title "VibeRes ${VERSION}" --notes-file CHANGELOG.md

# 4. Sync tap
git clone https://github.com/m-moravcik/homebrew-viberes /tmp/tap
cp Formula/viberes.rb /tmp/tap/Formula/viberes.rb
# (manually update version + sha256 in /tmp/tap/Casks/viberes-app.rb)
cd /tmp/tap && git add -A && git commit -m "viberes ${VERSION}" && git push
```
