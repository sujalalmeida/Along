import AppKit
import Carbon

@MainActor
final class HotkeyManager {
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    var onAction: ((UInt32) -> Void)?
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
                guard hotkey.signature == 0x5449_4C45 else { return OSStatus(eventNotHandledErr) }
                let id = hotkey.id
                // Carbon's application event handler is delivered on the application main run loop.
                MainActor.assumeIsolated {
                    Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue().onAction?(id)
                }
                return noErr
            }, 1, &event, pointer, &handler)
        guard status == noErr else {
            conflicts = ["Global shortcut handler unavailable (\(status))"]
            return
        }
        let bindings: [(UInt32, UInt32, String)] = [
            (1, UInt32(kVK_LeftArrow), "⌃⌥←"), (2, UInt32(kVK_RightArrow), "⌃⌥→"),
            (3, UInt32(kVK_ANSI_R), "⌃⌥R"), (4, UInt32(kVK_ANSI_P), "⌃⌥P"),
        ]
        for (id, code, label) in bindings {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(
                code, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x5449_4C45, id: id),
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
