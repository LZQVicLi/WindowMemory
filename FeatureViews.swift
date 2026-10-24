import SwiftUI

struct SceneSelector: View {
    @ObservedObject var model: Controller
    let p: ConsolePalette
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading,spacing: 4) {
                Text("当前场景").font(.system(size: 11,weight: .medium))
                Text("SCENE").font(.system(size: 8,design: .monospaced)).tracking(1).foregroundStyle(p.muted)
            }
            Picker("当前场景",selection: Binding(get: { model.current?.id ?? "" },set: { model.selectScene($0) })) {
                if model.current == nil { Text(model.scenes.isEmpty ? "尚未保存场景" : "请选择场景").tag("") }
                ForEach(model.scenes) { Text($0.name).tag($0.id) }
            }.labelsHidden().frame(maxWidth: 250)
            Spacer()
            Button { model.newScene() } label: { Label("新建",systemImage: "plus") }.controlSize(.small)
            Menu {
                Button("重命名…") { model.renameScene() }.disabled(model.current == nil)
                Button("导出当前场景…") { model.exportLayouts(currentOnly: true) }.disabled(model.current == nil)
                Button("导出全部场景…") { model.exportLayouts() }.disabled(model.state.layouts.isEmpty)
                Button("导入场景…") { model.importLayouts() }
                Divider()
                Button("删除当前场景…",role: .destructive) { model.deleteCurrent() }.disabled(model.current == nil)
            } label: { Image(systemName: "ellipsis").frame(width: 20) }.menuStyle(.borderlessButton).fixedSize()
        }.padding(14).consolePanel(p)
    }
}

struct AutomationView: View {
    @ObservedObject var model: Controller
    let p: ConsolePalette
    var body: some View {
        VStack(alignment: .leading,spacing: 20) {
            VStack(alignment: .leading,spacing: 15) {
                HStack {
                    Text("全局快捷键").font(.system(size: 13,weight: .semibold))
                    Spacer()
                    Toggle("启用全局快捷键",isOn: Binding(get: { model.state.preferences.shortcutsEnabled },set: { model.setPreference(\.shortcutsEnabled,$0) })).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
                }
                Text("在其他 App 中也可使用，作用于当前屏幕组合选中的场景。").font(.system(size: 10)).foregroundStyle(p.muted)
                ForEach(model.state.preferences.shortcuts) { shortcut in
                    HStack {
                        Text(shortcut.action.title).font(.system(size: 12))
                        Spacer()
                        Picker("\(shortcut.action.title)修饰键",selection: Binding(get: { shortcut.modifiers },set: { model.setShortcut(shortcut.action,modifiers: $0) })) {
                            ForEach(Shortcut.modifierChoices,id: \.1) { Text($0.0).tag($0.1) }
                        }.labelsHidden().frame(width: 120)
                        Picker("\(shortcut.action.title)按键",selection: Binding(get: { shortcut.keyCode },set: { model.setShortcut(shortcut.action,keyCode: $0) })) {
                            ForEach(Shortcut.keys,id: \.1) { Text($0.0).tag($0.1) }
                        }.labelsHidden().frame(width: 95)
                    }.disabled(!model.state.preferences.shortcutsEnabled)
                }
                if model.hotKeyErrors.isEmpty {
                    Text(model.demoMode ? "示例模式不注册真实快捷键。" : "若组合已被系统或其他 App 占用，会保留原设置并提示。").font(.system(size: 10)).foregroundStyle(p.muted)
                } else {
                    ForEach(model.hotKeyErrors,id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(.orange) }
                }
            }.padding(18).consolePanel(p)
            SceneSelector(model: model,p: p)
            VStack(alignment: .leading,spacing: 15) {
                HStack {
                    Text("启动顺序与等待时间").font(.system(size: 13,weight: .semibold))
                    Spacer()
                    Text("PER APP").font(.system(size: 8,design: .monospaced)).tracking(1).foregroundStyle(p.muted)
                }
                Text("“间隔”控制打开后等待多久再启动下一个 App；“窗口”等待用于持续尝试匹配和归位，最长 120 秒。已经成功归位的窗口不重复移动。").font(.system(size: 10)).foregroundStyle(p.muted).fixedSize(horizontal: false,vertical: true)
                ForEach(Array(model.targets.enumerated()),id: \.element.id) { index,target in
                    LaunchTimingRow(target: target,index: index,count: model.targets.count,model: model,p: p)
                    if index < model.targets.count-1 { Rectangle().fill(p.border).frame(height: 1) }
                }
                if model.targets.isEmpty { Text("请先保存场景并勾选需要启动的 App。").font(.system(size: 11)).foregroundStyle(p.muted) }
            }.padding(18).consolePanel(p)
            Text(model.message).font(.system(size: 11)).foregroundStyle(model.messageIsError ? .orange : p.muted)
        }
    }
}

struct LaunchTimingRow: View {
    let target: LaunchTarget; let index: Int; let count: Int
    @ObservedObject var model: Controller
    let p: ConsolePalette
    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d",index+1)).font(.system(size: 10,design: .monospaced)).foregroundStyle(p.accent)
            Text(target.name).font(.system(size: 11,weight: .medium)).lineLimit(1).frame(maxWidth: .infinity,alignment: .leading)
            HStack(spacing: 3) {
                Button { model.changeLaunchOrder(target.id,by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0 || model.launching).help("提前启动 \(target.name)").accessibilityLabel("提前启动 \(target.name)")
                Button { model.changeLaunchOrder(target.id,by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == count-1 || model.launching).help("推后启动 \(target.name)").accessibilityLabel("推后启动 \(target.name)")
            }.buttonStyle(.borderless).font(.system(size: 10))
            Stepper(value: Binding(get: { target.delay },set: { model.setLaunchTiming(target.id,delay: $0) }),in: 0...120,step: 0.5) {
                Text("间隔 \(target.delay.formatted(.number.precision(.fractionLength(0...1))))s").font(.system(size: 10,design: .monospaced))
            }.frame(width: 122).disabled(model.launching)
            Stepper(value: Binding(get: { target.windowTimeout },set: { model.setLaunchTiming(target.id,timeout: $0) }),in: 5...120,step: 5) {
                Text("窗口 \(Int(target.windowTimeout))s").font(.system(size: 10,design: .monospaced))
            }.frame(width: 120).disabled(model.launching)
        }.padding(.vertical,7)
    }
}
