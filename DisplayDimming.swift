import AppKit
import SwiftUI

/// Session-only, per-screen dimming. No gamma tables or monitor settings change.
final class DisplayDimming: ObservableObject {
    static let shared = DisplayDimming()
    @Published private(set) var levels: [String: Int] = [:]
    private var overlays: [String: NSPanel] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                           object: nil, queue: .main) { [weak self] _ in self?.reconcile() }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    static func target(_ display: ConnectedDisplay) -> NSScreen? {
        guard !display.mirrored, display.isStillConnected() else { return nil }
        return NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.number }
    }

    func set(_ level: Int, display: ConnectedDisplay) {
        guard (25...100).contains(level), let screen = Self.target(display) else { return }
        if level == 100 { remove(display.id); return }
        let panel = overlays[display.id] ?? makePanel(screen)
        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 1 - Double(level) / 100
        overlays[display.id] = panel
        levels[display.id] = level
        panel.orderFrontRegardless()
    }

    private func makePanel(_ screen: NSScreen) -> NSPanel {
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                            defer: false, screen: screen)
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none
        return panel
    }

    private func remove(_ id: String) {
        overlays.removeValue(forKey: id)?.close()
        levels[id] = nil
    }

    private func reconcile() {
        let screens = Dictionary(uniqueKeysWithValues: ConnectedDisplay.online().map { ($0.id, $0) })
        for id in Array(overlays.keys) {
            if let display = screens[id], let screen = Self.target(display) {
                overlays[id]?.setFrame(screen.frame, display: true)
            } else { remove(id) }
        }
    }
}
