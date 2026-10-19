import SwiftUI

struct PermissionView: View {
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var row: RowController
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("TileMe", systemImage: "rectangle.split.3x1")
                .font(.largeTitle.bold())
            Text("Your windows, in one scrolling row.")
                .font(.title3).foregroundStyle(.secondary)
            Text(
                "Open an app. Its window joins the row after the one you’re using. Move along the row without shrinking every window to fit."
            )
            .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                GridRow {
                    Text("Move left / right")
                    Text("⌃⌥ ← / →").monospaced()
                }
                GridRow {
                    Text("Change focused window width")
                    Text("⌃⌥ R").monospaced()
                }
                GridRow {
                    Text("Start / stop and restore")
                    Text("⌃⌥ P").monospaced()
                }
                GridRow {
                    Text("Trackpad navigation")
                    Text("⌃⌥ + horizontal scroll")
                }
            }.font(.callout)
            Divider()
            Label(
                permissions.isTrusted ? "Accessibility access granted" : "Accessibility access required",
                systemImage: permissions.isTrusted ? "checkmark.circle.fill" : "lock.shield"
            )
            .foregroundStyle(permissions.isTrusted ? .green : .orange)
            if !permissions.isTrusted {
                Text(
                    "Enable this copy of TileMe in System Settings → Privacy & Security → Accessibility (called Device Control and Data Access on newer macOS)."
                )
                .font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Request Access") { permissions.requestAccess() }.buttonStyle(.borderedProminent)
                    Button("Open Settings") { permissions.openSettings() }
                    Button("Check Again") { permissions.refresh() }
                }
                DisclosureGroup("Already enabled, but still not working?") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            "macOS has not granted access to this running copy. A rebuilt app can leave an enabled entry for an older build. Remove TileMe from the permission list with the − button, then use + to add the exact app shown below and enable it again."
                        )
                        Text(permissions.runningAppPath).font(.caption.monospaced()).textSelection(.enabled)
                        Button("Reveal This Copy in Finder") { permissions.revealRunningApp() }
                        Text(
                            "Return here and click Check Again. If access is still denied, quit and reopen this same copy. Checking again cannot grant permission by itself."
                        )
                    }.font(.caption).padding(.top, 6)
                }
            } else {
                Text(
                    "Close setup and choose Start Scrolling Row from the menu bar. Stop or quit TileMe to restore the original window positions."
                )
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if !row.shortcutWarning.isEmpty { Text(row.shortcutWarning).foregroundStyle(.orange).font(.caption) }
            if let error = permissions.settingsError { Text(error).foregroundStyle(.red) }
        }
        .padding(28).frame(width: 530)
    }
}
