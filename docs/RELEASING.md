# Releasing

1. Bump `VERSION`, update `CHANGELOG.md`, commit, `git tag vX.Y.Z && git push --tags`.
2. The `release` workflow builds the universal app, runs tests, creates `ClaudeBarLimit-X.Y.Z-macOS.zip` + `.sha256` and attaches them to the GitHub Release.
3. Update the cask in `tfiechowski/homebrew-tap` (`Casks/claude-bar-limit.rb`): set `version` and `sha256` from the `.sha256` file, then
   `brew audit --cask --online tfiechowski/tap/claude-bar-limit && brew style Casks/claude-bar-limit.rb`, open a PR.
4. Smoke test on a clean user: `brew install --cask tfiechowski/tap/claude-bar-limit`, launch, `brew upgrade`, `brew uninstall --cask`.

The app is ad-hoc signed and **not notarized**; never describe it otherwise.
