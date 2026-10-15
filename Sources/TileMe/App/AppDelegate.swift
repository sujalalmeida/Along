import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = PermissionManager()
    private var menuBar: MenuBarController?
    private var onboarding: NSWindow?
    private var permissionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(permissions: permissions) { [weak self] in
            self?.showOnboarding()
        }
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunched")
        if !hasLaunched || !permissions.isTrusted { showOnboarding() }
        UserDefaults.standard.set(true, forKey: "hasLaunched")

        // A cancellable async timer keeps UI state current without blocking the run loop.
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                self?.permissions.refresh()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        permissions.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTask?.cancel()
    }

    private func showOnboarding() {
        permissions.refresh()
        if onboarding == nil {
            let controller = NSHostingController(rootView: PermissionView(permissions: permissions))
            let window = NSWindow(contentViewController: controller)
            window.title = "TileMe Setup"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            onboarding = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        onboarding?.makeKeyAndOrderFront(nil)
    }
}
