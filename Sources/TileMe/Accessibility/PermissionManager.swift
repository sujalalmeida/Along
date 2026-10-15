import AppKit
import ApplicationServices
import Combine

/// Checks consent only; prompting is an explicit user action in onboarding.
@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var settingsError: String?

    func refresh() {
        isTrusted = AXIsProcessTrusted()
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
