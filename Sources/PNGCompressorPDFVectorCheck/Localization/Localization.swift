import Foundation

private enum AppLanguage {
    case english
    case russian
    case belarusian

    /// Mirrors the language `AppBundle.resources` itself resolved to, so string lookups and
    /// plural-category selection never disagree.
    static var current: AppLanguage {
        switch Bundle.main.preferredLocalizations.first {
        case "be": return .belarusian
        case "ru": return .russian
        default: return .english
        }
    }
}

/// Thin wrapper over `NSLocalizedString` bound to `AppBundle.resources`, plus a hand-rolled
/// plural-category dispatcher (rather than `.stringsdict`, which only supports `one`/`few`/
/// `many`/`other` via ICU's built-in rule tables — this keeps the rule visible and testable).
enum L10n {
    static func string(_ key: String, comment: String = "") -> String {
        NSLocalizedString(key, comment: comment)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }

    /// Looks up `"\(key).\(category)"`, where `category` is whichever plural form `count`
    /// selects for the current language, and formats it with `count`.
    static func plural(_ key: String, _ count: Int) -> String {
        let category = pluralCategory(for: count)
        let template = string("\(key).\(category)")
        return String(format: template, count)
    }

    private static func pluralCategory(for count: Int) -> String {
        switch AppLanguage.current {
        case .english:
            return count == 1 ? "one" : "other"
        case .russian, .belarusian:
            let mod10 = count % 10
            let mod100 = count % 100

            if (11...14).contains(mod100) {
                return "many"
            }

            switch mod10 {
            case 1: return "one"
            case 2, 3, 4: return "few"
            default: return "many"
            }
        }
    }
}
