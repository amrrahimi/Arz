import Foundation

extension L10n {
    /// The language in use: the user's choice, else the first supported
    /// system language, else English.
    static var current: String {
        let chosen = Settings.shared.language
        if !chosen.isEmpty, table["quit"]?[chosen] != nil { return chosen }
        for preferred in Locale.preferredLanguages {
            let code = String(preferred.prefix(2))
            if table["quit"]?[code] != nil { return code }
        }
        return "en"
    }

    static var isRightToLeft: Bool { rtl.contains(current) }

    static func t(_ key: String) -> String {
        table[key]?[current] ?? table[key]?["en"] ?? key
    }
}
