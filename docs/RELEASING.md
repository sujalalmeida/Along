# Releasing Along

Current candidate: **Along 0.7.1 preview**, Apple Silicon only, macOS 13+.

## Prepare

1. Finish the fresh-install checklist below before calling a download tested.
2. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist`.
3. Update `docs/release-notes.md`.
4. Run `./Scripts/test.sh`.
5. For a local candidate, run `./Scripts/package-release.sh`. For a public release, commit the source first and run `REQUIRE_CLEAN_SOURCE=1 ./Scripts/package-release.sh`.
6. Verify `SHA256SUMS.txt` from inside the generated release folder with `shasum -a 256 -c SHA256SUMS.txt`.
7. Check `release.json`: the version/architecture must match the download. Final published artifacts should be built from a clean, committed source tree. A dirty candidate records that fact and must be rebuilt after the source is committed.

Generated downloads belong in GitHub Releases, not in Git. `dist/` and `build/` are ignored. Source, icons, documentation, and scripts belong in the repository.

## Fresh-install test

Use the final DMG downloaded through a browser, preferably on another Apple Silicon Mac or a fresh macOS account. A local launch does not exercise download quarantine or a new user's Accessibility permissions.

- Verify the checksum; open the DMG and check the icon/background arrangement.
- Drag Along to Applications, eject the DMG, and open the installed copy.
- Check the actual first-launch warning. If appropriate, use Apple's per-app Open Anyway flow; do not disable Gatekeeper or remove quarantine attributes to make the test pass.
- Enable Accessibility for the Applications copy. Confirm setup reports access granted.
- Start with three normal windows. Open another and check insertion after the active column.
- Check arrow navigation, continuous modified trackpad scrolling, width cycling, manual resizing, and Reduce Motion.
- Check closing/minimizing/hiding a window and changing Spaces.
- Stop/quit and compare restored positions. Test relaunch and replacement by a newer build.
- Check CPU/memory during ordinary use; report the app/window count alongside readings.
- Test the oldest supported macOS version before advertising it as verified. The current deployment target is 13.0; that is not a claim of fresh-machine testing on macOS 13.

Record the machine, OS version, artifact checksum, and results in release notes. The initial package is a candidate pending this testing.

## Publish manually after testing

1. Commit and push the source you want to release. Build the final package from that clean commit with `REQUIRE_CLEAN_SOURCE=1 ./Scripts/package-release.sh`.
2. Create a GitHub release with a matching version tag, `v0.7.1`. Keep the historical TileMe `v0.6.0` assets unchanged.
3. Mark it **pre-release** until fresh-install testing is complete.
4. Update the README release status to match the published version. Paste the release notes and attach the DMG, ZIP, `SHA256SUMS.txt`, `INSTALL.txt`, `LICENSE`, and `release.json`.
5. Tell users: **Apple Silicon; macOS 13+; ad-hoc signed; not notarized.** Include the first-launch and Accessibility instructions.
6. Download the uploaded artifact once and verify its checksum.

No publishing or GitHub release creation is performed by the packaging script. The website can later link directly to the DMG release asset.

## Without an Apple membership

These downloads are not Developer ID verified or Apple notarized. Users may see Gatekeeper warnings, and managed Macs may block them. The DMG installer does not grant Accessibility access; each user grants that separately. See [Apple's instructions](https://support.apple.com/102445).

Moving to Developer ID signing and notarization later does not require distributing through the App Store. Do not describe an ad-hoc signature as Apple approval.
