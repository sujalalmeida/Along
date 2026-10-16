import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let permissions: PermissionManager
    private let row: RowController
    private let showOnboarding: () -> Void

    init(permissions: PermissionManager, row: RowController, showOnboarding: @escaping () -> Void) {
        self.permissions = permissions; self.row = row; self.showOnboarding = showOnboarding
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "TileMe")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "TileMe — Scrolling windows"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }
    func presentPanel() {
        if !popover.isShown { togglePanel() }
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        permissions.refresh()
        row.rememberTargetApplication()
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel(permissions: permissions, row: row,
            setup: { [weak self] in self?.popover.performClose(nil); self?.showOnboarding() },
            quit: { NSApplication.shared.terminate(nil) }))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    func popoverDidClose(_ notification: Notification) {
        // Release SwiftUI's view graph when the panel is not in use.
        popover.contentViewController = nil
    }
}
