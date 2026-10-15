import AppKit
import TileMeCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let permissions: PermissionManager
    private let showOnboarding: () -> Void
    private let windowManager = WindowManager()
    private var targetPID: pid_t?
    private var isBusy = false
    private var actionItems: [NSMenuItem] = []
    private let resultItem = NSMenuItem(title: "Focus a window, then choose an action", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(permissions: PermissionManager, showOnboarding: @escaping () -> Void) {
        self.permissions = permissions
        self.showOnboarding = showOnboarding
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "TileMe")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "TileMe — Window tiling"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: AppIdentity.name, action: nil, keyEquivalent: ""))
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)
        resultItem.isEnabled = false
        menu.addItem(resultItem)
        menu.addItem(.separator())
        for action in SnapAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(snap(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            menu.addItem(item)
            actionItems.append(item)
            if [.bottomHalf, .bottomRight, .rightTwoThirds].contains(action) { menu.addItem(.separator()) }
        }
        menu.addItem(.separator())
        addItem("Accessibility & Setup…", action: #selector(openSetup), to: menu)
        addItem("Open Accessibility Settings…", action: #selector(openSettings), to: menu)
        menu.addItem(.separator())
        addItem("Quit TileMe", action: #selector(quit), key: "q", to: menu)
        statusItem.menu = menu
        updateStatus()
    }

    private func addItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) {
        permissions.refresh()
        let frontmost = NSWorkspace.shared.frontmostApplication
        targetPID = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost?.processIdentifier
        updateStatus()
    }

    private func updateStatus() {
        permissionItem.title = permissions.isTrusted ? "Accessibility: Granted" : "Accessibility: Access Required"
        for item in actionItems { item.isEnabled = permissions.isTrusted && targetPID != nil && !isBusy }
        if !permissions.isTrusted { resultItem.title = "Grant access in Accessibility & Setup…" }
        else if targetPID == nil { resultItem.title = "Focus another app's window first" }
    }

    @objc private func snap(_ sender: NSMenuItem) {
        guard !isBusy, let raw = sender.representedObject as? String,
              let action = SnapAction(rawValue: raw), let pid = targetPID,
              let primary = NSScreen.screens.first else { return }
        let screens = NSScreen.screens.map { ScreenDescriptor(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let defaults = UserDefaults.standard
        let inner = defaults.object(forKey: "innerGap") as? Double ?? 8
        let outer = defaults.object(forKey: "outerGap") as? Double ?? 8
        isBusy = true
        resultItem.title = "Applying \(action.title)…"
        updateStatus()
        Task { [weak self] in
            guard let self else { return }
            let message = await windowManager.perform(action, pid: pid, screens: screens, primaryMaxY: primary.frame.maxY,
                                                      innerGap: inner, outerGap: outer)
            isBusy = false
            resultItem.title = message
            resultItem.toolTip = message
            statusItem.button?.toolTip = "TileMe — \(message)"
            updateStatus()
        }
    }

    @objc private func openSetup() { showOnboarding() }
    @objc private func openSettings() { permissions.openSettings() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
