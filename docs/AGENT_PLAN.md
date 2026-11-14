# ClaudeLimit — Coding Agent Implementation Brief

## Mission
Build and publish a lightweight, reliable, open-source native macOS menu-bar app that shows a user's Claude Code usage limits without any additional authentication. It should reuse their already-authenticated local Claude Code installation. Optimize for a delightful end-user onboarding flow and an exceptionally clear GitHub README. Do not add a backend, telemetry, or a paid Apple Developer dependency.

**Marketing line:** **Claude usage, always one glance away.**
**Subheading:** See your Claude Code usage and reset times right in the macOS menu bar. Already using Claude Code? No API key, no extra login, no SwiftBar.

## Inputs / cornerstone implementation
Read and preserve the behaviors of the provided files before modifying:
- `claude-usage.1m.sh` — user's functional SwiftBar script, which runs `claude -p "/usage"`, parses a `Current session:` line, and displays used percentage. Note: `C: 19%` in this script means **19% used**, not remaining.
- `ClaudeLimitApp-source.zip` — initial SwiftUI native menu-bar prototype containing `ClaudeLimit.swift`, `build.sh`, `README.md`. It uses `MenuBarExtra`, `UsageStore`, 60-second polling, local Claude CLI executable discovery, a toggle for remaining percentage, and links to billing and Claude. Treat it as a prototype, **not** production-ready code: it has no CLI timeout, may hang when reading a pipe, only parses current-session usage, and hasn't been compiled/tested on macOS.

When the agent starts, copy/extract the source ZIP and read all three files. Retain the minimal architecture and working user-facing behavior, but refactor as needed for robustness and testability. Keep original script in `references/` with attribution, not as a runtime dependency.

## Hard requirements
1. macOS 13+ native Swift/SwiftUI app; supports both Apple Silicon and Intel or makes support explicit based on verified CI artifacts.
2. Menu-bar-only (`LSUIElement=true`), no Dock icon, no permanent window.
3. Default title `C: NN%` represents **percent used**, matching original script. Setting allows **percent remaining** instead. Use `C: ?%` only when unavailable; never display stale data as current without marking it stale.
4. Menu shows current 5-hour session usage, reset time, weekly usage when data is available, freshness/error state, Refresh Now, toggle used/remaining, Open Claude billing (`https://claude.ai/settings/billing`), and Quit. Optional Open Claude shortcut.
5. Auto-refresh every 60 seconds by default (configurable to 1/5/10 minutes if easy). Do not overlap refreshes.
6. No new auth flow, no API keys, no password prompt, no copying login tokens, no reading Claude keychain secrets, no browser cookies, no direct undocumented API integration. Interact via user's existing authenticated CLI process only, **subject to confirming this integration is permitted**.
7. No backend, analytics, telemetry, trackers, ads, or network requests by the app beyond those performed by Claude Code CLI. Explain explicitly that invoking Claude Code may make network requests.
8. The app must not prompt Claude to generate content or consume model tokens just to check quota. Verify CLI behavior rather than assuming `claude -p '/usage'` is a safe structured usage endpoint. If verification fails, stop and document the limitation instead of using hidden OAuth endpoints or quietly billing the user's plan.
9. Avoid changing global Gatekeeper/security settings; never recommend `spctl --master-disable`, blanket quarantine removal, or unverified bypasses.
10. Source and releases public on GitHub, MIT license for code original to this repository; check licenses of any reused code.

## Architecture
Use a small testable structure rather than a heavyweight architecture:
- `App/ClaudeLimitApp.swift` — SwiftUI `MenuBarExtra` and menu actions.
- `App/UsageStore.swift` — observable state, refresh coordination, timers, stale handling, settings.
- `App/ClaudeCLI.swift` — CLI executable discovery, Process orchestration, timeouts, exit status and error capture, no shell interpolation. Check likely native installer paths and Homebrew paths, handle symlinks, allow user-configured CLI path only if auto-discovery fails. GUI apps have a limited PATH.
- `App/UsageParser.swift` — pure parsing of captured CLI output into typed usage metrics. Tolerate ANSI sequences, unicode separators, varying whitespace, absent optional data, localized/changed formats by returning clear errors instead of bogus numbers.
- `Tests/` — parser fixtures and unit tests; mocked process runner for timeout/failure scenarios.
- `scripts/build.sh` — reproducible local app build with `xcrun swiftc` or an Xcode project; ensure Info.plist metadata, bundle ID and version are correct.
- `scripts/package.sh` — predictable ZIP artifact with correct `.app` layout and checksum.

