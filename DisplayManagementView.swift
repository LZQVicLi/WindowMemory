import AppKit
import SwiftUI

private final class DisplayScanToken {
    private let lock = NSLock()
    private var stopped = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
}

private final class DisplayManagementState: ObservableObject {
    @Published var displays: [ConnectedDisplay] = []
    @Published var profiles: [String: MonitorProfile] = [:]
    @Published var scanning = Set<String>()
    @Published var working = Set<String>()
    @Published var outcomes: [String: DisplayWriteResult] = [:]
    private var scan: DisplayScanToken?
    private var scheduledRefresh: DispatchWorkItem?

    deinit { scan?.cancel(); scheduledRefresh?.cancel() }

    func reload(demo: Bool) {
        scan?.cancel()
        scheduledRefresh?.cancel()
        if demo {
            displays = [
                ConnectedDisplay(number: 1, uuid: "demo-main", name: "MacBook Pro", builtIn: true,
                                 primary: true, width: 1440, height: 900, refresh: 60, rotation: 0, mirrored: false),
                ConnectedDisplay(number: 2, uuid: "demo-portrait", name: "Portrait Display", builtIn: false,
                                 primary: false, width: 1600, height: 2560, refresh: 100, rotation: 90, mirrored: false)
            ]
            profiles = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, .example(builtIn: $0.builtIn)) })
            scanning = []; outcomes = [:]
            return
        }

        displays = ConnectedDisplay.online()
        let ids = Set(displays.map(\.id))
        profiles = profiles.filter { ids.contains($0.key) }
        outcomes = outcomes.filter { ids.contains($0.key) }
        scanning = ids
        let token = DisplayScanToken()
        scan = token
        for screen in displays {
            DisplayHardware.queue.async { [weak self] in
                guard !token.cancelled else { return }
                let profile = MonitorProfile.probe(screen, isCancelled: { token.cancelled })
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.scan === token, !token.cancelled else { return }
                    self.profiles[screen.id] = profile
                    self.scanning.remove(screen.id)
                }
            }
        }
    }

    func topologyChanged(demo: Bool) {
        guard !demo else { return }
        scan?.cancel()
        scheduledRefresh?.cancel()
        // Hide old controls during hot-plug negotiation; write operations also
        // verify the physical display identity immediately before sending.
        scanning = Set(displays.map(\.id))
        let update = DispatchWorkItem { [weak self] in self?.reload(demo: false) }
        scheduledRefresh = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: update)
    }

    func apply(_ value: UInt16, _ control: MonitorAdjustment, screen: ConnectedDisplay, demo: Bool) {
        guard !scanning.contains(screen.id), !working.contains(screen.id),
              let live = profiles[screen.id]?.controls.first(where: { $0.id == control.id }),
              live == control, control.accepts(value), value != control.current else { return }
        if demo {
            finish(.verified(value), for: control, on: screen)
            return
        }
        working.insert(screen.id)
        outcomes[screen.id] = nil
        DisplayHardware.queue.async { [weak self] in
            let result = DisplayHardware.apply(value, to: control, on: screen)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.working.remove(screen.id)
                self.finish(result, for: control, on: screen)
                if result == .sent && control.code.needsConfirmation(value) { self.topologyChanged(demo: false) }
            }
        }
    }

    private func finish(_ result: DisplayWriteResult, for control: MonitorAdjustment, on screen: ConnectedDisplay) {
        guard displays.contains(where: { $0.id == screen.id }) else { return }
        switch result {
        case .verified(let value), .different(let value):
            if let index = profiles[screen.id]?.controls.firstIndex(where: { $0.id == control.id }) {
                profiles[screen.id]?.controls[index].current = value
            }
        case .sent, .failed: break
        }
        outcomes[screen.id] = result
    }
}

struct DisplayManagementView: View {
    let demo: Bool
    let p: ConsolePalette
    @StateObject private var state = DisplayManagementState()
    @ObservedObject private var dimmer = DisplayDimming.shared
    @State private var pending: Change?

