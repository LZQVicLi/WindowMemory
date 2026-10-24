import AppKit
import Carbon

final class GlobalHotKeys {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32:ShortcutAction] = [:]
    var onAction: ((ShortcutAction) -> Void)?

    func configure(_ shortcuts: [Shortcut], enabled: Bool) -> [String] {
        for ref in references { UnregisterEventHotKey(ref) }
        references = []; actions = [:]
        guard enabled else { return [] }
        guard validShortcuts(shortcuts) else { return ["快捷键重复或不受支持，请选择不同的组合。"] }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),eventKind: UInt32(kEventHotKeyPressed))
            let result = InstallEventHandler(GetApplicationEventTarget(), { _,event,context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
                var id = EventHotKeyID()
                let status = GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
                if status == noErr, let action = manager.actions[id.id] { manager.onAction?(action); return noErr }
                return OSStatus(eventNotHandledErr)
            },1,&type,Unmanaged.passUnretained(self).toOpaque(),&handler)
            if result != noErr { return ["无法建立全局快捷键监听（\(result)）。"] }
        }
        var failures: [String] = []
        for (index,shortcut) in shortcuts.enumerated() {
            let id = UInt32(index+1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode,shortcut.modifiers,EventHotKeyID(signature: 0x574D454D,id: id),GetApplicationEventTarget(),0,&reference)
            if status == noErr, let reference { references.append(reference); actions[id] = shortcut.action }
            else { failures.append("\(shortcut.label) 注册失败，可能被其他 App 占用（\(status)）。") }
        }
        return failures
    }
    deinit {
        for ref in references { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
