//
//  AndroidExtractor.swift
//  PolyglotAndroidExtractor
//

import Foundation
import PolyglotCore

/// Extracts translatable strings from Android string resource files (strings.xml).
public class AndroidExtractor {
    public init() {}

    /// Extract all strings from a directory, scanning for res/values/strings.xml files.
    public func extract(from directory: URL) throws -> ExtractedStrings {
        let files = findDefaultStringsFiles(in: directory)
        var allKeys: [StringKey] = []
        for url in files {
            allKeys.append(contentsOf: try extractFromFile(at: url))
        }
        // Deduplicate by key name (first occurrence wins)
        var seen = Set<String>()
        let deduped = allKeys.filter { seen.insert($0.key).inserted }
        return ExtractedStrings(keys: deduped, platform: .android, extractedAt: Date())
    }

    /// Extract strings from a single strings.xml file.
    public func extractFromFile(at url: URL) throws -> [StringKey] {
        let data = try Data(contentsOf: url)
        let doc = try XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever)
        guard let root = doc.rootElement(), root.name == "resources" else { return [] }

        var keys: [StringKey] = []
        for child in root.children ?? [] {
            guard let el = child as? XMLElement else { continue }
            switch el.name {
            case "string":
                if let k = parseStringElement(el, filePath: url.path) { keys.append(k) }
            case "plurals":
                if let k = parsePluralsElement(el, filePath: url.path) { keys.append(k) }
            default:
                break // skip string-array, declare-styleable, etc.
            }
        }
        return keys
    }

    // MARK: - Element parsers

    private func parseStringElement(_ el: XMLElement, filePath: String) -> StringKey? {
        guard el.attribute(forName: "translatable")?.stringValue != "false" else { return nil }
        guard let name = el.attribute(forName: "name")?.stringValue,
              let raw = el.stringValue, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let text = unescapeAndroidString(raw)
        // Skip placeholder extraction for strings marked formatted="false" (e.g. URLs, regexes)
        let isFormatted = el.attribute(forName: "formatted")?.stringValue != "false"
        let placeholders = isFormatted ? extractPlaceholders(from: text) : []
        return StringKey(
            key: name,
            baseText: text,
            platform: .android,
            filePath: filePath,
            placeholders: placeholders
        )
    }

    private func parsePluralsElement(_ el: XMLElement, filePath: String) -> StringKey? {
        guard el.attribute(forName: "translatable")?.stringValue != "false" else { return nil }
        guard let name = el.attribute(forName: "name")?.stringValue else { return nil }

        var forms: [PluralCategory: String] = [:]
        for child in el.children ?? [] {
            guard let item = child as? XMLElement,
                  item.name == "item",
                  let quantityStr = item.attribute(forName: "quantity")?.stringValue,
                  let category = PluralCategory(rawValue: quantityStr),
                  let raw = item.stringValue
            else { continue }
            forms[category] = unescapeAndroidString(raw)
        }
        guard !forms.isEmpty else { return nil }

        let baseText = forms[.other] ?? forms.values.first ?? ""
        let placeholders = extractPlaceholders(from: baseText)
        return StringKey(
            key: name,
            baseText: baseText,
            platform: .android,
            filePath: filePath,
            placeholders: placeholders,
            pluralForms: forms
        )
    }

    // MARK: - Placeholder extraction

    /// Extracts Android format specifiers: %1$s, %2$d, %s, %d, %f, etc.
    func extractPlaceholders(from text: String) -> [Placeholder] {
        var placeholders: [Placeholder] = []
        // Matches: %1$s, %2$d, %s, %d, %f, %e, %g, %x, %o, %a, %b, %c, %h, %n
        let pattern = #"%((\d+)\$)?([sdifeExXgGaAbchno])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = text as NSString
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let format = ns.substring(with: match.range)
            let position = match.range.location

            var order: Int? = nil
            if match.range(at: 2).location != NSNotFound {
                order = Int(ns.substring(with: match.range(at: 2)))
            }

            let typeChar = match.range(at: 3).location != NSNotFound
                ? ns.substring(with: match.range(at: 3))
                : ""
            let type: String
            switch typeChar {
            case "s", "b", "h": type = "string"
            case "d", "i", "o", "x", "X", "c": type = "integer"
            case "f", "e", "E", "g", "G", "a", "A": type = "float"
            default: type = "string"
            }

            placeholders.append(Placeholder(format: format, type: type, position: position, order: order))
        }
        return placeholders
    }

    // MARK: - String unescaping

    /// Unescape Android XML string escaping conventions.
    func unescapeAndroidString(_ raw: String) -> String {
        var s = raw
        // Order matters: unescape backslash sequences before XML entities
        s = s.replacingOccurrences(of: "\\'",  with: "'")
        s = s.replacingOccurrences(of: "\\\"", with: "\"")
        s = s.replacingOccurrences(of: "\\n",  with: "\n")
        s = s.replacingOccurrences(of: "\\t",  with: "\t")
        s = s.replacingOccurrences(of: "\\\\", with: "\\")
        return s
    }

    // MARK: - File discovery

    /// Returns all XML resource files in directories named exactly "values" (not "values-es" etc.)
    func findDefaultStringsFiles(in directory: URL) -> [URL] {
        var result: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        for case let url as URL in enumerator {
            guard url.pathExtension == "xml" else { continue }
            let parent = url.deletingLastPathComponent().lastPathComponent
            guard parent == "values" else { continue }
            result.append(url)
        }
        return result
    }
}
