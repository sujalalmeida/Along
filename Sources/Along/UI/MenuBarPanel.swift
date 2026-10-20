import AlongCore
import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var row: RowController
    let setup: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.split.3x1.fill")
                    .font(.title2).foregroundStyle(.orange)
                    .frame(width: 40, height: 40)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppIdentity.name).font(.title3.bold())
                    Text("Room for every window").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()

            }
            VStack(alignment: .leading, spacing: 10) {
                Text(row.enabled ? "YOUR ROW" : "READY WHEN YOU ARE")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                Text(permissions.isTrusted ? row.message : "Allow Accessibility access to arrange your windows.")
                    .font(.callout).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(
                        maxWidth: .infinity, alignment: .leading)
                Button(action: { permissions.isTrusted ? row.toggle() : setup() }) {
                    HStack {
                        Image(
                            systemName: permissions.isTrusted ? (row.enabled ? "pause.fill" : "play.fill") : "lock.open"
                        )
                        Text(
                            permissions.isTrusted
                                ? (row.enabled ? "Stop & restore windows" : "Start scrolling row")
                                : "Enable Accessibility")
                        Spacer()
                        if permissions.isTrusted { Text("⌃⌥P").font(.caption.monospaced()).opacity(0.7) }
                    }.padding(.vertical, 5).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(row.busy && !row.enabled)
            }
            .padding(14).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            if !row.enabled && row.pendingRestorations > 0 {
                Button("Retry restoring windows") { Task { await row.stop() } }
                    .disabled(row.busy)
            }
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    navigation("Previous", icon: "arrow.left", shortcut: "⌃⌥←", direction: -1)
                    navigation("Next", icon: "arrow.right", shortcut: "⌃⌥→", direction: 1)
                }
                Button {
                    row.send(.resize)
                } label: {
                    HStack {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        Text("Cycle window width")
                        Spacer()
                        Text("⌃⌥R").foregroundStyle(.secondary).font(.caption.monospaced())
                    }.padding(10).frame(maxWidth: .infinity)
                        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain)
            }.disabled(!row.enabled)
            if !row.shortcutWarning.isEmpty {
                Label(row.shortcutWarning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Label("Hold ⌃⌥ and scroll sideways to move along your row.", systemImage: "hand.draw")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Button(action: setup) { Label("Setup", systemImage: "gearshape") }
                Spacer()
                Button("Quit \(AppIdentity.name)", action: quit).help("Restore windows and quit")
            }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 340)
    }
    private func navigation(_ title: String, icon: String, shortcut: String, direction: Int) -> some View {
        Button {
            row.send(.step(direction))
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                    Spacer()
                    Text(shortcut).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text(title).font(.callout.weight(.medium))
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityLabel("\(title) window")
    }
}
