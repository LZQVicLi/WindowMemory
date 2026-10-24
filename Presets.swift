import AppKit
import SwiftUI

struct InstalledApplication: Identifiable, Equatable {
    var id: String
    var name: String
    var path: String
    static func discover(in roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),URL(fileURLWithPath: "/Applications"),URL(fileURLWithPath: "/System/Applications"),URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications")]) -> [InstalledApplication] {
        var found: [String:InstalledApplication] = [:]
        for root in roots {
            guard let files = FileManager.default.enumerator(at: root,includingPropertiesForKeys: [.isDirectoryKey],options: [.skipsHiddenFiles,.skipsPackageDescendants]) else { continue }
            for case let url as URL in files {
                if url.pathComponents.count-root.pathComponents.count > 4 { files.skipDescendants(); continue }
                guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url.resolvingSymlinksInPath()),
                      let id = bundle.bundleIdentifier, !id.hasPrefix("local.vic.windowmemory"), found[id] == nil,
                      let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else { continue }
                let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                found[id] = InstalledApplication(id: id,name: name,path: url.path)
            }
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
struct PresetRegion: Identifiable {
    var id: String
    var title: String
    var frame: Frame
}
enum PresetPattern: String, CaseIterable, Identifiable {
    case communication, columns, grid, focus, portraitStack, portraitReading, portraitTriple, tripleColumns, laptopWork, topBottom, quadColumns, centerFocus
    var id: String { rawValue }
    var title: String {
        switch self {
        case .communication: return L("顶部通讯 + 双工作区")
        case .columns: return L("左右双栏")
        case .grid: return L("四格工作区")
        case .focus: return L("单窗专注")
        case .portraitStack: return L("竖屏：通讯 / 阅读 / 参考")
        case .portraitReading: return L("竖屏：长文阅读 + 工具")
        case .portraitTriple: return L("竖屏：三层工作区")
        case .tripleColumns: return L("宽屏：三列协作")
        case .laptopWork: return L("主屏：工作 + 侧边工具")
        case .topBottom: return L("上下双区")
        case .quadColumns: return L("超宽屏：四列工作区")
        case .centerFocus: return L("居中主工作区 + 两侧工具")
        }
    }
    var regions: [PresetRegion] {
        switch self {
        case .communication: return [
            PresetRegion(id: "communication",title: L("通讯"),frame: Frame(x: 0,y: 0,width: 1,height: 0.24)),
            PresetRegion(id: "primary",title: L("主工作区"),frame: Frame(x: 0,y: 0.24,width: 0.62,height: 0.76)),
            PresetRegion(id: "secondary",title: L("辅助工作区"),frame: Frame(x: 0.62,y: 0.24,width: 0.38,height: 0.76))]
        case .columns: return [
            PresetRegion(id: "primary",title: L("主工作区"),frame: Frame(x: 0,y: 0,width: 0.6,height: 1)),
            PresetRegion(id: "secondary",title: L("辅助工作区"),frame: Frame(x: 0.6,y: 0,width: 0.4,height: 1))]
        case .grid: return (0..<4).map { i in PresetRegion(id: "grid\(i)",title: L("区域 \(i+1)"),frame: Frame(x: Double(i%2)*0.5,y: Double(i/2)*0.5,width: 0.5,height: 0.5)) }
        case .portraitStack: return [
            PresetRegion(id: "communication",title: L("通讯"),frame: Frame(x: 0,y: 0,width: 1,height: 0.22)),
            PresetRegion(id: "primary",title: L("主工作区"),frame: Frame(x: 0,y: 0.22,width: 1,height: 0.52)),
            PresetRegion(id: "secondary",title: L("辅助工作区"),frame: Frame(x: 0,y: 0.74,width: 1,height: 0.26))]
        case .portraitReading: return [
            PresetRegion(id: "primary",title: L("主工作区"),frame: Frame(x: 0,y: 0,width: 1,height: 0.72)),
            PresetRegion(id: "secondary",title: L("辅助工作区"),frame: Frame(x: 0,y: 0.72,width: 1,height: 0.28))]
        case .portraitTriple: return (0..<3).map { i in PresetRegion(id: "stack\(i)",title: L("区域 \(i+1)"),frame: Frame(x: 0,y: Double(i)/3,width: 1,height: 1.0/3)) }
        case .tripleColumns: return (0..<3).map { i in PresetRegion(id: "column\(i)",title: L("区域 \(i+1)"),frame: Frame(x: Double(i)/3,y: 0,width: 1.0/3,height: 1)) }
        case .topBottom: return [
            PresetRegion(id: "primary",title: L("主工作区"),frame: Frame(x: 0,y: 0,width: 1,height: 0.5)),
            PresetRegion(id: "secondary",title: L("辅助工作区"),frame: Frame(x: 0,y: 0.5,width: 1,height: 0.5))]
        case .quadColumns: return (0..<4).map { i in PresetRegion(id: "wide\(i)",title: L("区域 \(i+1)"),frame: Frame(x: Double(i)/4,y: 0,width: 0.25,height: 1)) }
        case .centerFocus: return [
            PresetRegion(id: "secondary",title: L("辅助工作区"),frame: Frame(x: 0,y: 0,width: 0.22,height: 1)),
            PresetRegion(id: "primary",title: L("主工作区"),frame: Frame(x: 0.22,y: 0,width: 0.56,height: 1)),
            PresetRegion(id: "communication",title: L("通讯"),frame: Frame(x: 0.78,y: 0,width: 0.22,height: 1))]
        case .laptopWork: return [
            PresetRegion(id: "primary",title: L("主工作区"),frame: Frame(x: 0,y: 0,width: 0.68,height: 1)),
            PresetRegion(id: "secondary",title: L("辅助工作区"),frame: Frame(x: 0.68,y: 0,width: 0.32,height: 0.6)),
            PresetRegion(id: "communication",title: L("通讯"),frame: Frame(x: 0.68,y: 0.6,width: 0.32,height: 0.4))]
        case .focus: return [PresetRegion(id: "primary",title: L("主工作区"),frame: Frame(x: 0,y: 0,width: 1,height: 1))]
        }
    }
}
struct PresetScreenDraft {
    var monitorID: String
    var pattern: PresetPattern = .communication
    var assignments: [String:InstalledApplication] = [:]
    var customRegions: [PresetRegion]? = nil
    var regions: [PresetRegion] { customRegions ?? pattern.regions }
    var slots: [WindowSlot] {
        regions.compactMap { region in
            guard let app = assignments[region.id] else { return nil }
            return WindowSlot(bundleID: app.id,appName: app.name,title: "",monitorID: monitorID,relative: region.frame)
        }
    }
}
func makePresetLayout(name: String, monitors: [Monitor], drafts: [PresetScreenDraft]) -> Layout? {
    let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let connected = Set(monitors.map(\.id))
    guard !cleaned.isEmpty, cleaned.count <= 100, Set(drafts.map(\.monitorID)).count == drafts.count,
          drafts.allSatisfy({ connected.contains($0.monitorID) }) else { return nil }
    let slots = drafts.flatMap(\.slots)
    guard !slots.isEmpty else { return nil }
    return Layout(id: UUID().uuidString,name: cleaned,updatedAt: Date(),monitors: monitors,windows: slots)
}

extension Controller {
    func savePreset(name: String, monitors captured: [Monitor], drafts: [PresetScreenDraft]) -> Bool {
        guard layoutKey(captured) == layoutKey(monitors) else { tell(L("屏幕连接已变化，请重新打开预设编辑器。"),error: true); return false }
        guard let layout = makePresetLayout(name: name,monitors: monitors,drafts: drafts) else { return false }
        let previous = state
        state.layouts.append(layout)
        guard selectScene(layout.id) else { state = previous; return false }
        selectedPage = "workspace"
        tell(L("预设已保存为场景，可启动 App 并恢复。留空的区域不会创建窗口。"))
        return true
    }
}
struct PresetEditor: View {
    @ObservedObject var model: Controller
    @Environment(\.dismiss) private var dismiss
    @State private var name = L("预设布局")
    @State private var drafts: [PresetScreenDraft] = []
    @State private var selectedMonitor = ""
    @State private var apps: [InstalledApplication] = []
    @State private var loading = true
    @State private var saveError = ""
    @State private var activeRegion: String?
    @State private var captured: [Monitor] = []
    private var selected: Monitor? { captured.first { $0.id == selectedMonitor } }
    private var p: ConsolePalette { ConsolePalette(model.darkAppearance ? .dark : .light) }
    private var draftIndex: Int? { drafts.firstIndex { $0.monitorID == selectedMonitor } }
    private var configured: Int { drafts.flatMap(\.slots).count }
    private var recommendations: [PresetRecommendation] {
        guard let selected else { return [] }
        var result = recommendedPresets(for: selected,screenCount: captured.count)
        if let index = draftIndex, !result.contains(where: { $0.pattern == drafts[index].pattern }) {
            result.append(PresetRecommendation(pattern: drafts[index].pattern,reason: L("手动选择的模板会按此屏可用尺寸缩放。")))
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            HStack {
                VStack(alignment: .leading,spacing: 5) {
                    Text(L("按屏幕选择推荐布局")).font(.system(size: 20,weight: .semibold))
                    Text(L("点区域中央选择本机 App，可只配置部分区域。每个屏幕可选不同预设。"))
                        .font(.system(size: 11)).foregroundStyle(p.muted).fixedSize(horizontal: false,vertical: true)
                }
                Spacer()
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField(L("场景名称"),text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Picker(L("显示器"),selection: $selectedMonitor) { ForEach(captured) { Text($0.name).tag($0.id) } }.labelsHidden()
                if let index = draftIndex {
                    if drafts[index].customRegions != nil {
                        Text(L("自定义模板")).font(.system(size: 12,weight: .medium)).foregroundStyle(p.accent)
                    } else {
                    Picker(L("布局预设"),selection: Binding(get: { drafts[index].pattern },set: { pattern in
                        drafts[index].customRegions = nil
                        drafts[index].pattern = pattern
                        let ids = Set(pattern.regions.map(\.id))
                        drafts[index].assignments = drafts[index].assignments.filter { ids.contains($0.key) }
                    })) { ForEach(recommendations) { Text($0.pattern.title).tag($0.pattern) } }.labelsHidden()
                    }
                }
            }
            if let screen = selected {
                Text(screenSummary(screen)).font(.system(size: 11,weight: .medium)).foregroundStyle(p.accent)
                ScrollView(.horizontal,showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recommendations) { recommendation in
                            Button {
                                if let index = draftIndex {
                                    drafts[index].customRegions = nil
                                    drafts[index].pattern = recommendation.pattern
                                    let ids = Set(recommendation.pattern.regions.map(\.id))
                                    drafts[index].assignments = drafts[index].assignments.filter { ids.contains($0.key) }
                                }
                            } label: {
                                VStack(alignment: .leading,spacing: 6) {
                                    PresetThumbnail(pattern: recommendation.pattern,p: p).aspectRatio(screen.bounds.width/screen.bounds.height,contentMode: .fit).frame(width: 130,height: 48)
                                    Text(recommendation.pattern.title).font(.system(size: 10,weight: .semibold)).lineLimit(2)
                                }.padding(10).frame(width: 160,alignment: .leading).background(p.raised,in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(draftIndex.map { drafts[$0].customRegions == nil && drafts[$0].pattern == recommendation.pattern } == true ? p.accent : p.border,lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(height: 105)
            }
            if let index = draftIndex {
                GeometryReader { geometry in
                    let monitor = captured.first { $0.id == selectedMonitor }
                    let aspect = (monitor?.visible.width ?? 16)/(monitor?.visible.height ?? 10)
                    let width = min(geometry.size.width,geometry.size.height*aspect)
                    let height = width/aspect
                    ZStack(alignment: .topLeading) {
                        ForEach(drafts[index].regions) { region in
                            regionView(region,index: index)
                                .frame(width: max(1,width*region.frame.width-6),height: max(1,height*region.frame.height-6))
                                .position(x: width*(region.frame.x+region.frame.width/2),y: height*(region.frame.y+region.frame.height/2))
                        }
                    }.frame(width: width,height: height).frame(maxWidth: .infinity,maxHeight: .infinity)
                }.frame(minHeight: 220,maxHeight: .infinity)
            }
            Text(L("占位仅保存位置和尺寸；真正启动后再移动已有窗口。不会创建文档、浏览器标签或同一 App 的额外窗口。"))
                .font(.system(size: 11)).foregroundStyle(p.muted).fixedSize(horizontal: false,vertical: true)
            if !saveError.isEmpty { Text(saveError).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Text(L("已配置 \(configured) 个区域")).font(.system(size: 11)).foregroundStyle(p.accent)
                Spacer()
                Button(L("保存为新场景")) {
                    if model.savePreset(name: name,monitors: captured,drafts: drafts) { dismiss() } else { saveError = model.message }
                }.buttonStyle(.borderedProminent).disabled(configured == 0 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 100 || model.launching)
            }
        }.padding(24).frame(width: 820,height: 740).background(p.background).foregroundStyle(p.text).tint(p.accent)
            .environment(\.colorScheme,model.darkAppearance ? .dark : .light)
            .environment(\.locale,Locale(identifier: model.state.preferences.language.resolvedCode))
            .environment(\.layoutDirection,model.state.preferences.language.isRightToLeft ? .rightToLeft : .leftToRight)
            .onAppear {
                captured = model.monitors
                selectedMonitor = captured.first { $0.id == model.presetScreenID }?.id ?? captured.first { $0.isPrimary }?.id ?? captured.first?.id ?? ""
                drafts = captured.map { screen in
                    let recommendations = recommendedPresets(for: screen,screenCount: captured.count)
                    let preferred = screen.id == selectedMonitor ? model.presetPattern : nil
                    return PresetScreenDraft(monitorID: screen.id,pattern: preferred ?? recommendations.first?.pattern ?? .focus)
                }
                if let template = model.selectedUserTemplate, let index = draftIndex {
                    name = template.name
                    drafts[index].customRegions = template.regions.map { PresetRegion(id: $0.id,title: $0.title,frame: $0.frame) }
                    for region in template.regions {
                        if let id = region.bundleID, !id.isEmpty {
                            drafts[index].assignments[region.id] = InstalledApplication(id: id,name: region.appName ?? id,path: NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path ?? "")
                        }
                    }
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let discovered = InstalledApplication.discover()
                    DispatchQueue.main.async { apps = discovered; loading = false }
                }
            }
    }
    private func regionView(_ region: PresetRegion,index: Int) -> some View {
        let app = drafts[index].assignments[region.id]
        return VStack(spacing: 3) {
            Text(region.title).font(.system(size: 9,weight: .semibold)).lineLimit(1).foregroundStyle(p.muted)
            Button { activeRegion = region.id } label: {
                HStack(spacing: 5) {
                    if let app { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 20,height: 20) }
                    else { Image(systemName: "plus.app").font(.system(size: 18)) }
                    Text(app?.name ?? L("选择应用")).font(.system(size: 11,weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity,maxHeight: .infinity)
            }.buttonStyle(.plain)
                .popover(isPresented: Binding(get: { activeRegion == region.id },set: { if !$0 { activeRegion = nil } })) {
                    AppSelectionPopover(apps: apps,loading: loading) { selected in
                        drafts[index].assignments[region.id] = selected
                        activeRegion = nil
                    }
                }
        }.padding(5).background(app == nil ? p.raised : p.accent.opacity(0.09),in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(app == nil ? p.border : p.accent.opacity(0.7),style: StrokeStyle(lineWidth: 1,dash: app == nil ? [5,4] : [])))
    }
}
struct AppSelectionPopover: View {
    let apps: [InstalledApplication]
    let loading: Bool
    let select: (InstalledApplication?) -> Void
    @State private var query = ""
    private var filtered: [InstalledApplication] { apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(L("选择已安装的应用")).font(.headline)
            TextField(L("搜索应用名称"),text: $query).textFieldStyle(.roundedBorder)
            Button(L("留空此区域")) { select(nil) }.controlSize(.small)
            if loading { ProgressView().frame(maxWidth: .infinity,maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { app in
                            Button { select(app) } label: {
                                HStack {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 24,height: 24)
                                    VStack(alignment: .leading,spacing: 3) {
                                        Text(app.name).font(.system(size: 12))
                                        Text(app.id).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }.padding(6).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if filtered.isEmpty { Text(L("没有找到应用")).font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(16).frame(width: 320,height: 400)
    }
}
