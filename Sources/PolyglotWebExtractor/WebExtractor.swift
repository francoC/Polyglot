//
//  WebExtractor.swift
//  PolyglotWebExtractor
//

import Foundation
import PolyglotCore

/// Extracts translatable strings from JavaScript/TypeScript source files.
/// Detects t("key"), i18n.t("key"), $t("key"), this.$t("key") call patterns.
public class WebExtractor {
    public init() {}

    /// Extract all strings from a directory, scanning JS/TS/JSX/TSX/Vue/Svelte files.
    public func extract(from directory: URL) throws -> ExtractedStrings {
        let files = findSourceFiles(in: directory)
        var allKeys: [StringKey] = []
        for url in files {
            allKeys.append(contentsOf: try extractFromFile(at: url))
        }
        var seen = Set<String>()
        let deduped = allKeys.filter { seen.insert($0.key).inserted }
        return ExtractedStrings(keys: deduped, platform: .web, extractedAt: Date())
    }

    /// Extract strings from a single source file.
    public func extractFromFile(at url: URL) throws -> [StringKey] {
        let source = try String(contentsOf: url, encoding: .utf8)
        return extractKeys(from: source, filePath: url.path)
    }

    // MARK: - Core extraction

    /// Extracts i18n keys from source text.
    /// Matches: t("key"), i18n.t("key"), $t("key"), this.$t("key")
    /// \bt ensures "t" is at a word boundary, so format(), getAttribute() etc. are skipped.
    func extractKeys(from source: String, filePath: String) -> [StringKey] {
        var keys: [StringKey] = []
        // \bt matches standalone t, t after ".", t after "$" — but NOT t inside longer words like "format"
        let pattern = #"\bt\s*\(\s*(?:"([^"\\]*(?:\\.[^"\\]*)*)"|'([^'\\]*(?:\\.[^'\\]*)*)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = source as NSString
        let lines = source.components(separatedBy: "\n")

        regex.enumerateMatches(in: source, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }

            // Group 1: double-quoted key, Group 2: single-quoted key
            let key: String
            if match.range(at: 1).location != NSNotFound {
                key = ns.substring(with: match.range(at: 1))
            } else if match.range(at: 2).location != NSNotFound {
                key = ns.substring(with: match.range(at: 2))
            } else { return }

            let unescaped = unescapeJS(key)
            guard !unescaped.isEmpty else { return }

            let position = match.range.location
            let line = lineNumber(for: position, in: source, lines: lines)
            let stringPos = StringPosition(
                startPosition: position,
                endPosition: position + match.range.length,
                lineNumber: line
            )

            let placeholders = extractPlaceholders(from: unescaped)
            keys.append(StringKey(
                key: unescaped,
                baseText: unescaped,
                platform: .web,
                filePath: filePath,
                positions: [stringPos],
                placeholders: placeholders
            ))
        }
        return keys
    }

    // MARK: - Placeholder extraction

    /// Extracts {{name}} (i18next) and {name} (next-intl/FormatJS) placeholders.
    func extractPlaceholders(from text: String) -> [Placeholder] {
        let ns = text as NSString

        // Try {{name}} first
        if let regex = try? NSRegularExpression(pattern: #"\{\{(\w+)\}\}"#) {
            var results: [Placeholder] = []
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match else { return }
                results.append(Placeholder(
                    format: ns.substring(with: match.range),
                    type: "string",
                    position: match.range.location
                ))
            }
            if !results.isEmpty { return results }
        }

        // Fall back to {name} — use negative lookahead/lookbehind to avoid matching inside {{}}
        if let regex = try? NSRegularExpression(pattern: #"(?<!\{)\{(\w+)\}(?!\})"#) {
            var results: [Placeholder] = []
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match else { return }
                results.append(Placeholder(
                    format: ns.substring(with: match.range),
                    type: "string",
                    position: match.range.location
                ))
            }
            return results
        }

        return []
    }

    // MARK: - File discovery

    /// Returns JS/TS/JSX/TSX/Vue/Svelte files, skipping build output and dependency directories.
    func findSourceFiles(in directory: URL) -> [URL] {
        let skipDirs: Set<String> = [
            "node_modules", ".next", "dist", "build", ".nuxt",
            ".output", "coverage", ".git", ".svelte-kit", "out", ".turbo"
        ]
        let extensions: Set<String> = ["js", "ts", "jsx", "tsx", "vue", "svelte"]
        var result: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        for case let url as URL in enumerator {
            if skipDirs.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard extensions.contains(url.pathExtension) else { continue }
            result.append(url)
        }
        return result
    }

    // MARK: - Helpers

    private func unescapeJS(_ s: String) -> String {
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            guard s[i] == "\\" else { result.append(s[i]); i = s.index(after: i); continue }
            let next = s.index(after: i)
            guard next < s.endIndex else { result.append("\\"); break }
            switch s[next] {
            case "'":  result.append("'");  i = s.index(after: next)
            case "\"": result.append("\""); i = s.index(after: next)
            case "\\": result.append("\\"); i = s.index(after: next)
            case "n":  result.append("\n"); i = s.index(after: next)
            case "t":  result.append("\t"); i = s.index(after: next)
            case "r":  result.append("\r"); i = s.index(after: next)
            case "0":  result.append("\0"); i = s.index(after: next)
            case "b":  result.append("\u{0008}"); i = s.index(after: next)
            case "f":  result.append("\u{000C}"); i = s.index(after: next)
            case "v":  result.append("\u{000B}"); i = s.index(after: next)
            case "x":
                // \xXX — exactly two hex digits
                let h1 = s.index(after: next)
                guard h1 < s.endIndex else { result.append("\\"); result.append(s[next]); i = s.index(after: next); break }
                let h2 = s.index(after: h1)
                guard h2 < s.endIndex else { result.append("\\"); result.append(s[next]); i = s.index(after: next); break }
                let hEnd = s.index(after: h2)
                if let scalar = UInt32(s[h1..<hEnd], radix: 16).flatMap(Unicode.Scalar.init) {
                    result.append(Character(scalar))
                    i = hEnd
                } else {
                    result.append("\\"); result.append(s[next]); i = s.index(after: next)
                }
            case "u":
                let afterU = s.index(after: next)
                if afterU < s.endIndex && s[afterU] == "{" {
                    // \u{XXXXX} — variable-length code point
                    if let closeIdx = s[afterU...].firstIndex(of: "}") {
                        let hexStart = s.index(after: afterU)
                        if let scalar = UInt32(s[hexStart..<closeIdx], radix: 16).flatMap(Unicode.Scalar.init) {
                            result.append(Character(scalar))
                            i = s.index(after: closeIdx)
                        } else {
                            result.append("\\"); result.append(s[next]); i = s.index(after: next)
                        }
                    } else {
                        result.append("\\"); result.append(s[next]); i = s.index(after: next)
                    }
                } else {
                    // \uXXXX — exactly four hex digits
                    let end = s.index(afterU, offsetBy: 4, limitedBy: s.endIndex) ?? s.endIndex
                    if s.distance(from: afterU, to: end) == 4,
                       let scalar = UInt32(s[afterU..<end], radix: 16).flatMap(Unicode.Scalar.init) {
                        result.append(Character(scalar))
                        i = end
                    } else {
                        result.append("\\"); result.append(s[next]); i = s.index(after: next)
                    }
                }
            default:
                result.append("\\"); result.append(s[next]); i = s.index(after: next)
            }
        }
        return result
    }

    private func lineNumber(for position: Int, in source: String, lines: [String]) -> Int {
        var offset = 0
        for (i, line) in lines.enumerated() {
            offset += line.utf8.count + 1 // +1 for newline
            if offset > position { return i + 1 }
        }
        return lines.count
    }
}
