# Verification and policy gates

## Verified (2026-11-14, Claude Code 2.1.325, macOS 15, Apple Silicon)
- `claude -p "/usage"` prints `Current session: N% used · resets <time> (<tz>)`, `Current week (all models): …` and per-model weekly lines, in ~4 s.
- It is a **local command**: the stored transcript shows a `local_command` entry and no assistant turn, i.e. no model generation.
- By default the CLI writes a ~5 KB transcript per invocation (the original SwiftBar script left thousands). ClaudeBarLimit passes `--no-session-persistence`, verified to produce identical output and no file; it falls back to plain `-p /usage` if the flag is rejected.

## NOT verified — blockers before public release
- **Terms of service.** ClaudeBarLimit only launches the user's own `claude` binary and never touches tokens, keychain or cookies, which is the least invasive method available. But I could not confirm Anthropic's current terms explicitly permit third-party tools driving the CLI, and `/usage` output is not a documented, stable API. Review Anthropic's current Consumer/Commercial Terms and Claude Code docs before publishing.
- Behavior with API-key / Console auth (no subscription limits) is unverified; the app reports "no usage limits" if no lines appear.
- Not tested: clean-machine Gatekeeper first launch, Intel hardware, Homebrew install/upgrade/uninstall, real screenshot.
