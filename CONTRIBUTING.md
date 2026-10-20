# Contributing

Small fixes and reproducible bug reports are welcome.

Use Swift 6, run `./Scripts/test.sh`, and build the app before opening a pull request. For window-management changes, try the affected action with a few real windows too; model tests cannot check how another app responds to Accessibility requests.

Keep UI copy short and changes focused. Don't add private window-server APIs or new runtime dependencies without discussing the need first. Include original artwork sources when changing icons.

For a bug report, include your Mac model/chip, macOS version, Along version, the affected application, and the steps to reproduce it. Avoid sharing screenshots or window titles that contain private information.

Release instructions live in [docs/RELEASING.md](docs/RELEASING.md). Generated apps and DMGs should not be committed.

Contributions are provided under the project's MIT license.

Tests for window behavior should use the injected Accessibility boundary rather than requiring control of another app.

The optional development skill is [error-handling-patterns](.agents/skills/error-handling-patterns/SKILL.md) from [wshobson/agents](https://github.com/wshobson/agents). Its upstream MIT notice is included in that directory; it is not bundled with the app.
