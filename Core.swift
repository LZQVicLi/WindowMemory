import Foundation

struct Frame: Codable, Equatable {
    var x: Double; var y: Double; var width: Double; var height: Double
    init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    func relative(to screen: Frame) -> Frame {
        Frame(x: (x-screen.x)/screen.width, y: (y-screen.y)/screen.height,
              width: width/screen.width, height: height/screen.height)
    }
    func placed(in screen: Frame) -> Frame {
        let w = min(screen.width, max(80, width*screen.width))
        let h = min(screen.height, max(60, height*screen.height))
        return Frame(x: min(max(screen.x, screen.x+x*screen.width), screen.x+screen.width-w),
                     y: min(max(screen.y, screen.y+y*screen.height), screen.y+screen.height-h),
                     width: w, height: h)
    }
}

struct Monitor: Codable, Identifiable {
    var id: String
    var name: String
    var bounds: Frame
    var visible: Frame
}

struct WindowSlot: Codable, Identifiable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var title: String
    var monitorID: String
    var relative: Frame
    var enabled = true
}

struct Layout: Codable, Identifiable {
    var id: String
    var name: String
    var updatedAt: Date
    var monitors: [Monitor]
    var windows: [WindowSlot]
    var launchRules: [LaunchRule] = []
    var screenKey: String { layoutKey(monitors) }

    init(id: String, name: String, updatedAt: Date, monitors: [Monitor], windows: [WindowSlot], launchRules: [LaunchRule] = []) {
        self.id = id; self.name = name; self.updatedAt = updatedAt; self.monitors = monitors; self.windows = windows; self.launchRules = launchRules
    }
    enum CodingKeys: String, CodingKey { case id, name, updatedAt, monitors, windows, launchRules }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self,forKey: .id); name = try c.decode(String.self,forKey: .name)
        updatedAt = try c.decode(Date.self,forKey: .updatedAt)
        monitors = try c.decode([Monitor].self,forKey: .monitors); windows = try c.decode([WindowSlot].self,forKey: .windows)
        launchRules = try c.decodeIfPresent([LaunchRule].self,forKey: .launchRules) ?? []
    }
}

struct LaunchRule: Codable, Equatable {
    var bundleID: String
    var delay: Double = 0.5
    var windowTimeout: Double = 30
}

enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case launch, restore, save
    var id: String { rawValue }
    var title: String { switch self { case .launch: return "启动当前场景"; case .restore: return "恢复当前场景"; case .save: return "记住当前布局" } }
}
struct Shortcut: Codable, Equatable, Identifiable {
    var action: ShortcutAction
    var keyCode: UInt32
    var modifiers: UInt32 = 6400
    var id: String { action.rawValue }
    static let keys: [(String,UInt32)] = [("↩",36),("R",15),("S",1),("W",13),("1",18),("2",19),("3",20),("4",21),("5",23),("6",22),("Space",49)]
    static let modifierChoices: [(String,UInt32)] = [("⌃⌥⌘",6400),("⌃⌥",6144),("⌃⇧⌘",4864),("⌥⇧⌘",2816)]
    static let defaults = [Shortcut(action: .launch,keyCode: 36),Shortcut(action: .restore,keyCode: 15),Shortcut(action: .save,keyCode: 1)]
    var label: String { (Self.modifierChoices.first { $0.1 == modifiers }?.0 ?? "?") + (Self.keys.first { $0.1 == keyCode }?.0 ?? "?") }
}
func validShortcuts(_ values: [Shortcut]) -> Bool {
    Set(values.map { "\($0.modifiers):\($0.keyCode)" }).count == values.count &&
    Set(values.map(\.action)).count == values.count && values.count == ShortcutAction.allCases.count &&
    values.allSatisfy { item in Shortcut.keys.contains { $0.1 == item.keyCode } && Shortcut.modifierChoices.contains { $0.1 == item.modifiers } }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" }
    }
}

struct Preferences: Codable {
    var automatic = true
    var onLaunch = true
    var onNewWindow = true
    var onDisplay = true
    var onWake = true
    var showWindowOnLogin = true
    var launchAppsOnLogin = false
    var appearance: AppearanceMode = .dark
    var shortcutsEnabled = true
    var shortcuts = Shortcut.defaults

