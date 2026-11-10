import AppKit
import SwiftUI

final class UpdateState: ObservableObject {
    enum Status: Equatable {
        case idle, checking, current, available, downloading, installing, unavailable, failed, rollback(String)
        var busy: Bool { self == .checking || self == .downloading || self == .installing }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var release: ProjectRelease?

    var canInstall: Bool {
        release?.package != nil && AppUpdateInstaller.canInstall(at: Bundle.main.bundleURL)
    }

    func check() {
        guard !status.busy, let installed = ReleaseVersion(appVersion) else { return }
        status = .checking
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.release = try await UpdateNetwork.latest(installed: installed)
                self.status = self.release == nil ? .current : .available
            } catch {
                self.status = self.release == nil ? .unavailable : .failed
            }
        }
    }

    func openRelease() { NSWorkspace.shared.open(release?.page ?? ProjectRelease.releases) }

    func install() {
        guard !status.busy, let release, canInstall else { return }
        let destination = Bundle.main.bundleURL, version = appVersion
        status = .downloading
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stage = try await AppUpdateInstaller.prepare(release, at: destination)
                var preserve = false
                defer { if !preserve { try? FileManager.default.removeItem(at: stage.directory) } }
                self.status = .installing
                // Re-check the live bundle in case another updater or Finder
                // changed the target while the package was downloading.
                guard AppUpdateInstaller.canInstall(at: destination),
                      AppUpdateInstaller.installedVersion(at: destination) == version,
                      AppUpdateInstaller.swap(destination, stage.replacement) else { throw UpdateIssue.install }
                preserve = true
                do {
                    let config = NSWorkspace.OpenConfiguration()
                    config.createsNewApplicationInstance = true
                    let app = try await NSWorkspace.shared.openApplication(at: destination, configuration: config)
                    guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier, !app.isTerminated,
                          app.bundleIdentifier == AppUpdateInstaller.identifier,
                          app.bundleURL?.resolvingSymlinksInPath().path == destination.resolvingSymlinksInPath().path else { throw UpdateIssue.launch }
                } catch {
                    guard AppUpdateInstaller.swap(destination, stage.replacement) else {
                        throw UpdateIssue.rollback(stage.replacement.path)
                    }
                    preserve = false
                    throw UpdateIssue.launch
                }
                if (try? AppUpdateInstaller.retainPrevious(stage.replacement, version: version)) != nil { preserve = false }
                NSApp.terminate(nil)
            } catch UpdateIssue.rollback(let path) {
                self.status = .rollback(path)
            } catch {
                self.status = .failed
            }
        }
    }
}

struct UpdateFooter: View {
    @ObservedObject var state: UpdateState
    let p: ConsolePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let release = state.release {
                Label(L("发现新版本 v\(release.version)"), systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(p.accent)
            }
            if state.status.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(statusText).font(.system(size: 10)).foregroundStyle(p.muted)
                }
            } else if case .rollback(let path) = state.status {
                Text(L("无法恢复旧版本；备份位于：\(path)")).font(.system(size: 10))
                    .lineLimit(3).foregroundStyle(.orange).textSelection(.enabled)
                    .help(path)
                link
            } else if state.release != nil {
                if state.status == .failed {
                    Text(L("更新未完成，可重试或手动下载。")).font(.system(size: 10)).foregroundStyle(.orange)
                }
                if state.canInstall {
                    Button(L("一键更新")) { state.install() }
                        .controlSize(.small)
                        .help(L("校验后替换并重启；可能需要重新开启窗口控制权限。"))
                }
                link
            } else {
                if state.status != .idle {
                    Text(statusText).font(.system(size: 10)).foregroundStyle(p.muted)
                }
                Button(L("检查更新")) { state.check() }.buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(p.accent)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var link: some View {
        Button(L("打开下载页")) { state.openRelease() }.buttonStyle(.plain)
            .font(.system(size: 10)).foregroundStyle(p.muted)
    }

    private var statusText: String {
        switch state.status {
        case .checking: return L("正在检查更新…")
        case .current: return L("已是最新版本")
        case .downloading: return L("正在下载并校验…")
        case .installing: return L("正在安装并重启…")
        case .unavailable: return L("暂时无法检查更新")
        default: return ""
        }
    }
}
