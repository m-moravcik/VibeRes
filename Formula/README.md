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

When releasing a new version:

1. Tag the release in this repo (`git tag vX.Y.Z && git push --tags`).
2. Update `version` and `tag:` in `Formula/viberes.rb` here.
3. Sync the file to the tap repo (`m-moravcik/homebrew-viberes/Formula/viberes.rb`).
4. Commit and push the tap.

(A future GitHub Action could automate step 3-4 on tag push.)
