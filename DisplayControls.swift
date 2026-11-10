import Foundation

enum MonitorControlCode: UInt8, CaseIterable {
    case brightness = 0x10, contrast = 0x12, input = 0x60, color = 0x14
    case volume = 0x62, mute = 0x8D, power = 0xD6
    case red = 0x16, green = 0x18, blue = 0x1A, sharpness = 0x87, saturation = 0x8A
    case backlight = 0x6B, blackRed = 0x6C, blackGreen = 0x6E, blackBlue = 0x70
    case scaling = 0x86, displayMode = 0xDC, osdLanguage = 0xCC

    var title: String {
        switch self {
        case .brightness: return L("亮度")
        case .contrast: return L("对比度")
        case .input: return L("输入源")
        case .color: return L("色彩预设")
        case .volume: return L("显示器音量")
        case .mute: return L("显示器静音")
        case .power: return L("显示器电源")
        case .red: return L("红色增益")
        case .green: return L("绿色增益")
        case .blue: return L("蓝色增益")
        case .sharpness: return L("锐度")
        case .saturation: return L("饱和度")
        case .backlight: return L("背光强度")
        case .blackRed: return L("红色黑电平")
        case .blackGreen: return L("绿色黑电平")
        case .blackBlue: return L("蓝色黑电平")
        case .scaling: return L("画面缩放")
        case .displayMode: return L("画面模式")
        case .osdLanguage: return L("显示器菜单语言")
        }
    }

    var isAdvanced: Bool {
        switch self {
        case .brightness, .contrast, .input, .color, .volume, .mute: return false
        default: return true
        }
    }

    var isChoice: Bool {
        [.input, .color, .mute, .power, .scaling, .displayMode, .osdLanguage].contains(self)
    }

    var probeWithoutCapabilities: Bool {
        [.brightness, .contrast, .input, .volume, .mute].contains(self)
    }

    func valueTitle(_ value: UInt16) -> String {
        let hex = String(format: "0x%02X", value)
        switch self {
        case .input:
            return [0x01: "VGA 1", 0x02: "VGA 2", 0x03: "DVI 1", 0x04: "DVI 2",
                    0x0F: "DisplayPort 1", 0x10: "DisplayPort 2", 0x11: "HDMI 1", 0x12: "HDMI 2"][value] ?? hex
        case .color:
            switch value {
            case 0x01: return "sRGB"
            case 0x02: return L("原生色彩")
            case 0x03...0x0A: return "\([4000, 5000, 6500, 7500, 8200, 9300, 10000, 11500][Int(value)-3]) K"
            case 0x0B...0x0D: return L("自定义 \(Int(value)-10)")
            default: return hex
            }
        case .mute: return value == 1 ? L("已静音") : (value == 2 ? L("未静音") : hex)
        case .power:
            switch value {
            case 1: return L("开启")
            case 2: return L("待机")
            case 3: return L("挂起")
            case 4, 5: return L("关闭") + " · " + hex
            default: return hex
            }
        default: return hex
        }
    }

    func needsConfirmation(_ value: UInt16) -> Bool { self == .input || (self == .power && value != 1) }
}

struct MonitorAdjustment: Identifiable, Equatable {
    enum Style: Equatable { case range(UInt16), options([UInt16]), readOnly }
    let code: MonitorControlCode
    let native: Bool
    var current: UInt16
    let style: Style
    var id: UInt8 { code.rawValue }

    init(code: MonitorControlCode, reading: DDCReading, advertised: [UInt16]) {
        self.code = code
        native = false
        current = reading.current
        if code.isChoice || !advertised.isEmpty {
            // Unknown multi-byte mute/blank encodings must not blank a display.
            let values = advertised.filter {
                switch code {
                case .mute: return reading.current <= 0xFF && [1,2].contains($0)
                case .power: return (1...5).contains($0)
                case .input: return $0 > 0 && $0 <= 0xFF
                default: return $0 <= 0xFF
                }
            }
            // With no capabilities list, the current input is useful but
            // guessing the presence of HDMI/DP/USB-C ports is not.
            style = values.isEmpty ? .readOnly : .options(values)
        } else {
            style = reading.maximum > 0 && reading.current <= reading.maximum ? .range(reading.maximum) : .readOnly
        }
    }

