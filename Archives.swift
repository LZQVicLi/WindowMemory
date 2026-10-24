import Foundation

struct LayoutArchive: Codable {
    var format = "windowmemory.layouts"
    var version = 1
    var exportedAt = Date()
    var layouts: [Layout]
}

enum ArchiveError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(text) = self { return text }; return nil }
}

func decodeLayouts(_ data: Data) throws -> [Layout] {
    guard data.count <= 5_000_000 else { throw ArchiveError.invalid("文件超过 5 MB，无法导入。") }
    let object = try JSONSerialization.jsonObject(with: data) as? [String:Any]
    let layouts: [Layout]
    if object?["format"] != nil {
        let archive = try JSONDecoder().decode(LayoutArchive.self,from: data)
        guard archive.format == "windowmemory.layouts", archive.version == 1 else { throw ArchiveError.invalid("不支持的布局文件格式或版本。") }
        layouts = archive.layouts
    } else {
        let legacy = try JSONDecoder().decode(SavedState.self,from: data)
        guard (1...3).contains(legacy.version) else { throw ArchiveError.invalid("不支持的配置版本。") }
        layouts = legacy.layouts
    }
    try validateLayouts(layouts)
    return layouts
}

func validateLayouts(_ layouts: [Layout]) throws {
    guard !layouts.isEmpty, layouts.count <= 100, Set(layouts.map(\.id)).count == layouts.count else { throw ArchiveError.invalid("场景数量或标识无效。") }
    func finite(_ f: Frame) -> Bool { [f.x,f.y,f.width,f.height].allSatisfy(\.isFinite) && f.width > 0 && f.height > 0 }
    for layout in layouts {
        guard !layout.name.isEmpty, layout.name.count <= 200, layout.id.count <= 4096,
              !layout.monitors.isEmpty, layout.monitors.count <= 16,
              Set(layout.monitors.map(\.id)).count == layout.monitors.count,
              layout.monitors.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && $0.name.count <= 200 && finite($0.bounds) && finite($0.visible) }),
              layout.windows.count <= 500, Set(layout.windows.map(\.id)).count == layout.windows.count else { throw ArchiveError.invalid("场景或屏幕数据无效：\(layout.name.prefix(80))") }
        let ids = Set(layout.monitors.map(\.id))
        for slot in layout.windows {
            guard !slot.bundleID.isEmpty, slot.bundleID.count <= 256, slot.appName.count <= 256, slot.title.count <= 4096,
                  ids.contains(slot.monitorID), finite(slot.relative), slot.relative.width <= 20, slot.relative.height <= 20,
                  abs(slot.relative.x) <= 100, abs(slot.relative.y) <= 100 else { throw ArchiveError.invalid("窗口数据无效：\(layout.name.prefix(80))") }
        }
        guard layout.launchRules.count <= 500, Set(layout.launchRules.map(\.bundleID)).count == layout.launchRules.count,
              layout.launchRules.allSatisfy({ !$0.bundleID.isEmpty && $0.bundleID.count <= 256 && $0.delay.isFinite && (0...120).contains($0.delay) && $0.windowTimeout.isFinite && (1...120).contains($0.windowTimeout) }) else { throw ArchiveError.invalid("启动顺序或等待时间无效。") }
    }
}

func remapLayout(_ layout: Layout, to monitors: [Monitor], mapping: [String:String]) throws -> Layout {
    let available = Set(monitors.map(\.id))
    var result = layout
    for index in result.windows.indices {
        let source = result.windows[index].monitorID
        guard let target = mapping[source], available.contains(target) else { throw ArchiveError.invalid("缺少屏幕映射。") }
        result.windows[index].monitorID = target
    }
    result.monitors = monitors
    return result
}
