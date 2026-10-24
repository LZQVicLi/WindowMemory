import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en", french = "fr", spanish = "es", russian = "ru", arabic = "ar"
    var id: String { rawValue }
    static let supportedCodes = ["zh-Hans","en","fr","es","ru","ar"]
    var resolvedCode: String {
        guard self == .system else { return rawValue }
        for preferred in Locale.preferredLanguages {
            let code = preferred.split(separator: "-").first.map(String.init) ?? preferred
            if code == "zh" { return "zh-Hans" }
            if Self.supportedCodes.contains(code) { return code }
        }
        return "en"
    }
    var isRightToLeft: Bool { resolvedCode == "ar" }
    var title: String {
        switch self {
        case .system: return L("跟随系统")
        case .chinese: return "简体中文"
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        case .russian: return "Русский"
        case .arabic: return "العربية"
        }
    }
}

// Interpolation stays separate from the translation key, including user-provided window titles.
struct LocalizedText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    var key: String
    var arguments: [String] = []
    init(stringLiteral value: String) { key = value }
    init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) { key += "{\(arguments.count)}"; arguments.append(String(describing: value)) }
    }
}
enum Localization {
    static var language: AppLanguage = .system
    static let translations: [String:[String:String]] = {
        guard let url = Bundle.main.url(forResource: "Translations",withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String:[String:String]].self,from: data) else { return [:] }
        return values
    }()
    static func render(_ text: LocalizedText, code: String) -> String {
        let template = code == "zh-Hans" ? text.key : (translations[text.key]?[code] ?? translations[text.key]?["en"] ?? text.key)
        // Scan the template once: substitutions must never interpret placeholders in user content.
        var output = "", remainder = template[...]
        while let start = remainder.firstIndex(of: "{"), let end = remainder[start...].firstIndex(of: "}") {
            output += remainder[..<start]
            let token = remainder[remainder.index(after: start)..<end]
            if let index = Int(token), text.arguments.indices.contains(index) { output += text.arguments[index] }
            else { output += remainder[start...end] }
            remainder = remainder[remainder.index(after: end)...]
        }
        output += remainder
        return output
    }
}
func L(_ text: LocalizedText) -> String { Localization.render(text,code: Localization.language.resolvedCode) }
var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
