#!/bin/bash
# Compiles the parser/CLI/store logic with the test harness and runs it. Needs only Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 5 -o "$OUT/tests" \
  App/UsageParser.swift App/ClaudeCLI.swift App/UsageStore.swift App/Formatting.swift Tests/main.swift
"$OUT/tests" "$PWD/Tests/Fixtures"