    init() {}
    enum CodingKeys: String, CodingKey {
        case automatic, onLaunch, onNewWindow, onDisplay, onWake, showWindowOnLogin, launchAppsOnLogin, appearance, shortcutsEnabled, shortcuts
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        automatic = try c.decodeIfPresent(Bool.self,forKey: .automatic) ?? true
        onLaunch = try c.decodeIfPresent(Bool.self,forKey: .onLaunch) ?? true
        onNewWindow = try c.decodeIfPresent(Bool.self,forKey: .onNewWindow) ?? true
        onDisplay = try c.decodeIfPresent(Bool.self,forKey: .onDisplay) ?? true
        onWake = try c.decodeIfPresent(Bool.self,forKey: .onWake) ?? true
        showWindowOnLogin = try c.decodeIfPresent(Bool.self,forKey: .showWindowOnLogin) ?? true
        launchAppsOnLogin = try c.decodeIfPresent(Bool.self,forKey: .launchAppsOnLogin) ?? false
        appearance = try c.decodeIfPresent(AppearanceMode.self,forKey: .appearance) ?? .dark
        shortcutsEnabled = try c.decodeIfPresent(Bool.self,forKey: .shortcutsEnabled) ?? true
        shortcuts = try c.decodeIfPresent([Shortcut].self,forKey: .shortcuts) ?? Shortcut.defaults
    }
}

struct SavedState: Codable {
    var version = 3
    var preferences = Preferences()
    var layouts: [Layout] = []
    var activeLayouts: [String:String] = [:]
    init(version: Int = 3, preferences: Preferences = Preferences(), layouts: [Layout] = [], activeLayouts: [String:String] = [:]) {
        self.version = version; self.preferences = preferences; self.layouts = layouts; self.activeLayouts = activeLayouts
    }
    enum CodingKeys: String, CodingKey { case version,preferences,layouts,activeLayouts }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self,forKey: .version) ?? 1
        preferences = try c.decodeIfPresent(Preferences.self,forKey: .preferences) ?? Preferences()
        layouts = try c.decode([Layout].self,forKey: .layouts)
        activeLayouts = try c.decodeIfPresent([String:String].self,forKey: .activeLayouts) ?? [:]
    }
}

func selectedLayout(in state: SavedState, screenKey: String) -> Layout? {
    let layouts = state.layouts.filter { $0.screenKey == screenKey }
    let selected = state.activeLayouts[screenKey]
    if selected == "" { return nil }
    return layouts.first { $0.id == selected } ?? layouts.first
}

struct LaunchTarget: Identifiable, Equatable {
    var id: String
    var name: String
    var delay: Double = 0.5
    var windowTimeout: Double = 30
}

func launchTargets(_ slots: [WindowSlot], rules: [LaunchRule] = []) -> [LaunchTarget] {
    var seen = Set<String>()
    let unique: [LaunchTarget] = slots.compactMap {
        guard $0.enabled, !$0.bundleID.isEmpty, seen.insert($0.bundleID).inserted else { return nil }
        return LaunchTarget(id: $0.bundleID,name: $0.appName)
    }
    let ordered = rules.map(\.bundleID) + unique.map(\.id).filter { id in !rules.contains { $0.bundleID == id } }
    return ordered.compactMap { id in
        guard var target = unique.first(where: { $0.id == id }) else { return nil }
        if let rule = rules.first(where: { $0.bundleID == id }) {
            target.delay = rule.delay; target.windowTimeout = rule.windowTimeout
        }
        return target
    }
}

func windowRetryDelays(timeout: Double) -> [Double] {
    let limit = min(120,max(1,timeout.isFinite ? timeout : 30))
    return Array(Set([0.5,1.5,4.0,9.0,18.0,30.0,45.0,60.0,90.0,120.0].filter { $0 <= limit } + [limit])).sorted()
}

func shouldShowWindowAtStartup(isLogin: Bool, background: Bool, firstRun: Bool, showAtLogin: Bool) -> Bool {
    if firstRun { return true }
    if background { return false }
    return !isLogin || showAtLogin
}

func layoutKey(_ monitors: [Monitor]) -> String { monitors.map(\.id).sorted().joined(separator: "|") }

// One-to-one assignment prevents several windows being restored into the same slot.
// Exact titles win. Empty/changing titles fall back to the app's window order.
func matchWindows(savedTitles: [String], liveTitles: [String]) -> [(Int, Int)] {
    var usedSaved = Set<Int>(), usedLive = Set<Int>(), result: [(Int, Int)] = []
    func add(_ s: Int, _ l: Int) {
        usedSaved.insert(s); usedLive.insert(l); result.append((s,l))
    }
    for s in savedTitles.indices where !savedTitles[s].isEmpty {
        if let l = liveTitles.indices.first(where: { !usedLive.contains($0) && liveTitles[$0] == savedTitles[s] }) {
            add(s,l)
        }
    }
    for s in savedTitles.indices where !usedSaved.contains(s) && savedTitles[s].count >= 5 {
        let candidates = liveTitles.indices.filter {
            !usedLive.contains($0) && liveTitles[$0].count >= 5 &&
            (liveTitles[$0].contains(savedTitles[s]) || savedTitles[s].contains(liveTitles[$0]))
        }
        if candidates.count == 1 { add(s,candidates[0]) }
    }
    for s in savedTitles.indices where !usedSaved.contains(s) {
        if let l = liveTitles.indices.first(where: { !usedLive.contains($0) }) { add(s,l) }
    }
    return result
}

