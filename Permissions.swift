import AppKit
import SwiftUI

final class AppearanceHostingView: NSHostingView<MainView> {
    var onAppearanceChange: ((NSAppearance) -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let appearance = effectiveAppearance
        DispatchQueue.main.async { [weak self] in self?.onAppearanceChange?(appearance) }
    }
}

extension Controller {
    func showPermissionGuide() {
        checkPermission()
        let alreadyVisible = permissionPanel?.isVisible == true
        if permissionPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0,y: 0,width: 470,height: 520),styleMask: [.titled,.closable,.utilityWindow],backing: .buffered,defer: false)
            panel.title = L("窗口控制权限")
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: PermissionGuide(model: self))
            panel.center()
            permissionPanel = panel
        }
        permissionChecks = 0
        permissionPanel?.orderFrontRegardless()
        if !alreadyVisible { WindowAccess.requestPermission() }
    }
}
struct PermissionGuide: View {
    @ObservedObject var model: Controller
    private var p: ConsolePalette { ConsolePalette(model.darkAppearance ? .dark : .light) }
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().frame(width: 66,height: 66)
                .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                .help(L("将 App 图标拖到系统权限列表"))
                .accessibilityLabel(L("将 App 图标拖到系统权限列表"))
            Text(L("拖入列表，开启窗口控制")).font(.system(size: 17,weight: .semibold))
            Text(L("将上方 App 图标拖入系统设置的权限列表，再开启“窗口记忆”旁的开关。也可以点列表中的“＋”添加应用。"))
                .font(.system(size: 12)).multilineTextAlignment(.center).fixedSize(horizontal: false,vertical: true)
            Label(model.permitted ? L("窗口控制权限已开启") : L("尚未获得系统授权"),systemImage: model.permitted ? "checkmark.circle.fill" : "clock")
                .font(.system(size: 12,weight: .medium)).foregroundStyle(model.permitted ? p.accent : .orange)
            if !model.permitted && model.permissionChecks >= 12 {
                Text(L("若系统开关已开启，请移除列表中的旧记录，再拖入当前 App 并开启。必要时退出并重新打开 App。"))
                    .font(.system(size: 11)).foregroundStyle(p.muted).fixedSize(horizontal: false,vertical: true)
            }
            HStack {
                Button(L("在 Finder 中显示 App")) { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                Spacer()
                Button(model.permitted ? L("完成") : L("重新检查")) {
                    model.checkPermission()
                    if model.permitted { model.permissionPanel?.close() }
                }.keyboardShortcut(.defaultAction)
            }.controlSize(.small)
        }.padding(24).frame(width: 470).frame(minHeight: 520).background(p.background).foregroundStyle(p.text).tint(p.accent)
            .environment(\.colorScheme,model.darkAppearance ? .dark : .light)
            .environment(\.locale,Locale(identifier: model.state.preferences.language.resolvedCode))
            .environment(\.layoutDirection,model.state.preferences.language.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
