# AGENTS.md

## Cursor Cloud specific instructions

### Platform requirement: macOS only — cannot build/test/run on the Linux Cloud VM

This repository is a **macOS-only** menu bar application (`WeatherOverlay`). Every source
and test file imports Apple-proprietary frameworks that **only exist in the macOS SDK** and
are **not available** in the open-source Swift toolchain for Linux:

- `Cocoa`, `AppKit`, `SwiftUI`, `ServiceManagement`, `IOKit` — macOS-only frameworks.
- `Combine` — Apple-proprietary, not shipped with Linux Swift.

Because the Cursor Cloud VM runs Linux (Ubuntu), you **cannot** `swift build`, `swift test`,
or run the app here. Even with the Swift toolchain installed, compilation stops at the first
`import Cocoa` with `error: no such module 'Cocoa'`. There is no runnable subset: the single
library target (`WeatherOverlayCore`) contains `AppDelegate.swift` (imports `Cocoa`), so the
whole module fails to compile, which in turn blocks all tests.

**Do not attempt to make this project build on Linux** (e.g. by shimming/removing macOS
imports). That would mean rewriting the app and is out of scope for environment setup.

### Where the real build/test/run happens

All development, testing, and running must be done on **macOS 13+ (Ventura)** with the Swift
5.9+ toolchain (Xcode). The standard commands are already documented — do not duplicate them:

- Build & run: see `README.md` ("Build from Source") and `build_app.sh`.
- Tests: `swift test` (see `README.md` → Development). This only works on macOS.
- CI: `.github/workflows/release.yml` runs on `runs-on: macos-latest`.

### What the update script does

The project has **no external Swift package dependencies** (pure Swift, no lockfile), and
nothing on Linux can compile it, so the startup update script is intentionally a no-op. There
are no Linux dependencies to refresh.