## CLI subprocess robustness
- Call executable with `Process` and arguments `-p`, `/usage` only after validating behavior on real authenticated Claude Code installation.
- Background execution; never block the main/UI thread.
- Explicit bounded timeout, e.g. 15 seconds; terminate timed-out child and ensure resources/threads cleanly exit. Handle pipe output concurrently (or use bounded file-backed output) to avoid deadlock with large stdout/stderr; cap captured output size.
- Distinguish CLI not installed, not authenticated, invocation timeout, nonzero exit, unexpected format, and temporary offline failures. Provide friendly inline help for each.
- No secrets or raw CLI output in routine logs/crash reports. Keep user data on device.
- Don't spam requests: no overlap, backoff on repeated failures, pause/reduce refresh if appropriate.
- Cache last successful result and timestamp, label stale data explicitly. Countdown based on an actual parseable reset timestamp when available; never invent reset dates.
- Verify whether the CLI's output is reliable and whether running it has nontrivial costs; if not, report unsupported behavior and seek a compliant alternative that preserves zero-auth UX.

## UI specification
Menu bar default: `C: 19%` (used); toggle changes to remaining percentage. On error `C: ?%`.

Menu content:
```
ClaudeLimit                         Updated 1m ago
Current session (5h)               81% used
19% remaining                      Resets in 2h 14m
Weekly (7d)                        43% used [if available]
Resets [verified timestamp or human-readable text]
-----------------------------------------------
Refresh now
Show remaining in menu bar          [toggle]
Open Claude billing                 [browser]
Open Claude                         [browser, optional]
-----------------------------------------------
Quit ClaudeLimit
```
Treat sample percentages/countdowns as illustrative only. Native macOS visual style; no custom design system or animations necessary. Format reset in user's locale/time zone if parseable; otherwise show original safe text as-is. Menu bar has accessible labels, clear error text, and no UI freeze.

## Repo and GitHub setup
- Preferred GitHub repos (if names are available and account access permitted): `tfiechowski/claude-limit` for app and `tfiechowski/homebrew-tap` for cask. If lacking GitHub permissions, prepare them locally and list exact manual commands. Do not claim they were created until confirmed.
- Public app repo with LICENSE (MIT), README, CONTRIBUTING (short), CHANGELOG (short), `.gitignore`, build/test workflow, release workflow, screenshots or a real screenshot/GIF captured from running app (never fabricated as an actual screenshot), and issue templates only if useful.
- Stable bundle identifier such as `dev.tfi.claudelimit` (verify suitable uniqueness before publishing) and display name `ClaudeLimit`.
- No third-party dependencies unless needed; keep build understandable.

## Distribution channel A — Homebrew (primary)
Create cask `Casks/claude-limit.rb` in `tfiechowski/homebrew-tap` pointing to versioned GitHub release artifact and verified SHA-256. Set `app 'ClaudeLimit.app'`, suitable macOS minimum, description, homepage, update/uninstall behavior as appropriate.

Public command **after publishing and validating the tap**:
```sh
brew install --cask tfiechowski/tap/claude-limit
```
Upgrade: `brew upgrade --cask tfiechowski/tap/claude-limit`.
Uninstall: `brew uninstall --cask tfiechowski/tap/claude-limit`.

Do not imply Homebrew removes Gatekeeper warnings. Test installed artifact on clean macOS with default protections. If app is ad-hoc signed/unnotarized, inform users that first launch may require System Settings > Privacy & Security > Open Anyway. Avoid claims of literally zero clicks in all environments. See https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap and https://docs.brew.sh/Taps; verify Homebrew cask syntax via `brew audit`/`brew style` where possible.

## Distribution channel B — GitHub Releases
Publish tagged semantic-versioned ZIP containing standalone `ClaudeLimit.app`, checksum, changelog, clear platform support, and install steps:
1. Download ZIP from Releases.
2. Unzip and drag ClaudeLimit.app into Applications.
3. Launch. If macOS blocks unsigned/unnotarized app, follow Apple's official approval UI (System Settings > Privacy & Security > Open Anyway).
4. Requires Claude Code CLI already installed and signed in.
Provide source ZIP automatically via GitHub and optional release asset. Avoid DMG unless ZIP experience proves insufficient.

## Distribution channel C — From source
Provide:
```sh
git clone https://github.com/tfiechowski/claude-limit.git
cd claude-limit
./scripts/build.sh
open dist/ClaudeLimit.app
```
Document Xcode Command Line Tools as **build-only** prerequisite, not required for binary installation. CLI must still be installed and authenticated for functionality.

## Release automation
GitHub Actions on macOS runner:
- PR: compile, run parser/process tests, lint/check if available, verify app bundle metadata and architecture.
- Tag `vX.Y.Z`: build release `.app`, ad-hoc sign if appropriate, package ZIP, compute SHA-256, attach release and changelog.
- Update Homebrew cask `version`, `sha256` and URL via pull request or a controlled bot workflow with narrowly scoped credentials. Avoid making an unreviewed failure-prone release change silently. If not automated initially, document exact update commands in `docs/RELEASING.md`.
- Build universal binaries with both target architectures if compatible; verify using `lipo -info`, or release separate architecture-tagged artifacts with appropriate casks.
- Inspect and confirm codesigning/notarization status. Never claim notarized when not.

