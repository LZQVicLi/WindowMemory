import AppKit
import SwiftUI
import ServiceManagement

struct ConsolePalette {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var background: Color { dark ? Color(hex: 0x0b1014) : Color(hex: 0xf3f6f5) }
    var sidebar: Color { dark ? Color(hex: 0x0f171c) : Color(hex: 0xe9efec) }
    var panel: Color { dark ? Color(hex: 0x111b21) : .white }
    var raised: Color { dark ? Color(hex: 0x19262c) : Color(hex: 0xeff4f1) }
    var border: Color { dark ? Color(hex: 0x273b40) : Color(hex: 0xd5e1db) }
    var text: Color { dark ? Color(hex: 0xe5f1ed) : Color(hex: 0x142c25) }
    var muted: Color { dark ? Color(hex: 0x93aaa6) : Color(hex: 0x60776d) }
    var accent: Color { dark ? Color(hex: 0x70efba) : Color(hex: 0x11764c) }
    var cyan: Color { dark ? Color(hex: 0x78cce6) : Color(hex: 0x236b86) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255)/255,green: Double((hex >> 8) & 255)/255,blue: Double(hex & 255)/255)
    }
}
extension View {
    func consolePanel(_ p: ConsolePalette) -> some View {
        self.background(p.panel,in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.border,lineWidth: 1))
    }
}

struct MainView: View {
    @ObservedObject var model: Controller
    var body: some View {
        ConsoleShell(model: model).preferredColorScheme(model.state.preferences.appearance == .system ? nil : (model.state.preferences.appearance == .dark ? .dark : .light))
    }
}

struct ConsoleShell: View {
    @ObservedObject var model: Controller
    @Environment(\.colorScheme) private var scheme
    private var p: ConsolePalette { ConsolePalette(scheme) }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(p.border).frame(width: 1)
            VStack(spacing: 0) {
                header
                Rectangle().fill(p.border).frame(height: 1)
                ScrollView {
                    if model.selectedPage == "settings" { SettingsView(model: model,p: p).padding(24) }
                    else if model.selectedPage == "automation" { AutomationView(model: model,p: p).padding(24) }
                    else { WorkspaceView(model: model,p: p).padding(24) }
                }
            }.background(p.background)
        }.foregroundStyle(p.text).tint(p.accent).background(p.background).ignoresSafeArea()
    }
    private var sidebar: some View {
        VStack(alignment: .leading,spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.3.group").font(.system(size: 23,weight: .medium)).foregroundStyle(p.accent)
                VStack(alignment: .leading,spacing: 3) {
                    Text("窗口记忆").font(.system(size: 17,weight: .semibold))
                    Text("WINDOW MEMORY").font(.system(size: 8,weight: .medium,design: .monospaced)).tracking(1.4).foregroundStyle(p.muted)
                }
            }.padding(.bottom,36)
            Text("WORKSPACE").font(.system(size: 9,weight: .medium,design: .monospaced)).tracking(1.5).foregroundStyle(p.muted).padding(.leading,10).padding(.bottom,12)
            nav("布局控制台",icon: "square.grid.2x2",page: "workspace")
            nav("启动与快捷键",icon: "keyboard",page: "automation")
            nav("设置",icon: "slider.horizontal.3",page: "settings").keyboardShortcut(",",modifiers: .command)
            Spacer(minLength: 30)
            VStack(alignment: .leading,spacing: 15) {
                HStack(spacing: 7) {
                    Circle().fill(model.permitted ? p.accent : .orange).frame(width: 5,height: 5)
                    Text(model.permitted ? "窗口控制已授权" : "等待窗口控制权限").font(.system(size: 10))
                }
                HStack(spacing: 7) {
                    Image(systemName: "power").font(.system(size: 10))
                    Text(model.loginEnabled ? "登录启动已开启" : "登录启动未开启").font(.system(size: 10))
                }.foregroundStyle(p.muted)
                Rectangle().fill(p.border).frame(height: 1)
                HStack {
                    Text("LOCAL / v1.2").font(.system(size: 9,design: .monospaced)).foregroundStyle(p.muted)
                    Spacer()
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 12)) }
                        .buttonStyle(.plain).help("退出窗口记忆").accessibilityLabel("退出窗口记忆")
                }
            }
        }.padding(.horizontal,18).padding(.top,56).padding(.bottom,22).frame(width: 192).background(p.sidebar)
    }
    private func nav(_ title: String, icon: String, page: String) -> some View {
        let selected = model.selectedPage == page
        return Button { model.selectedPage = page } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 16)
                Text(title).font(.system(size: 12,weight: selected ? .semibold : .regular))
                Spacer()
                if selected { Rectangle().fill(p.accent).frame(width: 3,height: 13) }
            }.foregroundStyle(selected ? p.accent : p.muted).padding(.horizontal,11).padding(.vertical,13)
                .background(selected ? p.accent.opacity(0.08) : .clear,in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).padding(.bottom,7)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading,spacing: 5) {
                Text(model.selectedPage == "settings" ? "PREFERENCES / PERSONAL" : (model.selectedPage == "automation" ? "AUTOMATION / SHORTCUTS" : "WORKSPACE / CONTROL"))
                    .font(.system(size: 9,weight: .medium,design: .monospaced)).tracking(1.6).foregroundStyle(p.muted)
                Text(model.selectedPage == "settings" ? "设置" : (model.selectedPage == "automation" ? "启动与快捷键" : "布局控制台")).font(.system(size: 23,weight: .semibold))
            }
            Spacer()
            Button { model.setPreference(\.automatic,!model.state.preferences.automatic) } label: {
                HStack(spacing: 7) {
                    Circle().fill(model.state.preferences.automatic ? p.accent : p.muted).frame(width: 5,height: 5)
                    Text(model.state.preferences.automatic ? "AUTO ON" : "PAUSED").font(.system(size: 10,weight: .medium,design: .monospaced)).tracking(0.8)
                }.foregroundStyle(model.state.preferences.automatic ? p.accent : p.muted)
                    .padding(.horizontal,12).padding(.vertical,9).background(p.raised,in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.border,lineWidth: 1))
            }.buttonStyle(.plain).help("暂停或继续自动恢复").accessibilityLabel(model.state.preferences.automatic ? "暂停自动恢复" : "继续自动恢复")
        }.padding(.horizontal,26).padding(.top,43).padding(.bottom,18)
    }
}

