# TileMe

An open-source native macOS menu bar window manager built with SwiftUI and AppKit.

## Current milestone: Stage 2

Implemented: menu bar app, Accessibility onboarding, halves, quarters, thirds, left/right two-thirds, maximize, center, and restore. Snapping uses the target window’s display and its usable area. Global keyboard shortcuts arrive in Stage 3.

Requires macOS 13 or newer and Swift 6 command-line tools or Xcode. Development is targeting Apple Silicon.

## Build and run

```sh
./Scripts/build-app.sh
open build/TileMe.app
```

Run the app bundle rather than `swift run` so macOS can associate permission with TileMe's bundle identity. Open `Package.swift` in Xcode to edit and build the source; use the script to produce the standalone app bundle with its Info.plist. Full Xcode is not required for the script. On this Mac, the installed Command Line Tools contain mismatched public/private Swift Package manifest interfaces. The script detects this and uses a copy of the matching public interfaces inside `.build/`. It also uses a local compiler overlay when duplicate legacy SwiftBridging module maps are present. These workarounds do not change system files; the overlay generator requires Python 3. Direct Xcode/SwiftPM builds may require repairing or updating Command Line Tools if affected by the same mismatch.

For an optimized build:

```sh
CONFIGURATION=release ./Scripts/build-app.sh
```

Quit any running TileMe instance before rebuilding or replacing it.

## Install and grant access

1. Build the app, then copy `build/TileMe.app` into `/Applications` using Finder.
2. Open `/Applications/TileMe.app`.
3. In setup, click **Request Access**, then **Open Accessibility Settings**.
4. Enable TileMe under System Settings → Privacy & Security → Accessibility. Use the + button to add the installed app if needed.
5. Return to TileMe. Its status updates automatically; **Check Again** also refreshes it.

Only you can grant Accessibility consent in System Settings. Closing setup leaves the app running in the menu bar. Reopen setup or quit from that menu. To snap a window, close setup, focus a normal window in another app, then select an action from TileMe’s menu. The result appears at the top of the menu and in the icon’s tooltip. Actions are disabled without permission or while another operation is running.

## Local signing

The build script uses ad-hoc signing by default; no paid developer account is required for the local build. For a stable signing identity, list your available signing identities and provide one explicitly:

```sh
security find-identity -v -p codesigning
SIGNING_IDENTITY='Your signing identity' ./Scripts/build-app.sh
```

Keep the app's bundle identifier, installation location, and signing identity consistent. Ad-hoc rebuilds may require removing and re-adding TileMe in Accessibility settings. The app is not sandboxed; `Resources/TileMe.entitlements` explicitly disables App Sandbox. Distribution notarization is outside this personal-use milestone.

For now, add the installed app manually in System Settings → General → Login Items (the label may vary by macOS version). An in-app launch-at-login control using SMAppService is planned for Stage 8.

## Planned shortcuts

All use Control+Option. These are reserved defaults, not active in Stage 2.

| Action | Key |
| --- | --- |
| Left/right/top/bottom half | Arrow keys |
| Top-left/top-right/bottom-left/bottom-right quarter | U / I / J / K |
| Left/center/right third | D / F / G |
| Left/right two-thirds | E / T |
| Maximize | Return |
| Center | C |
| Restore | Backspace |
| Previous/next display | [ / ] |
| Toggle auto-tiling | A |
| Pause/enable | P |
| Saved layouts | User assigned |

## Source guide

