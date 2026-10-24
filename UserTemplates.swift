import AppKit
import SwiftUI

struct UserTemplateRegion: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var frame: Frame
    var bundleID: String? = nil
    var appName: String? = nil
}
struct UserLayoutTemplate: Codable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var sourceAspect: Double
    var regions: [UserTemplateRegion]
}
func validUserTemplate(_ template: UserLayoutTemplate) -> Bool {
    !template.id.isEmpty && !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && template.name.count <= 100 && template.sourceAspect.isFinite && (0.1...10).contains(template.sourceAspect) && (1...32).contains(template.regions.count) && Set(template.regions.map(\.id)).count == template.regions.count && template.regions.allSatisfy {
        let f = $0.frame
        return !$0.id.isEmpty && $0.title.count <= 100 && [f.x,f.y,f.width,f.height].allSatisfy(\.isFinite) && f.x >= 0 && f.y >= 0 && f.width >= 0.05 && f.height >= 0.05 && f.x+f.width <= 1.000001 && f.y+f.height <= 1.000001 && ($0.bundleID?.count ?? 0) <= 256 && ($0.appName?.count ?? 0) <= 256
    }
}
func templatesFromLayout(_ layout: Layout) -> [UserLayoutTemplate] {
    layout.monitors.compactMap { screen in
        let slots = layout.windows.filter { $0.monitorID == screen.id && $0.enabled }
        guard !slots.isEmpty, slots.count <= 32 else { return nil }
        let regions = slots.enumerated().map { index, slot in
            let w = min(1,max(0.05,slot.relative.width)), h = min(1,max(0.05,slot.relative.height))
            let frame = Frame(x: min(1-w,max(0,slot.relative.x)),y: min(1-h,max(0,slot.relative.y)),width: w,height: h)
            return UserTemplateRegion(title: L("区域 \(index+1)"),frame: frame,bundleID: slot.bundleID,appName: slot.appName)
        }
        return UserLayoutTemplate(name: layout.name+" · "+screen.name,sourceAspect: screen.visible.width/screen.visible.height,regions: regions)
    }
}
extension Controller {
    func openUserTemplateEditor(_ template: UserLayoutTemplate? = nil) {
        editingTemplate = template
        showUserTemplateEditor = true
    }
    @discardableResult
    func saveUserTemplate(_ template: UserLayoutTemplate) -> Bool {
        guard validUserTemplate(template), state.userTemplates.count < 100 || state.userTemplates.contains(where: { $0.id == template.id }) else { tell(L("模板无效：请检查名称、区域边界和数量。"),error: true); return false }
        let previous = state.userTemplates
        if let index = state.userTemplates.firstIndex(where: { $0.id == template.id }) { state.userTemplates[index] = template }
        else { state.userTemplates.append(template) }
        guard persist() else { state.userTemplates = previous; return false }
        tell(L("模板已保存到布局库。")); return true
    }
    func addCurrentSceneToLibrary() {
        guard let current else { return }
        guard !current.monitors.contains(where: { screen in current.windows.filter { $0.enabled && $0.monitorID == screen.id }.count > 32 }) else { tell(L("每个屏幕最多支持 32 个模板区域，请先减少窗口数量。"),error: true); return }
        let templates = templatesFromLayout(current)
        guard !templates.isEmpty, templates.allSatisfy(validUserTemplate), state.userTemplates.count+templates.count <= 100 else { tell(L("没有可添加的区域，或模板库已达到 100 个模板。"),error: true); return }
        let previous = state.userTemplates
        state.userTemplates += templates
        guard persist() else { state.userTemplates = previous; return }
        selectedPage = "library"
        tell(L("已将场景按屏幕添加到我的模板。"))
    }
    func useUserTemplate(_ template: UserLayoutTemplate, on screenID: String) {
        guard !launching else { return }
        presetScreenID = screenID; presetPattern = nil; selectedUserTemplate = template; showPresetEditor = true
    }
    func deleteUserTemplate(_ template: UserLayoutTemplate) {
        let alert = NSAlert(); alert.messageText = L("删除模板“\(template.name)”？")
        alert.informativeText = L("已保存的场景与当前窗口不会改变。")
        alert.addButton(withTitle: L("删除")); alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let previous = state.userTemplates
        state.userTemplates.removeAll { $0.id == template.id }
        if !persist() { state.userTemplates = previous }
    }
}
struct UserTemplateEditor: View {
    @ObservedObject var model: Controller
    @Environment(\.dismiss) private var dismiss
    @State private var draft = UserLayoutTemplate(name: L("我的新模板"),sourceAspect: 1.6,regions: [UserTemplateRegion(title: L("主工作区"),frame: Frame(x: 0,y: 0,width: 1,height: 1))])
    @State private var saveError = ""
    @State private var referenceID = ""
    private var p: ConsolePalette { ConsolePalette(model.darkAppearance ? .dark : .light) }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            HStack {
                Text(L("自定义模板")).font(.system(size: 20,weight: .semibold))
                Spacer()
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField(L("模板名称"),text: $draft.name).textFieldStyle(.roundedBorder)
                Picker(L("显示器"),selection: $referenceID) {
                    Text(L("自定义模板")).tag("")
                    ForEach(model.monitors) { Text($0.name).tag($0.id) }
                }.frame(width: 250)
            }
            Text(L("以百分比设置区域。位置与尺寸按目标屏幕缩放；区域可重叠。"))
                .font(.system(size: 11)).foregroundStyle(p.muted)
            HStack(alignment: .top,spacing: 18) {
                TemplatePreview(template: draft,p: p).frame(width: 220,height: 280).consolePanel(p)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($draft.regions) { $region in
                            VStack(alignment: .leading,spacing: 7) {
                                HStack {
                                    TextField(L("区域名称"),text: $region.title).textFieldStyle(.roundedBorder)
                                    Button { draft.regions.removeAll { $0.id == region.id } } label: { Image(systemName: "minus.circle") }.disabled(draft.regions.count == 1).help(L("移除区域"))
                                }
                                HStack {
                                    percent(L("左"),region: $region,key: \.x)
                                    percent(L("上"),region: $region,key: \.y)
                                    percent(L("宽"),region: $region,key: \.width)
                                    percent(L("高"),region: $region,key: \.height)
                                }
                            }.padding(10).consolePanel(p)
                        }
                        Button(L("添加区域")) {
                            draft.regions.append(UserTemplateRegion(title: L("区域 \(draft.regions.count+1)"),frame: Frame(x: 0,y: 0,width: 0.5,height: 0.5)))
                        }.disabled(draft.regions.count >= 32)
                    }
                }
            }
            if !saveError.isEmpty { Text(saveError).font(.system(size: 11)).foregroundStyle(.orange) }
            if !validUserTemplate(draft) { Text(L("模板无效：请检查名称、区域边界和数量。")).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Text(L("模板保存后，在布局库选择使用，再为各区域选择 App。"))
                    .font(.system(size: 10)).foregroundStyle(p.muted)
                Spacer()
                Button(L("保存模板")) { if model.saveUserTemplate(draft) { dismiss() } else { saveError = model.message } }
                    .buttonStyle(.borderedProminent).disabled(!validUserTemplate(draft))
            }
        }.padding(24).frame(width: 850,height: 600).background(p.background).foregroundStyle(p.text).tint(p.accent)
            .environment(\.colorScheme,model.darkAppearance ? .dark : .light)
            .environment(\.locale,Locale(identifier: model.state.preferences.language.resolvedCode))
            .environment(\.layoutDirection,model.state.preferences.language.isRightToLeft ? .rightToLeft : .leftToRight)
            .onAppear {
                if let original = model.editingTemplate {
                    draft = original
                    referenceID = model.monitors.first { abs($0.visible.width/$0.visible.height-original.sourceAspect) < 0.01 }?.id ?? ""
                } else if let screen = model.monitors.first(where: { $0.isPrimary }) ?? model.monitors.first {
                    draft.sourceAspect = screen.visible.width/screen.visible.height; referenceID = screen.id
                }
            }
            .onChange(of: referenceID) { _, id in
                if let screen = model.monitors.first(where: { $0.id == id }) { draft.sourceAspect = screen.visible.width/screen.visible.height }
            }
    }
    private func percent(_ title: String,region: Binding<UserTemplateRegion>,key: WritableKeyPath<Frame,Double>) -> some View {
        HStack(spacing: 3) {
            Text(title).font(.system(size: 10))
            TextField("%",value: Binding(get: { region.wrappedValue.frame[keyPath: key]*100 },set: { value in
                if value.isFinite { region.wrappedValue.frame[keyPath: key] = min(100,max(0,value))/100 }
            }),format: .number.precision(.fractionLength(0...1))).textFieldStyle(.roundedBorder).frame(width: 54)
        }
    }
}
struct TemplatePreview: View {
    let template: UserLayoutTemplate
    let p: ConsolePalette
    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width,geometry.size.height*template.sourceAspect)
            let height = width/template.sourceAspect
            ZStack {
                ForEach(Array(template.regions.enumerated()),id: \.element.id) { index, region in
                    RoundedRectangle(cornerRadius: 4).fill(p.accent.opacity(0.15+Double(index%3)*0.16))
                        .overlay(Text("\(index+1)").font(.system(size: 10,design: .monospaced)))
                        .frame(width: max(1,width*region.frame.width-3),height: max(1,height*region.frame.height-3))
                        .position(x: width*(region.frame.x+region.frame.width/2),y: height*(region.frame.y+region.frame.height/2))
                }
            }.frame(width: width,height: height).frame(maxWidth: .infinity,maxHeight: .infinity)
        }.padding(8).clipped().accessibilityHidden(true)
    }
}
