# Building Along

## Requirements

- macOS with Xcode or Command Line Tools providing Swift 6.
- App target: Apple Silicon, macOS 13.0+. Intel is not a supported app target.
- Python 3.10+ for DMG packaging; initial packaging-tool setup needs internet access.
- `hdiutil`, `iconutil`, `codesign`, `ditto`, and `lipo`, supplied with macOS/developer tools.

The app has no third-party runtime dependencies. Tests use Apple's Swift Testing framework.

```sh
./Scripts/test.sh
CONFIGURATION=release ./Scripts/build-app.sh
open build/Along.app
```

`build-app.sh` compiles `arm64-apple-macosx13.0`, assembles a staged `.app`, embeds the icon and MIT license, signs it, checks its architecture and signature, then replaces the destination. The default is ad-hoc signing. Debug is the default configuration; use release for downloads.

You can choose another destination without replacing your working app:

```sh
APP_PATH="$PWD/build/test/Along.app" CONFIGURATION=release ./Scripts/build-app.sh
```

The destination must be an absolute path ending in `.app`. It must not be running. Quit through Along's menu to restore managed windows before replacing a copy.

## App icon and installer artwork

Original vector drawing code lives in `Resources/Artwork/GenerateArtwork.swift`. The generated ICNS and PNG files are committed so ordinary builds do not need to regenerate them.

```sh
./Scripts/generate-artwork.sh
```

The ICNS includes standard sizes from 16 to 1024 pixels. The installer background is a 640 × 370 PNG fitting inside the installer window, including space for Finder chrome.

## Package a download

```sh
./Scripts/package-release.sh
```

The script builds an ARM64 release at `build/distribution/Along.app`, then creates:

- A read-only compressed DMG with a custom Finder background, positioned app icon, Applications shortcut, and Read Me.
- A ZIP containing the same app bundle.
- Installation notes, license, release notes, source/version metadata, and SHA-256 checksums.

It remounts the finished DMG and verifies the packaged app's signature, architecture, icon, license, metadata, and Applications link. Temporary images are detached on exit. Existing release output is not overwritten; increase the app version or set `DIST_DIR` to a different folder for a test build.

The Python tools `ds-store` and `mac-alias` are isolated in `.build/packaging/venv`. Versions and wheel hashes are pinned in `Scripts/packaging-requirements.txt`. Wheels are downloaded over HTTPS and pip verifies their hashes before installing them. No Python environment or build tool is shipped inside Along. Their upstream projects are [ds_store](https://github.com/dmgbuild/ds_store) and [mac_alias](https://github.com/dmgbuild/mac_alias), both MIT licensed.

For a public release, use `REQUIRE_CLEAN_SOURCE=1 ./Scripts/package-release.sh`; it refuses uncommitted source. Local candidate packaging still records a dirty working tree in `release.json`.

To verify an app manually:

```sh
./Scripts/verify-release.sh /path/to/Along.app 0.7.0
```

## Signing

Ad-hoc signing provides a local code-integrity signature, not a verified publisher identity. It does not satisfy Gatekeeper's Developer ID/notarization checks. No Apple membership, App Store submission, notarization, or signing credentials are used by `package-release.sh`.

`build-app.sh` optionally accepts `SIGNING_IDENTITY` for developers who have a certificate. With that set, it enables hardened runtime and a secure timestamp. That alone does not notarize an app. The preview packaging script deliberately uses ad-hoc signing and labels its output accordingly.

## Toolchain troubleshooting

`toolchain-env.sh` detects stale Swift Package manifest interfaces and duplicate SwiftBridging module definitions left by some Command Line Tools upgrades. It uses copies and an overlay under `.build/`, without editing system tools. If compilation fails outside those cases, use a complete, matching Xcode/Command Line Tools installation.

Tests execute on the build host's architecture. Cross-compilation and inspecting a deployment target do not establish runtime compatibility with every macOS release; use the test checklist before publishing.