- `Package.swift`: Swift 6 executable and independent core library.
- `Sources/TileMe/App/TileMeApp.swift`: native application entry point and accessory activation policy.
- `Sources/TileMe/App/AppDelegate.swift`: application lifetime, setup window, and cancellable permission refresh loop.
- `Sources/TileMe/App/MenuBarController.swift`: status icon, permission indicator, setup/settings actions, and Quit.
- `Sources/TileMe/Accessibility/PermissionManager.swift`: Accessibility checks, explicit permission prompt, and System Settings deep link.
- `Sources/TileMe/UI/PermissionView.swift`: SwiftUI onboarding with granted/denied states.
- `Sources/TileMeCore/AppIdentity.swift`: shared application identity.
- `Resources/Info.plist`: bundle metadata and `LSUIElement = true`.
- `Resources/TileMe.entitlements`: explicitly disables sandboxing.
- `Sources/TileMeCore/SnapAction.swift`: supported actions and their menu names.
- `Sources/TileMeCore/ScreenGeometry.swift`: pure target-frame math, gap handling, display selection, and AX/AppKit coordinate conversion.
- `Sources/TileMe/Accessibility/WindowManager.swift`: queue-confined AX reads/writes, validation, bounded retries, result reporting, and per-window restore history.
- `Tests/TileMeCoreTests/ScreenGeometryTests.swift`: eight Swift Testing tests for geometry behavior and boundary cases.
- `Scripts/build-app.sh`: compiles, assembles, signs, and verifies the app bundle.
- `Scripts/toolchain-env.sh`: shared local toolchain workarounds.
- `Scripts/test.sh`: runs Swift Testing without requiring XCTest.

## Roadmap and validation

1. **Project + permissions:** build and launch; check menu, setup, denied/granted states, close/reopen, and quit.
2. **Snapping:** AX window operations; halves, quarters, thirds, two-thirds, maximize, center, restore; unit tests for frame calculations and gaps.
3. **Hotkeys:** global registration, conflicts, action menu, pause/enable.
4. **Displays:** coordinate conversion, display cycling, visible-frame insets, disconnect handling.
5. **Drag snapping:** edge/corner preview, release-to-snap, cancellation.
6. **Saved layouts:** capture/edit/apply normalized regions with app matching and persistence.
7. **Auto-tiling:** grid/master-stack, eligible current-Space windows, restoration.
8. **Settings:** shortcut editing, gaps, exclusions, login registration, final acceptance checks.

Run geometry tests with `./Scripts/test.sh`. Accessibility integration requires manual testing with consent and real app windows; compilation alone cannot verify it.

## License

MIT. See LICENSE.

## Stage 1 verification on the development Mac

- Swift 6 debug build completed successfully using the documented local toolchain workarounds.
- App bundle Info.plist and entitlements passed `plutil` validation.
- Ad-hoc code signature passed `codesign --verify --strict`.
- Launched the app bundle and confirmed its process remained running.
- Interactive UI and granted-permission checks remain manual: Computer Use permission was unavailable during development. Verify setup, Request Access, the System Settings link, permission refresh, closing/reopening setup, and Quit.


## Stage 2 behavior and verification

- All eight geometry tests passed; the app compiled and its signature was verified.
- AX manipulation of other apps still needs manual verification with Accessibility consent. Automated geometry tests do not establish compatibility with every app.
- Restore saves the frame before the first TileMe action, preserves it across subsequent snaps, and clears it after a successful restore. History is in memory, limited to the last 128 distinct windows, and resets when TileMe quits.
- Full-screen, minimized, and nonstandard windows are skipped. Unsupported resizing and application-enforced limits are reported in the menu. AX operations use a dedicated serial worker, per-message timeouts, and at most one retry.
- Default inner and outer gaps are 8 points. The settings UI comes later; set persisted values now with `defaults write io.tileme.app innerGap -float 12` and `defaults write io.tileme.app outerGap -float 12`, then restart TileMe. Use 0 for no gaps. Center preserves size unless the window is too large for the usable area.
- Maximize fills the usable area; it does not enter macOS full-screen mode. Menu actions use the window with focus in the app that was frontmost when the menu opened.

Manual acceptance checklist: grant access; focus a Finder or browser window; try left/right halves and all quarters; try thirds and two-thirds; maximize and center; restore and compare with the original frame. Check a size-constrained window and a full-screen window for graceful refusal. Global hotkeys, display cycling, drag snapping, saved layouts, auto-tiling, and the complete settings UI remain later milestones.
