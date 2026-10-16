import AppKit
import ApplicationServices
import Combine

/// Checks consent only; prompting is an explicit user action in onboarding.
@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var settingsError: String?

    var runningAppPath: String { Bundle.main.bundleURL.path }

    func revealRunningApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }

    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        settingsError = NSWorkspace.shared.open(url)
            ? nil
            : "Open System Settings → Privacy & Security → Accessibility manually."
    }
}