## README — design and writing requirements
README is the product landing page, aimed at an end user, not a Swift developer. Front-load value, screenshot, installation, and zero-extra-login reassurance. Target opening structure:

```md
# ClaudeLimit

**Claude usage, always one glance away.**

A tiny, free macOS menu-bar app that shows your Claude Code usage and reset times. It reuses the Claude Code login you already have — no separate authentication, API keys, SwiftBar, or setup.

[Real screenshot or short GIF]

## Install in one command

```sh
brew install --cask tfiechowski/tap/claude-limit
```

Already using Claude Code? Launch ClaudeLimit from Applications. Look for `C: 19%` in your menu bar — that means 19% of your current session limit has been used.

**Requirements:** macOS 13+, Claude Code installed and signed in. Homebrew is required only for Homebrew installation. Because this build is not Apple-notarized, macOS may request one-time approval on first launch. [How to approve](link-to-official-Apple-guidance).

## What you get
- Current 5-hour usage at a glance
- Reset time and weekly usage where available
- Refresh and billing shortcut
- No extra login or tracking

## Other ways to install
- [Download the latest ZIP](link-to-real-release)
- Build from source [instructions]

## FAQs
- Does this require a Claude API key? No.
- Does it need Claude Code? Yes, installed and signed in.
- Is `C: 19%` used or remaining? Used by default; configurable.
- Does it run any background server? No.
- Why does macOS warn me? The app is not notarized; explain legitimate approval steps.
- How do I update? `brew upgrade --cask tfiechowski/tap/claude-limit`.
- How do I uninstall? `brew uninstall --cask tfiechowski/tap/claude-limit`.
- What if Claude usage cannot be read? Explain status, compatibility and how to report an issue.

## Privacy
No custom auth, telemetry, analytics, or external backend. Usage checks invoke your locally authenticated Claude Code CLI, which may communicate with Anthropic.

## License
MIT
```

Keep README short (ideally 1-2 screens before FAQs). Include badges only when meaningful and verified (release, license, supported macOS). Do not place architecture explanations above installation. Do not show mockups as actual screenshots. Never say 'no authentication required' without qualifying 'if already signed into Claude Code.' Do not promise 'one-click install' or 'no security warnings' for unsigned builds.

## Legal, policy, and distribution gates
- Confirm Anthropic's current terms permit the third-party integration method and specifically reuse of local Claude Code CLI login. If not permitted or unclear, flag it prominently and do not work around restrictions by scraping cookies or private endpoints.
- Confirm `claude -p '/usage'` is a stable enough, non-content-generation invocation. The user's working SwiftBar script demonstrates their local behavior but is not a public compatibility or policy guarantee.
- Verify no accidental collection of credentials or user prompts. Explain privacy simply.
- Use no unlicensed logos or official affiliation claims. State 'Unofficial open-source utility; not affiliated with Anthropic' in README/footer.

## Test matrix
- Fresh macOS installation with Claude Code installed and logged in.
- Claude CLI not found: clear error with install documentation.
- CLI installed but not authenticated: clear actionable error, no login UI in app.
- CLI output changes / reset line missing: no crash or fabricated numbers.
- Offline/timeout/process failure: stale status and retry.
- Intel and Apple Silicon where supported.
- User-specific CLI binary locations and different PATH environments.
- Homebrew install/upgrade/uninstall on a clean user environment.
- GitHub ZIP install and macOS Gatekeeper first launch.
- Correct menu-bar percentage mode and accessibility.

## Suggested execution phases and acceptance gates
1. **Verify foundation:** inspect attachments, validate actual CLI output on authenticated Mac and policy compliance; identify all blockers. If CLI or terms fail, stop public release and explain rather than silently switch integration mechanism.
2. **Harden app:** refactor into testable components; implement async process timeout, robust parser, errors/staleness and 5h/7d data where supported.
3. **Test locally:** compile, unit tests, manual smoke test on Mac; record reproducible success evidence and real screenshot.
4. **Prepare public repository:** source, MIT license, concise landing-page README, scripts, CI.
5. **Release artifacts:** tagged ZIP + checksums + GitHub Release; validate first launch.
6. **Homebrew tap:** create/modify tap, cask + SHA, audit and actual install/update/uninstall smoke test.
7. **Polish:** release notes, short social/demo copy, troubleshooting, clean final instructions.

## Definition of done
- A Claude Code user can run the advertised Homebrew command and install a working menu-bar app without setting up separate credentials (subject to standard macOS Gatekeeper approval).
- App accurately shows used percentage, remaining toggle, and real reset information; weekly data when available.
- No hangs/freezes when CLI is slow or broken.
- No backend, telemetry, private-endpoint hacks or secrets stored.
- Both ZIP and Homebrew release flows verified, with real downloadable assets and exact commands.
- README begins with benefit and installation, not implementation details, and sets honest expectations about Claude Code prerequisite and unsigned macOS installation.
- Coding agent finishes with repository links, release URL, exact install command, CI results, and any unsatisfied acceptance gates. Never claim a release or test exists without verification.
