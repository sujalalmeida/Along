import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let permissions: PermissionManager
    private let row: RowController
    private let showOnboarding: () -> Void
    private let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Start Scrolling Row", action: nil, keyEquivalent: "p")
    private var actions: [NSMenuItem] = []
    private var subscriptions: Set<AnyCancellable> = []

    init(permissions: PermissionManager, row: RowController, showOnboarding: @escaping () -> Void) {
        self.permissions = permissions; self.row = row; self.showOnboarding = showOnboarding
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "TileMe Scrolling Row")
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        let heading = NSMenuItem(title: "TileMe · Scrolling Windows", action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading)
        status.isEnabled = false; menu.addItem(status); menu.addItem(.separator())
        toggleItem.action = #selector(toggle); toggleItem.target = self
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(toggleItem)
        actions.append(add("Previous Window", #selector(previous), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), to: menu))
        actions.append(add("Next Window", #selector(next), key: String(UnicodeScalar(NSRightArrowFunctionKey)!), to: menu))
        actions.append(add("Cycle Window Width", #selector(resize), key: "r", to: menu))
        menu.addItem(.separator())
        let swipe = NSMenuItem(title: "Navigate: ⌃⌥ + horizontal trackpad scroll", action: nil, keyEquivalent: "")
        swipe.isEnabled = false; menu.addItem(swipe)
        menu.addItem(.separator())
        _ = add("Setup & Permissions…", #selector(setup), to: menu)
        _ = add("Quit & Restore Windows", #selector(quit), to: menu)
        statusItem.menu = menu
        row.$message.sink { [weak self] value in self?.status.title = value; self?.statusItem.button?.toolTip = value }.store(in: &subscriptions)
        row.$enabled.sink { [weak self] value in self?.toggleItem.title = value ? "Stop Row & Restore Windows" : "Start Scrolling Row" }.store(in: &subscriptions)
    }
    private func add(_ title: String, _ action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.keyEquivalentModifierMask = [.control, .option]; menu.addItem(item)
        return item
    }
    func menuWillOpen(_ menu: NSMenu) {
        permissions.refresh()
        toggleItem.isEnabled = !row.busy && (permissions.isTrusted || row.enabled)
        for item in actions { item.isEnabled = row.enabled && !row.busy }
        if !row.shortcutWarning.isEmpty { status.title = row.shortcutWarning }
        else if !permissions.isTrusted { status.title = "Grant Accessibility access in Setup" }
        else { status.title = row.message }
    }
    @objc private func toggle() { row.toggle() }
    @objc private func previous() { row.send(.step(-1)) }
    @objc private func next() { row.send(.step(1)) }
    @objc private func resize() { row.send(.resize) }
    @objc private func setup() { showOnboarding() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