struct WorkspaceView: View {
    @ObservedObject var model: Controller
    let p: ConsolePalette
    var body: some View {
        VStack(alignment: .leading,spacing: 17) {
            if !model.permitted {
                HStack(spacing: 12) {
                    Image(systemName: "lock.open").foregroundStyle(.orange)
                    VStack(alignment: .leading,spacing: 4) {
                        Text("允许控制窗口，才能恢复布局").font(.system(size: 12,weight: .medium))
                        Text("在系统设置中开启“窗口记忆”的窗口控制权限。").font(.system(size: 10)).foregroundStyle(p.muted)
                    }
                    Spacer()
                    Button("开启权限") { WindowAccess.requestPermission() }.controlSize(.small)
                }.padding(14).consolePanel(p)
            }
            SceneSelector(model: model,p: p)
            HStack(spacing: 12) {
                MetricCard(title: "显示器",label: "DISPLAYS",value: model.monitors.count,icon: "display.2",p: p)
                MetricCard(title: "布局 App",label: "APPLICATIONS",value: model.targets.count,icon: "app.dashed",p: p)
                MetricCard(title: "已保存窗口",label: "WINDOWS",value: model.current?.windows.count ?? 0,icon: "macwindow",p: p)
            }
            VStack(alignment: .leading,spacing: 0) {
                HStack {
                    Label("屏幕与窗口布局",systemImage: "viewfinder").font(.system(size: 12,weight: .medium))
                    Spacer()
                    Text(model.current == nil ? "UNSAVED" : "SAVED").font(.system(size: 9,weight: .medium,design: .monospaced)).tracking(1).foregroundStyle(model.current == nil ? p.muted : p.accent)
                }.padding(.horizontal,16).padding(.top,15)
                ZStack {
                    GridBackground(color: p.border.opacity(0.6))
                    MonitorDiagram(monitors: model.monitors,slots: model.current?.windows ?? [],p: p).padding(.horizontal,30).padding(.vertical,16)
                }.frame(height: 166).padding(.top,6)
                HStack {
                    Text(model.current == nil ? "把窗口摆好，然后记住当前布局。" : "当前屏幕组合已匹配")
                    Spacer()
                    if let layout = model.current {
                        Text(layout.updatedAt.formatted(date: .abbreviated,time: .shortened)).font(.system(size: 9,design: .monospaced))
                    }
                }.font(.system(size: 10)).foregroundStyle(p.muted).padding(.horizontal,16).padding(.bottom,13)
            }.consolePanel(p)
            HStack(spacing: 10) {
                action("记住布局",icon: "square.and.arrow.down",primary: false) { model.saveLayout() }.disabled(!model.permitted || model.busy || model.launching)
                action("恢复位置",icon: "arrow.uturn.backward",primary: false) { model.restore(manual: true) }.disabled(!model.permitted || model.current == nil || model.busy || model.launching)
                action(model.launching ? "取消启动" : "启动 App 并恢复",icon: model.launching ? "stop.fill" : "play.fill",primary: true) {
                    if model.launching { model.cancelLaunch() } else { model.launchAndRestore() }
                }.disabled(model.targets.isEmpty || model.busy)
                Menu {
                    Button("撤销上次手动恢复") { model.undo() }.disabled(!model.canUndo)
                    Button("打开布局文件夹") { NSWorkspace.shared.open(model.folder) }
                    Divider()
                    Button("重命名当前场景…") { model.renameScene() }.disabled(model.current == nil)
                    Button("导出当前场景…") { model.exportLayouts(currentOnly: true) }.disabled(model.current == nil)
                    Button("删除当前场景…",role: .destructive) { model.deleteCurrent() }.disabled(model.current == nil)
                } label: { Image(systemName: "ellipsis").frame(width: 24,height: 28) }.menuStyle(.borderlessButton).fixedSize().foregroundStyle(p.muted)
            }
            HStack(alignment: .top,spacing: 8) {
                Text(model.messageIsError ? "!" : ">").font(.system(size: 12,weight: .bold,design: .monospaced)).foregroundStyle(model.messageIsError ? .orange : p.accent)
                Text(model.launching ? model.launchProgress : model.message).font(.system(size: 11)).foregroundStyle(model.messageIsError ? .orange : p.muted).textSelection(.enabled)
                Spacer(minLength: 0)
                if model.launching { ProgressView().controlSize(.small).scaleEffect(0.7) }
            }.padding(.horizontal,3).frame(minHeight: 18)
            if !model.launchFailures.isEmpty {
                VStack(alignment: .leading,spacing: 5) {
                    ForEach(model.launchFailures,id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(.orange) }
                }.padding(12).frame(maxWidth: .infinity,alignment: .leading).consolePanel(p)
            }
            windowList
            HStack {
                Image(systemName: "internaldrive").font(.system(size: 9))
                Text("布局保存在本机 · 全屏、最小化及其他空间中的窗口可能受系统限制。")
                Spacer()
            }.font(.system(size: 9)).foregroundStyle(p.muted)
        }
    }
    private func action(_ title: String, icon: String, primary: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title,systemImage: icon).font(.system(size: 12,weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical,13)
                .foregroundStyle(primary ? (p.dark ? Color(hex: 0x092a1c) : .white) : p.text)
                .background(primary ? p.accent : p.raised,in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(primary ? p.accent : p.border,lineWidth: 1))
        }.buttonStyle(ConsoleButtonStyle())
    }
    private var windowList: some View {
        VStack(alignment: .leading,spacing: 0) {
            HStack {
                Text("布局中的窗口").font(.system(size: 12,weight: .semibold))
                Spacer()
                Text("勾选参与启动与恢复").font(.system(size: 10)).foregroundStyle(p.muted)
            }.padding(16)
            Rectangle().fill(p.border).frame(height: 1)
            if let layout = model.current, !layout.windows.isEmpty {
                ForEach(Array(layout.windows.enumerated()),id: \.element.id) { index,slot in
                    WindowRow(slot: slot,index: index,layout: layout,model: model,p: p)
                    if index != layout.windows.count-1 { Rectangle().fill(p.border.opacity(0.6)).frame(height: 1).padding(.horizontal,16) }
                }
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "square.dashed").font(.system(size: 23)).foregroundStyle(p.accent.opacity(0.6))
                    Text("还没有记录窗口").font(.system(size: 12,weight: .medium))
                    Text("打开常用 App，摆好窗口后点击“记住布局”。").font(.system(size: 10)).foregroundStyle(p.muted)
                }.frame(maxWidth: .infinity).padding(32)
            }
        }.consolePanel(p)
    }
}

