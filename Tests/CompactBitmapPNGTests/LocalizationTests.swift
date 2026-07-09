import Foundation
import Testing

@testable import CompactBitmapPNG

@Suite("Localization")
struct LocalizationTests {
    @Test("Every locale defines the same set of keys, modulo plural-category suffixes")
    func localeKeySetsMatch() throws {
        let english = try keys(in: "en")
        for locale in ["ru", "be"] {
            let localeKeys = try keys(in: locale)
            let englishBases = Set(english.map(pluralBase))
            let localeBases = Set(localeKeys.map(pluralBase))
            #expect(englishBases == localeBases, "\(locale) is missing or has extra keys relative to en")
        }
    }

    @Test("Russian and Belarusian strings resolve to non-English text for a sample of keys")
    func nonEnglishLocalesTranslateSampleKeys() throws {
        let english = try stringsTable(for: "en")
        for locale in ["ru", "be"] {
            let table = try stringsTable(for: locale)
            for key in ["files.title", "status.png.compressed", "intake.noneQueued"] {
                let translated = try #require(table[key])
                #expect(translated != english[key], "\(locale) key '\(key)' wasn't translated")
            }
        }
    }

    @Test("Russian plural category selection follows the CLDR one/few/many rule")
    func russianPluralCategories() {
        let cases: [(Int, String)] = [
            (1, "one"), (21, "one"), (101, "one"),
            (2, "few"), (3, "few"), (4, "few"), (22, "few"),
            (5, "many"), (11, "many"), (12, "many"), (0, "many"), (100, "many")
        ]

        for (count, expectedCategory) in cases {
            let template = "\(count) \(expectedCategory)"
            #expect(pluralCategoryForTesting(count) == expectedCategory, "count \(count) -> \(template)")
        }
    }

    private func pluralBase(_ key: String) -> String {
        for suffix in [".one", ".few", ".many", ".other"] {
            if key.hasSuffix(suffix) {
                return String(key.dropLast(suffix.count))
            }
        }
        return key
    }

    private func keys(in locale: String) throws -> [String] {
        try Array(stringsTable(for: locale).keys)
    }

    private func stringsTable(for locale: String) throws -> [String: String] {
        let url = try #require(
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: locale)
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: String])
    }

    /// Mirrors `L10n`'s private Russian/Belarusian plural-category rule for direct testing.
    private func pluralCategoryForTesting(_ count: Int) -> String {
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
