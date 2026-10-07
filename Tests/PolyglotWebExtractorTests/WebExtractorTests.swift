import XCTest
@testable import PolyglotWebExtractor
import PolyglotCore

final class WebExtractorTests: XCTestCase {
    let extractor = WebExtractor()

    // MARK: - Key extraction

    func testDoubleQuotedKey() {
        let keys = extractor.extractKeys(from: #"const title = t("auth.login.title");"#, filePath: "app.ts")
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].key, "auth.login.title")
        XCTAssertEqual(keys[0].platform, .web)
    }

    func testSingleQuotedKey() {
        let keys = extractor.extractKeys(from: "const label = t('button.submit');", filePath: "app.ts")
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].key, "button.submit")
    }

    func testMemberCallI18nT() {
        let keys = extractor.extractKeys(from: #"i18n.t("settings.title")"#, filePath: "app.ts")
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].key, "settings.title")
    }

    func testDollarT() {
        // Vue-style $t
        let keys = extractor.extractKeys(from: #"{{ $t("nav.home") }}"#, filePath: "App.vue")
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].key, "nav.home")
    }

    func testThisDollarT() {
        let keys = extractor.extractKeys(from: #"this.$t("profile.title")"#, filePath: "component.ts")
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].key, "profile.title")
    }

    func testMultipleKeysInFile() {
        let source = """
        const a = t("key.one");
        const b = t("key.two");
        const c = t('key.three');
        """
        let keys = extractor.extractKeys(from: source, filePath: "app.ts")
        XCTAssertEqual(keys.count, 3)
        XCTAssertEqual(Set(keys.map { $0.key }), ["key.one", "key.two", "key.three"])
    }

    func testNaturalLanguageKey() {
        // i18next natural-language mode: full sentence as key
        let keys = extractor.extractKeys(from: #"t("Welcome to our application")"#, filePath: "app.ts")
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].key, "Welcome to our application")
    }

    // MARK: - False positive prevention

    func testFormatFunctionNotExtracted() {
        // "format" ends in t but should NOT be extracted
        let keys = extractor.extractKeys(from: #"format("some string")"#, filePath: "app.ts")
        XCTAssertEqual(keys.count, 0)
    }

    func testGetAttributeNotExtracted() {
        let keys = extractor.extractKeys(from: #"getAttribute("data-id")"#, filePath: "app.ts")
        XCTAssertEqual(keys.count, 0)
    }

    func testTemplateStringSkipped() {
        // Dynamic key — regex won't match template literals with expressions
        let keys = extractor.extractKeys(from: "t(`key.${name}`)", filePath: "app.ts")
        XCTAssertEqual(keys.count, 0)
    }

    // MARK: - Placeholder extraction

    func testDoubleBracePlaceholder() {
        let placeholders = extractor.extractPlaceholders(from: "Hello {{name}}, you have {{count}} messages")
        XCTAssertEqual(placeholders.count, 2)
        XCTAssertEqual(placeholders[0].format, "{{name}}")
        XCTAssertEqual(placeholders[1].format, "{{count}}")
        XCTAssertEqual(placeholders[0].type, "string")
    }

    func testSingleBracePlaceholder() {
        let placeholders = extractor.extractPlaceholders(from: "Hello {name}, welcome!")
        XCTAssertEqual(placeholders.count, 1)
        XCTAssertEqual(placeholders[0].format, "{name}")
    }

    func testDoubleBraceTakesPriorityOverSingle() {
        // {{name}} should be detected as double-brace, not also matched as {name}
        let placeholders = extractor.extractPlaceholders(from: "Hello {{name}}")
        XCTAssertEqual(placeholders.count, 1)
        XCTAssertEqual(placeholders[0].format, "{{name}}")
    }

    func testNoPlaceholders() {
        XCTAssertTrue(extractor.extractPlaceholders(from: "Hello world").isEmpty)
    }

    // MARK: - File discovery

    func testFindsJSTSJSXTSXFiles() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let extensions = ["js", "ts", "jsx", "tsx", "vue", "svelte"]
        for ext in extensions {
            try "".write(to: tmp.appendingPathComponent("file.\(ext)"), atomically: true, encoding: .utf8)
        }
        try "".write(to: tmp.appendingPathComponent("file.json"), atomically: true, encoding: .utf8)

        let found = extractor.findSourceFiles(in: tmp)
        XCTAssertEqual(found.count, extensions.count)
        XCTAssertFalse(found.contains { $0.pathExtension == "json" })
    }

    func testSkipsNodeModules() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nodeModules = tmp.appendingPathComponent("node_modules/somelib")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "t('skip.me')".write(to: nodeModules.appendingPathComponent("index.ts"), atomically: true, encoding: .utf8)
        try "t('keep.me')".write(to: tmp.appendingPathComponent("app.ts"), atomically: true, encoding: .utf8)

        let found = extractor.findSourceFiles(in: tmp)
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found[0].lastPathComponent == "app.ts")
    }

    // MARK: - Position tracking

    func testLineNumberIsRecorded() {
        let source = "const a = 1;\nconst b = t(\"my.key\");"
        let keys = extractor.extractKeys(from: source, filePath: "app.ts")
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].positions.first?.lineNumber, 2)
    }
}