struct ConsoleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.35)
    }
}

struct MetricCard: View {
    let title: String; let label: String; let value: Int; let icon: String; let p: ConsolePalette
    var body: some View {
        HStack {
            VStack(alignment: .leading,spacing: 6) {
                Text(label).font(.system(size: 8,weight: .medium,design: .monospaced)).tracking(1).foregroundStyle(p.muted)
                HStack(alignment: .firstTextBaseline,spacing: 9) {
                    Text(String(format: "%02d",value)).font(.system(size: 28,weight: .medium,design: .monospaced)).foregroundStyle(p.accent)
                    Text(title).font(.system(size: 10)).foregroundStyle(p.muted)
                }
            }
            Spacer(minLength: 5)
            Image(systemName: icon).font(.system(size: 18,weight: .light)).foregroundStyle(p.muted.opacity(0.6))
        }.padding(15).frame(maxWidth: .infinity).consolePanel(p)
    }
}

struct WindowRow: View {
    let slot: WindowSlot; let index: Int; let layout: Layout
    @ObservedObject var model: Controller
    let p: ConsolePalette
    var body: some View {
        HStack(spacing: 10) {
            Toggle("参与启动与恢复：\(slot.appName)",isOn: Binding(get: { slot.enabled },set: { model.setSlot(slot.id,enabled: $0) })).labelsHidden().toggleStyle(.checkbox)
            Text(String(format: "%02d",index+1)).font(.system(size: 9,design: .monospaced)).foregroundStyle(p.muted.opacity(0.7)).frame(width: 17)
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: slot.bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 25,height: 25)
            } else { Image(systemName: "app.dashed").frame(width: 25,height: 25).foregroundStyle(p.muted) }
            VStack(alignment: .leading,spacing: 4) {
                HStack(spacing: 7) {
                    Text(slot.appName).font(.system(size: 12,weight: .medium))
                    Circle().fill(model.runningBundleIDs.contains(slot.bundleID) ? p.accent : p.muted.opacity(0.4)).frame(width: 4,height: 4)
                }
                Text(slot.title.isEmpty ? "普通窗口" : slot.title).font(.system(size: 9)).foregroundStyle(p.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let monitor = layout.monitors.first(where: { $0.id == slot.monitorID }) {
                let f = slot.relative.placed(in: monitor.visible)
                VStack(alignment: .trailing,spacing: 4) {
                    Text(monitor.name).font(.system(size: 9)).foregroundStyle(p.cyan).lineLimit(1)
                    Text("\(Int(f.width)) × \(Int(f.height)) pt").font(.system(size: 10,design: .monospaced)).foregroundStyle(p.muted)
                }.frame(maxWidth: 170,alignment: .trailing)
            }
        }.padding(.horizontal,16).padding(.vertical,12).opacity(slot.enabled ? 1 : 0.45)
    }
}

