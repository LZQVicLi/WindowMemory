import Foundation

func runFeatureTests() {
    var count = 0
    func check(_ value: @autoclosure () -> Bool, _ text: String) {
        guard value() else { fatalError("FAIL: \(text)") }; count += 1; print("PASS: \(text)")
    }
    func rejects(_ data: Data) -> Bool { do { _ = try decodeLayouts(data); return false } catch { return true } }
    let encoder = JSONEncoder()
    let sample = sampleState()
    let work = sample.layouts[0]
    check(sample.layouts.count == 3 && Set(sample.layouts.map(\.id)).count == 3, "multiple named scenes have distinct identities")
    check(Set(sample.layouts.map(\.screenKey)).count == 1, "several scenes share one display combination")
    check(sample.activeLayouts[work.screenKey] == work.id, "active scene is stored per display combination")
    let archive = try! encoder.encode(LayoutArchive(layouts: sample.layouts))
    let decoded = try! decodeLayouts(archive)
    check(decoded.count == 3 && decoded[0].launchRules == work.launchRules, "archive round-trip preserves launch rules and scenes")
    let roundTrip = try! JSONDecoder().decode(SavedState.self,from: encoder.encode(sample))
    check(roundTrip.activeLayouts == sample.activeLayouts, "scene selection survives restart")
    var old = try! JSONSerialization.jsonObject(with: encoder.encode(sample)) as! [String:Any]
    old.removeValue(forKey: "activeLayouts"); old["version"] = 2
    var oldLayouts = old["layouts"] as! [[String:Any]]
    for i in oldLayouts.indices { oldLayouts[i].removeValue(forKey: "launchRules") }; old["layouts"] = oldLayouts
    let oldData = try! JSONSerialization.data(withJSONObject: old)
    check((try! decodeLayouts(oldData))[0].windows.count == 4, "v1.1 backup imports without lost windows")
    check((try! JSONDecoder().decode(SavedState.self,from: oldData)).activeLayouts.isEmpty, "legacy active scene migration defaults safely")
    let rules = [LaunchRule(bundleID: "com.apple.Terminal",delay: 7,windowTimeout: 90),LaunchRule(bundleID: "com.apple.Safari",delay: 2)]
    let targets = launchTargets(work.windows,rules: rules)
    check(targets[0].id == "com.apple.Terminal" && targets[1].id == "com.apple.Safari", "launch order follows per-app configuration")
    check(targets[0].delay == 7 && targets[0].windowTimeout == 90, "launch timing survives planning")
    check(targets.count == 4, "unconfigured apps appended exactly once")
    var slots = work.windows; slots[2].enabled = false
    check(!launchTargets(slots,rules: rules).contains { $0.id == "com.apple.Terminal" }, "disabled apps excluded even when ordered")
    let targetScreen = Monitor(id: "new-monitor",name: "New display",bounds: work.monitors[0].bounds,visible: work.monitors[0].visible)
    let mapping = Dictionary(uniqueKeysWithValues: work.monitors.map { ($0.id,targetScreen.id) })
    let remapped = try! remapLayout(work,to: [targetScreen],mapping: mapping)
    check(remapped.windows.allSatisfy { $0.monitorID == targetScreen.id }, "migration can combine old monitors on a new screen")
    check(remapped.windows.map(\.relative) == work.windows.map(\.relative), "monitor remapping preserves relative geometry")
    do { _ = try remapLayout(work,to: [targetScreen],mapping: [:]); check(false,"missing screen mappings rejected") } catch { check(true,"missing screen mappings rejected") }
    var invalid = work; invalid.windows[0].relative.width = -1
    check(rejects(try! encoder.encode(LayoutArchive(layouts: [invalid]))), "negative dimensions rejected")
    invalid = work; invalid.windows[0].monitorID = "missing"
    check(rejects(try! encoder.encode(LayoutArchive(layouts: [invalid]))), "unknown monitor assignments rejected")
    invalid = work; invalid.launchRules = [LaunchRule(bundleID: "test",delay: -3)]
    check(rejects(try! encoder.encode(LayoutArchive(layouts: [invalid]))), "negative launch delays rejected")
    invalid = work; invalid.launchRules = [LaunchRule(bundleID: "test",windowTimeout: 999)]
    check(rejects(try! encoder.encode(LayoutArchive(layouts: [invalid]))), "unbounded restore timeout rejected")
    invalid = work; invalid.windows.append(invalid.windows[0])
    check(rejects(try! encoder.encode(LayoutArchive(layouts: [invalid]))), "duplicate window identities rejected")
    check(rejects(try! encoder.encode(LayoutArchive(layouts: [work,work]))), "duplicate scene identities rejected")
    var future = LayoutArchive(layouts: [work]); future.version = 999
    check(rejects(try! encoder.encode(future)), "future archive schema rejected")
    future.version = 1; future.format = "other.format"
    check(rejects(try! encoder.encode(future)), "foreign archive type rejected")
    check(rejects(Data(repeating: 32,count: 5_000_001)), "oversized import rejected")
    check(rejects(Data("not json".utf8)), "malformed JSON rejected")
    check(validShortcuts(Shortcut.defaults), "default global shortcuts valid")
    var bindings = Shortcut.defaults; bindings[1].keyCode = bindings[0].keyCode
    check(!validShortcuts(bindings), "duplicate keyboard combinations rejected")
    bindings = Shortcut.defaults; bindings[0].modifiers = 0
    check(!validShortcuts(bindings), "unmodified global keys rejected")
    bindings = Shortcut.defaults; bindings[0].keyCode = 999
    check(!validShortcuts(bindings), "unknown key codes rejected")
    check(windowRetryDelays(timeout: 120).last == 120 && windowRetryDelays(timeout: 5).last == 5, "per-app retry schedule honors slow and fast timeouts")
    check(windowRetryDelays(timeout: -5).last == 1 && windowRetryDelays(timeout: 999).last == 120, "retry schedule is always bounded")
    var selection = sample
    check(selectedLayout(in: selection,screenKey: work.screenKey)?.id == work.id, "stored scene selection is respected")
    selection.activeLayouts = [:]
    check(selectedLayout(in: selection,screenKey: work.screenKey)?.id == work.id, "legacy layout remains selected without active-scene metadata")
    selection.activeLayouts[work.screenKey] = ""
    check(selectedLayout(in: selection,screenKey: work.screenKey) == nil, "newly imported screen groups can remain inactive until selected")
    count += runInterfaceTests()
    print("All \(20+count) checks passed.")
}
