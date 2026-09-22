# Formula reference

The canonical Homebrew formula for `viberes` lives in the
[m-moravcik/homebrew-viberes](https://github.com/m-moravcik/homebrew-viberes)
tap repo, since Homebrew requires tap repos to be named `homebrew-*`.

`Formula/viberes.rb` here is a reference copy kept alongside the source code
so changes to the build invocation can be reviewed in the same PR. To install
the CLI as a user, run:

```bash
brew install m-moravcik/viberes/viberes
```

Releasing needs nothing done here. The `sync-tap` job in
[.github/workflows/release.yml](../.github/workflows/release.yml) rewrites
`version` and `tag:` in the tap's formula, and the version and sha256 in the
cask, on every tag push, then commits and pushes the tap.

The copy in this directory is not on that path, so its `version` and `tag:`
lines trail the latest release until refreshed by hand. The part worth
reviewing here is the build invocation - `depends_on`, `install`, `test` - not
the version. The tap is the source of truth for what a user installs.
