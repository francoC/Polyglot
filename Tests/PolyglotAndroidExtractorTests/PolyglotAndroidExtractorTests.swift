import XCTest
@testable import PolyglotAndroidExtractor
@testable import PolyglotCore

final class PolyglotAndroidExtractorTests: XCTestCase {

    private let extractor = AndroidExtractor()

    private func parse(_ xml: String) throws -> [StringKey] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return try extractor.extractFromFile(at: url)
    }

    func testSimpleString() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <resources>
            <string name="app_name">My App</string>
        </resources>
        """
        let keys = try parse(xml)
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].key, "app_name")
        XCTAssertEqual(keys[0].baseText, "My App")
        XCTAssertEqual(keys[0].platform, .android)
        XCTAssertFalse(keys[0].isPlural)
    }

    func testTranslatableFalseIsSkipped() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <resources>
            <string name="visible">Hello</string>
            <string name="hidden" translatable="false">debug</string>
        </resources>
        """
        let keys = try parse(xml)
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].key, "visible")
    }

    func testPluralString() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <resources>
            <plurals name="items_count">
                <item quantity="one">%d item</item>
                <item quantity="other">%d items</item>
            </plurals>
        </resources>
        """
        let keys = try parse(xml)
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].key, "items_count")
        XCTAssertTrue(keys[0].isPlural)
        XCTAssertEqual(keys[0].pluralForms?[.one], "%d item")
        XCTAssertEqual(keys[0].pluralForms?[.other], "%d items")
        XCTAssertEqual(keys[0].baseText, "%d items")
    }

    func testStringEscaping() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <resources>
            <string name="apostrophe">don\\'t stop</string>
        </resources>
        """
        let keys = try parse(xml)
        XCTAssertEqual(keys[0].baseText, "don't stop")
    }

    func testFormatSpecifierExtraction() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <resources>
            <string name="welcome">Hello, %1$s! You have %2$d messages.</string>
        </resources>
        """
        let keys = try parse(xml)
        XCTAssertEqual(keys[0].placeholders.count, 2)
        XCTAssertEqual(keys[0].placeholders[0].format, "%1$s")
        XCTAssertEqual(keys[0].placeholders[0].order, 1)
        XCTAssertEqual(keys[0].placeholders[1].format, "%2$d")
        XCTAssertEqual(keys[0].placeholders[1].order, 2)
    }

    func testFindsOnlyDefaultValuesDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let valuesDir = tmp.appendingPathComponent("res/values")
        let esDir     = tmp.appendingPathComponent("res/values-es")
        try FileManager.default.createDirectory(at: valuesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: esDir,     withIntermediateDirectories: true)

        let defaultXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <resources><string name="key">Default</string></resources>
        """
        let esXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <resources><string name="key">Predeterminado</string></resources>
        """
        try defaultXML.write(to: valuesDir.appendingPathComponent("strings.xml"), atomically: true, encoding: .utf8)
        try esXML.write(to: esDir.appendingPathComponent("strings.xml"),           atomically: true, encoding: .utf8)

        let result = try extractor.extract(from: tmp)
        XCTAssertEqual(result.keys.count, 1)
        XCTAssertEqual(result.keys[0].baseText, "Default")
    }
}
