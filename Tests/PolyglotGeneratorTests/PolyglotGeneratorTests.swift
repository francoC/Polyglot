//
//  PolyglotGeneratorTests.swift
//  PolyglotGeneratorTests
//

import XCTest
@testable import PolyglotGenerator
@testable import PolyglotCore

final class PolyglotGeneratorTests: XCTestCase {

    func testGeneratorInitialization() {
        XCTAssertNotNil(Generator())
    }

    // MARK: - CLDR category table

    func testRequiredCategoriesEnglish() {
        XCTAssertEqual(Generator.requiredCategories(for: "en"), [.one, .other])
    }

    func testRequiredCategoriesRussian() {
        XCTAssertEqual(Generator.requiredCategories(for: "ru"), [.one, .few, .many, .other])
    }

    func testRequiredCategoriesArabic() {
        XCTAssertEqual(Generator.requiredCategories(for: "ar"), [.zero, .one, .two, .few, .many, .other])
    }

    func testRequiredCategoriesHebrew() {
        XCTAssertEqual(Generator.requiredCategories(for: "he"), [.one, .two, .many, .other])
    }

    func testRequiredCategoriesChineseSimplified() {
        XCTAssertEqual(Generator.requiredCategories(for: "zh-Hans"), [.other])
    }

    func testRequiredCategoriesUnknownFallsBackToDefault() {
        XCTAssertEqual(Generator.requiredCategories(for: "xx"), [.one, .other])
    }

    func testRequiredCategoriesBaseTagFallback() {
        // pt-BR not in table; base "pt" not in table either → default
        XCTAssertEqual(Generator.requiredCategories(for: "pt-BR"), [.one, .other])
    }

    // MARK: - stringsdict generation

    private func makeBundle(forms: [PluralCategory: String], languageCode: String) throws -> String {
        let key = StringKey(
            key: "items.count", baseText: "%d items",
            platform: .ios, filePath: "/fake/File.swift",
            pluralForms: forms
        )
        let translation = Translation(
            languageCode: languageCode, text: "%d items",
            approved: true, pluralForms: forms
        )
        let entry = TranslationEntry(key: key, translations: [languageCode: translation])
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try Generator().generateBundle(from: [entry], outputDirectory: tmpDir)
        let dictURL = tmpDir.appendingPathComponent("\(languageCode).lproj/Localizable.stringsdict")
        return try String(contentsOf: dictURL, encoding: .utf8)
    }

    func testStringsDictEnglishStructure() throws {
        let xml = try makeBundle(forms: [.one: "%d item", .other: "%d items"], languageCode: "en")
        XCTAssertTrue(xml.contains("NSStringLocalizedFormatKey"))
        XCTAssertTrue(xml.contains("%#@value@"))
        XCTAssertTrue(xml.contains("NSStringPluralRuleType"))
        XCTAssertTrue(xml.contains("<key>one</key>"))
        XCTAssertTrue(xml.contains("<string>%d item</string>"))
        XCTAssertTrue(xml.contains("<key>other</key>"))
        XCTAssertTrue(xml.contains("<string>%d items</string>"))
        // Russian-only categories must not appear
        XCTAssertFalse(xml.contains("<key>few</key>"))
        XCTAssertFalse(xml.contains("<key>many</key>"))
    }

    func testStringsDictRussianHasFourCategories() throws {
        let forms: [PluralCategory: String] = [
            .one: "%d предмет", .few: "%d предмета",
            .many: "%d предметов", .other: "%d предмета"
        ]
        let xml = try makeBundle(forms: forms, languageCode: "ru")
        XCTAssertTrue(xml.contains("<key>one</key>"))
        XCTAssertTrue(xml.contains("<key>few</key>"))
        XCTAssertTrue(xml.contains("<key>many</key>"))
        XCTAssertTrue(xml.contains("<key>other</key>"))
        XCTAssertFalse(xml.contains("<key>zero</key>"))
        XCTAssertFalse(xml.contains("<key>two</key>"))
    }

    func testStringsDictArabicHasSixCategories() throws {
        let forms: [PluralCategory: String] = [
            .zero: "لا عناصر", .one: "عنصر واحد", .two: "عنصران",
            .few: "%d عناصر", .many: "%d عنصرًا", .other: "%d عنصر"
        ]
        let xml = try makeBundle(forms: forms, languageCode: "ar")
        for cat in PluralCategory.allCases {
            XCTAssertTrue(xml.contains("<key>\(cat.rawValue)</key>"), "Missing category: \(cat.rawValue)")
        }
    }

