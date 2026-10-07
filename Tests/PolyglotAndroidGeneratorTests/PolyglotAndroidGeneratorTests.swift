import XCTest
@testable import PolyglotAndroidGenerator
@testable import PolyglotCore

final class PolyglotAndroidGeneratorTests: XCTestCase {

    private let generator = AndroidGenerator()

    // MARK: - Directory naming

    func testDirNameSimpleLanguage() {
        XCTAssertEqual(AndroidGenerator.androidResourceDirName(for: "es"), "values-es")
        XCTAssertEqual(AndroidGenerator.androidResourceDirName(for: "fr"), "values-fr")
        XCTAssertEqual(AndroidGenerator.androidResourceDirName(for: "en"), "values-en")
    }

    func testDirNameRegionCode() {
        XCTAssertEqual(AndroidGenerator.androidResourceDirName(for: "pt-BR"), "values-pt-rBR")
        XCTAssertEqual(AndroidGenerator.androidResourceDirName(for: "zh-CN"), "values-zh-rCN")
    }

    func testDirNameScriptCode() {
        XCTAssertEqual(AndroidGenerator.androidResourceDirName(for: "zh-Hans"), "values-b+zh+Hans")
        XCTAssertEqual(AndroidGenerator.androidResourceDirName(for: "zh-Hant"), "values-b+zh+Hant")
    }

    // MARK: - String escaping

    func testEscapeApostrophe() {
        XCTAssertEqual(generator.escapeAndroidString("don't"), "don\\'t")
    }

    func testEscapeAmpersand() {
        XCTAssertEqual(generator.escapeAndroidString("a & b"), "a &amp; b")
    }

    func testEscapeLessThan() {
        XCTAssertEqual(generator.escapeAndroidString("a < b"), "a &lt; b")
    }

    // MARK: - XML generation

