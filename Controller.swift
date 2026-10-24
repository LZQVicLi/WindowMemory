import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

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
    @Published var message = L("先摆好窗口，再点“记住当前布局”。")
    @Published var messageIsError = false
    @Published var busy = false
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var selectedPage = "workspace"
    @Published var launching = false
    @Published var launchProgress = ""
    @Published var launchFailures: [String] = []
    @Published var runningBundleIDs = Set<String>()
    @Published var hotKeyErrors: [String] = []
    @Published var showPresetEditor = false
    var presetScreenID: String?
    var presetPattern: PresetPattern?
    var selectedUserTemplate: UserLayoutTemplate?
    @Published var showUserTemplateEditor = false
    var editingTemplate: UserLayoutTemplate?
    @Published var darkAppearance = false
    @Published var permissionChecks = 0
    var permissionPanel: NSPanel?
    let demoMode = CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--ui-self-test") || (Bundle.main.object(forInfoDictionaryKey: "WindowMemoryDemo") as? Bool == true)
    private var hotKeys = GlobalHotKeys()
    var scenes: [Layout] { state.layouts.filter { $0.screenKey == layoutKey(monitors) } }
    var current: Layout? {
        selectedLayout(in: state,screenKey: layoutKey(monitors))
    }
    var targets: [LaunchTarget] { launchTargets(current?.windows ?? [],rules: current?.launchRules ?? []) }
    var canUndo: Bool { !undoFrames.isEmpty }
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
    private var storageReadOnly = false
    private var launchToken: UUID?
    private var activeLaunchRequest: UUID?

    override init() {
        super.init()
        if demoMode {
            state = sampleState(); monitors = state.layouts[0].monitors; permitted = true; loginEnabled = true
            Localization.language = state.preferences.language
            runningBundleIDs = Set(state.layouts[0].windows.map(\.bundleID)); applyAppearance(); return
        }
        monitors = WindowAccess.monitors()
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let loaded = try JSONDecoder().decode(SavedState.self,from: Data(contentsOf: file))
                guard (1...3).contains(loaded.version) else { throw ArchiveError.invalid(L("不支持的配置版本。")) }
                if !loaded.layouts.isEmpty { try validateLayouts(loaded.layouts) }
                state = loaded; state.version = 3
                if !validShortcuts(state.preferences.shortcuts) { state.preferences.shortcuts = Shortcut.defaults }
            }
            catch { storageReadOnly = true; tell(L("布局文件读取失败；原文件已保留。\(error.localizedDescription)"),error: true) }
        }
        refreshLogin()
        updateRunningApps()
        Localization.language = state.preferences.language
        if !messageIsError { message = L("先摆好窗口，再点“记住当前布局”。") }
        applyAppearance()
    }
    func start() {
        if demoMode { showWindow(); return }
        hotKeys.onAction = { [weak self] action in
            guard let self else { return }
            switch action { case .launch: self.launchAndRestore(); case .restore: _ = self.restore(manual: true); case .save: self.saveLayout() }
        }
        hotKeyErrors = hotKeys.configure(state.preferences.shortcuts,enabled: state.preferences.shortcutsEnabled)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group",accessibilityDescription: L("窗口记忆"))
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClick)
        statusItem.button?.sendAction(on: [.leftMouseUp,.rightMouseUp])
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self,selector: #selector(appLaunched(_:)),name: NSWorkspace.didLaunchApplicationNotification,object: nil)
        nc.addObserver(self,selector: #selector(appTerminated(_:)),name: NSWorkspace.didTerminateApplicationNotification,object: nil)
        nc.addObserver(self,selector: #selector(woke),name: NSWorkspace.didWakeNotification,object: nil)
        NotificationCenter.default.addObserver(self,selector: #selector(displaysChanged),name: NSApplication.didChangeScreenParametersNotification,object: nil)
        NotificationCenter.default.addObserver(self,selector: #selector(becameActive),name: NSApplication.didBecomeActiveNotification,object: nil)
        // Common modes keep permission feedback alive while a panel or menu is open.
        timer = Timer(timeInterval: 1,repeats: true) { [weak self] _ in self?.checkPermission() }
        RunLoop.main.add(timer!,forMode: .common)
        if permitted { attachAll(); scheduleEnvironmentRestore() }
        let first = !UserDefaults.standard.bool(forKey: "hasOpened")
        if first { UserDefaults.standard.set(true,forKey: "hasOpened") }
        let login = isLoginLaunch || CommandLine.arguments.contains("--simulate-login")
        if shouldShowWindowAtStartup(isLogin: login,background: CommandLine.arguments.contains("--background"),firstRun: first,showAtLogin: state.preferences.showWindowOnLogin) { showWindow() }
        if login && state.preferences.launchAppsOnLogin {
            DispatchQueue.main.asyncAfter(deadline: .now()+4) { [weak self] in self?.launchAndRestore() }
        }
    }
    private var isLoginLaunch: Bool {
        NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
    func tell(_ text: String, error: Bool = false) { message = text; messageIsError = error }
    @discardableResult
    func persist() -> Bool {
        if demoMode { return true }
        guard !storageReadOnly else { tell(L("原布局文件读取失败，已停止写入以保留原文件。请先备份并修复布局文件。"),error: true); return false }
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
        } catch { tell(L("无法保存布局：\(error.localizedDescription)"),error: true); return false }
    }
    func setPreference(_ key: WritableKeyPath<Preferences,Bool>, _ value: Bool) {
        state.preferences[keyPath: key] = value
        if key == \Preferences.shortcutsEnabled {
            hotKeyErrors = hotKeys.configure(state.preferences.shortcuts,enabled: value)
        }
        generation += 1
        persist()
    }
    func setAppearance(_ mode: AppearanceMode) {
        state.preferences.appearance = mode
        applyAppearance()
        persist()
    }
    private func applyAppearance() {
        switch state.preferences.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // AppKit owns the native appearance. Never leave a SwiftUI preferredColorScheme override.
        window?.appearance = nil
        window?.contentView?.appearance = nil
        window?.backgroundColor = NSColor.windowBackgroundColor
        refreshAppearance(window?.effectiveAppearance ?? NSApp.effectiveAppearance)
    }
    func refreshAppearance(_ appearance: NSAppearance) {
        let dark = appearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua
        if darkAppearance != dark { darkAppearance = dark }
    }
    func setLanguage(_ language: AppLanguage) {
        state.preferences.language = language
        Localization.language = language
        if persist() { tell(L("语言设置已更新。")) }
        window?.title = L("窗口记忆")
        permissionPanel?.title = L("窗口控制权限")
        statusItem?.button?.setAccessibilityLabel(L("窗口记忆"))
    }
    func updateRunningApps() {
        let next = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if next != runningBundleIDs { runningBundleIDs = next }
    }
    func launchAndRestore() {
        if demoMode { tell(L("示例模式：不会打开或移动真实 App。")); return }
        guard !launching, let layout = current else { tell(L("请先保存当前屏幕组合的布局。"),error: true); return }
        let apps = launchTargets(layout.windows,rules: layout.launchRules)
        guard !apps.isEmpty else { tell(L("没有勾选需要启动的 App。"),error: true); return }
        displayWork?.cancel()
        generation += 1
        launchToken = UUID()
        let token = launchToken!
        launching = true; launchFailures = []
        handled = [:]
        _ = restore(manual: true)
        tell(L("正在启动布局中的 \(apps.count) 个 App…"))
        openNext(apps,index: 0,token: token,layoutID: layout.id,opened: 0,alreadyRunning: 0)
    }
    func cancelLaunch() {
        launchToken = nil; activeLaunchRequest = nil; launching = false; launchProgress = ""
        tell(L("已取消后续启动与归位。已经打开的 App 会保留。"))
    }
    private func openNext(_ apps: [LaunchTarget], index: Int, token: UUID, layoutID: String, opened: Int, alreadyRunning: Int) {
        guard launchToken == token else { return }
        guard current?.id == layoutID else { cancelLaunch(); return }
        guard index < apps.count else {
            launching = false; launchProgress = ""
            updateRunningApps()
            if !launchFailures.isEmpty { tell(L("已发起 \(opened) 个 App 的启动，\(alreadyRunning) 个已在运行；部分 App 无法打开。"),error: true) }
            else if !permitted { tell(L("App 已打开。开启窗口控制权限后可恢复布局。"),error: true) }
            else { tell(L("\(opened) 个 App 已打开，\(alreadyRunning) 个已在运行；窗口出现后自动归位。")) }
            return
        }
        let target = apps[index]
        guard current?.windows.contains(where: { $0.bundleID == target.id && $0.enabled }) == true else {
            openNext(apps,index: index+1,token: token,layoutID: layoutID,opened: opened,alreadyRunning: alreadyRunning)
            return
        }
        launchProgress = "\(index+1) / \(apps.count) · \(target.name)"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: target.id).first
        if let running, !WindowAccess.windows(for: running).isEmpty {
            scheduleManualRestore(target.id,pid: running.processIdentifier,token: token,layoutID: layoutID,timeout: target.windowTimeout)
            DispatchQueue.main.asyncAfter(deadline: .now()+target.delay) { [weak self] in
                self?.openNext(apps,index: index+1,token: token,layoutID: layoutID,opened: opened,alreadyRunning: alreadyRunning+1)
            }
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.id) else {
            launchFailures.append(L("\(target.name)：未找到已安装的 App"))
            openNext(apps,index: index+1,token: token,layoutID: layoutID,opened: opened,alreadyRunning: alreadyRunning)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = false
        let request = UUID()
        activeLaunchRequest = request
        DispatchQueue.main.asyncAfter(deadline: .now()+20) { [weak self] in
            guard let self, self.launchToken == token, self.activeLaunchRequest == request else { return }
            self.activeLaunchRequest = nil
            self.launchFailures.append(L("\(target.name)：启动响应超时，可稍后重试"))
            self.openNext(apps,index: index+1,token: token,layoutID: layoutID,opened: opened,alreadyRunning: alreadyRunning)
        }
        NSWorkspace.shared.openApplication(at: url,configuration: configuration) { [weak self] app,error in
            DispatchQueue.main.async {
                guard let self, self.launchToken == token, self.current?.id == layoutID, self.activeLaunchRequest == request else { return }
                self.activeLaunchRequest = nil
                if let app {
                    self.attach(app)
                    self.scheduleManualRestore(target.id,pid: app.processIdentifier,token: token,layoutID: layoutID,timeout: target.windowTimeout)
                } else { self.launchFailures.append(L("\(target.name)：\(error?.localizedDescription ?? L("启动失败"))")) }
                DispatchQueue.main.asyncAfter(deadline: .now()+target.delay) {
                    self.openNext(apps,index: index+1,token: token,layoutID: layoutID,opened: opened+(app == nil ? 0 : 1),alreadyRunning: alreadyRunning)
                }
            }
        }
    }
    private func scheduleManualRestore(_ id: String, pid: pid_t, token: UUID, layoutID: String, timeout: Double) {
        let delays = windowRetryDelays(timeout: timeout)
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now()+delay) { [weak self] in
                guard let self, self.launchToken == token, self.current?.id == layoutID,
                      NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == id else { return }
                _ = self.restore(appID: id,onlyUnhandled: true,manual: true,recordUndo: false,reportEmpty: false)
            }
        }
    }
    func setSlot(_ id: UUID, enabled: Bool) {
        guard let sceneID = current?.id, let p = state.layouts.firstIndex(where: { $0.id == sceneID }),
              let w = state.layouts[p].windows.firstIndex(where: { $0.id == id }) else { return }
        state.layouts[p].windows[w].enabled = enabled
        persist()
    }
    func saveLayout() {
        if demoMode { tell(L("示例模式：布局仅用于界面展示。")); return }
        guard permitted else { showPermissionGuide(); return }
        guard !busy else { return }
        busy = true; isSaving = true; generation += 1; launchToken = nil; launching = false
        defer { busy = false; isSaving = false }
        monitors = WindowAccess.monitors()
        let live = WindowAccess.allWindows()
        let oldEnabled = Dictionary(grouping: current?.windows ?? [],by: \.bundleID).mapValues { $0.contains(where: \.enabled) }
        let slots: [WindowSlot] = live.compactMap { w in
            guard let screen = WindowAccess.monitor(for: w.frame,in: monitors) else { return nil }
            return WindowSlot(bundleID: w.bundleID,appName: w.appName,title: w.title,monitorID: screen.id,
                              relative: w.frame.relative(to: screen.visible),enabled: oldEnabled[w.bundleID] ?? true)
        }
        guard !slots.isEmpty else { tell(L("没有找到可保存的普通窗口。请先打开 App 窗口，并退出全屏或最小化。"),error: true); return }
        let key = layoutKey(monitors)
        let layout = Layout(id: current?.id ?? UUID().uuidString,name: current?.name ?? L("默认场景"),updatedAt: Date(),monitors: monitors,windows: slots,launchRules: current?.launchRules ?? [])
        if let i = state.layouts.firstIndex(where: { $0.id == layout.id }) { state.layouts[i] = layout }
        else { state.layouts.append(layout) }
        state.activeLayouts[key] = layout.id
        for app in NSWorkspace.shared.runningApplications {
            handled[app.processIdentifier] = Set(WindowAccess.windows(for: app).map { CFHash($0.element) })
        }
        if persist() { tell(L("已记住 \(Set(slots.map(\.bundleID)).count) 个 App、\(slots.count) 个窗口的位置。")) }
    }
    @discardableResult
    func restore(appID: String? = nil, onlyUnhandled: Bool = false, manual: Bool = false, recordUndo: Bool = true, reportEmpty: Bool = true) -> Int {
        guard !demoMode, permitted, !busy, !isSaving else { return 0 }
        guard manual || (state.preferences.automatic && Date() > automaticSuspendedUntil) else { return 0 }
        guard let layout = current else {
            if manual { tell(L("这套屏幕还没有保存布局。请先点“记住当前布局”。")) }
            return 0
        }
        busy = true; defer { busy = false }
        var moved = 0, failed = 0
        let slots = layout.windows.filter { $0.enabled && (appID == nil || $0.bundleID == appID) }
        let grouped = Dictionary(grouping: slots,by: \.bundleID)
        if manual && recordUndo { undoFrames = [] }
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, let saved = grouped[id] else { continue }
            let windows = WindowAccess.windows(for: app)
            let pairs = matchWindows(savedTitles: saved.map(\.title),liveTitles: windows.map(\.title))
            for (s,l) in pairs {
                let w = windows[l], slot = saved[s], hash = CFHash(w.element)
                if onlyUnhandled && handled[app.processIdentifier,default: []].contains(hash) { continue }
                guard let screen = monitors.first(where: { $0.id == slot.monitorID }) else { continue }
                if manual && recordUndo { undoFrames.append((w,w.frame)) }
                if WindowAccess.move(w,to: slot.relative.placed(in: screen.visible)) {
                    moved += 1; handled[app.processIdentifier,default: []].insert(hash)
                } else { failed += 1 }
            }
        }
        if moved > 0 || failed > 0 || (manual && reportEmpty) {
            if failed > 0 { tell(L("已恢复 \(moved) 个窗口；\(failed) 个窗口受 App 尺寸限制或系统权限影响。"),error: true) }
            else if moved == 0 { tell(L("暂时没有可恢复的窗口。请打开已保存的 App，并退出全屏或最小化。")) }
            else { tell(L("已恢复 \(moved) 个窗口 · \(Date().formatted(date: .omitted,time: .shortened))")) }
        }
        return moved
    }
    func undo() {
        guard !undoFrames.isEmpty else { tell(L("还没有可撤销的手动恢复。")); return }
        automaticSuspendedUntil = Date().addingTimeInterval(10)
        generation += 1; launchToken = nil; launching = false
        var count = 0
        for (w,f) in undoFrames { if WindowAccess.move(w,to: f) { count += 1 } }
        undoFrames = []; tell(L("已撤销，\(count) 个窗口回到恢复前的位置。"))
    }
    func deleteCurrent() {
        guard let layout = current else { return }
        let alert = NSAlert()
        alert.messageText = L("删除当前场景“\(layout.name)”？")
        alert.informativeText = L("不会改变当前窗口位置。其他场景与屏幕组合的布局会保留。")
        alert.addButton(withTitle: L("忘记布局")); alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.layouts.removeAll { $0.id == layout.id }; generation += 1; launchToken = nil; launching = false
        if persist() { tell(L("已忘记当前布局。")) }
    }
    @objc private func becameActive() { checkPermission() }
    func checkPermission() {
        if demoMode { return }
        let now = WindowAccess.trusted
        if permissionPanel?.isVisible == true { permissionChecks += 1 }
        if now != permitted {
            permitted = now
            if now { attachAll(); tell(L("权限已开启。把窗口摆好后，点“记住当前布局”。")) }
            else {
                for observer in observers.values { CFRunLoopRemoveSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes) }
                observers = [:]; handled = [:]
                tell(L("窗口控制权限已关闭，自动恢复已停止。"),error: true)
            }
        }
        // Some apps are not ready to accept AX notifications immediately after launching.
        if now { attachAll() }
        refreshLogin()
        updateRunningApps()
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
        updateRunningApps()
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        attach(app)
        guard state.preferences.onLaunch, let id = app.bundleIdentifier else { return }
        scheduleApp(id,pid: app.processIdentifier)
    }
    @objc private func appTerminated(_ note: Notification) {
        updateRunningApps()
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
        let timeout = current?.launchRules.first(where: { $0.bundleID == id })?.windowTimeout ?? 30
        for delay in windowRetryDelays(timeout: timeout) {
            DispatchQueue.main.asyncAfter(deadline: .now()+delay) { [weak self] in
                guard let self, self.generation == token, NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == id else { return }
                if let app = NSRunningApplication(processIdentifier: pid) { self.attach(app) }
                _ = self.restore(appID: id,onlyUnhandled: true)
            }
        }
    }
    @objc private func displaysChanged() {
        generation += 1; launchToken = nil; launching = false
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
            if loginNeedsApproval { SMAppService.openSystemSettingsLoginItems(); tell(L("请在系统设置中允许“窗口记忆”登录时打开。")) }
        } catch { refreshLogin(); tell(L("登录启动设置失败：\(error.localizedDescription)"),error: true) }
    }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1020,height: 790),styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing: .buffered,defer: false)
            w.title = L("窗口记忆")
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.minSize = NSSize(width: 900,height: 650)
            w.isReleasedWhenClosed = false
            let host = AppearanceHostingView(rootView: MainView(model: self))
            host.onAppearanceChange = { [weak self] appearance in self?.refreshAppearance(appearance) }
            w.contentView = host
            w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func statusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            for (title,action) in [(L("打开窗口记忆"),#selector(openPanel)),(L("启动布局 App 并恢复"),#selector(launchFromMenu)),(L("记住当前布局"),#selector(saveFromMenu)),(L("立即恢复"),#selector(restoreFromMenu)),(L("设置…"),#selector(settingsFromMenu)),(state.preferences.automatic ? L("暂停自动恢复") : L("继续自动恢复"),#selector(toggleAutomatic)),(L("退出窗口记忆"),#selector(quit))] {
                let item = NSMenuItem(title: title,action: action,keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else { showWindow() }
    }
    @objc private func openPanel() { showWindow() }
    @objc private func saveFromMenu() { saveLayout() }
    @objc private func restoreFromMenu() { _ = restore(manual: true) }
    @objc private func launchFromMenu() { launchAndRestore() }
    @objc private func settingsFromMenu() { selectedPage = "settings"; showWindow() }
    @objc private func toggleAutomatic() { setPreference(\.automatic,!state.preferences.automatic) }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension Controller {
    @discardableResult
    func selectScene(_ id: String) -> Bool {
        guard scenes.contains(where: { $0.id == id }) else { return false }
        launchToken = nil; launching = false; displayWork?.cancel(); generation += 1; handled = [:]; undoFrames = []
        state.activeLayouts[layoutKey(monitors)] = id
        if persist() { tell(L("已选择“\(current?.name ?? "")”，可立即恢复或启动此场景。")); return true }
        return false
    }
    private func askName(title: String, initial: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        alert.informativeText = L("同一套屏幕可以保存多个工作场景。新场景以当前已保存的布局为起点。")
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0,y: 0,width: 300,height: 25)
        alert.accessoryView = field; alert.addButton(withTitle: L("保存")); alert.addButton(withTitle: L("取消"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { tell(L("场景名称应为 1–100 个字符。"),error: true); return nil }
        return name
    }
    func newScene() {
        guard let name = askName(title: L("新建场景"),initial: L("新场景")) else { return }
        let layout = Layout(id: UUID().uuidString,name: name,updatedAt: Date(),monitors: monitors,windows: current?.windows ?? [],launchRules: current?.launchRules ?? [])
        state.layouts.append(layout); selectScene(layout.id)
    }
    func renameScene() {
        guard let layout = current, let name = askName(title: L("重命名场景"),initial: layout.name), let index = state.layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        state.layouts[index].name = name
        if persist() { tell(L("场景已重命名为“\(name)”。")) }
    }
    func changeLaunchOrder(_ id: String, by offset: Int) {
        guard let layout = current, let p = state.layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        var ordered = launchTargets(layout.windows,rules: layout.launchRules)
        guard let i = ordered.firstIndex(where: { $0.id == id }), ordered.indices.contains(i+offset) else { return }
        ordered.swapAt(i,i+offset)
        let disabled = layout.launchRules.filter { rule in !ordered.contains { $0.id == rule.bundleID } }
        state.layouts[p].launchRules = ordered.map { LaunchRule(bundleID: $0.id,delay: $0.delay,windowTimeout: $0.windowTimeout) } + disabled
        persist()
    }
    func setLaunchTiming(_ id: String, delay: Double? = nil, timeout: Double? = nil) {
        guard let layout = current, let p = state.layouts.firstIndex(where: { $0.id == layout.id }),
              delay.map({ $0.isFinite && (0...120).contains($0) }) ?? true,
              timeout.map({ $0.isFinite && (1...120).contains($0) }) ?? true else { return }
        var rule = layout.launchRules.first { $0.bundleID == id } ?? LaunchRule(bundleID: id)
        if let delay { rule.delay = delay }; if let timeout { rule.windowTimeout = timeout }
        if let i = state.layouts[p].launchRules.firstIndex(where: { $0.bundleID == id }) { state.layouts[p].launchRules[i] = rule }
        else {
            let active = launchTargets(layout.windows,rules: layout.launchRules)
            state.layouts[p].launchRules = active.map { $0.id == id ? rule : LaunchRule(bundleID: $0.id,delay: $0.delay,windowTimeout: $0.windowTimeout) }
                + layout.launchRules.filter { old in !active.contains { $0.id == old.bundleID } }
        }
        persist()
    }
    func setShortcut(_ action: ShortcutAction, keyCode: UInt32? = nil, modifiers: UInt32? = nil) {
        var next = state.preferences.shortcuts
        guard let i = next.firstIndex(where: { $0.action == action }) else { return }
        if let keyCode { next[i].keyCode = keyCode }; if let modifiers { next[i].modifiers = modifiers }
        guard validShortcuts(next) else { hotKeyErrors = [L("快捷键重复，请给每个操作选择不同的组合。")]; return }
        let errors = demoMode ? [] : hotKeys.configure(next,enabled: state.preferences.shortcutsEnabled)
        guard errors.isEmpty else {
            hotKeyErrors = errors
            _ = hotKeys.configure(state.preferences.shortcuts,enabled: state.preferences.shortcutsEnabled)
            return
        }
        hotKeyErrors = []; state.preferences.shortcuts = next; persist()
    }
    func exportLayouts(currentOnly: Bool = false) {
        let layouts = currentOnly ? current.map { [$0] } ?? [] : state.layouts
        guard !layouts.isEmpty else { tell(L("没有可导出的场景。"),error: true); return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "WindowMemory-\(currentOnly ? "scene" : "layouts").json"
        panel.title = L("导出布局与启动配置")
        panel.message = L("文件包含窗口标题、App 清单与屏幕信息。请妥善保存。")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            try encoder.encode(LayoutArchive(layouts: layouts)).write(to: url,options: .atomic)
            tell(L("已导出 \(layouts.count) 个场景。"))
        } catch { tell(L("导出失败：\(error.localizedDescription)"),error: true) }
    }
    func importLayouts() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.title = L("导入场景"); panel.message = L("支持导出的布局文件或旧版 layouts.json；以新增方式导入，不覆盖已有场景。")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 5_000_000 else { throw ArchiveError.invalid(L("文件超过 5 MB。")) }
            var imported = try decodeLayouts(Data(contentsOf: url))
            if imported.contains(where: { $0.screenKey != layoutKey(monitors) }) {
                let alert = NSAlert(); alert.messageText = L("为导入场景匹配屏幕")
                alert.informativeText = L("跨 Mac 导入时可将所有导入场景绑定到当前屏幕组合。请选择每个原屏幕对应的目标；也可以保留原绑定，待连接原屏幕后使用。")
                var unique: [Monitor] = []
                for screen in imported.flatMap(\.monitors) where !unique.contains(where: { $0.id == screen.id }) { unique.append(screen) }
                guard unique.count <= 16 else { throw ArchiveError.invalid(L("原屏幕过多，请分批导入。")) }
                let view = NSView(frame: NSRect(x: 0,y: 0,width: 440,height: unique.count*34))
                var pickers: [NSPopUpButton] = []
                for (i,screen) in unique.enumerated() {
                    let y = CGFloat((unique.count-i-1)*34)
                    let label = NSTextField(labelWithString: "\(screen.name) · \(screen.id.prefix(6))")
                    label.frame = NSRect(x: 0,y: y+3,width: 220,height: 24); label.lineBreakMode = .byTruncatingTail; view.addSubview(label)
                    let picker = NSPopUpButton(frame: NSRect(x: 225,y: y,width: 210,height: 28))
                    picker.addItems(withTitles: monitors.enumerated().map { "\($0.offset+1). \($0.element.name)" })
                    let preferred = monitors.firstIndex(where: { $0.id == screen.id }) ?? monitors.firstIndex(where: { $0.name == screen.name }) ?? min(i,max(0,monitors.count-1))
                    picker.selectItem(at: preferred); view.addSubview(picker); pickers.append(picker)
                }
                alert.accessoryView = view; alert.addButton(withTitle: L("映射到当前屏幕")); alert.addButton(withTitle: L("保留原绑定")); alert.addButton(withTitle: L("取消"))
                let response = alert.runModal()
                if response == .alertThirdButtonReturn { return }
                if response == .alertFirstButtonReturn {
                    var mapping: [String:String] = [:]
                    for (i,screen) in unique.enumerated() {
                        guard monitors.indices.contains(pickers[i].indexOfSelectedItem) else { throw ArchiveError.invalid(L("没有可用的目标屏幕。")) }
                        mapping[screen.id] = monitors[pickers[i].indexOfSelectedItem].id
                    }
                    imported = try imported.map { try remapLayout($0,to: monitors,mapping: mapping) }
                }
            }
            for index in imported.indices { imported[index].id = UUID().uuidString; imported[index].name += L("（导入）") }
            let existingKeys = Set(state.layouts.map(\.screenKey))
            state.layouts.append(contentsOf: imported)
            for layout in imported where !existingKeys.contains(layout.screenKey) { state.activeLayouts[layout.screenKey] = "" }
            if persist() { tell(L("已新增导入 \(imported.count) 个场景。请在场景选择器中选择；导入不会自动启动 App。")) }
        } catch { tell(L("导入失败：\(error.localizedDescription)"),error: true) }
    }
}
