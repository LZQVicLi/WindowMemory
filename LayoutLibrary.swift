import SwiftUI

struct PresetRecommendation: Identifiable {
    var pattern: PresetPattern
    var reason: String
    var id: String { pattern.id }
}
enum DisplayCategory: String, CaseIterable, Identifiable {
    case laptop, landscape, portrait, ultrawide, superwide, square, productivity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .laptop: return L("笔记本 · 16:10")
        case .landscape: return L("常规横屏 · 16:9")
        case .portrait: return L("竖屏 · 9:16 / 10:16")
        case .ultrawide: return L("超宽屏 · 21:9")
        case .superwide: return L("超宽带鱼屏 · 32:9")
        case .square: return L("方屏 · 1:1")
        case .productivity: return L("办公屏 · 4:3 / 3:2")
        }
    }
    var aspect: Double {
        switch self { case .laptop: return 1.6; case .landscape: return 16.0/9; case .portrait: return 9.0/16; case .ultrawide: return 21.0/9; case .superwide: return 32.0/9; case .square: return 1; case .productivity: return 1.5 }
    }
    var examples: String {
        switch self {
        case .laptop: return "1440 × 900 · 1512 × 982 · 1728 × 1117"
        case .landscape: return "1920 × 1080 · 2560 × 1440 · 3840 × 2160"
        case .portrait: return "1080 × 1920 · 1440 × 2560 · 1600 × 2560"
        case .ultrawide: return "2560 × 1080 · 3440 × 1440 · 5120 × 2160"
        case .superwide: return "3840 × 1080 · 5120 × 1440 · 7680 × 2160"
        case .square: return "1920 × 1920 · 2560 × 2560"
        case .productivity: return "1600 × 1200 · 2560 × 1707 · 3000 × 2000"
        }
    }
    var patterns: [PresetPattern] {
        switch self {
        case .laptop: return [.columns,.laptopWork,.focus]
        case .landscape: return [.columns,.laptopWork,.grid,.communication,.focus]
        case .portrait: return [.portraitStack,.portraitReading,.portraitTriple,.topBottom,.focus]
        case .ultrawide: return [.tripleColumns,.centerFocus,.columns,.grid,.focus]
        case .superwide: return [.quadColumns,.centerFocus,.tripleColumns,.grid,.focus]
        case .square: return [.grid,.topBottom,.columns,.focus]
        case .productivity: return [.columns,.grid,.laptopWork,.topBottom,.focus]
        }
    }
    static func matching(_ screen: Monitor) -> DisplayCategory {
        // Bounds retain the physical orientation; visible space excludes menu bar and Dock.
        let ratio = screen.bounds.width/screen.bounds.height
        if ratio < 0.85 { return .portrait }
        if ratio >= 3 { return .superwide }
        if ratio >= 2.1 { return .ultrawide }
        if ratio <= 1.2 { return .square }
        if ratio < 1.52 { return .productivity }
        if ratio <= 1.7 { return .laptop }
        return .landscape
    }
}
func recommendedPresets(for screen: Monitor, screenCount: Int = 1) -> [PresetRecommendation] {
    let width = screen.visible.width, height = screen.visible.height
    let ratio = width/height
    let patterns: [PresetPattern]
    let reason: String
    if ratio < 0.85 {
        if height >= 1500 && width >= 850 { patterns = [.portraitStack,.portraitReading,.portraitTriple,.focus] }
        else { patterns = [.portraitReading,.focus] }
        reason = L("竖屏优先纵向分区，减少窄列；适合通讯、阅读和参考资料。")
    } else if ratio >= 3 && width >= 3000 {
        patterns = [.quadColumns,.centerFocus,.tripleColumns,.focus]
        reason = L("32:9 屏幕可使用四列或居中主工作区，避免窗口横跨整个屏幕。")
    } else if ratio >= 2.1 && width >= 2000 {
        patterns = [.tripleColumns,.columns,.laptopWork,.focus]
        reason = L("超宽屏适合并排协作，保留足够的单窗宽度。")
    } else if width <= 1800 || height < 1000 {
        patterns = screen.isPrimary ? (screenCount > 1 ? [.columns,.focus,.laptopWork] : [.laptopWork,.columns,.focus]) : [.focus,.columns]
        reason = screen.isPrimary ? (screenCount > 1 ? L("多屏主屏优先保留工作窗口，通讯和参考资料可放到副屏。") : L("单屏兼顾主要工作与侧边工具，也可选择双栏或专注布局。")) : L("紧凑副屏优先单窗或双栏，适合辅助任务。")
    } else {
        patterns = screen.isPrimary ? [.laptopWork,.columns,.grid,.communication] : [.columns,.communication,.grid,.focus]
        reason = L("大尺寸横屏可容纳更多窗口，主次工作区按可用尺寸分配。")
    }
    return patterns.map { PresetRecommendation(pattern: $0,reason: reason) }
}
func screenSummary(_ screen: Monitor) -> String {
    let role = screen.isPrimary ? L("主屏") : L("副屏")
    let orientation = screen.visible.height > screen.visible.width ? L("竖屏") : L("横屏")
    return L("\(role) · \(orientation) · 可用 \(Int(screen.visible.width)) × \(Int(screen.visible.height)) pt")
}
extension Controller {
    func openLayoutLibrary(for screenID: String? = nil, pattern: PresetPattern? = nil) {
        guard !launching else { return }
        selectedUserTemplate = nil
        presetScreenID = screenID
        presetPattern = pattern
        showPresetEditor = true
    }
}
struct PresetThumbnail: View {
    let pattern: PresetPattern
    let p: ConsolePalette
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(pattern.regions.enumerated()),id: \.element.id) { index, region in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == 0 ? p.accent.opacity(0.65) : p.cyan.opacity(index == 1 ? 0.4 : 0.22))
                        .frame(width: max(1,geometry.size.width*region.frame.width-3),height: max(1,geometry.size.height*region.frame.height-3))
                        .position(x: geometry.size.width*(region.frame.x+region.frame.width/2),y: geometry.size.height*(region.frame.y+region.frame.height/2))
                }
            }
        }.accessibilityHidden(true)
    }
}
struct LayoutLibraryView: View {
    @ObservedObject var model: Controller
    let p: ConsolePalette
    @State private var browsing: DisplayCategory?
    @State private var targetScreenID = ""
    private var targetID: String { model.monitors.first { $0.id == targetScreenID }?.id ?? model.monitors.first { $0.isPrimary }?.id ?? model.monitors.first?.id ?? "" }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            HStack {
                Text(L("布局库")).font(.system(size: 13,weight: .semibold))
                Spacer()
                Text("LAYOUT LIBRARY").font(.system(size: 8,design: .monospaced)).tracking(1.2).foregroundStyle(p.muted)
            }
            Text(L("检测到 \(model.monitors.count) 个屏幕，主屏由 macOS 自动识别。"))
                .font(.system(size: 11)).foregroundStyle(p.muted)
            Picker(L("浏览模板"),selection: $browsing) {
                Text(L("自动匹配当前屏幕")).tag(nil as DisplayCategory?)
                ForEach(DisplayCategory.allCases) { Text($0.title).tag(Optional($0)) }
            }.frame(maxWidth: 380,alignment: .leading)
            if let category = browsing {
                VStack(alignment: .leading,spacing: 12) {
                    Text(category.title).font(.system(size: 12,weight: .semibold))
                    Text(category.examples).font(.system(size: 10,design: .monospaced)).foregroundStyle(p.muted)
                    Picker(L("应用到屏幕"),selection: Binding(get: { targetID },set: { targetScreenID = $0 })) {
                        ForEach(model.monitors) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 370,alignment: .leading)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155),spacing: 10)],spacing: 10) {
                        ForEach(category.patterns) { pattern in
                            Button { model.openLayoutLibrary(for: targetID,pattern: pattern) } label: {
                                VStack(alignment: .leading,spacing: 8) {
                                    PresetThumbnail(pattern: pattern,p: p).aspectRatio(category.aspect,contentMode: .fit).frame(height: 80)
                                    Text(pattern.title).font(.system(size: 10,weight: .medium)).lineLimit(2)
                                }.padding(11).frame(maxWidth: .infinity,alignment: .leading).background(p.raised,in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).disabled(model.launching || model.monitors.isEmpty)
                        }
                    }
                    Text(L("浏览其他屏幕类型不会改变现有布局。选择模板后，可在目标屏幕上预览并配置 App。"))
                        .font(.system(size: 10)).foregroundStyle(p.muted).fixedSize(horizontal: false,vertical: true)
                }
            } else {
            ForEach(model.monitors.sorted { $0.isPrimary && !$1.isPrimary }) { screen in
                VStack(alignment: .leading,spacing: 12) {
                    HStack {
                        Image(systemName: screen.visible.height > screen.visible.width ? "rectangle.portrait" : "display").foregroundStyle(p.accent)
                        VStack(alignment: .leading,spacing: 4) {
                            Text(screen.name).font(.system(size: 12,weight: .semibold))
                            Text(screenSummary(screen)).font(.system(size: 10)).foregroundStyle(p.muted)
                            Text(DisplayCategory.matching(screen).title).font(.system(size: 9)).foregroundStyle(p.cyan)
                        }
                        Spacer()
                        Button(L("为此屏配置")) { model.openLayoutLibrary(for: screen.id) }.controlSize(.small).disabled(model.launching)
                    }
                    Text(recommendedPresets(for: screen,screenCount: model.monitors.count).first?.reason ?? "").font(.system(size: 10)).foregroundStyle(p.muted).fixedSize(horizontal: false,vertical: true)
                    ScrollView(.horizontal,showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(recommendedPresets(for: screen,screenCount: model.monitors.count)) { recommendation in
                                Button {
                                    model.openLayoutLibrary(for: screen.id,pattern: recommendation.pattern)
                                } label: {
                                    VStack(alignment: .leading,spacing: 7) {
                                        PresetThumbnail(pattern: recommendation.pattern,p: p).aspectRatio(screen.bounds.width/screen.bounds.height,contentMode: .fit).frame(width: 125,height: 56)
                                        Text(recommendation.pattern.title).font(.system(size: 10)).lineLimit(2)
                                    }.padding(10).frame(width: 145,alignment: .leading).background(p.panel,in: RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain).disabled(model.launching)
                            }
                        }
                    }
                }.padding(13).background(p.raised,in: RoundedRectangle(cornerRadius: 9))
            }
            }
            VStack(alignment: .leading,spacing: 12) {
                HStack {
                    Text(L("我的模板")).font(.system(size: 13,weight: .semibold))
                    Spacer()
                    Button(L("从当前场景添加")) { model.addCurrentSceneToLibrary() }.disabled(model.current == nil)
                    Button(L("新建模板")) { model.openUserTemplateEditor() }
                }.controlSize(.small)
                if model.state.userTemplates.isEmpty {
                    Text(L("还没有自定义模板。可新建分区，也可把已保存的场景添加到这里。"))
                        .font(.system(size: 11)).foregroundStyle(p.muted)
                } else {
                    Picker(L("应用到屏幕"),selection: Binding(get: { targetID },set: { targetScreenID = $0 })) {
                        ForEach(model.monitors) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 370,alignment: .leading)
                    ForEach(model.state.userTemplates) { template in
                        HStack(spacing: 14) {
                            TemplatePreview(template: template,p: p).frame(width: 90,height: 65)
                            VStack(alignment: .leading,spacing: 5) {
                                Text(template.name).font(.system(size: 12,weight: .medium))
                                Text(L("\(template.regions.count) 个区域")).font(.system(size: 10)).foregroundStyle(p.muted)
                            }
                            Spacer()
                            Button(L("使用")) { model.useUserTemplate(template,on: targetID) }.disabled(model.monitors.isEmpty || model.launching)
                            Button(L("编辑")) { model.openUserTemplateEditor(template) }
                            Button { model.deleteUserTemplate(template) } label: { Image(systemName: "trash") }.help(L("删除"))
                        }.controlSize(.small).padding(10).background(p.raised,in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.padding(.top,8)
            Text(model.message).font(.system(size: 10)).foregroundStyle(model.messageIsError ? .orange : p.muted)
            Text(L("可只配置一个屏幕，其他屏幕保持不参与。推荐依据可用尺寸与方向，不保证每个 App 的最小窗口尺寸都适配。"))
                .font(.system(size: 10)).foregroundStyle(p.muted).fixedSize(horizontal: false,vertical: true)
        }.padding(18).consolePanel(p)
    }
}
