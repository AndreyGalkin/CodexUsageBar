# CodexUsage

CodexUsage is a native, menu-bar-only macOS 14+ app. It shows the percentage remaining in the current Codex five-hour and weekly windows, refreshes every 30 seconds, and keeps the last successful values visible if a refresh fails.

## How it works

The app locates the `codex` executable in Homebrew locations, `~/.local/bin`, app bundles, and `PATH`. For each refresh it launches `codex app-server --stdio`, performs the supported JSON-RPC `initialize` handshake, and calls `account/rateLimits/read`. It reads only the returned rate-limit data and never reads, stores, or logs authentication tokens. Percentages are calculated as `clamp(100 - usedPercent, 0...100)`.

CodexUsage depends on the locally installed Codex CLI/app-server and your existing Codex login. The protocol is supplied by Codex but may evolve; errors appear in the dropdown while the last successful reading remains in the menu bar.

## Build and test

Open `CodexUsage.xcodeproj` in Xcode, select the CodexUsage scheme, and run. Or use:

```sh
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -configuration Release build
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage test
```

## Install

Build the Release configuration, locate `CodexUsage.app` in Xcode's Products group (Show in Finder), and copy it to `/Applications`. Launch it once, then optionally enable **Launch at Login** in its menu.

The app has no Dock icon or regular launch window. macOS may require approval in **System Settings → General → Login Items** after registering it for login.
