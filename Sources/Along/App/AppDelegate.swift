import AlongCore
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let permissions = PermissionManager()
    private let row = RowController()
    private var terminating = false
    private var menuBar: MenuBarController?
    private var onboarding: NSWindow?
    private var permissionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(permissions: permissions, row: row) { [weak self] in
            self?.showOnboarding()
        }
        row.startMonitoring()
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunched")
        if !hasLaunched || !permissions.isTrusted || !UserDefaults.standard.bool(forKey: "rowOnboardingSeen") {
            showOnboarding()
        }
        UserDefaults.standard.set(true, forKey: "rowOnboardingSeen")
        UserDefaults.standard.set(true, forKey: "hasLaunched")

        // A cancellable async timer keeps UI state current without blocking the run loop.
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                self?.permissions.refresh()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.presentPanel()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        permissions.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        terminating = true
        Task {
            await row.stop()
            if row.pendingRestorations > 0 {
                let alert = NSAlert()
                alert.messageText = "Some windows could not be restored"
                alert.informativeText =
                    "Keep \(AppIdentity.name) open to retry after the affected apps respond or their windows are unminimized. Quitting discards the saved positions."
                alert.addButton(withTitle: "Keep \(AppIdentity.name) Open")
                alert.addButton(withTitle: "Quit Anyway")
                if alert.runModal() == .alertFirstButtonReturn {
                    terminating = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            await row.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTask?.cancel()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === onboarding { onboarding = nil }
    }

    private func showOnboarding() {
        permissions.refresh()
        if onboarding == nil {
            let controller = NSHostingController(rootView: PermissionView(permissions: permissions, row: row))
            let window = NSWindow(contentViewController: controller)
            window.title = "\(AppIdentity.name) Setup"
            window.delegate = self
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            onboarding = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        onboarding?.makeKeyAndOrderFront(nil)
    }
}