    func testStringsDictChineseHasOnlyOther() throws {
        let xml = try makeBundle(forms: [.other: "%d 项目"], languageCode: "zh")
        XCTAssertTrue(xml.contains("<key>other</key>"))
        XCTAssertFalse(xml.contains("<key>one</key>"))
    }

    // MARK: - Denormalization in .strings output

    func testGeneratorDenormalizesIosPlaceholderInStringsFile() throws {
        let phs = [Placeholder(format: "%@", type: "string", position: 6, order: 0)]
        let key = StringKey(key: "greeting", baseText: "Hello {0}",
                            platform: .ios, filePath: "/fake/File.swift", placeholders: phs)
        // Translation stored in normalized form
        let translation = Translation(languageCode: "es", text: "Hola {0}", approved: true)
        let entry = TranslationEntry(key: key, translations: ["es": translation])
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try Generator().generateBundle(from: [entry], outputDirectory: tmpDir)
        let content = try String(contentsOf: tmpDir.appendingPathComponent("es.lproj/Localizable.strings"), encoding: .utf8)
        XCTAssertTrue(content.contains("\"Hola %@\""), "generator must denormalize {0} → %@ for iOS")
        XCTAssertFalse(content.contains("{0}"), "normalized form must not appear in .strings output")
    }

    func testGeneratorDenormalizesMultiplePlaceholders() throws {
        let phs = [
            Placeholder(format: "%@", type: "string",  position: 6,  order: 0),
            Placeholder(format: "%d", type: "integer", position: 16, order: 1),
        ]
        let key = StringKey(key: "msg", baseText: "Hello {0}, have {1} items",
                            platform: .ios, filePath: "/fake/File.swift", placeholders: phs)
        let translation = Translation(languageCode: "en", text: "Hello {0}, have {1} items", approved: true)
        let entry = TranslationEntry(key: key, translations: ["en": translation])
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try Generator().generateBundle(from: [entry], outputDirectory: tmpDir)
        let content = try String(contentsOf: tmpDir.appendingPathComponent("en.lproj/Localizable.strings"), encoding: .utf8)
        XCTAssertTrue(content.contains("\"Hello %@, have %d items\""), "both placeholders must be denormalized")
    }

    func testGeneratorPlainStringNotAffectedByDenormalize() throws {
        let key = StringKey(key: "plain", baseText: "Hello World",
                            platform: .ios, filePath: "/fake/File.swift")
        let translation = Translation(languageCode: "en", text: "Hello World", approved: true)
        let entry = TranslationEntry(key: key, translations: ["en": translation])
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try Generator().generateBundle(from: [entry], outputDirectory: tmpDir)
        let content = try String(contentsOf: tmpDir.appendingPathComponent("en.lproj/Localizable.strings"), encoding: .utf8)
        XCTAssertTrue(content.contains("\"Hello World\""))
    }

    func testGeneratorDenormalizesStringsDictPluralForms() throws {
        let phs = [Placeholder(format: "%d", type: "integer", position: 0, order: 0)]
        let forms: [PluralCategory: String] = [.one: "{0} item", .other: "{0} items"]
        let key = StringKey(key: "items.count", baseText: "{0} items",
                            platform: .ios, filePath: "/fake/File.swift",
                            placeholders: phs, pluralForms: forms)
        let translation = Translation(languageCode: "en", text: "{0} items",
                                      approved: true, pluralForms: forms)
        let entry = TranslationEntry(key: key, translations: ["en": translation])
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try Generator().generateBundle(from: [entry], outputDirectory: tmpDir)
        let xml = try String(contentsOf: tmpDir.appendingPathComponent("en.lproj/Localizable.stringsdict"), encoding: .utf8)
        XCTAssertTrue(xml.contains("<string>%d item</string>"), "plural 'one' form must be denormalized")
        XCTAssertTrue(xml.contains("<string>%d items</string>"), "plural 'other' form must be denormalized")
        XCTAssertFalse(xml.contains("{0}"), "normalized form must not appear in stringsdict")
    }

    func testStringsDictFallsBackToBaseTextWhenNoForms() throws {
        let key = StringKey(
            key: "items.count", baseText: "some items",
            platform: .ios, filePath: "/fake/File.swift",
            pluralForms: [:]   // plural but no source forms known
        )
        let translation = Translation(languageCode: "en", text: "some items", approved: true, pluralForms: nil)
        let entry = TranslationEntry(key: key, translations: ["en": translation])
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try Generator().generateBundle(from: [entry], outputDirectory: tmpDir)
        let xml = try String(contentsOf: tmpDir.appendingPathComponent("en.lproj/Localizable.stringsdict"), encoding: .utf8)
        // Falls back to baseText for all required categories
        XCTAssertTrue(xml.contains("<string>some items</string>"))
    }
}
