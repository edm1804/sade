import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, turkish, english
    var id: Self { self }

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
    }

    var code: String {
        switch self {
        case .turkish: return "tr"
        case .english: return "en"
        case .system:
            return Self.supportedCode(for: Locale.preferredLanguages)
        }
    }

    static func supportedCode(for preferences: [String]) -> String {
        for preference in preferences {
            let code = preference.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if code == "tr" { return "tr" }
            if code == "en" { return "en" }
        }
        return "en"
    }

    var locale: Locale { Locale(identifier: code == "tr" ? "tr_TR" : "en_US") }
    var title: String {
        switch self {
        case .system: return L("Sistem")
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }
}

/// Translate interface copy only. User content and stored identifiers never pass through this helper.
func L(_ key: String, _ arguments: String...) -> String {
    let language = AppLanguage.current
    let bundle = Bundle.main.path(forResource: language.code, ofType: "lproj")
        .flatMap { Bundle(path: $0) } ?? Bundle.main
    let format = bundle.localizedString(forKey: key, value: key, table: "Localizable")
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: language.locale, arguments: arguments)
}

func filterTitle(_ value: String) -> String {
    ["Bugün", "Bu hafta", "Tüm görevler", "Tamamlananlar"].contains(value) ? L(value) : value
}