struct SettingsView: View {
    @ObservedObject var model: Controller
    let p: ConsolePalette
    func preference(_ key: WritableKeyPath<Preferences,Bool>) -> Binding<Bool> {
        Binding(get: { model.state.preferences[keyPath: key] },set: { model.setPreference(key,$0) })
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 20) {
            VStack(alignment: .leading,spacing: 15) {
                sectionTitle("外观",code: "APPEARANCE")
                HStack(spacing: 12) {
                    ForEach(AppearanceMode.allCases) { mode in
                        appearanceButton(mode)
                    }
                }
                Text("外观设置只影响窗口记忆，切换后立即生效。").font(.system(size: 10)).foregroundStyle(p.muted)
            }.padding(18).consolePanel(p)
            VStack(alignment: .leading,spacing: 0) {
                sectionTitle("开机与登录",code: "STARTUP").padding(18)
                SettingRow(title: "登录时启动窗口记忆",detail: "登录 Mac 后自动运行，菜单栏保持可用。",value: Binding(get: { model.loginEnabled || model.loginNeedsApproval },set: { model.setLogin($0) }),p: p)
                SettingRow(title: "登录启动后显示主界面",detail: "开启后直接显示控制台；关闭后安静运行在菜单栏。",value: preference(\.showWindowOnLogin),p: p)
                SettingRow(title: "登录时启动布局中的 App",detail: "自动打开当前屏幕布局勾选的 App，并等待窗口归位。",value: preference(\.launchAppsOnLogin),p: p)
                if model.loginNeedsApproval {
                    Button("在系统设置中允许登录启动") { ServiceManagement.SMAppService.openSystemSettingsLoginItems() }.font(.system(size: 11)).padding(16)
                }
            }.consolePanel(p)
            VStack(alignment: .leading,spacing: 0) {
                sectionTitle("自动恢复",code: "AUTOMATION").padding(18)
                SettingRow(title: "启用自动恢复",detail: "暂停后仍可手动恢复或一键启动工作区。",value: preference(\.automatic),p: p)
                VStack(spacing: 0) {
                    SettingRow(title: "App 启动时",detail: "软件打开后，恢复已记住的窗口位置。",value: preference(\.onLaunch),p: p)
                    SettingRow(title: "新窗口出现时",detail: "匹配保存的窗口记录；额外窗口保持当前位置。",value: preference(\.onNewWindow),p: p)
                    SettingRow(title: "屏幕连接变化时",detail: "按当前屏幕组合切换到对应布局。",value: preference(\.onDisplay),p: p)
                    SettingRow(title: "电脑唤醒时",detail: "等待显示器就绪后恢复窗口。",value: preference(\.onWake),p: p)
                }.disabled(!model.state.preferences.automatic).opacity(model.state.preferences.automatic ? 1 : 0.45)
            }.consolePanel(p)
            VStack(alignment: .leading,spacing: 14) {
                sectionTitle("数据与权限",code: "LOCAL STORAGE")
                HStack {
                    VStack(alignment: .leading,spacing: 5) {
                        Text(model.permitted ? "窗口控制权限已开启" : "需要开启窗口控制权限").font(.system(size: 12,weight: .medium))
                        Text("\(model.state.layouts.count) 套布局 · 数据仅保存在本机").font(.system(size: 10)).foregroundStyle(p.muted)
                    }
                    Spacer()
                    Button("系统权限设置") { WindowAccess.requestPermission() }.controlSize(.small)
                    Button("布局文件夹") { NSWorkspace.shared.open(model.folder) }.controlSize(.small)
                }
                HStack {
                    Button("导出全部场景…") { model.exportLayouts() }.disabled(model.state.layouts.isEmpty)
                    Button("导入场景…") { model.importLayouts() }
                    Spacer()
                    Text("跨 Mac 导入时可重新匹配屏幕").font(.system(size: 10)).foregroundStyle(p.muted)
                }
            }.padding(18).consolePanel(p)
            HStack {
                Text("WINDOW MEMORY / 1.2.0").font(.system(size: 9,design: .monospaced)).tracking(1)
                Spacer()
                Text(model.message).font(.system(size: 10)).lineLimit(2)
            }.foregroundStyle(model.messageIsError ? .orange : p.muted)
        }
    }
    private func sectionTitle(_ title: String,code: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13,weight: .semibold))
            Spacer()
            Text(code).font(.system(size: 8,design: .monospaced)).tracking(1.2).foregroundStyle(p.muted)
        }
    }
    private func appearanceButton(_ mode: AppearanceMode) -> some View {
        let selected = model.state.preferences.appearance == mode
        return Button { model.setAppearance(mode) } label: {
            VStack(alignment: .leading,spacing: 12) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5).fill(mode == .light ? Color(hex: 0xe7efeb) : Color(hex: 0x0b1118))
                    if mode == .system { Rectangle().fill(Color(hex: 0xe7efeb)).frame(width: 54).clipShape(UnevenRoundedRectangle(topLeadingRadius: 5,bottomLeadingRadius: 5)).frame(maxWidth: .infinity,alignment: .leading) }
                    HStack(alignment: .top,spacing: 7) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x2b8462)).frame(width: 17)
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x789b8a).opacity(0.6)).frame(height: 5)
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x789b8a).opacity(0.25))
                        }
                    }.padding(10)
                }.frame(height: 61)
                HStack {
                    Text(mode.title).font(.system(size: 11,weight: .medium))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? p.accent : p.muted.opacity(0.4)).font(.system(size: 12))
                }
            }.padding(12).frame(maxWidth: .infinity).background(selected ? p.accent.opacity(0.06) : p.raised,in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? p.accent : p.border,lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel("外观：\(mode.title)").accessibilityValue(selected ? "已选择" : "未选择")
    }
}

