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

## Releases

Pushing a version tag builds and tests the app on GitHub's macOS runner, then
publishes `WindowSaver-macOS.zip` and its SHA-256 checksum as a GitHub Release.

The tag must match `CFBundleShortVersionString` in `Info.plist` (with a `v`
prefix). The initial release is therefore:

```sh
git tag -a v0.0.1 -m "Window Saver 0.0.1"
git push origin v0.0.1
```

The release ZIP has an ad-hoc signature that keeps the app bundle intact, but
it is not Developer ID-signed or notarized. macOS may require the user to
right-click the app and select **Open** the first time. To distribute without
that warning, add Developer ID signing and notarization credentials to the
release workflow.
