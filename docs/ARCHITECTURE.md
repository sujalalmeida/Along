# How TileMe fits together

TileMe manages a horizontal row of real macOS windows. Adding a window inserts a column after the selected one; moving through the row changes the viewport rather than shrinking neighboring windows. It uses public Accessibility APIs and has no runtime dependencies.

## Responsibilities

- **TileMeCore** contains the row model, coordinate conversion, spring motion, and bounded navigation buffer. It has no AppKit or Accessibility side effects.
- **RowController** owns menu state and input on the main actor. It coalesces repeated input, caches window scans, and assigns a generation to each row session so an old operation cannot update a new session's UI.
- **RowWindowEngine** owns AX window references, original frames, and layout execution on one serial worker. The `@unchecked Sendable` annotation depends on that confinement: only the locked motion-interruption token is accessed outside the worker. Do not add unsynchronized public access to its state.
- **WindowAccessibility** is the boundary to other apps. The system implementation validates values and exposes failures as `WindowAccessError`. Tests substitute a fake implementation without moving real windows or needing Accessibility permission.
- **HotkeyManager** owns Carbon registrations. **MenuBarController** and the SwiftUI views present the app; **PermissionManager** tracks permission for the exact installed copy.

No Accessibility IPC runs on the main actor. Animation waits happen on the window worker, with a bounded duration and an interruption token. Direct scrolling avoids reading every window after every successful write; settling and periodic scans reconcile actual geometry.

## Failure and restoration rules

1. Capture a window's original frame once, before its first managed placement.
2. A timeout is not proof that a window closed. Preserve its record and original frame, skip writes to it, and recheck it on a later scan.
3. A failed placement invalidates the cached frame. The next request must retry rather than assume the target was reached.
4. Stopping tries each saved original independently and verifies the resulting frame. Closed windows and terminated apps can be forgotten. Refused writes, timeouts, minimized windows, and full-screen windows retain their originals for an explicit retry.
5. A second stop or quit joins an in-flight restoration. Failure messages take precedence over routine Space/display-change messages. Quitting with unresolved originals requires a choice because those frames live only in memory.
6. Window titles are presentation data. Missing titles use a generic label; logs contain operation names and error codes, never titles or window contents.

## Verification

Run `./Scripts/test.sh` for model and worker recovery tests. Run a staged release build as described in [BUILDING.md](BUILDING.md). Fake Accessibility tests establish TileMe's recovery decisions; they cannot prove another app accepts a resize or that motion feels smooth. Use [performance-checks.md](performance-checks.md) and the release checklist on real Macs.

Format Swift sources with `xcrun swift-format format --in-place --recursive Sources Tests Package.swift`. The repository configuration uses four spaces and a 120-column limit. Use the formatter supplied with the project's Swift toolchain to avoid unrelated formatting changes across toolchain versions.

## Reliability review, October 2026

The review found and corrected these paths:

| Finding | Change |
| --- | --- |
| Failed or skipped restoration discarded originals | Keep unresolved frames and offer **Retry restoring windows** |
| A successful AX return could still leave a constrained restoration | Read back and verify the restored frame |
| Failed scroll writes cached the requested target | Invalidate the cache on failure |
| A transient eligibility read could discard a live record | Preserve it and defer writes until a successful scan |
| Animation and focus failures were ignored | Stop repeated animation writes and surface focus failure |
| Space-change copy hid restoration failure | Give recovery status priority |
| A quit request could overtake an existing stop | Join the shared restoration task |
| Stale completion could update another session | Check a session generation before applying results |
| Arbitrary navigation integers could overflow | Clamp movement before adding it to the index |
| Invalid viewport/gap values could corrupt row offsets | Validate geometry and normalize spacing consistently |
| Old snapping implementation remained compiled | Remove it and retain tests for the current row workflow |

Remaining limits are deliberate: one selected display/current Space, fixed shortcuts and gaps, in-memory restoration, and app-specific off-screen constraints. This review does not establish crash recovery, latency or memory benchmarks, compatibility with every macOS version, or legal clearance.

### Local verification

On October 19, 2026, all 33 tests passed after these changes, including 11 worker recovery tests. Swift formatting lint and `git diff --check` passed. A separate release build at `build/reliability-review/TileMe.app` passed the bundle verifier, ARM64 architecture check, and ad-hoc code-signature verification. This is a local review build, not an updated published release. The installed app was not replaced. The new retry/quit UI and real-app behavior still need a manual check with Accessibility enabled.
