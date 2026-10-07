//
//  PolyglotCoreTests.swift
//  PolyglotCoreTests
//

import XCTest
@testable import PolyglotCore

final class PolyglotCoreTests: XCTestCase {

    func testPluralCategoryRoundTripsJSON() throws {
        let categories: [PluralCategory] = [.zero, .one, .two, .few, .many, .other]
        let data = try JSONEncoder().encode(categories)
        let decoded = try JSONDecoder().decode([PluralCategory].self, from: data)
        XCTAssertEqual(decoded, categories)
    }

    func testStringKeyPluralFormsRoundTrip() throws {
        let forms: [PluralCategory: String] = [.one: "%d item", .other: "%d items"]
        let key = StringKey(
            key: "items.count", baseText: "%d items",
            platform: .ios, filePath: "/fake/File.swift",
            pluralForms: forms
        )
        XCTAssertTrue(key.isPlural)
        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(StringKey.self, from: data)
        XCTAssertEqual(decoded.pluralForms, forms)
        XCTAssertTrue(decoded.isPlural)
    }

    func testStringKeyNonPluralRoundTrip() throws {
        let key = StringKey(
            key: "welcome.title", baseText: "Welcome",
            platform: .ios, filePath: "/fake/File.swift"
        )
        XCTAssertFalse(key.isPlural)
        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(StringKey.self, from: data)
        XCTAssertNil(decoded.pluralForms)
        XCTAssertFalse(decoded.isPlural)
    }

    func testBackwardCompatOldJSONWithIsPluralTrue() throws {
        let oldJSON = """
        {
          "key": "items.count",
          "baseText": "%d items",
          "platform": "ios",
          "filePath": "/fake/File.swift",
          "positions": [],
          "placeholders": [],
          "isPlural": true
        }
        """.data(using: .utf8)!
        let key = try JSONDecoder().decode(StringKey.self, from: oldJSON)
        // Legacy "isPlural" is ignored; pluralForms=nil → isPlural=false
        XCTAssertNil(key.pluralForms)
        XCTAssertFalse(key.isPlural)
    }

    func testBackwardCompatOldJSONWithIsPluralFalse() throws {
        let oldJSON = """
        {
          "key": "welcome.title",
          "baseText": "Welcome",
          "platform": "ios",
          "filePath": "/fake/File.swift",
          "isPlural": false
        }
        """.data(using: .utf8)!
        let key = try JSONDecoder().decode(StringKey.self, from: oldJSON)
        XCTAssertFalse(key.isPlural)
    }

    func testTranslationPluralFormsRoundTrip() throws {
        let forms: [PluralCategory: String] = [.one: "%d Artikel", .other: "%d Artikel"]
        let t = Translation(languageCode: "de", text: "%d Artikel", pluralForms: forms)
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(Translation.self, from: data)
        XCTAssertEqual(decoded.pluralForms, forms)
    }

    // MARK: - normalize

    func testNormalizeNoPlaceholdersIsNoop() {
        XCTAssertEqual(StringKey.normalize(text: "Hello World", placeholders: []), "Hello World")
    }

    func testNormalizeSingleIosPlaceholder() {
        let phs = [Placeholder(format: "%@", type: "string", position: 6, order: 0)]
        XCTAssertEqual(StringKey.normalize(text: "Hello %@", placeholders: phs), "Hello {0}")
    }

    func testNormalizeSingleAndroidPlaceholder() {
        let phs = [Placeholder(format: "%s", type: "string", position: 6, order: 0)]
        XCTAssertEqual(StringKey.normalize(text: "Hello %s", placeholders: phs), "Hello {0}")
    }

    func testNormalizeAndroidPositionalFormat() {
        let phs = [Placeholder(format: "%1$s", type: "string", position: 6, order: 0)]
        XCTAssertEqual(StringKey.normalize(text: "Hello %1$s", placeholders: phs), "Hello {0}")
    }

    func testNormalizeSingleWebNamedPlaceholder() {
        let phs = [Placeholder(format: "{{name}}", type: "string", position: 6, order: 0)]
        XCTAssertEqual(StringKey.normalize(text: "Hello {{name}}", placeholders: phs), "Hello {0}")
    }

    func testNormalizeSingleCurlyBracePlaceholder() {
        let phs = [Placeholder(format: "{name}", type: "string", position: 6, order: 0)]
        XCTAssertEqual(StringKey.normalize(text: "Hello {name}", placeholders: phs), "Hello {0}")
    }

