//
//  PolyglotExtractorTests.swift
//  PolyglotExtractorTests
//

import XCTest
@testable import PolyglotExtractor
@testable import PolyglotCore

final class PolyglotExtractorTests: XCTestCase {

    func testExtractorInitialization() {
        XCTAssertNotNil(Extractor())
    }

    // MARK: - Helpers

    private func extractFromSource(_ source: String, fileName: String = "Test.swift") throws -> [StringKey] {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try source.write(to: tmpFile, atomically: true, encoding: .utf8)
        return try Extractor().extractFromFile(at: tmpFile, platform: .ios)
    }

    // MARK: - Pattern 1: String.localizedStringWithFormat(NSLocalizedString(...), count)

    func testPattern1LocalizedStringWithFormat() throws {
        let source = """
        import Foundation
        func f(count: Int) {
            let s = String.localizedStringWithFormat(NSLocalizedString("tasks.pending.count", comment: "Number of pending tasks"), count)
        }
        """
        let keys = try extractFromSource(source, fileName: "P1.swift")
        let match = keys.first { $0.key == "tasks.pending.count" }
        XCTAssertNotNil(match, "Expected key 'tasks.pending.count' to be extracted")
        XCTAssertTrue(match!.isPlural, "Expected isPlural=true for Pattern 1")
    }

    // MARK: - Pattern 2: String(format: NSLocalizedString(...), count)

    func testPattern2StringFormatNSLocalizedString() throws {
        let source = """
        import Foundation
        func f(count: Int) {
            let s = String(format: NSLocalizedString("items.selected", comment: "Number of selected items"), count)
        }
        """
        let keys = try extractFromSource(source, fileName: "P2.swift")
        let match = keys.first { $0.key == "items.selected" }
        XCTAssertNotNil(match, "Expected key 'items.selected' to be extracted")
        // Pattern 2 is a plain format string; plurals come from Pattern 1 / .stringsdict.
        XCTAssertFalse(match!.isPlural, "Expected isPlural=false for Pattern 2")
    }

    func testPattern2StringFormatWithLiteralIsNotPlural() throws {
        // String(format: "literal %@", arg) must NOT be marked plural
        let source = """
        import Foundation
        func f(name: String) {
            let s = String(format: "Welcome, %@!", name)
        }
        """
        let keys = try extractFromSource(source, fileName: "P2NonPlural.swift")
        XCTAssertFalse(
            keys.contains { $0.isPlural && $0.baseText.contains("Welcome") },
            "String(format: literal) should not be marked plural"
        )
    }

    // MARK: - Pattern 3: Text("^[\(count) noun](inflect: true)")

    func testPattern3InflectText() throws {
        let source = #"""
        import SwiftUI
        struct V: View {
            let count = 1
            var body: some View {
                Text("^[\(count) task](inflect: true)")
            }
        }
        """#
        let keys = try extractFromSource(source, fileName: "P3.swift")
        let match = keys.first { $0.isPlural && $0.baseText.contains("task") }
        XCTAssertNotNil(match, "Expected a plural key containing 'task' from inflect pattern")
    }

    // MARK: - Non-plural patterns are unaffected

    func testRegularTextCallIsNotPlural() throws {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View { Text("Hello World") }
        }
        """
        let keys = try extractFromSource(source, fileName: "NonPlural.swift")
        XCTAssertFalse(keys.contains { $0.isPlural })
    }
}