func runSelfTests() {
    func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError("FAIL: \(label)") }
        print("PASS: \(label)")
    }
    let left = Frame(x: -1920, y: -300, width: 1920, height: 1080)
    let window = Frame(x: -1800, y: -200, width: 900, height: 600)
    let restored = window.relative(to: left).placed(in: left)
    check(abs(restored.x-window.x) < 0.001 && abs(restored.y-window.y) < 0.001 && abs(restored.width-window.width) < 0.001, "negative monitor coordinates round-trip")
    let right = Frame(x: 2560, y: 0, width: 3840, height: 2160)
    let scaled = window.relative(to: left).placed(in: right)
    check(scaled.width == 1800 && scaled.height == 1200 && scaled.x == 2800, "resolution changes preserve proportions")
    let oversized = Frame(x: -1, y: 2, width: 5, height: 5).placed(in: left)
    check(oversized == left, "oversized/off-screen frames are contained")
    let matches = matchWindows(savedTitles: ["Project A", "Project B"], liveTitles: ["Project B", "Project A"])
    check(matches.contains(where: { $0 == (0,1) }) && matches.contains(where: { $0 == (1,0) }), "multiple app windows match by title")
    let fewer = matchWindows(savedTitles: ["A","B","C"], liveTitles: ["new"])
    check(fewer.count == 1 && Set(fewer.map { $0.1 }).count == 1, "never reuse one live window")
    let changing = matchWindows(savedTitles: ["Project Alpha"], liveTitles: ["Project Alpha — edited"])
    check(changing.first?.1 == 0, "changing title partial match")
    let duplicate = matchWindows(savedTitles: ["","",""], liveTitles: ["",""])
    check(duplicate.count == 2 && Set(duplicate.map { $0.1 }).count == 2, "empty titles still get unique slots")
    let m1 = Monitor(id: "b", name: "Right", bounds: right, visible: right)
    let m2 = Monitor(id: "a", name: "Left", bounds: left, visible: left)
    check(layoutKey([m1,m2]) == layoutKey([m2,m1]), "monitor ordering does not change profile")
    check(layoutKey([m1]) != layoutKey([m1,m2]), "different display combinations have separate profiles")
    let state = SavedState(layouts: [Layout(id: "a|b", name: "双屏", updatedAt: Date(), monitors: [m1,m2], windows: [WindowSlot(bundleID: "test.app", appName: "Test", title: "", monitorID: "a", relative: window.relative(to: left))])])
    let data = try! JSONEncoder().encode(state)
    let decoded = try! JSONDecoder().decode(SavedState.self, from: data)
    check(decoded.layouts.first?.windows.first?.bundleID == "test.app", "layout JSON round-trip")
    let oldJSON = Data(#"{"automatic":false,"onLaunch":true,"onNewWindow":false,"onDisplay":true,"onWake":true}"#.utf8)
    let migrated = try! JSONDecoder().decode(Preferences.self,from: oldJSON)
    check(!migrated.automatic && !migrated.onNewWindow && migrated.onWake, "upgrade preserves existing preferences")
    check(migrated.showWindowOnLogin && !migrated.launchAppsOnLogin && migrated.appearance == .dark, "new preferences get safe migration defaults")
    var preferences = Preferences(); preferences.appearance = .light; preferences.showWindowOnLogin = false
    let preferencesRoundTrip = try! JSONDecoder().decode(Preferences.self,from: JSONEncoder().encode(preferences))
    check(preferencesRoundTrip.appearance == .light && !preferencesRoundTrip.showWindowOnLogin, "theme and login options persist")
    var first = state.layouts[0].windows[0]
    var second = first; second.id = UUID(); second.title = "Another window"
    var disabled = first; disabled.id = UUID(); disabled.bundleID = "disabled.app"; disabled.enabled = false
    first.enabled = true
    let targets = launchTargets([first,second,disabled])
    check(targets.count == 1 && targets[0].id == "test.app", "one launch per app and disabled apps excluded")
    check(launchTargets([disabled]).isEmpty, "disabled-only layout launches nothing")
    check(shouldShowWindowAtStartup(isLogin: true,background: false,firstRun: false,showAtLogin: true), "login can show control panel")
    check(!shouldShowWindowAtStartup(isLogin: true,background: false,firstRun: false,showAtLogin: false), "login can run quietly")
    check(shouldShowWindowAtStartup(isLogin: false,background: false,firstRun: false,showAtLogin: false), "manual launch always shows control panel")
    check(!shouldShowWindowAtStartup(isLogin: false,background: true,firstRun: false,showAtLogin: true), "background flag avoids foreground window")
    check(shouldShowWindowAtStartup(isLogin: true,background: true,firstRun: true,showAtLogin: false), "first run shows onboarding")
    print("Core checks passed.")
    runFeatureTests()
}
