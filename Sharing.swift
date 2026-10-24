import AppKit
import SwiftUI

enum ShareChannel: String, CaseIterable, Identifiable {
    case system, copy, x, facebook, linkedin, whatsapp, telegram, reddit, email, wechat
    var id: String { rawValue }
    static let projectURL = URL(string: "https://github.com/LZQVicLi/WindowMemory")!
    var title: String {
        switch self {
        case .system: return L("系统分享")
        case .copy: return L("复制项目链接")
        case .x: return "X"
        case .facebook: return "Facebook"
        case .linkedin: return "LinkedIn"
        case .whatsapp: return "WhatsApp"
        case .telegram: return "Telegram"
        case .reddit: return "Reddit"
        case .email: return L("电子邮件")
        case .wechat: return L("微信 / 其他")
        }
    }
    var icon: String {
        switch self { case .copy: return "link"; case .system: return "square.and.arrow.up"; case .email: return "envelope"; default: return "arrow.up.forward.app" }
    }
    func destination(text: String) -> URL? {
        let link = Self.projectURL.absoluteString
        let base: String
        let items: [URLQueryItem]
        switch self {
        case .x: base = "https://x.com/intent/tweet"; items = [.init(name: "url",value: link),.init(name: "text",value: text)]
        case .facebook: base = "https://www.facebook.com/sharer/sharer.php"; items = [.init(name: "u",value: link)]
        case .linkedin: base = "https://www.linkedin.com/sharing/share-offsite/"; items = [.init(name: "url",value: link)]
        case .whatsapp: base = "https://wa.me/"; items = [.init(name: "text",value: text+" "+link)]
        case .telegram: base = "https://t.me/share/url"; items = [.init(name: "url",value: link),.init(name: "text",value: text)]
        case .reddit: base = "https://www.reddit.com/submit"; items = [.init(name: "url",value: link),.init(name: "title",value: text)]
        case .email: base = "mailto:"; items = [.init(name: "subject",value: "WindowMemory"),.init(name: "body",value: text+"\n\n"+link)]
        case .system, .copy, .wechat: return nil
        }
        var components = URLComponents(string: base)!
        components.queryItems = items
        return components.url
    }
}

extension Controller {
    func share(_ channel: ShareChannel, from view: NSView? = nil) {
        let text = L("WindowMemory：免费的开源 Mac 多屏窗口布局管理工具。")
        if channel == .copy || channel == .wechat {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ShareChannel.projectURL.absoluteString,forType: .string)
            tell(channel == .copy ? L("项目链接已复制。") : L("项目链接已复制，可粘贴到微信或其他 App 中分享。"))
        } else if channel == .system, let view {
            NSSharingServicePicker(items: [text,ShareChannel.projectURL]).show(relativeTo: view.bounds,of: view,preferredEdge: .minY)
        } else if let url = channel.destination(text: text) {
            if !NSWorkspace.shared.open(url) { tell(L("无法打开分享渠道，请检查浏览器或默认邮件 App。"),error: true) }
        }
    }
}
struct SharingSettings: View {
    @ObservedObject var model: Controller
    let p: ConsolePalette
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(L("分享 WindowMemory")).font(.system(size: 13,weight: .semibold))
            Text(L("分享免费的开源工具。仅传递项目链接与介绍文字，不包含你的布局或窗口信息。"))
                .font(.system(size: 11)).foregroundStyle(p.muted).fixedSize(horizontal: false,vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145),spacing: 10)],spacing: 10) {
                ForEach(ShareChannel.allCases) { channel in
                    if channel == .system { SystemShareButton(model: model).frame(height: 30) }
                    else {
                        Button { model.share(channel) } label: {
                            HStack(spacing: 7) {
                                ShareChannelIcon(channel: channel).frame(width: 17,height: 17)
                                Text(channel.title)
                            }.font(.system(size: 11)).frame(maxWidth: .infinity,minHeight: 24)
                        }.controlSize(.small)
                    }
                }
            }
            Text(L("点击后进入对应渠道，由你确认发送；微信等渠道可使用复制链接或系统分享。"))
                .font(.system(size: 10)).foregroundStyle(p.muted).fixedSize(horizontal: false,vertical: true)
        }.padding(18).consolePanel(p)
    }
}
struct SystemShareButton: NSViewRepresentable {
    @ObservedObject var model: Controller
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: ShareChannel.system.title,target: context.coordinator,action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .rounded; button.image = NSImage(systemSymbolName: "square.and.arrow.up",accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        return button
    }
    func updateNSView(_ view: NSButton, context: Context) { view.title = ShareChannel.system.title }
    final class Coordinator: NSObject {
        let model: Controller
        init(_ model: Controller) { self.model = model }
        @objc func share(_ sender: NSButton) { model.share(.system,from: sender) }
    }
}

struct ShareChannelIcon: View {
    let channel: ShareChannel
    private var brandColor: Color {
        switch channel {
        case .facebook: return Color(hex: 0x1877F2)
        case .linkedin: return Color(hex: 0x0A66C2)
        case .whatsapp: return Color(hex: 0x25A652)
        case .telegram: return Color(hex: 0x26A5E4)
        case .reddit: return Color(hex: 0xFF4500)
        case .wechat: return Color(hex: 0x07C160)
        default: return .primary
        }
    }
    var body: some View {
        if let url = Bundle.main.url(forResource: channel.rawValue,withExtension: "png",subdirectory: "ShareIcons"),let icon = NSImage(contentsOf: url) {
            Image(nsImage: icon).resizable().renderingMode(.template).scaledToFit().foregroundStyle(brandColor).accessibilityHidden(true)
        } else { Image(systemName: channel.icon).accessibilityHidden(true) }
    }
}
