# Reliability review, October 2026


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
