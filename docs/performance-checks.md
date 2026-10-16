# Performance checks — 0.4.0

Checked on the development Mac on 2026-10-16.

- All 17 model tests passed, including bounded navigation buffering, reversal, row ordering, and geometry.
- Optimized release build and strict code-signature verification passed.
- Visually checked the new menu bar panel, disabled permission state, text wrapping, and setup dismissal.
- Window enumeration no longer runs on each navigation command. Full reconciliation is scheduled every two seconds during a row; focused-window checks run every 300 ms, with app lifecycle notifications triggering reconciliation.
- Pausing cancels the row timer. Closed windows are removed from restoration history after successful enumeration; terminated processes are pruned. Panel/setup view graphs are released on close.
- Animation interpolates over elapsed time (160 ms target), only sends intermediate updates to moving windows intersecting the viewport, and honors Reduce Motion. AX latency can still extend completion time.

## Measurement limits

The old running app showed 14,176 KiB RSS in one sample after an extended session. The new release showed 64,912 KiB RSS five seconds after launch with setup loaded. These are different states and are not a valid before/after memory comparison. A total-memory reduction has **not** been established. Releasing views and obsolete window references limits retention but does not force macOS or SwiftUI to return cached pages immediately.

The rebuilt executable needs refreshed Accessibility permission. Live navigation latency, active-row CPU, restoration, and a controlled repeated open/close memory test are still pending that refresh. Do not treat successful model tests as proof of live AX behavior.