    private struct Change: Identifiable {
        let id = UUID()
        let screen: ConnectedDisplay
        let control: MonitorAdjustment
        let value: UInt16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(L("已连接 \(state.displays.count) 台显示器")).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { state.reload(demo: demo) } label: { Label(L("刷新显示器"), systemImage: "arrow.clockwise") }
                    .disabled(!state.working.isEmpty)
                Button {
                    if !demo, let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: { Label(L("系统显示设置"), systemImage: "gearshape") }
                .disabled(demo)
            }
            Text(L("硬件控制、软件调暗和局域网遥控可分别使用。分辨率、刷新率和排列在系统显示设置中调整。"))
                .font(.system(size: 12)).foregroundStyle(p.muted)
            if state.displays.isEmpty {
                Text(L("未检测到在线显示器。")).foregroundStyle(p.muted)
                    .frame(maxWidth: .infinity, minHeight: 72).consolePanel(p)
            }
            ForEach(state.displays) { screen in card(screen) }
            if !demo { DisplayLANView(p: p) }
        }
        .onAppear { if state.displays.isEmpty { state.reload(demo: demo) } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in state.topologyChanged(demo: demo) }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in state.topologyChanged(demo: demo) }
        .alert(item: $pending) { change in
            Alert(title: Text(change.control.code.title + " · " + change.control.code.valueTitle(change.value)),
                  message: Text(L("切换后这台显示器可能失去本机画面。若无信号，可用显示器实体菜单切回。")),
                  primaryButton: .default(Text(L("确认切换"))) { apply(change) }, secondaryButton: .cancel(Text(L("取消"))))
        }
    }

    private func card(_ screen: ConnectedDisplay) -> some View {
        let profile = state.profiles[screen.id]
        let controls = profile?.controls ?? []
        let quick = controls.filter { !$0.code.isAdvanced }
        let advanced = controls.filter { $0.code.isAdvanced }
        let checking = state.scanning.contains(screen.id)
        let busy = state.working.contains(screen.id)
        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: screen.builtIn ? "laptopcomputer" : "display").font(.system(size: 24))
                    .foregroundStyle(p.accent).frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(screen.name).font(.system(size: 15, weight: .semibold))
                    Text(summary(screen, signal: profile?.signalTransport)).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.muted)
                }
                Spacer()
                if checking || busy {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(checking ? L("正在读取显示器") : L("正在应用显示设置"))
                } else if profile?.ddcResponded == true {
                    Text(profile?.version.map { "DDC/CI · MCCS " + $0 } ?? "DDC/CI")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(p.accent)
                } else if !controls.isEmpty {
                    Text(L("原生亮度")).font(.system(size: 10)).foregroundStyle(p.accent)
                }
            }

            if checking && controls.isEmpty {
                Text(L("正在读取显示器")).font(.system(size: 12)).foregroundStyle(p.muted)
            } else if controls.isEmpty {
                Text(screen.builtIn ? L("当前系统未提供可读取的硬件亮度。")
                                    : profile?.hasDDCTransport == true
                                        ? L("找到了控制接口，但显示器没有返回可调项目。可检查 OSD 的 DDC/CI 开关，或绕过扩展坞直连。")
                                        : L("macOS 未提供这条连接的硬件控制接口。可试 USB-C 转 DisplayPort 直连，或使用软件调暗。"))
                    .font(.system(size: 12)).foregroundStyle(p.muted)
            }
            if !controls.isEmpty {
                Divider()
                VStack(spacing: 12) {
                    ForEach(quick) { adjustment in row(adjustment, screen: screen) }
                    if !advanced.isEmpty || !(profile?.otherCodes.isEmpty ?? true) {
                        DisclosureGroup(L("更多硬件项目")) {
                            VStack(spacing: 12) {
                                ForEach(advanced) { adjustment in row(adjustment, screen: screen) }
                                if let codes = profile?.otherCodes, !codes.isEmpty {
                                    let listed = codes.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
                                    Text(L("固件报告的其他代码（仅供诊断）：\(listed)"))
                                        .font(.system(size: 10)).foregroundStyle(p.muted)
                                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                }
                            }.padding(.top, 12)
                        }
                    }
                }.disabled(checking || busy)
            }
            if !demo, DisplayDimming.target(screen) != nil {
                Divider()
                softwareRow(screen)
            }
            if let outcome = state.outcomes[screen.id] {
                Text(message(outcome)).font(.system(size: 11))
                    .foregroundStyle(outcome == .failed ? Color.orange : p.muted)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).consolePanel(p)
    }

    private func row(_ adjustment: MonitorAdjustment, screen: ConnectedDisplay) -> some View {
        DisplayAdjustmentRow(adjustment: adjustment, p: p) { value in
            let change = Change(screen: screen, control: adjustment, value: value)
            if !demo && adjustment.code.needsConfirmation(value) { pending = change } else { apply(change) }
        }
    }

    private func apply(_ change: Change) {
        state.apply(change.value, change.control, screen: change.screen, demo: demo)
    }

    private func softwareRow(_ screen: ConnectedDisplay) -> some View {
        let level = dimmer.levels[screen.id] ?? 100
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(L("软件调暗")).font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 104, alignment: .leading)
                Slider(value: Binding(get: { Double(level) }, set: { dimmer.set(Int($0), display: screen) }), in: 25...100, step: 1)
                    .accessibilityLabel(L("软件调暗"))
                Text("\(level)%").font(.system(size: 11, design: .monospaced)).monospacedDigit()
                Button(L("恢复原样")) { dimmer.set(100, display: screen) }.disabled(level == 100)
            }
            Text(L("仅调暗画面，不改变背光或输入源。退出应用后恢复。"))
                .font(.system(size: 10)).foregroundStyle(p.muted)
        }
    }

    private func summary(_ screen: ConnectedDisplay, signal: String?) -> String {
        var components = [screen.primary ? L("主屏") : L("副屏"), screen.builtIn ? L("内建显示器") : L("外接")]
        components.append("\(screen.width) × \(screen.height)")
        if screen.refresh > 0 { components.append(screen.refresh.formatted(.number.precision(.fractionLength(0...2))) + " Hz") }
        if screen.rotation != 0 { components.append("\(screen.rotation)°") }
        if screen.mirrored { components.append(L("镜像")) }
        if let signal { components.append(signal) }
        return components.joined(separator: " · ")
    }

    private func message(_ result: DisplayWriteResult) -> String {
        switch result {
        case .verified: return L("已应用并读回确认。")
        case .different: return L("显示器返回了不同的值，已显示实际读数。")
        case .sent: return L("已发送指令，暂未读回确认；可刷新查看。")
        case .failed: return L("未能应用设置。请检查连接或显示器当前模式后重试。")
        }
    }
}

