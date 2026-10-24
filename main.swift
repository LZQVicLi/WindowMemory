import AppKit
import SwiftUI

let accent = Color(red: 0.12,green: 0.46,blue: 0.40)

struct MainView: View {
    @ObservedObject var model: Controller
    func preference(_ key: WritableKeyPath<Preferences,Bool>) -> Binding<Bool> {
        Binding(get: { model.state.preferences[keyPath: key] },set: { model.setPreference(key,$0) })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading,spacing: 7) {
                        Text("让窗口，回到熟悉的位置。").font(.system(size: 27,weight: .semibold))
                        Text("摆好一次，记住每个 App 的屏幕、位置和大小。")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.state.preferences.automatic ? "自动恢复已开启" : "已暂停")
                        .font(.system(size: 11,weight: .medium)).padding(.horizontal,10).padding(.vertical,7)
                        .foregroundStyle(model.state.preferences.automatic ? accent : .secondary)
                        .background((model.state.preferences.automatic ? accent : .gray).opacity(0.10),in: Capsule())
                }
                if !model.permitted {
                    HStack(spacing: 14) {
                        Image(systemName: "hand.raised").font(.system(size: 22)).foregroundStyle(accent)
                        VStack(alignment: .leading,spacing: 5) {
                            Text("先允许窗口控制权限").font(.system(size: 14,weight: .semibold))
                            Text("在系统设置中开启“窗口记忆”，再回到这里保存布局。")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("去开启权限") { WindowAccess.requestPermission() }.controlSize(.large)
                    }.padding(16).background(accent.opacity(0.07),in: RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading,spacing: 12) {
                    HStack {
                        Label("当前屏幕组合",systemImage: "display.2").font(.system(size: 13,weight: .semibold))
                        Spacer()
                        Text("\(model.monitors.count) 个屏幕 · \(model.state.layouts.count) 套已保存布局")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    MonitorDiagram(monitors: model.monitors,slots: model.current?.windows ?? []).frame(height: 133)
                    HStack {
                        if let layout = model.current {
                            Text("已记住 \(layout.windows.count) 个窗口")
                            Spacer()
                            Text("更新于 \(layout.updatedAt.formatted(date: .abbreviated,time: .shortened))")
                        } else {
                            Text("这套屏幕还没有保存布局。接上常用屏幕，把窗口摆好后保存即可。")
                        }
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(18).background(Color(nsColor: .controlBackgroundColor),in: RoundedRectangle(cornerRadius: 16))
                HStack(spacing: 10) {
                    Button { model.saveLayout() } label: {
                        Label("记住当前布局",systemImage: "square.and.arrow.down")
                            .font(.system(size: 14,weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical,7)
                    }.buttonStyle(.borderedProminent).tint(accent).disabled(!model.permitted || model.busy)
                    Button { model.restore(manual: true) } label: {
                        Label("立即恢复",systemImage: "arrow.uturn.backward")
                            .font(.system(size: 14,weight: .medium)).frame(maxWidth: .infinity).padding(.vertical,7)
                    }.disabled(!model.permitted || model.current == nil || model.busy)
                    Menu {
                        Button("撤销上次手动恢复") { model.undo() }
                        Button("打开布局文件夹") { NSWorkspace.shared.open(model.folder) }
                        Divider()
                        Button("忘记当前布局…",role: .destructive) { model.deleteCurrent() }.disabled(model.current == nil)
                        Divider()
                        Button("退出窗口记忆") { NSApp.terminate(nil) }
                    } label: { Image(systemName: "ellipsis").frame(width: 24,height: 32) }.menuStyle(.borderlessButton).fixedSize()
                }
                Label(model.message,systemImage: model.messageIsError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 12)).foregroundStyle(model.messageIsError ? Color.orange : .secondary)
                    .fixedSize(horizontal: false,vertical: true)
                VStack(alignment: .leading,spacing: 13) {
                    HStack {
                        Text("自动归位").font(.system(size: 14,weight: .semibold))
                        Spacer()
                        Toggle("自动恢复",isOn: preference(\.automatic)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    HStack(spacing: 24) {
                        VStack(alignment: .leading,spacing: 10) {
                            Toggle("App 启动时",isOn: preference(\.onLaunch))
                            Toggle("新窗口出现时",isOn: preference(\.onNewWindow))
                        }
                        VStack(alignment: .leading,spacing: 10) {
                            Toggle("连接或断开屏幕时",isOn: preference(\.onDisplay))
                            Toggle("电脑唤醒时",isOn: preference(\.onWake))
                        }
                        Spacer()
                    }.font(.system(size: 12)).disabled(!model.state.preferences.automatic)
                    Divider()
                    HStack {
                        Toggle("登录时启动窗口记忆",isOn: Binding(get: { model.loginEnabled || model.loginNeedsApproval },set: { model.setLogin($0) }))
                        Spacer()
                        if model.loginNeedsApproval { Text("等待系统允许").foregroundStyle(.orange) }
                        else { Text("关闭此窗口后仍在菜单栏运行").foregroundStyle(.secondary) }
                    }.font(.system(size: 11))
                }.padding(16).background(Color(nsColor: .controlBackgroundColor),in: RoundedRectangle(cornerRadius: 14))
                if let layout = model.current {
                    VStack(alignment: .leading,spacing: 10) {
                        HStack {
                            Text("已记住的窗口").font(.system(size: 14,weight: .semibold))
                            Spacer()
                            Text("取消勾选的窗口不会自动移动").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        ForEach(layout.windows) { slot in
                            HStack(spacing: 9) {
                                Toggle("",isOn: Binding(get: { slot.enabled },set: { model.setSlot(slot.id,enabled: $0) })).labelsHidden()
                                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: slot.bundleID) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24,height: 24)
                                }
                                VStack(alignment: .leading,spacing: 3) {
                                    Text(slot.appName).font(.system(size: 12,weight: .medium))
                                    Text(slot.title.isEmpty ? "普通窗口" : slot.title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if let monitor = layout.monitors.first(where: { $0.id == slot.monitorID }) {
                                    let f = slot.relative.placed(in: monitor.visible)
                                    VStack(alignment: .trailing,spacing: 3) {
                                        Text(monitor.name).lineLimit(1)
                                        Text("\(Int(f.width)) × \(Int(f.height)) pt").monospacedDigit()
                                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical,5)
                        }
                    }.padding(16).background(Color(nsColor: .controlBackgroundColor),in: RoundedRectangle(cornerRadius: 14))
                }
                Text("布局仅保存在这台 Mac。普通窗口可恢复；全屏、最小化和其他空间中的窗口可能受系统限制。")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false,vertical: true)
            }.padding(26)
        }.background(Color(nsColor: .windowBackgroundColor)).tint(accent)
    }
}

struct MonitorDiagram: View {
    let monitors: [Monitor]
    let slots: [WindowSlot]
    var body: some View {
        GeometryReader { geo in
            let union = monitors.reduce(CGRect.null) { $0.union($1.bounds.rect) }
            let scale = min((geo.size.width-30)/max(1,union.width),(geo.size.height-27)/max(1,union.height))
            let originX = (geo.size.width-union.width*scale)/2
            let originY = (geo.size.height-union.height*scale)/2-4
            ForEach(Array(monitors.enumerated()),id: \.element.id) { index,m in
                let w = m.bounds.width*scale, h = m.bounds.height*scale
                let x = originX+(m.bounds.x-union.minX)*scale, y = originY+(m.bounds.y-union.minY)*scale
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.045))
                    RoundedRectangle(cornerRadius: 5).stroke(accent.opacity(0.4),lineWidth: 1.5)
                    ForEach(slots.filter { $0.monitorID == m.id && $0.enabled }) { slot in
                        RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.14)).overlay(RoundedRectangle(cornerRadius: 3).stroke(accent.opacity(0.28),lineWidth: 0.7))
                            .frame(width: max(3,min(1,slot.relative.width)*max(1,w-6)),height: max(3,min(1,slot.relative.height)*max(1,h-6)))
                            .offset(x: 3+max(0,slot.relative.x)*(w-6),y: 3+max(0,slot.relative.y)*(h-6))
                    }
                    Text("\(index+1)").font(.system(size: 10,weight: .semibold)).padding(5)
                        .background(.regularMaterial,in: Circle()).padding(5)
                }.frame(width: w,height: h).clipped().position(x: x+w/2,y: y+h/2)
                Text(m.name).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: max(w,60)).position(x: x+w/2,y: y+h+11)
            }
        }.accessibilityLabel("当前连接 \(monitors.count) 个屏幕")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: Controller!
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = Controller(); controller.start()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication,hasVisibleWindows flag: Bool) -> Bool {
        controller.showWindow(); return true
    }
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
