import AppKit
import SwiftUI
import ServiceManagement

private func windowEvent(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let controller = Unmanaged<Controller>.fromOpaque(context).takeUnretainedValue()
    var pid: pid_t = 0
    AXUIElementGetPid(element,&pid)
    DispatchQueue.main.async { controller.windowCreated(pid) }
}

final class Controller: NSObject, ObservableObject {
    @Published var state = SavedState()
    @Published var monitors: [Monitor] = []
    @Published var permitted = WindowAccess.trusted
    @Published var message = "先摆好窗口，再点“记住当前布局”。"
    @Published var messageIsError = false
    @Published var busy = false
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    var current: Layout? { state.layouts.first { $0.id == layoutKey(monitors) } }
    let folder = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("WindowMemory",isDirectory: true)
    var file: URL { folder.appendingPathComponent("layouts.json") }
    private var window: NSWindow?
    private var statusItem: NSStatusItem!
    private var observers: [pid_t: AXObserver] = [:]
    private var handled: [pid_t: Set<CFHashCode>] = [:]
    private var timer: Timer?
    private var displayWork: DispatchWorkItem?
    private var generation = 0
    private var undoFrames: [(LiveWindow,Frame)] = []
    private var automaticSuspendedUntil = Date.distantPast
    private var isSaving = false