private struct DisplayAdjustmentRow: View {
    let adjustment: MonitorAdjustment
    let p: ConsolePalette
    let commit: (UInt16) -> Void
    @State private var proposed: Double?

    var body: some View {
        HStack(spacing: 10) {
            Text(adjustment.code.title).font(.system(size: 12, weight: .medium))
                .frame(minWidth: 104, alignment: .leading)
            switch adjustment.style {
            case .range(let max):
                let shown = proposed ?? Double(adjustment.current)
                Slider(value: Binding(get: { min(Double(max), shown) }, set: { proposed = $0 }), in: 0...Double(max), step: 1)
                    .accessibilityLabel(adjustment.code.title)
                Text("\(Int(shown)) / \(max)").font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(p.muted).monospacedDigit()
                Button(L("应用")) { if let proposed { commit(UInt16(proposed)); self.proposed = nil } }
                    .disabled(proposed == nil || Int(shown) == Int(adjustment.current) || shown > Double(max))
            case .options(let values):
                Spacer()
                Menu(adjustment.code.valueTitle(adjustment.current)) {
                    ForEach(values, id: \.self) { value in
                        Button(adjustment.code.valueTitle(value)) { commit(value) }.disabled(value == adjustment.current)
                    }
                }.fixedSize().accessibilityLabel(adjustment.code.title)
            case .readOnly:
                Spacer()
                Text(adjustment.code.valueTitle(adjustment.current)).font(.system(size: 12, design: .monospaced))
                Text(adjustment.code == .input ? L("未公布可切换端口") : L("仅可读取"))
                    .font(.system(size: 10)).foregroundStyle(p.muted)
            }
        }.onChange(of: adjustment) { _, _ in proposed = nil }
    }
}
