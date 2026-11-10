import SwiftUI

struct DisplayLANView: View {
    let p: ConsolePalette
    @State private var host = ""
    @State private var paired: LANMonitorAddress?
    @State private var snapshot: LANMonitorSnapshot?
    @State private var pending: LANInput?
    @State private var request: Task<Void, Never>?
    @State private var status = ""
    @State private var volume: Int?

    var body: some View {
        DisclosureGroup(L("局域网遥控 · 澎湃 OS")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("仅适用于提供兼容遥控接口的澎湃 OS 显示器。请在显示器网络设置中查看 IP，并与 Mac 连到同一局域网。"))
                    .foregroundStyle(p.muted)
                if let snapshot {
                    HStack {
                        Text(snapshot.name).fontWeight(.semibold)
                        Spacer()
                        Button(L("断开遥控")) { disconnect() }
                    }
                    if !snapshot.inputs.isEmpty {
                        Menu(L("选择输入源")) {
                            ForEach(snapshot.inputs) { input in Button(input.sourceName) { pending = input } }
                        }.disabled(request != nil)
                    }
                    if snapshot.volume != nil {
                        HStack {
                            Text(L("显示器音量"))
                            if let volume { Text("\(volume)%").monospacedDigit() }
                            Spacer()
                            Button { changeVolume(.down) } label: { Image(systemName: "speaker.minus") }.accessibilityLabel(L("降低音量"))
                            Button { changeVolume(.up) } label: { Image(systemName: "speaker.plus") }.accessibilityLabel(L("提高音量"))
                        }.disabled(request != nil)
                    }
                } else {
                    HStack {
                        TextField(L("显示器局域网 IP"), text: $host).textFieldStyle(.roundedBorder)
                            .disabled(request != nil).onSubmit { connect() }
                        Button(L("测试连接")) { connect() }.disabled(request != nil || LANMonitorAddress(host) == nil)
                    }
                    if !host.isEmpty, LANMonitorAddress(host) == nil {
                        Text(L("请输入显示器的私有 IPv4 地址，例如 192.168.1.20。")).foregroundStyle(.orange)
                    }
                }
                if request != nil { ProgressView().controlSize(.small) }
                if !status.isEmpty { Text(status).foregroundStyle(p.muted) }
            }.font(.system(size: 12)).padding(.top, 10)
        }
        .padding(16).consolePanel(p)
        .alert(item: $pending) { input in
            Alert(title: Text(input.sourceName), message: Text(L("切换后这台显示器可能失去本机画面。若无信号，可用显示器实体菜单切回。")),
                  primaryButton: .default(Text(L("确认切换"))) { select(input) }, secondaryButton: .cancel(Text(L("取消"))))
        }
        .onDisappear { disconnect() }
    }

    private func connect() {
        guard request == nil, let address = LANMonitorAddress(host) else { return }
        status = ""
        request = Task { @MainActor in
            do {
                let found = try await LANMonitor(address: address).snapshot()
                guard !Task.isCancelled else { return }
                paired = address; snapshot = found; volume = found.volume
            } catch {
                guard !Task.isCancelled else { return }
                status = L("未连接到兼容显示器。请检查 IP、显示器网络及 macOS 的本地网络权限。")
            }
            request = nil
        }
    }

    private func select(_ input: LANInput) {
        guard request == nil, let paired, let snapshot else { return }
        status = ""
        request = Task { @MainActor in
            do {
                try await LANMonitor(address: paired).select(input, pairedName: snapshot.name)
                guard !Task.isCancelled else { return }
                status = L("已发送指令，暂未读回确认；可刷新查看。")
            } catch {
                guard !Task.isCancelled else { return }
                status = L("未能应用设置。请检查连接或显示器当前模式后重试。")
            }
            request = nil
        }
    }

    private func changeVolume(_ key: LANMonitor.VolumeKey) {
        guard request == nil, let paired, let snapshot else { return }
        status = ""
        request = Task { @MainActor in
            do {
                let reading = try await LANMonitor(address: paired).changeVolume(key, pairedName: snapshot.name)
                guard !Task.isCancelled else { return }
                volume = reading
                if reading == nil { status = L("已发送指令，暂未读回确认；可刷新查看。") }
            } catch {
                guard !Task.isCancelled else { return }
                status = L("未能应用设置。请检查连接或显示器当前模式后重试。")
            }
            request = nil
        }
    }

    private func disconnect() {
        request?.cancel()
        request = nil; paired = nil; snapshot = nil; volume = nil; status = ""
    }
}