    init(nativeBrightness: UInt16) {
        code = .brightness; native = true; current = nativeBrightness; style = .range(100)
    }

    func accepts(_ value: UInt16) -> Bool {
        switch style {
        case .range(let max): return value <= max
        case .options(let values): return values.contains(value)
        case .readOnly: return false
        }
    }
}

struct MonitorProfile {
    var controls: [MonitorAdjustment] = []
    var ddcResponded = false
    var version: String?
    var otherCodes: [UInt8] = []

    static func probe(_ display: ConnectedDisplay, isCancelled: () -> Bool = { false }) -> MonitorProfile {
        var result = MonitorProfile()
        if let monitor = DisplayHardware.ddc(display) {
            let capabilities = monitor.capabilities(isCancelled: isCancelled)
            result.version = capabilities?.version
            result.ddcResponded = capabilities != nil
            result.otherCodes = (capabilities?.features.keys.map { $0 } ?? [])
                .filter { MonitorControlCode(rawValue: $0) == nil }.sorted()
            for code in MonitorControlCode.allCases {
                guard !isCancelled(), display.isStillConnected() else { return result }
                guard code.probeWithoutCapabilities || capabilities?.features[code.rawValue] != nil else { continue }
                guard let reading = monitor.get(code.rawValue) else { continue }
                result.ddcResponded = true
                result.controls.append(MonitorAdjustment(code: code, reading: reading,
                    advertised: capabilities?.features[code.rawValue] ?? []))
            }
        }
        if !isCancelled(), !result.controls.contains(where: { $0.code == .brightness }),
           let brightness = DisplayHardware.nativeBrightness(display) {
            result.controls.insert(MonitorAdjustment(nativeBrightness: brightness), at: 0)
        }
        return result
    }

    static func example(builtIn: Bool) -> MonitorProfile {
        if builtIn { return MonitorProfile(controls: [MonitorAdjustment(nativeBrightness: 70)]) }
        let values: [(MonitorControlCode, UInt16, UInt16, [UInt16])] = [
            (.brightness, 75, 100, []), (.contrast, 60, 100, []), (.input, 0x0F, 0, [0x0F, 0x11, 0x12]),
            (.color, 5, 0, [1, 5, 8, 11]), (.volume, 25, 100, []), (.mute, 2, 0, [1, 2]),
            (.power, 1, 0, [1, 4]), (.red, 50, 100, []), (.green, 50, 100, []),
            (.blue, 50, 100, []), (.sharpness, 3, 5, [])
        ]
        return MonitorProfile(controls: values.map {
            MonitorAdjustment(code: $0.0, reading: DDCReading(current: $0.1, maximum: $0.2), advertised: $0.3)
        }, ddcResponded: true, version: "2.2")
    }
}

enum DisplayWriteResult: Equatable {
    case verified(UInt16)
    case different(UInt16)
    case sent
    case failed
}

extension DisplayHardware {
    static func apply(_ value: UInt16, to control: MonitorAdjustment, on display: ConnectedDisplay) -> DisplayWriteResult {
        guard control.accepts(value), display.isStillConnected() else { return .failed }
        if control.native {
            guard let actual = setNativeBrightness(value, for: display) else { return .failed }
            return actual == value ? .verified(actual) : .different(actual)
        }
        guard let monitor = ddc(display), let before = monitor.get(control.code.rawValue) else { return .failed }
        if case .range = control.style, value > before.maximum { return .different(before.current) }
        guard display.isStillConnected(), monitor.set(control.code.rawValue, value: value) else { return .failed }
        // Input/power changes can deliberately remove the transport. Do not
        // represent an acknowledged request as a verified setting.
        if control.code.needsConfirmation(value) { return .sent }
        var latest: UInt16?
        for _ in 0..<2 where display.isStillConnected() {
            if let actual = monitor.get(control.code.rawValue)?.current {
                if actual == value { return .verified(actual) }
                latest = actual
            }
        }
        return latest.map(DisplayWriteResult.different) ?? .sent
    }
}
