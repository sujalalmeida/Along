import SwiftUI

struct PermissionView: View {
    @ObservedObject var permissions: PermissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Welcome to TileMe", systemImage: "rectangle.split.2x2")
                .font(.largeTitle.bold())
            Text("TileMe lives in your menu bar. Accessibility access lets it move and resize windows in other apps.")
                .fixedSize(horizontal: false, vertical: true)
            Label(permissions.isTrusted ? "Accessibility access granted" : "Accessibility access required",
                  systemImage: permissions.isTrusted ? "checkmark.circle.fill" : "lock.shield")
                .foregroundStyle(permissions.isTrusted ? .green : .orange)
                .font(.headline)
            if permissions.isTrusted {
                Text("Close this window, focus a window in another app, then choose a snapping action from TileMe’s menu bar icon. Restore returns it to its frame before the first snap.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("1. Click Request Access.\n2. Open Accessibility Settings and enable TileMe.\n3. Return here. Permission status updates automatically.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Request Access") { permissions.requestAccess() }
                        .buttonStyle(.borderedProminent)
                    Button("Open Accessibility Settings") { permissions.openSettings() }
                }
                Text("If TileMe is missing from the list, use the + button and select this app. Install it in Applications before granting access for regular use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = permissions.settingsError {
                Text(error).foregroundStyle(.red)
            }
            Divider()
            HStack {
                Text("Stage 2 · Window snapping")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Check Again") { permissions.refresh() }
            }
        }
        .padding(28)
        .frame(width: 510)
    }
}
