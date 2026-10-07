//
//  WebGenerator.swift
//  PolyglotWebGenerator
//

import Foundation
import PolyglotCore

/// Generates flat JSON locale files (en.json, es.json, …) from translation entries.
/// Plural strings follow i18next convention: key_one, key_other, key_few, key_many, key_zero, key_two.
public class WebGenerator {
    public init() {}

    /// Write one JSON file per language into outputDirectory.
    public func generateBundle(from entries: [TranslationEntry], outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let langs = Set(entries.flatMap { $0.translations.keys }).sorted()
        for lang in langs {
            let content = try buildJSON(from: entries, language: lang)
            let fileURL = outputDirectory.appendingPathComponent("\(lang).json")
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - JSON builder

    /// Builds the JSON string for a single language. Keys are sorted for stable diffs.
    func buildJSON(from entries: [TranslationEntry], language: String) throws -> String {
        var pairs: [(key: String, value: String)] = []

        for entry in entries {
            guard let translation = entry.translations[language] else { continue }
            let baseKey = entry.key.key

            if entry.key.isPlural {
                // Use translation's pluralForms if available, fall back to source forms
                let forms = translation.pluralForms ?? entry.key.pluralForms ?? [:]
                // Emit categories in CLDR order for readability
                for category in PluralCategory.allCases {
                    if let text = forms[category] {
                        let denormalized = try StringKey.denormalize(text: text, placeholders: entry.key.placeholders)
                        pairs.append((key: "\(baseKey)_\(category.rawValue)", value: denormalized))
                    }
                }
            } else {
                let denormalized = try StringKey.denormalize(text: translation.text, placeholders: entry.key.placeholders)
                pairs.append((key: baseKey, value: denormalized))
            }
        }

        pairs.sort { $0.key < $1.key }

        var lines: [String] = ["{"]
        for (i, pair) in pairs.enumerated() {
            let comma = i < pairs.count - 1 ? "," : ""
            lines.append("  \(jsonString(pair.key)): \(jsonString(pair.value))\(comma)")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Returns the language codes that would be generated for this set of entries.
    public func languages(from entries: [TranslationEntry]) -> [String] {
        Set(entries.flatMap { $0.translations.keys }).sorted()
    }

    private func jsonString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
}
