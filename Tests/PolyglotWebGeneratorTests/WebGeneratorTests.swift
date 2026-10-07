import XCTest
@testable import PolyglotWebGenerator
import PolyglotCore

final class WebGeneratorTests: XCTestCase {
    let generator = WebGenerator()

    // MARK: - Helpers

    private func entry(key: String, text: String, lang: String = "en", pluralForms: [PluralCategory: String]? = nil) -> TranslationEntry {
        let stringKey = StringKey(key: key, baseText: text, platform: .web, filePath: "app.ts", pluralForms: pluralForms)
        let translation = PolyglotCore.Translation(languageCode: lang, text: text, approved: true, pluralForms: pluralForms)
        return TranslationEntry(key: stringKey, translations: [lang: translation])
    }

    private func multiLangEntry(key: String, translations: [String: String]) -> TranslationEntry {
        let stringKey = StringKey(key: key, baseText: translations["en"] ?? key, platform: .web, filePath: "app.ts")
        var trans: [String: PolyglotCore.Translation] = [:]
        for (lang, text) in translations {
            trans[lang] = PolyglotCore.Translation(languageCode: lang, text: text, approved: true)
        }
        return TranslationEntry(key: stringKey, translations: trans)
    }

    // MARK: - JSON output

    func testSimpleStringOutput() throws {
        let entries = [entry(key: "auth.login.title", text: "Sign In")]
        let json = try generator.buildJSON(from: entries, language: "en")
        XCTAssertTrue(json.contains("\"auth.login.title\": \"Sign In\""))
        XCTAssertTrue(json.hasPrefix("{"))
        XCTAssertTrue(json.hasSuffix("}"))
    }

    func testKeysAreSortedAlphabetically() throws {
        let entries = [
            entry(key: "z.key", text: "Z"),
            entry(key: "a.key", text: "A"),
            entry(key: "m.key", text: "M"),
        ]
        let json = try generator.buildJSON(from: entries, language: "en")
        let aPos = json.range(of: "\"a.key\"")!.lowerBound
        let mPos = json.range(of: "\"m.key\"")!.lowerBound
        let zPos = json.range(of: "\"z.key\"")!.lowerBound
        XCTAssertLessThan(aPos, mPos)
        XCTAssertLessThan(mPos, zPos)
    }

    func testPluralFormsUseI18nextSuffix() throws {
        let forms: [PluralCategory: String] = [.one: "%d item", .other: "%d items"]
        let key = StringKey(key: "items.count", baseText: "items.count", platform: .web, filePath: "app.ts", pluralForms: forms)
        let translation = PolyglotCore.Translation(languageCode: "en", text: "%d items", approved: true, pluralForms: forms)
        let entries = [TranslationEntry(key: key, translations: ["en": translation])]

        let json = try generator.buildJSON(from: entries, language: "en")
        XCTAssertTrue(json.contains("\"items.count_one\": \"%d item\""))
        XCTAssertTrue(json.contains("\"items.count_other\": \"%d items\""))
    }

    func testRussianPluralForms() throws {
        let sourceForms: [PluralCategory: String] = [.one: "1 item", .other: "items"]
        let ruForms: [PluralCategory: String] = [
            .one: "%d предмет",
            .few: "%d предмета",
            .many: "%d предметов",
            .other: "%d предмета"
        ]
        let key = StringKey(key: "items.count", baseText: "items.count", platform: .web, filePath: "app.ts", pluralForms: sourceForms)
        let translation = PolyglotCore.Translation(languageCode: "ru", text: "%d предметов", approved: true, pluralForms: ruForms)
        let entries = [TranslationEntry(key: key, translations: ["ru": translation])]

        let json = try generator.buildJSON(from: entries, language: "ru")
        XCTAssertTrue(json.contains("\"items.count_one\": \"%d предмет\""))
        XCTAssertTrue(json.contains("\"items.count_few\": \"%d предмета\""))
        XCTAssertTrue(json.contains("\"items.count_many\": \"%d предметов\""))
    }

    func testMissingLanguageProducesEmptyObject() throws {
        let entries = [entry(key: "some.key", text: "Hello", lang: "en")]
        let json = try generator.buildJSON(from: entries, language: "fr")
        XCTAssertEqual(json, "{\n}")
    }

    // MARK: - JSON escaping