    func testSimpleStringXML() throws {
        let key = StringKey(key: "app_name", baseText: "My App", platform: .android, filePath: "/fake/strings.xml")
        let translation = Translation(languageCode: "en", text: "My App", approved: true)
        let entry = TranslationEntry(key: key, translations: ["en": translation])
        let xml = try generator.buildStringsXML(entries: [entry], languageCode: "en")
        XCTAssertTrue(xml.contains(#"<string name="app_name">My App</string>"#))
        XCTAssertTrue(xml.contains(#"<?xml version="1.0" encoding="utf-8"?>"#))
        XCTAssertTrue(xml.contains("<resources>"))
        XCTAssertTrue(xml.contains("</resources>"))
    }

    func testPluralStringEnglishXML() throws {
        let forms: [PluralCategory: String] = [.one: "%d item", .other: "%d items"]
        let key = StringKey(
            key: "items_count", baseText: "%d items",
            platform: .android, filePath: "/fake/strings.xml",
            pluralForms: forms
        )
        let translation = Translation(languageCode: "en", text: "%d items", approved: true, pluralForms: forms)
        let entry = TranslationEntry(key: key, translations: ["en": translation])
        let xml = try generator.buildStringsXML(entries: [entry], languageCode: "en")
        XCTAssertTrue(xml.contains(#"<plurals name="items_count">"#))
        XCTAssertTrue(xml.contains(#"<item quantity="one">%d item</item>"#))
        XCTAssertTrue(xml.contains(#"<item quantity="other">%d items</item>"#))
        XCTAssertFalse(xml.contains(#"quantity="zero""#))
        XCTAssertFalse(xml.contains(#"quantity="few""#))
    }

    func testPluralStringRussianXML() throws {
        let forms: [PluralCategory: String] = [
            .one: "%d предмет", .few: "%d предмета",
            .many: "%d предметов", .other: "%d предмета"
        ]
        let key = StringKey(
            key: "items_count", baseText: "%d предметов",
            platform: .android, filePath: "/fake/strings.xml",
            pluralForms: forms
        )
        let translation = Translation(languageCode: "ru", text: "%d предметов", approved: true, pluralForms: forms)
        let entry = TranslationEntry(key: key, translations: ["ru": translation])
        let xml = try generator.buildStringsXML(entries: [entry], languageCode: "ru")
        XCTAssertTrue(xml.contains(#"quantity="one""#))
        XCTAssertTrue(xml.contains(#"quantity="few""#))
        XCTAssertTrue(xml.contains(#"quantity="many""#))
        XCTAssertTrue(xml.contains(#"quantity="other""#))
        XCTAssertFalse(xml.contains(#"quantity="zero""#))
        XCTAssertFalse(xml.contains(#"quantity="two""#))
    }

    // MARK: - Denormalization in XML output

    func testAndroidGeneratorDenormalizesSimpleString() throws {
        let phs = [Placeholder(format: "%s", type: "string", order: 0)]
        let key = StringKey(key: "greeting", baseText: "Hello {0}",
                            platform: .android, filePath: "/fake/strings.xml", placeholders: phs)
        let translation = Translation(languageCode: "es", text: "Hola {0}", approved: true)
        let entry = TranslationEntry(key: key, translations: ["es": translation])
        let xml = try generator.buildStringsXML(entries: [entry], languageCode: "es")
        XCTAssertTrue(xml.contains("<string name=\"greeting\">Hola %s</string>"),
                      "Android generator must denormalize {0} → %s")
        XCTAssertFalse(xml.contains("{0}"), "normalized form must not appear in Android XML")
    }

    func testAndroidGeneratorDenormalizesMultiplePlaceholders() throws {
        let phs = [
            Placeholder(format: "%s", type: "string",  order: 0),
            Placeholder(format: "%d", type: "integer", order: 1),
        ]
        let key = StringKey(key: "msg", baseText: "Hello {0}, have {1} items",
                            platform: .android, filePath: "/fake/strings.xml", placeholders: phs)
        let translation = Translation(languageCode: "en", text: "Hello {0}, have {1} items", approved: true)
        let entry = TranslationEntry(key: key, translations: ["en": translation])
        let xml = try generator.buildStringsXML(entries: [entry], languageCode: "en")
        XCTAssertTrue(xml.contains("Hello %s, have %d items"),
                      "both Android placeholders must be denormalized")
    }

    func testAndroidGeneratorPlainStringUnchanged() throws {
        let key = StringKey(key: "plain", baseText: "Hello World",
                            platform: .android, filePath: "/fake/strings.xml")
        let translation = Translation(languageCode: "en", text: "Hello World", approved: true)
        let entry = TranslationEntry(key: key, translations: ["en": translation])
        let xml = try generator.buildStringsXML(entries: [entry], languageCode: "en")
        XCTAssertTrue(xml.contains(">Hello World<"))
    }

    func testAndroidGeneratorDenormalizesPluralForms() throws {
        let phs = [Placeholder(format: "%d", type: "integer", order: 0)]
        let forms: [PluralCategory: String] = [.one: "{0} item", .other: "{0} items"]
        let key = StringKey(key: "items_count", baseText: "{0} items",
                            platform: .android, filePath: "/fake/strings.xml",
                            placeholders: phs, pluralForms: forms)
        let translation = Translation(languageCode: "en", text: "{0} items",
                                      approved: true, pluralForms: forms)
        let entry = TranslationEntry(key: key, translations: ["en": translation])
        let xml = try generator.buildStringsXML(entries: [entry], languageCode: "en")
        XCTAssertTrue(xml.contains("<item quantity=\"one\">%d item</item>"),
                      "plural 'one' form must be denormalized")
        XCTAssertTrue(xml.contains("<item quantity=\"other\">%d items</item>"),
                      "plural 'other' form must be denormalized")
        XCTAssertFalse(xml.contains("{0}"), "normalized form must not appear in Android XML")
    }

    func testGenerateBundleCreatesFiles() throws {
        let key = StringKey(key: "app_name", baseText: "My App", platform: .android, filePath: "/fake/strings.xml")
        let entry = TranslationEntry(key: key, translations: [
            "en": Translation(languageCode: "en", text: "My App",     approved: true),
            "es": Translation(languageCode: "es", text: "Mi aplicación", approved: true),
        ])
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try generator.generateBundle(from: [entry], outputDirectory: tmp)

        let enURL = tmp.appendingPathComponent("values-en/strings.xml")
        let esURL = tmp.appendingPathComponent("values-es/strings.xml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: enURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: esURL.path))
        let esContent = try String(contentsOf: esURL, encoding: .utf8)
        XCTAssertTrue(esContent.contains("Mi aplicación"))
    }
}
