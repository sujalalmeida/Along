# Along 0.7.0 preview

TileMe is now Along. This release keeps the same scrolling row workflow and adds better recovery when an app stops responding or refuses to restore its windows.

- Along branding in the app, installer, and download filenames.
- Retry restoring windows without losing the saved original positions.
- Wait for restoration before quitting; choose whether to quit if some windows still cannot be restored.
- Retry layout after a temporarily unavailable window becomes responsive again.
- Clearer reporting of failed window operations.

## Requirements and installation

Apple Silicon (M1 or newer), macOS 13 or later. Intel Macs are not supported.

1. Quit any running TileMe or Along copy from its menu bar menu.
2. Open the DMG and drag Along into Applications. Remove the older TileMe app if upgrading.
3. Eject the DMG and open Along from Applications.
4. If macOS blocks it, click Done, open System Settings → Privacy & Security, then choose Open Anyway for Along if you trust the download. Authenticate and confirm Open. See [Apple's instructions](https://support.apple.com/102445).
5. Enable Along in Privacy & Security → Accessibility. Return to Along and click Check Again.
6. Press **Control+Option+P** to start a row. Use **Control+Option+← / →** to navigate, **Control+Option+R** to cycle width, or hold **Control+Option** while scrolling horizontally.

These downloads are ad-hoc signed and not notarized by Apple. macOS cannot verify the publisher. Managed Macs may block them.

## Scope

One display and the current Space per session. Some apps limit window sizes or off-screen placement. Original positions are kept in memory; force-quitting or crashing cannot restore them. The internal bundle identifier stays the same for preference continuity. Ad-hoc updates may require a new Accessibility grant.

Automated and local package checks do not establish fresh-install behavior on another Mac or runtime compatibility with every supported macOS version. That testing remains pending; this is a preview release.