    func testNormalizeTwoIosPlaceholders() {
        let phs = [
            Placeholder(format: "%@", type: "string",  position: 6,  order: 0),
            Placeholder(format: "%d", type: "integer", position: 16, order: 1),
        ]
        let result = StringKey.normalize(text: "Hello %@, have %d items", placeholders: phs)
        XCTAssertEqual(result, "Hello {0}, have {1} items")
    }

    func testNormalizeTwoWebPlaceholders() {
        let phs = [
            Placeholder(format: "{{name}}",  type: "string",  position: 6,  order: 0),
            Placeholder(format: "{{count}}", type: "integer", position: 20, order: 1),
        ]
        let result = StringKey.normalize(text: "Hello {{name}}, you have {{count}} items", placeholders: phs)
        XCTAssertEqual(result, "Hello {0}, you have {1} items")
    }

    func testNormalizePreservesNonPlaceholderText() {
        let phs = [Placeholder(format: "%@", type: "string", position: 0, order: 0)]
        XCTAssertEqual(StringKey.normalize(text: "%@ is great", placeholders: phs), "{0} is great")
    }

    func testNormalizeDuplicateFormatPlaceholders() {
        // Two %@ tokens must become {0} and {1}, not both {0}.
        let phs = [
            Placeholder(format: "%@", type: "string", position: 0,  order: 0),
            Placeholder(format: "%@", type: "string", position: 13, order: 1),
        ]
        let result = StringKey.normalize(text: "%@ is better than %@", placeholders: phs)
        XCTAssertEqual(result, "{0} is better than {1}")
    }

    func testNormalizeDuplicateFormatRoundTrip() throws {
        let original = "%@ is better than %@"
        let phs = [
            Placeholder(format: "%@", type: "string", position: 0,  order: 0),
            Placeholder(format: "%@", type: "string", position: 13, order: 1),
        ]
        let normalized   = StringKey.normalize(text: original, placeholders: phs)
        let denormalized = try StringKey.denormalize(text: normalized, placeholders: phs)
        XCTAssertEqual(denormalized, original, "round-trip must restore text with duplicate-format placeholders")
    }

    func testNormalizeThreePlaceholdersSameFormat() {
        let phs = [
            Placeholder(format: "%@", type: "string", position: 0,  order: 0),
            Placeholder(format: "%@", type: "string", position: 5,  order: 1),
            Placeholder(format: "%@", type: "string", position: 10, order: 2),
        ]
        let result = StringKey.normalize(text: "%@ + %@ + %@", placeholders: phs)
        XCTAssertEqual(result, "{0} + {1} + {2}")
    }

    func testNormalizeIosAndAndroidSameResult() {
        let iosPhs    = [Placeholder(format: "%@", type: "string", position: 6, order: 0)]
        let androidPhs = [Placeholder(format: "%s", type: "string", position: 6, order: 0)]
        let iosNorm     = StringKey.normalize(text: "Hello %@", placeholders: iosPhs)
        let androidNorm = StringKey.normalize(text: "Hello %s", placeholders: androidPhs)
        XCTAssertEqual(iosNorm, androidNorm,
                       "iOS %@ and Android %s must produce identical normalized form")
    }

    func testNormalizeWebAndIosSameResult() {
        let iosPhs = [Placeholder(format: "%@",     type: "string", position: 6, order: 0)]
        let webPhs = [Placeholder(format: "{{name}}", type: "string", position: 6, order: 0)]
        let iosNorm = StringKey.normalize(text: "Hello %@",     placeholders: iosPhs)
        let webNorm = StringKey.normalize(text: "Hello {{name}}", placeholders: webPhs)
        XCTAssertEqual(iosNorm, webNorm,
                       "iOS %@ and Web {{name}} must produce identical normalized form")
    }

    // MARK: - denormalize

    func testDenormalizeNoPlaceholdersIsNoop() throws {
        XCTAssertEqual(try StringKey.denormalize(text: "Hello World", placeholders: []), "Hello World")
    }

    func testDenormalizeToIosFormat() throws {
        let phs = [Placeholder(format: "%@", type: "string", order: 0)]
        XCTAssertEqual(try StringKey.denormalize(text: "Hello {0}", placeholders: phs), "Hello %@")
    }