    override init() {
        super.init()
        monitors = WindowAccess.monitors()
        if FileManager.default.fileExists(atPath: file.path) {
            do { state = try JSONDecoder().decode(SavedState.self,from: Data(contentsOf: file)) }
            catch { tell("布局文件读取失败；原文件已保留。\(error.localizedDescription)",error: true) }
        }
        refreshLogin()
    }
    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group",accessibilityDescription: "窗口记忆")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClick)
        statusItem.button?.sendAction(on: [.leftMouseUp,.rightMouseUp])
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self,selector: #selector(appLaunched(_:)),name: NSWorkspace.didLaunchApplicationNotification,object: nil)
        nc.addObserver(self,selector: #selector(appTerminated(_:)),name: NSWorkspace.didTerminateApplicationNotification,object: nil)
        nc.addObserver(self,selector: #selector(woke),name: NSWorkspace.didWakeNotification,object: nil)
        NotificationCenter.default.addObserver(self,selector: #selector(displaysChanged),name: NSApplication.didChangeScreenParametersNotification,object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 2.5,repeats: true) { [weak self] _ in self?.checkPermission() }
        if permitted { attachAll(); scheduleEnvironmentRestore() }
        let first = !UserDefaults.standard.bool(forKey: "hasOpened")
        if first {
            UserDefaults.standard.set(true,forKey: "hasOpened")
            showWindow()
        }
        // A normal launch opens the small control window; login starts quietly.
        else if !CommandLine.arguments.contains("--background") && !isLoginLaunch { showWindow() }
    }
    private var isLoginLaunch: Bool {
        NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
    func tell(_ text: String, error: Bool = false) { message = text; messageIsError = error }
    @discardableResult
    func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            let data = try encoder.encode(state)
            if let previous = try? Data(contentsOf: file) {
                try previous.write(to: folder.appendingPathComponent("layouts.previous.json"),options: .atomic)
            }
            try data.write(to: file,options: [.atomic,.completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600],ofItemAtPath: file.path)
            return true
        } catch { tell("无法保存布局：\(error.localizedDescription)",error: true); return false }
    }
    func setPreference(_ key: WritableKeyPath<Preferences,Bool>, _ value: Bool) {
        state.preferences[keyPath: key] = value
        generation += 1
        persist()
    }
    func setSlot(_ id: UUID, enabled: Bool) {
        guard let p = state.layouts.firstIndex(where: { $0.id == layoutKey(monitors) }),
              let w = state.layouts[p].windows.firstIndex(where: { $0.id == id }) else { return }
        state.layouts[p].windows[w].enabled = enabled
        persist()
    }
    func saveLayout() {
        guard permitted else { WindowAccess.requestPermission(); return }
        guard !busy else { return }
        busy = true; isSaving = true; generation += 1
        defer { busy = false; isSaving = false }
        monitors = WindowAccess.monitors()
        let live = WindowAccess.allWindows()
        let oldEnabled = Dictionary(grouping: current?.windows ?? [],by: \.bundleID).mapValues { $0.contains(where: \.enabled) }
        let slots: [WindowSlot] = live.compactMap { w in
            guard let screen = WindowAccess.monitor(for: w.frame,in: monitors) else { return nil }
            return WindowSlot(bundleID: w.bundleID,appName: w.appName,title: w.title,monitorID: screen.id,
                              relative: w.frame.relative(to: screen.visible),enabled: oldEnabled[w.bundleID] ?? true)
        }
        guard !slots.isEmpty else { tell("没有找到可保存的普通窗口。请先打开 App 窗口，并退出全屏或最小化。",error: true); return }
        let key = layoutKey(monitors)
        let layout = Layout(id: key,name: monitors.map(\.name).joined(separator: " + "),updatedAt: Date(),monitors: monitors,windows: slots)
        if let i = state.layouts.firstIndex(where: { $0.id == key }) { state.layouts[i] = layout }
        else { state.layouts.append(layout) }
        for app in NSWorkspace.shared.runningApplications {
            handled[app.processIdentifier] = Set(WindowAccess.windows(for: app).map { CFHash($0.element) })
        }
        if persist() { tell("已记住 \(Set(slots.map(\.bundleID)).count) 个 App、\(slots.count) 个窗口的位置。") }
    }
    @discardableResult
    func restore(appID: String? = nil, onlyUnhandled: Bool = false, manual: Bool = false) -> Int {
        guard permitted, !busy, !isSaving else { return 0 }
        guard manual || (state.preferences.automatic && Date() > automaticSuspendedUntil) else { return 0 }
        guard let layout = current else {
            if manual { tell("这套屏幕还没有保存布局。请先点“记住当前布局”。") }
            return 0
        }
        busy = true; defer { busy = false }
        var moved = 0, failed = 0
        let slots = layout.windows.filter { $0.enabled && (appID == nil || $0.bundleID == appID) }
        let grouped = Dictionary(grouping: slots,by: \.bundleID)
        if manual { undoFrames = [] }
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, let saved = grouped[id] else { continue }
            let windows = WindowAccess.windows(for: app)
            let pairs = matchWindows(savedTitles: saved.map(\.title),liveTitles: windows.map(\.title))
            for (s,l) in pairs {
                let w = windows[l], slot = saved[s], hash = CFHash(w.element)
                if onlyUnhandled && handled[app.processIdentifier,default: []].contains(hash) { continue }
                guard let screen = monitors.first(where: { $0.id == slot.monitorID }) else { continue }
                if manual { undoFrames.append((w,w.frame)) }
                if WindowAccess.move(w,to: slot.relative.placed(in: screen.visible)) {
                    moved += 1; handled[app.processIdentifier,default: []].insert(hash)
                } else { failed += 1 }
            }
        }
        if moved > 0 || failed > 0 || manual {
            if failed > 0 { tell("已恢复 \(moved) 个窗口；\(failed) 个窗口受 App 尺寸限制或系统权限影响。",error: true) }
            else if moved == 0 { tell("暂时没有可恢复的窗口。请打开已保存的 App，并退出全屏或最小化。") }
            else { tell("已恢复 \(moved) 个窗口 · \(Date().formatted(date: .omitted,time: .shortened))") }
        }
        return moved
    }
    func undo() {
        guard !undoFrames.isEmpty else { tell("还没有可撤销的手动恢复。"); return }
        automaticSuspendedUntil = Date().addingTimeInterval(10)
        generation += 1
        var count = 0
        for (w,f) in undoFrames { if WindowAccess.move(w,to: f) { count += 1 } }
        undoFrames = []; tell("已撤销，\(count) 个窗口回到恢复前的位置。")
    }
    func deleteCurrent() {
        guard let layout = current else { return }
        let alert = NSAlert()
        alert.messageText = "忘记当前这套屏幕的布局？"
        alert.informativeText = "不会改变当前窗口位置。其他屏幕组合的布局会保留。"
        alert.addButton(withTitle: "忘记布局"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.layouts.removeAll { $0.id == layout.id }; generation += 1; persist(); tell("已忘记当前布局。")
    }
    private func checkPermission() {
        let now = WindowAccess.trusted
        if now != permitted {
            permitted = now
            if now { attachAll(); tell("权限已开启。把窗口摆好后，点“记住当前布局”。") }
            else { tell("窗口控制权限已关闭，自动恢复已停止。",error: true) }
        }
        // Some apps are not ready to accept AX notifications immediately after launching.
        if now { attachAll() }
        refreshLogin()
    }
    private func attachAll() {
        for app in NSWorkspace.shared.runningApplications { attach(app) }
    }
    private func attach(_ app: NSRunningApplication) {
        guard permitted, app.activationPolicy == .regular, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              observers[app.processIdentifier] == nil else { return }
        let pid = app.processIdentifier
        var observer: AXObserver?
        guard AXObserverCreate(pid,windowEvent,&observer) == .success, let observer else { return }
        let ax = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(observer,ax,kAXWindowCreatedNotification as CFString,context)
        if result == .success || result == .notificationAlreadyRegistered {
            observers[pid] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)
        }
    }
    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        attach(app)
        guard state.preferences.onLaunch, let id = app.bundleIdentifier else { return }
        scheduleApp(id,pid: app.processIdentifier)
    }
    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if let observer = observers.removeValue(forKey: app.processIdentifier) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)
        }
        handled.removeValue(forKey: app.processIdentifier)
    }
    func windowCreated(_ pid: pid_t) {
        guard state.preferences.onNewWindow, let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier else { return }
        scheduleApp(id,pid: pid)
    }
    private func scheduleApp(_ id: String, pid: pid_t) {
        guard state.preferences.automatic, current?.windows.contains(where: { $0.bundleID == id && $0.enabled }) == true else { return }
        let token = generation
        for delay in [0.5,1.5,4.0,9.0] {
            DispatchQueue.main.asyncAfter(deadline: .now()+delay) { [weak self] in
                guard let self, self.generation == token, NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == id else { return }
                if let app = NSRunningApplication(processIdentifier: pid) { self.attach(app) }
                _ = self.restore(appID: id,onlyUnhandled: true)
            }
        }
    }
    @objc private func displaysChanged() {
        generation += 1
        monitors = WindowAccess.monitors()
        if state.preferences.onDisplay { scheduleEnvironmentRestore() }
    }
    @objc private func woke() {
        if state.preferences.onWake { scheduleEnvironmentRestore() }
    }
    private func scheduleEnvironmentRestore() {
        displayWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.monitors = WindowAccess.monitors()
            self.handled = [:]
            self.attachAll()
            _ = self.restore()
        }
        displayWork = work
        DispatchQueue.main.asyncAfter(deadline: .now()+2.5,execute: work)
    }
    func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLogin()
            if loginNeedsApproval { SMAppService.openSystemSettingsLoginItems(); tell("请在系统设置中允许“窗口记忆”登录时打开。") }
        } catch { refreshLogin(); tell("登录启动设置失败：\(error.localizedDescription)",error: true) }
    }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 750,height: 730),styleMask: [.titled,.closable,.miniaturizable,.resizable],backing: .buffered,defer: false)
            w.title = "窗口记忆"
            w.minSize = NSSize(width: 690,height: 650)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainView(model: self))
            w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func statusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            for (title,action) in [("打开窗口记忆",#selector(openPanel)),("记住当前布局",#selector(saveFromMenu)),("立即恢复",#selector(restoreFromMenu)),(state.preferences.automatic ? "暂停自动恢复" : "继续自动恢复",#selector(toggleAutomatic)),("退出窗口记忆",#selector(quit))] {
                let item = NSMenuItem(title: title,action: action,keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else { showWindow() }
    }
    @objc private func openPanel() { showWindow() }
    @objc private func saveFromMenu() { saveLayout() }
    @objc private func restoreFromMenu() { _ = restore(manual: true) }
    @objc private func toggleAutomatic() { setPreference(\.automatic,!state.preferences.automatic) }
    @objc private func quit() { NSApp.terminate(nil) }
}
