#!/bin/bash
# Packages dist/ClaudeBarLimit.app into dist/ClaudeBarLimit-<version>-macOS.zip plus a .sha256 file.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
[ -d dist/ClaudeBarLimit.app ] || ./scripts/build.sh
ZIP="ClaudeBarLimit-$VERSION-macOS.zip"
rm -f "dist/$ZIP" "dist/$ZIP.sha256"
# ditto preserves the signature and bundle layout (unlike zip -r on some setups)
ditto -c -k --keepParent dist/ClaudeBarLimit.app "dist/$ZIP"
(cd dist && shasum -a 256 "$ZIP" > "$ZIP.sha256" && cat "$ZIP.sha256")
