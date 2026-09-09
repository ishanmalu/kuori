import AppKit
import Carbon.HIToolbox

/// One global hotkey via Carbon `RegisterEventHotKey` — the summon that needs
/// no permission and works from a menu-bar app. Default: ⌥⇧V.
enum Hotkey {
    private static var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?
    private static var installed = false

    /// key + modifiers as a display string ("⌥⇧V") for the menu.
    static let label = "⌥⇧V"

    static func register(_ action: @escaping () -> Void) {
        handler = action
        installHandler()

        if let ref { UnregisterEventHotKey(ref); Self.ref = nil }
        let id = EventHotKeyID(signature: OSType(0x44415359 /* 'DASY' */), id: 1)
        let mods = UInt32(optionKey | shiftKey)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), mods, id,
                                         GetApplicationEventTarget(), 0, &newRef)
        if status == noErr {
            ref = newRef
        } else {
            NSLog("Daisy: couldn't register \(label) (status \(status)) — another app may hold it")
        }
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { Hotkey.handler?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