struct SettingRow: View {
    let title: String; let detail: String
    @Binding var value: Bool
    let p: ConsolePalette
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(p.border.opacity(0.7)).frame(height: 1)
            HStack(spacing: 20) {
                VStack(alignment: .leading,spacing: 5) {
                    Text(title).font(.system(size: 12,weight: .medium))
                    Text(detail).font(.system(size: 10)).foregroundStyle(p.muted).fixedSize(horizontal: false,vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(title,isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }.padding(.horizontal,18).padding(.vertical,14)
        }
    }
}

struct GridBackground: View {
    let color: Color
    var body: some View {
        Canvas { context,size in
            var path = Path()
            for x in stride(from: CGFloat(0),through: size.width,by: 22) { path.move(to: CGPoint(x: x,y: 0)); path.addLine(to: CGPoint(x: x,y: size.height)) }
            for y in stride(from: CGFloat(0),through: size.height,by: 22) { path.move(to: CGPoint(x: 0,y: y)); path.addLine(to: CGPoint(x: size.width,y: y)) }
            context.stroke(path,with: .color(color),lineWidth: 0.4)
        }.accessibilityHidden(true)
    }
}

struct MonitorDiagram: View {
    let monitors: [Monitor]; let slots: [WindowSlot]; let p: ConsolePalette
    var body: some View {
        GeometryReader { geo in
            let union = monitors.reduce(CGRect.null) { $0.union($1.bounds.rect) }
            let scale = min((geo.size.width-30)/max(1,union.width),(geo.size.height-25)/max(1,union.height))
            let originX = (geo.size.width-union.width*scale)/2
            let originY = (geo.size.height-union.height*scale)/2-6
            ForEach(Array(monitors.enumerated()),id: \.element.id) { index,m in
                let w = m.bounds.width*scale, h = m.bounds.height*scale
                let x = originX+(m.bounds.x-union.minX)*scale, y = originY+(m.bounds.y-union.minY)*scale
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4).fill(p.background.opacity(0.85))
                    ForEach(Array(slots.filter { $0.monitorID == m.id && $0.enabled }.enumerated()),id: \.element.id) { i,slot in
                        let tint = i.isMultiple(of: 2) ? p.accent : p.cyan
                        RoundedRectangle(cornerRadius: 2).fill(tint.opacity(0.13)).overlay(RoundedRectangle(cornerRadius: 2).stroke(tint.opacity(0.6),lineWidth: 0.7))
                            .frame(width: max(3,min(1,slot.relative.width)*max(1,w-6)),height: max(3,min(1,slot.relative.height)*max(1,h-6)))
                            .offset(x: 3+max(0,slot.relative.x)*(w-6),y: 3+max(0,slot.relative.y)*(h-6))
                    }
                    Text(String(format: "%02d",index+1)).font(.system(size: 8,weight: .medium,design: .monospaced)).foregroundStyle(p.accent).padding(4).background(p.panel,in: RoundedRectangle(cornerRadius: 2)).padding(4)
                }.frame(width: w,height: h).clipped().overlay(RoundedRectangle(cornerRadius: 4).stroke(p.accent.opacity(0.65),lineWidth: 1)).position(x: x+w/2,y: y+h/2)
                Text(m.name).font(.system(size: 8,design: .monospaced)).foregroundStyle(p.muted).lineLimit(1)
                    .frame(width: max(w,70)).position(x: x+w/2,y: y+h+10)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("当前连接 \(monitors.count) 个屏幕，已记录 \(slots.count) 个窗口")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: Controller!
    func applicationDidFinishLaunching(_ notification: Notification) { controller = Controller(); controller.start() }
    func applicationShouldHandleReopen(_ sender: NSApplication,hasVisibleWindows flag: Bool) -> Bool { controller.showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

if CommandLine.arguments.contains("--self-test") { runSelfTests() }
else if CommandLine.arguments.contains("--diagnostics") {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    print("Accessibility: \(WindowAccess.trusted)")
    for m in WindowAccess.monitors() { print("Monitor: \(m.name) \(m.id) \(m.bounds)") }
    print("Readable ordinary windows: \(WindowAccess.allWindows().count)")
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
