# ClaudeLimit (prototype)

Minimal macOS menu bar app that reuses your existing Claude Code login by running `claude -p "/usage"`. No API key, separate login, or third-party package required.

## Requirements
- macOS 13+; Apple Silicon or Intel Mac
- Claude Code CLI installed and already signed in
- Xcode Command Line Tools (`xcode-select --install`) for building

## Build

```sh
./build.sh
open dist/ClaudeLimit.app
```

This creates `dist/ClaudeLimit.app` and `dist/ClaudeLimit-macOS.zip`.
The app appears in the menu bar, not the Dock. Default `C: XX%` means percent **used**, like the original SwiftBar script. Toggle "Show remaining percentage" to switch.

## Important caveats
- Prototype only; not compiled or tested on macOS in this environment.
- Claude Code's `/usage` text format may change. This parses the `Current session:` line from the user's plugin, not a stable public API.
- `claude -p "/usage"` must work in the user's installed version of Claude Code. If it doesn't, the app will display an error.
- The CLI command must return promptly. A blocked CLI process could delay refresh; add a timeout before public distribution.
- Unnotarized apps downloaded from GitHub may trigger Gatekeeper; users may need System Settings > Privacy & Security > Open Anyway.
- Before public release, verify Anthropic's rules on reusing authenticated Claude Code sessions from third-party apps.
