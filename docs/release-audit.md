# Along 0.7.0 release review

Reviewed October 19, 2026. Covers production Swift sources, tests, build and packaging scripts, app metadata, artwork, documentation, CI configuration, and the public GitHub release assets.

## Findings

| Finding | Status |
| --- | --- |
| Repository is now `sujalalmeida/Along`, but local links and the Git remote used `TileMac` | Updated current links and the remote to Along |
| Along and the earlier TileMe package both used version 0.6.0 | Along candidate is now 0.7.0, build 7 |
| Product identity and shortcut actions were repeated as literals/numeric IDs | Interface and diagnostics use `AppIdentity`; shortcut callbacks use `HotkeyAction` |
| A window recovering from an eligibility timeout could miss its layout target until another action | Reconciliation checks actual frames against targets; regression test added |
| Layout used an unnecessary forced dictionary lookup | Frames are calculated from positioned columns |
| Bundle verification did not compare the app version with the release version or check signed sandbox entitlements | Verifier checks both; packaging and CI supply the expected version |
| A public release could be packaged from uncommitted source by mistake | `REQUIRE_CLEAN_SOURCE=1` refuses it; local candidates remain available and record their source state |
| Current documentation mixed operating instructions and historical development observations | Historical records moved to `docs/history`; current instructions and performance methodology kept separate |
| Public release still downloads TileMe 0.6.0 | Unchanged historical release; publish a new Along 0.7.0 pre-release before sharing an Along download |

## Verification

- All 34 Swift Testing tests passed, including the recovery regression case.
- Optimized ARM64 build completed without compiler warnings in the reviewed run.
- Swift formatting lint, shell syntax, Python syntax, local documentation links, and `git diff --check` passed.
- Along 0.7.0 ZIP and mounted DMG passed bundle-name, executable-name, version/build, ARM64 architecture, ad-hoc signature, sandbox entitlement, license, icon, and installer checks.
- All candidate SHA-256 checksums matched. `release.json` matches the app name/version/architecture and correctly records uncommitted source changes.
- The verifier rejected a 0.6.0 app when asked to verify 0.7.0. Public-release mode rejected the uncommitted working tree before building.
- Downloaded the public v0.6.0 release's DMG, ZIP, notes, installation instructions, license, and metadata. Every supplied checksum matched. The mounted DMG's signature, architecture, metadata, and Applications shortcut passed inspection; the app is correctly identified as TileMe 0.6.0.
- The latest inspected GitHub CI run passed for commit `943caf9`. That run predates the uncommitted Along rename and these fixes; it does not validate this candidate.

Remaining TileMe references in current source are intentional: the stable `io.tileme.app` identifier and migration instructions. Other occurrences identify the old app, historical checks, or third-party projects. The workspace folder's name does not affect the shipped app. No current source TODOs, placeholder screens, or unfinished feature promises were found. Third-party development guidance retains its attribution and license.

## Before sharing the download

1. Commit and push the reviewed source, including renamed directories and new files. Confirm CI on that commit.
2. Build with `REQUIRE_CLEAN_SOURCE=1 ./Scripts/package-release.sh`. The local audit candidate is not the final committed-source artifact.
3. Publish a new **Along 0.7.0** pre-release with tag `v0.7.0`, current notes, DMG, ZIP, metadata, installation notes, license, and checksums. Preserve the old v0.6.0 assets.
4. Update the README release status. Add a short repository About description, such as “A free, open-source scrolling window manager for macOS.”
5. Download the published files and verify their checksums before linking them from LinkedIn or the website.

Fresh-account/other-Mac installation and live checks of the new recovery UI remain pending. No fresh-install result, universal compatibility, performance benchmark, Apple notarization, legal clearance, or absence of all defects is claimed by this review.
