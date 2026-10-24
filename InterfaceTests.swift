import AppKit
import SwiftUI

@discardableResult
func runInterfaceTests() -> Int {
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError("FAIL: \(label)") }; count += 1; print("PASS: \(label)")
    }
    check(AppLanguage.supportedCodes.count == 6 && AppLanguage.allCases.count == 7,"six UN languages plus system option")
    check(AppLanguage.arabic.isRightToLeft && !AppLanguage.english.isRightToLeft,"Arabic direction switches independently of OS language")
    let legacy = try! JSONDecoder().decode(Preferences.self,from: Data("{}".utf8))
    check(legacy.language == .system,"legacy settings default to system language")
    let future = try! JSONDecoder().decode(Preferences.self,from: Data("{\"language\":\"future-language\"}".utf8))
    check(future.language == .system,"unknown language preserves readable configuration")
    var preferences = Preferences(); preferences.language = .arabic
    check(try! JSONDecoder().decode(Preferences.self,from: JSONEncoder().encode(preferences)).language == .arabic,"language setting survives save and reload")
    check(Localization.translations.count >= 190,"translation resource is packaged in app bundle")
    let pattern = try! NSRegularExpression(pattern: #"\{\d+\}"#)
    func placeholders(_ value: String) -> [String] {
        pattern.matches(in: value,range: NSRange(value.startIndex...,in: value)).map { String(value[Range($0.range,in: value)!]) }.sorted()
    }
    for code in AppLanguage.supportedCodes where code != "zh-Hans" {
        check(Localization.translations.allSatisfy { key, row in
            guard let translated = row[code], !translated.isEmpty else { return false }
            return placeholders(key) == placeholders(translated)
        },"complete \(code) translations with intact placeholders")
    }
    let name = "Report {1} & <private>"
    let sentence: LocalizedText = "场景已重命名为“\(name)”。"
    check(Localization.render(sentence,code: "en") == "Scene renamed to “Report {1} & <private>”.","translation does not reinterpret placeholders in user content")
    check(Localization.render("已恢复 \(3) 个窗口 · \("12:30")",code: "en") == "Restored 3 windows · 12:30","dynamic status messages use translated templates")
    let shareText = "WindowMemory & العربية #test?"
    for channel in ShareChannel.allCases where ![.system,.copy,.wechat].contains(channel) {
        let url = channel.destination(text: shareText)!
        let values = URLComponents(url: url,resolvingAgainstBaseURL: false)!.queryItems ?? []
        check(url.scheme == (channel == .email ? "mailto" : "https") && values.contains(where: { $0.value?.contains(ShareChannel.projectURL.absoluteString) == true }),"\(channel.rawValue) share contains only the public project destination")
        if ![.facebook,.linkedin].contains(channel) {
            check(values.contains(where: { $0.value?.contains(shareText) == true }),"\(channel.rawValue) Unicode and reserved characters round-trip")
        }
    }
    check(ShareChannel.wechat.destination(text: shareText) == nil,"WeChat uses copy instead of an unsupported direct sharing URL")
    for pattern in PresetPattern.allCases {
        let regions = pattern.regions
        check(abs(regions.reduce(0) { $0+$1.frame.width*$1.frame.height }-1) < 0.00001 && regions.allSatisfy { $0.frame.x >= 0 && $0.frame.y >= 0 && $0.frame.x+$0.frame.width <= 1.00001 && $0.frame.y+$0.frame.height <= 1.00001 },"\(pattern.rawValue) preset covers its display within bounds")
        check(Set(regions.map(\.id)).count == regions.count,"\(pattern.rawValue) regions have stable unique IDs")
        check(regions.indices.allSatisfy { i in regions.indices.allSatisfy { j in
            i >= j || regions[i].frame.rect.intersection(regions[j].frame.rect).isEmpty || regions[i].frame.rect.intersection(regions[j].frame.rect).width*regions[i].frame.rect.intersection(regions[j].frame.rect).height < 0.000001
        } },"\(pattern.rawValue) preset regions never overlap")
    }
    let sample = sampleState().layouts[0]
    let first = sample.monitors[0], second = sample.monitors[1]
    let app = InstalledApplication(id: "test.app",name: "Test App",path: "/Applications/Test.app")
    var draft = PresetScreenDraft(monitorID: first.id)
    check(makePresetLayout(name: "Empty",monitors: sample.monitors,drafts: [draft]) == nil,"entirely empty presets cannot be saved")
    draft.assignments["communication"] = app
    let layout = makePresetLayout(name: " Partial ",monitors: sample.monitors,drafts: [draft])!
    check(layout.name == "Partial" && layout.windows.count == 1 && layout.monitors.count == 2,"partial preset saves only assigned regions and retains the display combination")
    check(layout.windows[0].title.isEmpty && layout.windows[0].enabled,"preset slots join normal title-fallback matching and launch flow")
    check((try? validateLayouts([layout])) != nil,"preset layout passes existing archive validation")
    let other = PresetScreenDraft(monitorID: second.id,pattern: .focus,assignments: ["primary":app])
    let multi = makePresetLayout(name: "Two screens",monitors: sample.monitors,drafts: [draft,other])!
    check(multi.windows.count == 2 && Set(multi.windows.map(\.monitorID)).count == 2,"preset assigns apps independently across displays")
    check(launchTargets(multi.windows).count == 1,"same app in several preset areas launches only once")
    check(makePresetLayout(name: " ",monitors: sample.monitors,drafts: [draft]) == nil,"blank preset names are rejected")
    check(makePresetLayout(name: String(repeating: "x",count: 101),monitors: sample.monitors,drafts: [draft]) == nil,"overlong preset names are rejected")
    check(makePresetLayout(name: "Duplicate",monitors: sample.monitors,drafts: [draft,draft]) == nil,"duplicate display drafts are rejected")
    check(makePresetLayout(name: "Missing",monitors: [second],drafts: [draft]) == nil,"disconnected preset display is rejected")
    let archive = try! decodeLayouts(JSONEncoder().encode(LayoutArchive(layouts: [multi])))
    check(archive.first?.windows.count == 2 && archive.first?.windows.first?.relative == multi.windows.first?.relative,"preset scenes round-trip through ordinary import and export")
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("WindowMemory-app-scan-"+UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: fixture) }
    let bundle = fixture.appendingPathComponent("Utilities/Fixture.app/Contents")
    try! FileManager.default.createDirectory(at: bundle.appendingPathComponent("MacOS"),withIntermediateDirectories: true)
    let info: [String:Any] = ["CFBundleIdentifier":"test.fixture.app","CFBundleName":"Fixture App","CFBundleExecutable":"Fixture","CFBundlePackageType":"APPL"]
    try! PropertyListSerialization.data(fromPropertyList: info,format: .xml,options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
    let executable = bundle.appendingPathComponent("MacOS/Fixture")
    try! Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try! FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath: executable.path)
    let discovered = InstalledApplication.discover(in: [fixture,fixture])
    check(discovered.count == 1 && discovered[0].id == "test.fixture.app" && discovered[0].name == "Fixture App","installed-app discovery finds nested bundles and deduplicates IDs")
    let aliases = fixture.appendingPathComponent("Aliases")
    try! FileManager.default.createDirectory(at: aliases,withIntermediateDirectories: true)
    try! FileManager.default.createSymbolicLink(at: aliases.appendingPathComponent("FixtureAlias.app"),withDestinationURL: bundle.deletingLastPathComponent())
    check(InstalledApplication.discover(in: [aliases]).first?.id == "test.fixture.app","installed-app discovery resolves application symlinks")
    var compactPrimary = sample.monitors[0]; compactPrimary.isPrimary = true
    check(recommendedPresets(for: compactPrimary,screenCount: 2).first?.pattern == .columns,"compact primary prioritizes main work when a secondary display is connected")
    check(recommendedPresets(for: compactPrimary,screenCount: 1).first?.pattern == .laptopWork,"single-display recommendations balance main work and tools")
    check(!recommendedPresets(for: compactPrimary,screenCount: 2).contains { [.portraitStack,.portraitReading,.portraitTriple,.tripleColumns].contains($0.pattern) },"laptop display excludes portrait and ultrawide-only patterns")
    var portrait = sample.monitors[1]; portrait.visible = Frame(x: -1600,y: -900,width: 1600,height: 2510)
    check(recommendedPresets(for: portrait,screenCount: 2).first?.pattern == .portraitStack,"large portrait recommends stacked chat, reading and references")
    check(!recommendedPresets(for: portrait,screenCount: 2).contains { [.columns,.tripleColumns,.grid].contains($0.pattern) },"portrait recommendations avoid narrow columns and grid")
    portrait.visible = Frame(x: 0,y: 0,width: 720,height: 1280)
    check(recommendedPresets(for: portrait).count == 2 && recommendedPresets(for: portrait).first?.pattern == .portraitReading,"small portrait avoids excessive partitions")
    var wide = compactPrimary; wide.visible = Frame(x: 0,y: 0,width: 3440,height: 1400)
    check(recommendedPresets(for: wide).first?.pattern == .tripleColumns,"ultrawide recommendations use three spacious columns")
    let oldMonitorData = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(compactPrimary)) as! [String:Any]
    var legacyMonitor = oldMonitorData; legacyMonitor.removeValue(forKey: "isPrimary")
    check(try! JSONDecoder().decode(Monitor.self,from: JSONSerialization.data(withJSONObject: legacyMonitor)).isPrimary == false,"legacy monitor records migrate without losing layouts")
    check(try! JSONDecoder().decode(Monitor.self,from: JSONEncoder().encode(compactPrimary)).isPrimary,"primary display metadata round-trips")
    check([ShareChannel.x,.facebook,.linkedin,.whatsapp,.telegram,.reddit,.wechat].allSatisfy { Bundle.main.url(forResource: $0.rawValue,withExtension: "png",subdirectory: "ShareIcons") != nil },"all seven brand icons are bundled for offline use")
    for category in DisplayCategory.allCases {
        var representative = compactPrimary
        representative.bounds = Frame(x: 0,y: 0,width: 1600*category.aspect,height: 1600)
        representative.visible = representative.bounds
        check(DisplayCategory.matching(representative) == category,"\(category.rawValue) display family matches its aspect ratio")
        check(category.patterns.count >= 3 && Set(category.patterns).count == category.patterns.count,"\(category.rawValue) catalog has several distinct templates")
    }
    var superwide = compactPrimary; superwide.visible = Frame(x: 0,y: 0,width: 5120,height: 1400)
    check(recommendedPresets(for: superwide,screenCount: 2).first?.pattern == .quadColumns,"32:9 display prioritizes four-column templates")
    let savedTemplates = templatesFromLayout(sample)
    check(savedTemplates.count == 2 && savedTemplates.allSatisfy(validUserTemplate),"saved multi-display scenes become valid per-display library templates")
    check(savedTemplates.flatMap(\.regions).count == sample.windows.filter(\.enabled).count,"adding a scene to the library preserves all enabled regions")
    check(savedTemplates.flatMap(\.regions).allSatisfy { $0.bundleID != nil && $0.appName != nil },"scene templates preserve app assignments without window-title matching")
    var libraryState = sampleState(); libraryState.userTemplates = savedTemplates
    let libraryReload = try! JSONDecoder().decode(SavedState.self,from: JSONEncoder().encode(libraryState))
    check(libraryReload.userTemplates.count == 2 && libraryReload.userTemplates[0].regions == savedTemplates[0].regions,"custom library survives configuration save and reload")
    var blankStateObject = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(libraryState)) as! [String:Any]
    blankStateObject.removeValue(forKey: "userTemplates")
    check(try! JSONDecoder().decode(SavedState.self,from: JSONSerialization.data(withJSONObject: blankStateObject)).userTemplates.isEmpty,"older configurations migrate to an empty custom library")
    var custom = UserLayoutTemplate(name: "Custom",sourceAspect: 1.6,regions: [UserTemplateRegion(title: "Work",frame: Frame(x: 0,y: 0,width: 0.7,height: 1))])
    check(validUserTemplate(custom),"custom templates can save geometry without assigning apps")
    let customRegion = PresetRegion(id: custom.regions[0].id,title: "Work",frame: custom.regions[0].frame)
    let customDraft = PresetScreenDraft(monitorID: compactPrimary.id,assignments: [customRegion.id: app],customRegions: [customRegion])
    check(customDraft.slots.count == 1 && customDraft.slots[0].relative.width == 0.7,"custom template geometry flows into the existing launch and restore scene planner")
    custom.regions[0].frame.x = 0.5
    check(!validUserTemplate(custom),"custom region overflowing screen is rejected")
    custom.regions[0].frame = Frame(x: 0,y: 0,width: 0.01,height: 1)
    check(!validUserTemplate(custom),"unusable tiny custom regions are rejected")
    custom.regions[0].frame = Frame(x: 0,y: 0,width: 0.5,height: 1)
    custom.regions.append(custom.regions[0])
    check(!validUserTemplate(custom),"duplicate custom region IDs are rejected")
    custom.regions = [];check(!validUserTemplate(custom),"entirely empty custom templates are rejected")
    custom = savedTemplates[0]; custom.name = " "
    check(!validUserTemplate(custom),"blank custom template names are rejected")
    custom = savedTemplates[0]; custom.sourceAspect = .nan
    check(!validUserTemplate(custom),"non-finite custom template aspect ratios are rejected")
    return count
}

// Runs against actual AppKit/SwiftUI hosting, using demo data and no user configuration writes.
func runAppearanceUITests() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = nil
    let systemDark = app.effectiveAppearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua
    let model = Controller()
    model.showWindow()
    func pump() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15)) }
    func check(_ condition: Bool, _ label: String) {
        guard condition else { fatalError("FAIL: \(label)") }; print("PASS: \(label)")
    }
    for _ in 0..<3 {
        model.setAppearance(.dark); pump()
        check(model.darkAppearance,"native and SwiftUI switch to dark")
        model.setAppearance(.system); pump()
        check(app.appearance == nil && model.darkAppearance == systemDark,"dark → system immediately restores current OS appearance")
        model.setAppearance(.light); pump()
        check(!model.darkAppearance,"native and SwiftUI switch to light")
        model.setAppearance(.system); pump()
        check(model.darkAppearance == systemDark,"light → system restores current OS appearance")
    }
    for language in AppLanguage.allCases {
        model.setLanguage(language); pump()
        check(model.state.preferences.language == language,"language switches live: \(language.rawValue)")
    }
    for window in app.windows { window.close() }
    print("All 19 native appearance/language checks passed.")
}