    func testDenormalizeToAndroidFormat() throws {
        let phs = [Placeholder(format: "%s", type: "string", order: 0)]
        XCTAssertEqual(try StringKey.denormalize(text: "Hello {0}", placeholders: phs), "Hello %s")
    }

    func testDenormalizeToWebDoubleBraceFormat() throws {
        let phs = [Placeholder(format: "{{name}}", type: "string", order: 0)]
        XCTAssertEqual(try StringKey.denormalize(text: "Hello {0}", placeholders: phs), "Hello {{name}}")
    }

    func testDenormalizeTwoPlaceholders() throws {
        let phs = [
            Placeholder(format: "%@", type: "string",  order: 0),
            Placeholder(format: "%d", type: "integer", order: 1),
        ]
        XCTAssertEqual(
            try StringKey.denormalize(text: "Hello {0}, have {1} items", placeholders: phs),
            "Hello %@, have %d items"
        )
    }

    func testDenormalizeTwoAndroidPlaceholders() throws {
        let phs = [
            Placeholder(format: "%s", type: "string",  order: 0),
            Placeholder(format: "%d", type: "integer", order: 1),
        ]
        XCTAssertEqual(
            try StringKey.denormalize(text: "Hello {0}, have {1} items", placeholders: phs),
            "Hello %s, have %d items"
        )
    }

    func testDenormalizeTwoWebPlaceholders() throws {
        let phs = [
            Placeholder(format: "{{name}}",  type: "string",  order: 0),
            Placeholder(format: "{{count}}", type: "integer", order: 1),
        ]
        XCTAssertEqual(
            try StringKey.denormalize(text: "Hello {0}, you have {1} items", placeholders: phs),
            "Hello {{name}}, you have {{count}} items"
        )
    }

    // MARK: - Round-trip

    func testRoundTripIosTwoPlaceholders() throws {
        let original = "Hello %@, you have %d notifications"
        let phs = [
            Placeholder(format: "%@", type: "string",  position: 6,  order: 0),
            Placeholder(format: "%d", type: "integer", position: 20, order: 1),
        ]
        let normalized   = StringKey.normalize(text: original, placeholders: phs)
        let denormalized = try StringKey.denormalize(text: normalized, placeholders: phs)
        XCTAssertEqual(denormalized, original, "round-trip must restore original iOS text")
    }

    func testRoundTripAndroid() throws {
        let original = "Welcome back, %s! You have %d messages."
        let phs = [
            Placeholder(format: "%s", type: "string",  position: 14, order: 0),
            Placeholder(format: "%d", type: "integer", position: 29, order: 1),
        ]
        let normalized   = StringKey.normalize(text: original, placeholders: phs)
        let denormalized = try StringKey.denormalize(text: normalized, placeholders: phs)
        XCTAssertEqual(denormalized, original, "round-trip must restore original Android text")
    }

    func testRoundTripWeb() throws {
        let original = "Hello {{name}}, you have {{count}} items"
        let phs = [
            Placeholder(format: "{{name}}",  type: "string",  position: 6,  order: 0),
            Placeholder(format: "{{count}}", type: "integer", position: 23, order: 1),
        ]
        let normalized   = StringKey.normalize(text: original, placeholders: phs)
        let denormalized = try StringKey.denormalize(text: normalized, placeholders: phs)
        XCTAssertEqual(denormalized, original, "round-trip must restore original Web text")
    }

    func testCrossPlatformTranslationDelivery() throws {
        // Simulate: iOS canonical has %@, Android alias has %s.
        // LLM translates normalized form "Hola {0}" — denormalize to each platform.
        let translatedNormalized = "Hola {0}"
        let iosPhs    = [Placeholder(format: "%@", order: 0)]
        let androidPhs = [Placeholder(format: "%s", order: 0)]
        let webPhs    = [Placeholder(format: "{{name}}", order: 0)]

        XCTAssertEqual(try StringKey.denormalize(text: translatedNormalized, placeholders: iosPhs),    "Hola %@")
        XCTAssertEqual(try StringKey.denormalize(text: translatedNormalized, placeholders: androidPhs), "Hola %s")
        XCTAssertEqual(try StringKey.denormalize(text: translatedNormalized, placeholders: webPhs),    "Hola {{name}}")
    }
}
