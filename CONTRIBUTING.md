# Contributing

- Build: `./scripts/build.sh` — Test: `./scripts/test.sh` (Xcode Command Line Tools only).
- Parsing lives in `App/UsageParser.swift` and is pure: add a fixture in `Tests/Fixtures/` and a case in `Tests/main.swift` for any new CLI output format.
- Hard rules: no network code, no telemetry, no reading credentials/keychain/cookies, no new dependencies.
