//
//  AndroidGenerator.swift
//  PolyglotAndroidGenerator
//

import Foundation
import PolyglotCore

/// Generates Android string resource files (strings.xml) from translation entries.
public class AndroidGenerator {
    public init() {}

    /// Write per-locale strings.xml files under outputDirectory/res/values-{locale}/.
    public func generateBundle(from entries: [TranslationEntry], outputDirectory: URL) throws {
        // Collect all language codes present in the entries
        var languages = Set<String>()
        for entry in entries { languages.formUnion(entry.translations.keys) }

        let fm = FileManager.default
        for lang in languages.sorted() {
            let dirName = Self.androidResourceDirName(for: lang)
            let langDir = outputDirectory.appendingPathComponent(dirName)
            try fm.createDirectory(at: langDir, withIntermediateDirectories: true)

            let xml = try buildStringsXML(entries: entries, languageCode: lang)
            try xml.write(
                to: langDir.appendingPathComponent("strings.xml"),
                atomically: true, encoding: .utf8
            )
        }
    }

    // MARK: - XML generation

    func buildStringsXML(entries: [TranslationEntry], languageCode: String) throws -> String {
        var lines: [String] = [
            #"<?xml version="1.0" encoding="utf-8"?>"#,
            "<resources>"
        ]

        for entry in entries.sorted(by: { $0.key.key < $1.key.key }) {
            guard let translation = entry.translations[languageCode] else { continue }

            if entry.key.isPlural {
                lines.append(contentsOf: try buildPluralsElement(
                    name: entry.key.key,
                    translation: translation,
                    sourceKey: entry.key,
                    languageCode: languageCode
                ))
            } else {
                let denormalized = try StringKey.denormalize(text: translation.text, placeholders: entry.key.placeholders)
                let escaped = escapeAndroidString(denormalized)
                lines.append("    <string name=\"\(entry.key.key)\">\(escaped)</string>")
            }
        }

        lines.append("</resources>")
        return lines.joined(separator: "\n") + "\n"
    }

    private func buildPluralsElement(
        name: String,
        translation: Translation,
        sourceKey: StringKey,
        languageCode: String
    ) throws -> [String] {
        var lines = ["    <plurals name=\"\(name)\">"]
        let required = PluralCategory.requiredCategories(for: languageCode)

        for category in required {
            let rawText = translation.pluralForms?[category]
                ?? sourceKey.pluralForms?[category]
                ?? translation.text
            let text = try StringKey.denormalize(text: rawText, placeholders: sourceKey.placeholders)
            lines.append("        <item quantity=\"\(category.rawValue)\">\(escapeAndroidString(text))</item>")
        }

        lines.append("    </plurals>")
        return lines
    }

    // MARK: - String escaping

    /// Escape a string for inclusion in Android strings.xml.
    func escapeAndroidString(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\\", with: "\\\\")
        s = s.replacingOccurrences(of: "'",  with: "\\'")
        s = s.replacingOccurrences(of: "\"", with: "\\\"")
        s = s.replacingOccurrences(of: "\n", with: "\\n")
        s = s.replacingOccurrences(of: "\t", with: "\\t")
        s = s.replacingOccurrences(of: "&",  with: "&amp;")
        s = s.replacingOccurrences(of: "<",  with: "&lt;")
        return s
    }

    // MARK: - Locale directory naming

    /// Maps a BCP 47 language code to an Android resource directory name.
    /// - Simple language (es) → values-es
    /// - Language + region (pt-BR) → values-pt-rBR
    /// - Language + script (zh-Hans) → values-b+zh+Hans
    /// - Language + script + region (zh-Hant-TW) → values-b+zh+Hant+TW
    public static func androidResourceDirName(for languageCode: String) -> String {
        let parts = languageCode.split(separator: "-").map(String.init)
        switch parts.count {
        case 1:
            return "values-\(parts[0])"
        case 2:
            let lang = parts[0]
            let sub  = parts[1]
            // 4-char subtag = script (Hans, Hant, Latn…) → BCP 47 format
            if sub.count == 4 && sub.first?.isUppercase == true {
                return "values-b+\(lang)+\(sub)"
            }
            // 2-char uppercase = region → old format values-{lang}-r{REGION}
            return "values-\(lang)-r\(sub)"
        default:
            return "values-b+" + parts.joined(separator: "+")
        }
    }
}
