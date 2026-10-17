# TileMe

A scrolling window manager for macOS. Free, open source, and built with Swift and AppKit.

I wanted a better way to see my open windows without constantly moving them around or making everything smaller to fit. TileMe puts them side by side in a row. When the row gets wider than the screen, you move along it.

The idea came from TileMyMac. I wanted an open-source version I could use on my own Mac, understand, and change. This is my own implementation of that workflow, with room to keep improving it.

## How it works

Start a row and keep opening apps as usual. Each new window gets a place after the one you're using. The other windows keep their widths, and the row shifts to bring the selected window into view.

TileMe lives in the menu bar. There's no Dock icon and no separate desktop to work inside. It's your actual app windows, arranged into a row.

- Move between windows with the keyboard or trackpad.
- Change one window's width without resizing its neighbors.
- Stop the row to return windows to their original positions.

## Build it

You'll need macOS 13 or later and a Swift 6 toolchain through Xcode or Apple's Command Line Tools. I use it on Apple Silicon.

From the project folder:

```sh
./Scripts/build-app.sh
open build/TileMe.app
```

For a release build:

```sh
CONFIGURATION=release ./Scripts/build-app.sh
```

You can copy `build/TileMe.app` into `/Applications`. Pick one copy to use, and grant Accessibility access to that copy. Launch the app bundle rather than using `swift run`.

**Quit TileMe from its menu before rebuilding.** That lets it restore your windows; the build script will refuse to replace a running copy.

### Signing

The build script signs locally by default. You don't need a paid developer account to build it for yourself.

If you have a signing identity, you can use it instead:

```sh
security find-identity -v -p codesigning
SIGNING_IDENTITY='Your signing identity' ./Scripts/build-app.sh
```

A consistent signing identity helps keep macOS permissions intact between builds. With the default ad-hoc signature, a changed build may need to be added to Accessibility settings again.

## Working on the code

Open `Package.swift` in Xcode, or use your editor and the build scripts.

The main pieces are:

| Location | Purpose |
| --- | --- |
| `Sources/TileMeCore/ScrollingRow.swift` | Column order, window widths, and scrolling calculations |
| `Sources/TileMe/Row/` | Window discovery, focus, placement, and restoration |
| `Sources/TileMe/Input/` | Global keyboard shortcuts |
| `Sources/TileMe/Accessibility/` | Permission handling and Accessibility API access |
| `Sources/TileMe/UI/` | Setup and menu bar panel |
| `Sources/TileMe/App/` | App lifecycle and menu bar controls |
| `Tests/TileMeCoreTests/` | Row and geometry tests |

Run the tests with:

```sh
./Scripts/test.sh
```

The tests use Swift Testing. Window control uses Apple's Accessibility API, and the app runs outside the App Sandbox. It doesn't capture your screen or use private window-server APIs.

The scripts also handle two mismatched Command Line Tools files I ran into during development. Those workarounds stay inside `.build/` and don't modify your system installation. Python 3 is needed if the compiler-overlay workaround is used.

Issues and pull requests are welcome. If an app behaves oddly, include your macOS version, the app name, and what you did just before it happened. Window sizing rules vary between apps, so a small reproducible example helps.

## Performance

Navigation reuses the known row instead of enumerating every app on each key press. Repeated arrow presses are combined into a bounded pending move, so input isn't silently dropped while an animation runs. Keyboard navigation uses interruptible spring motion. New input retargets from the current position and velocity instead of finishing an old movement first. Motion follows the display refresh rate, up to 120 Hz, and respects macOS Reduce Motion.

While a row is active, TileMe checks focus every 300 ms and reconciles the full window list every two seconds, with extra checks for app lifecycle changes and newly focused windows. The row timer is stopped while paused. Closed-window references are removed after successful enumeration, and the menu panel and setup view are released when closed.

For everyday use, build with `CONFIGURATION=release ./Scripts/build-app.sh`. These changes reduce repeated work; memory and switching latency still depend on the number of windows and how quickly their apps respond to Accessibility requests.

## Things to know

TileMe manages one display and the current Space at a time. Changing Spaces or the display configuration stops the row and attempts to restore your windows. Separate rows for each display and Space aren't supported yet.

Full-screen, minimized, hidden, and non-resizable windows stay out of the active row. Some apps enforce minimum widths or restrict off-screen placement; TileMe reports those constraints in its menu.

Window positions are kept in memory while TileMe runs. Use **Stop & restore windows** or **Quit TileMe** when you're done. A force-quit or crash can't restore them, and windows that are still minimized or full-screen are left alone.

Shortcuts are fixed, and gaps are 12 points. Custom shortcuts, exclusions, saved rows, and adjustable gaps aren't available yet.

## License

[MIT](LICENSE). Use it, change it, or build something else from it.

## Operating guide

### 1. Give TileMe access

Open TileMe and click **Request Access**, then **Open Settings**. Enable TileMe under **Privacy & Security → Accessibility**. On newer macOS versions, that page is called **Device Control and Data Access**.

TileMe needs this permission to move and resize other apps' windows. Setup will show **Accessibility access granted** when it's ready.

If the switch is already on but TileMe still says access is required:

1. Expand **Already enabled, but still not working?** in setup.
2. Click **Reveal This Copy in Finder** to locate the app you're actually running.
3. Remove the old TileMe entry from the permission list with **−**.
4. Use **+** to add that exact copy, then enable it.
5. Return to TileMe and click **Check Again**. Quit and reopen the same copy if needed.

This can happen after rebuilding an ad-hoc signed app; the enabled entry may belong to the previous build.

### 2. Start a row

Close setup, move your pointer onto the display you want to use, and press **Control+Option+P**. You can also choose **Start scrolling row** from TileMe's menu bar icon.

Normal windows on that display join the row. Open another app or window and it will join after the selected column. The row starts only when you ask it to.

### 3. Move around and resize

| Action | Shortcut |
| --- | --- |
| Previous window | **Control+Option+←** |
| Next window | **Control+Option+→** |
| Cycle the selected window's width | **Control+Option+R** |
| Start or stop the row | **Control+Option+P** |
| Navigate with the trackpad | Hold **Control+Option** and scroll horizontally |

Width cycles through roughly one-third, half, two-thirds, and the full usable display width. You can also resize a window manually; the row picks up its new width.

Trackpad scrolling moves the row continuously with your gesture and settles on a nearby window when you stop. Clicking or switching to a managed window brings it into view. Click the menu bar icon to open the control panel. It shows your position in the row, previous/next controls, width cycling, and any shortcut or placement problems. Modified trackpad scrolling may also reach the app underneath it.

### 4. Stop and restore

Press **Control+Option+P** again, or choose **Stop & restore windows**. TileMe restores the positions it saved when the windows joined the row.

To close TileMe entirely, choose **Quit TileMe** from its menu. Closing the setup window only dismisses setup.

If you want TileMe to launch when you log in, add the installed app under **System Settings → General → Login Items**. You'll still start the row yourself with **Control+Option+P**.
