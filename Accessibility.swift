import AppKit
import ApplicationServices

struct LiveWindow {
    var element: AXUIElement
    var bundleID: String
    var appName: String
    var title: String
    var frame: Frame
}

enum WindowAccess {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    static func frame(_ element: AXUIElement) -> Frame? {
        guard let p = value(element,kAXPositionAttribute), let s = value(element,kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size),
              size.width > 30, size.height > 30 else { return nil }
        return Frame(CGRect(origin: point, size: size))
    }
    static func windows(for app: NSRunningApplication) -> [LiveWindow] {
        guard trusted, app.activationPolicy == .regular,
              let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.4)
        guard let items = value(element,kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return items.compactMap { window in
            AXUIElementSetMessagingTimeout(window, 0.4)
            let role = value(window,kAXRoleAttribute) as? String
            let subrole = value(window,kAXSubroleAttribute) as? String
            guard role == kAXWindowRole, subrole == kAXStandardWindowSubrole,
                  (value(window,kAXMinimizedAttribute) as? Bool) != true,
                  (value(window,"AXFullScreen") as? Bool) != true,
                  let f = frame(window) else { return nil }
            return LiveWindow(element: window, bundleID: bundle, appName: app.localizedName ?? bundle,
                              title: value(window,kAXTitleAttribute) as? String ?? "", frame: f)
        }
    }
    static func allWindows() -> [LiveWindow] {
        NSWorkspace.shared.runningApplications.flatMap { windows(for: $0) }
    }
    static func move(_ window: LiveWindow, to target: Frame) -> Bool {
        var size = CGSize(width: target.width, height: target.height)
        var point = CGPoint(x: target.x, y: target.y)
        guard let s = AXValueCreate(.cgSize,&size), let p = AXValueCreate(.cgPoint,&point) else { return false }
        // Setting size again after crossing displays handles apps that clamp to the old screen.
        _ = AXUIElementSetAttributeValue(window.element,kAXSizeAttribute as CFString,s)
        let positionResult = AXUIElementSetAttributeValue(window.element,kAXPositionAttribute as CFString,p)
        _ = AXUIElementSetAttributeValue(window.element,kAXSizeAttribute as CFString,s)
        _ = AXUIElementSetAttributeValue(window.element,kAXPositionAttribute as CFString,p)
        guard positionResult == .success, let actual = frame(window.element) else { return false }
        return abs(actual.x-target.x) < 16 && abs(actual.y-target.y) < 16 &&
            abs(actual.width-target.width) < 24 && abs(actual.height-target.height) < 24
    }
    static func monitors() -> [Monitor] {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
            let id = CFUUIDCreateString(nil,uuid) as String
            let v = screen.visibleFrame
            return Monitor(id: id, name: screen.localizedName, bounds: Frame(CGDisplayBounds(displayID)),
                           visible: Frame(CGRect(x: v.minX, y: primaryTop-v.maxY, width: v.width, height: v.height)))
        }
    }
    static func monitor(for frame: Frame, in monitors: [Monitor]) -> Monitor? {
        monitors.max {
            let a = $0.bounds.rect.intersection(frame.rect), b = $1.bounds.rect.intersection(frame.rect)
            return (a.isNull ? 0 : a.width*a.height) < (b.isNull ? 0 : b.width*b.height)
        }
    }
}
