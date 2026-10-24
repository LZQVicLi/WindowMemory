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

    init() {}
    enum CodingKeys: String, CodingKey {
        case automatic, onLaunch, onNewWindow, onDisplay, onWake, showWindowOnLogin, launchAppsOnLogin, appearance
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
    }
}

struct SavedState: Codable {
    var version = 2
    var preferences = Preferences()
    var layouts: [Layout] = []
}

struct LaunchTarget: Identifiable, Equatable {
    var id: String
    var name: String
}

func launchTargets(_ slots: [WindowSlot]) -> [LaunchTarget] {
    var seen = Set<String>()
    return slots.compactMap {
        guard $0.enabled, !$0.bundleID.isEmpty, seen.insert($0.bundleID).inserted else { return nil }
        return LaunchTarget(id: $0.bundleID,name: $0.appName)
    }
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
    print("All 20 self-tests passed.")
}
