# Window Saver

Native macOS 15+ menu-bar utility for saving and restoring open-window geometry by display configuration.

## Build

Open `WindowSaver.xcodeproj` in Xcode and run the `WindowSaver` scheme, or run:

```sh
xcodebuild -project WindowSaver.xcodeproj -scheme WindowSaver -configuration Debug -derivedDataPath .build build CODE_SIGNING_ALLOWED=NO
```

The app is deliberately not sandboxed: macOS Accessibility access is required to enumerate and position windows. On first save or restore, use **Grant Access** and enable Window Saver under **Privacy & Security → Accessibility**.

## What is implemented

- menu-bar-only SwiftUI application (no ordinary Dock presence)
- stable display configurations and one atomic, versioned JSON snapshot per configuration
- Accessibility permission checking, window capture, deterministic matching, and geometry restoration
- confirmation before replacing a snapshot
- debounced restoration following display changes
- app-launch restoration limited to the newly launched app, with a ten-second polling window
- diagnostics for moved, unmatched, ambiguous, unsupported, and failed windows

Snapshots are stored locally at `~/Library/Application Support/WindowSaver/snapshots.json`.