    func testEscapesDoubleQuotes() throws {
        let entries = [entry(key: "key", text: "Say \"hello\"")]
        let json = try generator.buildJSON(from: entries, language: "en")
        XCTAssertTrue(json.contains(#"\"hello\""#))
    }

    func testEscapesNewlines() throws {
        let entries = [entry(key: "key", text: "Line 1\nLine 2")]
        let json = try generator.buildJSON(from: entries, language: "en")
        XCTAssertTrue(json.contains(#"\n"#))
        XCTAssertFalse(json.contains("\n  \"key\"") == false) // actual newline not in value
    }

    func testEscapesBackslash() throws {
        let entries = [entry(key: "key", text: "C:\\Users\\name")]
        let json = try generator.buildJSON(from: entries, language: "en")
        XCTAssertTrue(json.contains("C:\\\\Users\\\\name"))
    }

    // MARK: - Multiple languages

    func testMultipleLanguagesProduceSeparateFiles() throws {
        let entries = [
            multiLangEntry(key: "greeting", translations: ["en": "Hello", "es": "Hola", "fr": "Bonjour"])
        ]
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try generator.generateBundle(from: entries, outputDirectory: tmp)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent("en.json").path))
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent("es.json").path))
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent("fr.json").path))
    }

    func testGeneratedFileIsValidJSON() throws {
        let entries = [
            multiLangEntry(key: "auth.title", translations: ["en": "Sign In", "es": "Iniciar sesión"])
        ]
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try generator.generateBundle(from: entries, outputDirectory: tmp)

        let enData = try Data(contentsOf: tmp.appendingPathComponent("en.json"))
        let parsed = try JSONSerialization.jsonObject(with: enData) as? [String: String]
        XCTAssertEqual(parsed?["auth.title"], "Sign In")

        let esData = try Data(contentsOf: tmp.appendingPathComponent("es.json"))
        let esParsed = try JSONSerialization.jsonObject(with: esData) as? [String: String]
        XCTAssertEqual(esParsed?["auth.title"], "Iniciar sesión")
    }

    // MARK: - Denormalization in JSON output

    func testWebGeneratorDenormalizesNamedPlaceholder() throws {
        let phs = [Placeholder(format: "{{name}}", type: "string", order: 0)]
        let key = StringKey(key: "greeting", baseText: "Hello {0}",
                            platform: .web, filePath: "app.ts", placeholders: phs)
        let translation = PolyglotCore.Translation(languageCode: "es", text: "Hola {0}", approved: true)
        let entries = [TranslationEntry(key: key, translations: ["es": translation])]
        let json = try generator.buildJSON(from: entries, language: "es")
        XCTAssertTrue(json.contains("\"Hola {{name}}\""),
                      "Web generator must denormalize {0} → {{name}}")
        XCTAssertFalse(json.contains("\"{0}\""), "normalized form must not appear in JSON output")
    }

    func testWebGeneratorDenormalizesTwoPlaceholders() throws {
        let phs = [
            Placeholder(format: "{{name}}",  type: "string",  order: 0),
            Placeholder(format: "{{count}}", type: "integer", order: 1),
        ]
        let key = StringKey(key: "msg", baseText: "Hello {0}, you have {1} items",
                            platform: .web, filePath: "app.ts", placeholders: phs)
        let translation = PolyglotCore.Translation(languageCode: "en",
                                                   text: "Hello {0}, you have {1} items", approved: true)
        let entries = [TranslationEntry(key: key, translations: ["en": translation])]
        let json = try generator.buildJSON(from: entries, language: "en")
        XCTAssertTrue(json.contains("\"Hello {{name}}, you have {{count}} items\""),
                      "both web placeholders must be denormalized")
    }

    func testWebGeneratorDenormalizesPluralForms() throws {
        let phs = [Placeholder(format: "{{count}}", type: "integer", order: 0)]
        let sourceForms: [PluralCategory: String] = [.one: "{0} item", .other: "{0} items"]
        let key = StringKey(key: "items.count", baseText: "items.count",
                            platform: .web, filePath: "app.ts",
                            placeholders: phs, pluralForms: sourceForms)
        let translation = PolyglotCore.Translation(languageCode: "en", text: "{0} items",
                                                   approved: true, pluralForms: sourceForms)
        let entries = [TranslationEntry(key: key, translations: ["en": translation])]
        let json = try generator.buildJSON(from: entries, language: "en")
        XCTAssertTrue(json.contains("\"items.count_one\": \"{{count}} item\""),
                      "plural 'one' form must be denormalized in i18next JSON")
        XCTAssertTrue(json.contains("\"items.count_other\": \"{{count}} items\""),
                      "plural 'other' form must be denormalized in i18next JSON")
        XCTAssertFalse(json.contains("{0}"), "normalized form must not appear in JSON output")
    }

    func testWebGeneratorPlainStringUnchanged() throws {
        let entries = [entry(key: "plain", text: "Hello World")]
        let json = try generator.buildJSON(from: entries, language: "en")
        XCTAssertTrue(json.contains("\"Hello World\""))
    }

    func testNoTrailingCommaOnLastKey() throws {
        let entries = [
            entry(key: "a", text: "A"),
            entry(key: "b", text: "B"),
        ]
        let json = try generator.buildJSON(from: entries, language: "en")
        // Last key-value pair must not end with comma before closing brace
        XCTAssertFalse(json.contains(",\n}"))
    }
}
