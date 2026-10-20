import AppKit
import Carbon

enum HotkeyAction: UInt32, Sendable {
    case previousWindow = 1
    case nextWindow
    case cycleWidth
    case toggleRow
}

@MainActor
final class HotkeyManager {
    private nonisolated static let signature: OSType = 0x414C_4E47  // ALNG
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    var onAction: ((HotkeyAction) -> Void)?
    private(set) var conflicts: [String] = []

    func start() {
        guard handler == nil else { return }
        conflicts.removeAll()
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var hotkey = EventHotKeyID()
                let result = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
                guard result == noErr else { return result }
                guard hotkey.signature == HotkeyManager.signature else { return OSStatus(eventNotHandledErr) }
                guard let action = HotkeyAction(rawValue: hotkey.id) else { return OSStatus(eventNotHandledErr) }
                // Carbon's application event handler is delivered on the application main run loop.
                MainActor.assumeIsolated {
                    Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue().onAction?(action)
                }
                return noErr
            }, 1, &event, pointer, &handler)
        guard status == noErr else {
            conflicts = ["Global shortcut handler unavailable (\(status))"]
            return
        }
        let bindings: [(HotkeyAction, UInt32, String)] = [
            (.previousWindow, UInt32(kVK_LeftArrow), "⌃⌥←"), (.nextWindow, UInt32(kVK_RightArrow), "⌃⌥→"),
            (.cycleWidth, UInt32(kVK_ANSI_R), "⌃⌥R"), (.toggleRow, UInt32(kVK_ANSI_P), "⌃⌥P"),
        ]
        for (id, code, label) in bindings {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(
                code, UInt32(controlKey | optionKey), EventHotKeyID(signature: Self.signature, id: id.rawValue),
                GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref {
                keys.append(ref)
            } else {
                conflicts.append("\(label) unavailable (\(result))")
            }
        }
    }
    func stop() {
        for key in keys { UnregisterEventHotKey(key) }
        keys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
