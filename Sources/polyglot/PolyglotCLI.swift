//
//  PolyglotCLI.swift
//  polyglot
//

import Foundation
import ArgumentParser
import PolyglotCore
import PolyglotExtractor
import PolyglotGenerator
import PolyglotAndroidExtractor
import PolyglotAndroidGenerator
import PolyglotWebExtractor
import PolyglotWebGenerator

@main
struct PolyglotCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "polyglot",
        abstract: "Polyglot — multi-platform localization suite\n\nConfig file: searches .polyglot.json in the current directory, then ~/.polyglot.json. Override with --config.",
        subcommands: [Extract.self, Upload.self, Download.self, Generate.self, Sync.self, Check.self, Status.self]
    )
}

// MARK: - Extract

struct Extract: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "extract",
        abstract: "Extract translatable strings from Swift source code"
    )

    @Argument(help: "Path to source directory or single .swift file")
    var path: String

    @Option(name: .shortAndLong, help: "Platform (ios, android, web)")
    var platform: String = "ios"

    @Option(name: .shortAndLong, help: "Output file path (JSON); prints to stdout if omitted")
    var output: String?

    func run() async throws {
        let resolvedPlatform = platform.lowercased()
        guard Platform(rawValue: resolvedPlatform) != nil else {
            let valid = Platform.allCases.map { $0.rawValue }.joined(separator: ", ")
            throw ValidationError("Unknown platform '\(platform)'. Valid values: \(valid)")
        }
        let url = URL(fileURLWithPath: path)
        let extracted: ExtractedStrings
        switch resolvedPlatform {
        case "android":
            extracted = try AndroidExtractor().extract(from: url)
        case "web":
            extracted = try WebExtractor().extract(from: url)
        default:
            extracted = try Extractor().extract(from: url)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(extracted)

        if let outputPath = output {
            try data.write(to: URL(fileURLWithPath: outputPath))
            print("✅ Extracted \(extracted.keys.count) strings to \(outputPath)")
        } else if let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }
}

// MARK: - Upload

struct Upload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload extracted strings to the Polyglot CRM backend"
    )

    @Argument(help: "Path to extracted strings JSON file (output of 'extract')")
    var input: String

    @Option(name: .long, help: "Path to .polyglot.json config file (default: searches CWD then ~/.polyglot.json)")
    var config: String?

    @Option(name: .long, help: "Project ID (overrides config file)")
    var projectId: String?

    @Option(name: .long, help: "Backend API URL (overrides config file)")
    var apiURL: String?

    @Option(name: .long, help: "API key (overrides config file)")
    var apiKey: String?

    func run() async throws {
        let cfg = try resolveConfig(configPath: config, projectId: projectId, apiURL: apiURL, apiKey: apiKey)
        try validateProjectId(cfg.projectId)

        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let extracted = try decoder.decode(ExtractedStrings.self, from: data)

        print("Uploading \(extracted.keys.count) strings to project \(cfg.projectId)...")
        let response = try await apiUpload(extracted: extracted, config: cfg)
        print("✅ Upload complete — id: \(response.uploadId)")
        print("   New: \(response.stats.new)  Updated: \(response.stats.updated)  Unchanged: \(response.stats.unchanged)")
        if !response.keyMappings.isEmpty {
            print("   ⚠️  \(response.keyMappings.count) key(s) remapped by CRM — re-run 'extract' to sync")
        }
    }
}

// MARK: - Download

struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Download translations from the Polyglot CRM backend"
    )

    @Option(name: .long, help: "Path to .polyglot.json config file")
    var config: String?

    @Option(name: .long, help: "Project ID (overrides config file)")
    var projectId: String?

    @Option(name: .long, help: "Backend API URL (overrides config file)")
    var apiURL: String?

    @Option(name: .long, help: "API key (overrides config file)")
    var apiKey: String?

    @Option(name: .long, help: "Only download translations updated after this ISO8601 timestamp (incremental sync)")
    var since: String?

    @Option(name: .long, help: "Platform filter (ios, android, web); omit for all canonical keys")
    var platform: String?

    @Option(name: .shortAndLong, help: "Output file path for translations JSON")
    var output: String = "translations.json"

    func run() async throws {
        let cfg = try resolveConfig(configPath: config, projectId: projectId, apiURL: apiURL, apiKey: apiKey)
        try validateProjectId(cfg.projectId)
        try validateOutputPath(output, label: "--output")
        if let since {
            guard ISO8601DateFormatter().date(from: since) != nil else {
                throw ValidationError("'--since' value '\(since)' is not a valid ISO8601 timestamp (e.g. 2024-01-15T12:00:00Z)")
            }
        }
        let resolvedPlatform = platform?.lowercased() ?? cfg.platform

        print("Downloading translations for project \(cfg.projectId)...")
        let file = try await apiDownload(config: cfg, languages: nil, since: since, platform: resolvedPlatform)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        try data.write(to: URL(fileURLWithPath: output))

        let langList = Set(file.entries.flatMap { $0.translations.keys }).sorted().joined(separator: ", ")
        print("✅ Downloaded \(file.entries.count) entries [\(langList)] to \(output)")
    }
}

// MARK: - Generate

struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate .lproj bundles from extracted strings or a downloaded translations file"
    )

    @Argument(help: "Path to extracted strings JSON (output of 'extract') or translations JSON (output of 'download')")
    var input: String

    @Option(name: .shortAndLong, help: "Output directory for .lproj bundles")
    var output: String

    @Option(name: .long, help: "Comma-separated language codes (used only when input is ExtractedStrings; ignored for TranslationsFile)")
    var languages: String = "en"

    @Option(name: .shortAndLong, help: "Bundle version tag (optional)")
    var version: String?

    func run() async throws {
        try validateOutputPath(output, label: "--output")
        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let languageCodes = languages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Auto-detect format: TranslationsFile has "entries" key, ExtractedStrings has "keys" key.
        let entries: [TranslationEntry]
        do {
            let translationsFile = try decoder.decode(TranslationsFile.self, from: data)
            if !translationsFile.entries.isEmpty {
                entries = translationsFile.entries
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "no entries"))
            }
        } catch {
            let extracted = try decoder.decode(ExtractedStrings.self, from: data)
            entries = extracted.keys.map { key in
                var translations: [String: Translation] = [:]
                for lang in languageCodes {
                    translations[lang] = Translation(
                        languageCode: lang,
                        text: key.baseText,
                        approved: lang == "en",
                        pluralForms: lang == "en" ? key.pluralForms : nil
                    )
                }
                return TranslationEntry(key: key, translations: translations)
            }
        }

        let detectedPlatform = entries.first?.key.platform ?? .ios
        let outputURL = URL(fileURLWithPath: output)

        switch detectedPlatform {
        case .android:
            try AndroidGenerator().generateBundle(from: entries, outputDirectory: outputURL)
        case .web:
            try WebGenerator().generateBundle(from: entries, outputDirectory: outputURL)
        default:
            try Generator().generateBundle(from: entries, outputDirectory: outputURL, version: version)
        }

        let langs = Set(entries.flatMap { $0.translations.keys }).sorted().joined(separator: ", ")
        print("✅ Generated [\(langs)] bundles (\(entries.count) strings) at \(output)")
    }
}

// MARK: - Sync

struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Full pipeline: extract → upload → download → generate"
    )

    @Argument(help: "Path to source directory (overrides sourceDir in config)")
    var sourcePath: String?

    @Option(name: .long, help: "Path to .polyglot.json config file")
    var config: String?

    @Option(name: .long, help: "Project ID (overrides config file)")
    var projectId: String?

    @Option(name: .long, help: "Backend API URL (overrides config file)")
    var apiURL: String?

    @Option(name: .long, help: "API key (overrides config file)")
    var apiKey: String?

    @Option(name: .shortAndLong, help: "Platform (ios, android, web); overrides config file")
    var platform: String?

    @Option(name: .shortAndLong, help: "Output directory for generated files (overrides outputDir in config)")
    var output: String?

    @Flag(name: .long, help: "Skip waiting for translations and download immediately after upload")
    var noWait: Bool = false

    @Option(name: .long, help: "Maximum seconds to wait for translations (overrides config; default: 3600). Pass 0 for no limit.")
    var timeout: Int?

    func run() async throws {
        let cfg = try resolveConfig(configPath: config, projectId: projectId, apiURL: apiURL, apiKey: apiKey)
        try validateProjectId(cfg.projectId)
        let resolvedPlatform = platform?.lowercased() ?? cfg.platform ?? "ios"
        guard Platform(rawValue: resolvedPlatform) != nil else {
            let valid = Platform.allCases.map { $0.rawValue }.joined(separator: ", ")
            throw ValidationError("Unknown platform '\(resolvedPlatform)'. Valid values: \(valid)")
        }

        guard let resolvedSource = sourcePath ?? cfg.sourceDir else {
            throw ValidationError("Provide a source directory as an argument or set sourceDir in .polyglot.json")
        }
        let resolvedOutput = output ?? cfg.outputDir ?? "./Localizations"
        try validateOutputPath(resolvedOutput, label: "--output / outputDir")
        let sourceURL = URL(fileURLWithPath: resolvedSource)

        // 1. Extract
        print("1/4 Extracting strings from \(resolvedSource)...")
        let extracted: ExtractedStrings
        switch resolvedPlatform {
        case "android": extracted = try AndroidExtractor().extract(from: sourceURL)
        case "web":     extracted = try WebExtractor().extract(from: sourceURL)
        default:        extracted = try Extractor().extract(from: sourceURL)
        }
        print("    Found \(extracted.keys.count) strings")

        // 2. Upload
        print("2/4 Uploading to project \(cfg.projectId)...")
        let uploadResponse = try await apiUpload(extracted: extracted, config: cfg)
        print("    New: \(uploadResponse.stats.new)  Updated: \(uploadResponse.stats.updated)  Unchanged: \(uploadResponse.stats.unchanged)")

        // 2b. Wait for translations if requested
        if !noWait && (uploadResponse.stats.new + uploadResponse.stats.updated) > 0 {
            print("⏳ Waiting for translations to complete...")
            let resolvedTimeout = timeout ?? cfg.syncTimeout ?? 3600
            let deadline: Date? = resolvedTimeout > 0 ? Date().addingTimeInterval(TimeInterval(resolvedTimeout)) : nil
            let timeoutLabel = resolvedTimeout > 0 ? "\(resolvedTimeout)s" : "unlimited"
            while true {
                do {
                    let status = try await apiStatus(config: cfg, languages: nil, platform: resolvedPlatform)
                    if status.pending == 0 {
                        print("   ✓ All translations ready")
                        break
                    }
                    if let deadline, Date() >= deadline {
                        print("   ⚠️  Translation timeout after \(timeoutLabel) — downloading what's ready")
                        break
                    }
                    print("   \(status.pending) translation(s) pending — checking again in 5s...")
                } catch {
                    if let deadline, Date() >= deadline {
                        print("   ⚠️  Status check failed, timeout reached — downloading what's ready")
                        break
                    }
                    print("   ⚠️  Status check failed (\(error.localizedDescription)) — retrying in 5s...")
                }
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }

        // 3. Download
        print("3/4 Downloading translations...")
        let translationsFile = try await apiDownload(config: cfg, languages: nil, platform: resolvedPlatform)
        print("    Downloaded \(translationsFile.entries.count) entries")

        // 4. Generate
        print("4/4 Generating bundles at \(resolvedOutput)...")
        let outputURL = URL(fileURLWithPath: resolvedOutput)
        switch resolvedPlatform {
        case "android": try AndroidGenerator().generateBundle(from: translationsFile.entries, outputDirectory: outputURL)
        case "web":     try WebGenerator().generateBundle(from: translationsFile.entries, outputDirectory: outputURL)
        default:        try Generator().generateBundle(from: translationsFile.entries, outputDirectory: outputURL)
        }
        print("✅ Sync complete")
    }
}

// MARK: - Check

struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check for translation issues: missing keys, placeholder mismatches, unapproved translations"
    )

    @Argument(help: "Path to extracted strings JSON file (output of 'extract')")
    var extracted: String

    @Option(name: .long, help: "Path to translations JSON file (output of 'download')")
    var translations: String?

    @Option(name: .long, help: "Path to generated .lproj bundle directory")
    var bundleDir: String?

    @Flag(help: "Exit non-zero on warnings (UNAPPROVED, ORPHAN) in addition to errors")
    var strict: Bool = false

    func run() async throws {
        guard translations != nil || bundleDir != nil else {
            print("❌ Provide --translations <file> and/or --bundle-dir <dir>")
            throw ExitCode.failure
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let extractedData = try Data(contentsOf: URL(fileURLWithPath: extracted))
        let extractedStrings = try decoder.decode(ExtractedStrings.self, from: extractedData)
        let extractedByKey = Dictionary(uniqueKeysWithValues: extractedStrings.keys.map { ($0.key, $0) })

        var allIssues: [CheckIssue] = []

        // — Translations-file mode —
        if let translationsPath = translations {
            let tData = try Data(contentsOf: URL(fileURLWithPath: translationsPath))
            let tDecoder = JSONDecoder()
            tDecoder.dateDecodingStrategy = .iso8601
            let file = try tDecoder.decode(TranslationsFile.self, from: tData)

            var langs = Set<String>()
            for entry in file.entries { langs.formUnion(entry.translations.keys) }
            let requestedLangs = langs.sorted()

            for lang in requestedLangs {
                allIssues.append(contentsOf: checkAgainstTranslationsFile(
                    lang: lang, extractedByKey: extractedByKey, file: file
                ))
            }
        }

        // — Bundle-dir mode —
        if let bundleDirPath = bundleDir {
            allIssues.append(contentsOf: try checkAgainstBundleDir(
                bundleDirURL: URL(fileURLWithPath: bundleDirPath),
                extractedByKey: extractedByKey,
                requestedLangs: nil
            ))
        }

        // — Report —
        let errors   = allIssues.filter { $0.severity == .error }
        let warnings = allIssues.filter { $0.severity == .warning }

        if allIssues.isEmpty {
            print("✅ No issues found")
            return
        }

        if !errors.isEmpty {
            print("\nERRORS (\(errors.count)):")
            for issue in errors.sorted(by: { $0.formatted < $1.formatted }) {
                print("  \(issue.formatted)")
            }
        }
        if !warnings.isEmpty {
            print("\nWARNINGS (\(warnings.count)):")
            for issue in warnings.sorted(by: { $0.formatted < $1.formatted }) {
                print("  \(issue.formatted)")
            }
        }

        let summary = "\(errors.count) error(s), \(warnings.count) warning(s)"
        if !errors.isEmpty || (strict && !warnings.isEmpty) {
            print("\n❌ \(summary) — check failed")
            throw ExitCode.failure
        } else {
            print("\n⚠️  \(summary)")
        }
    }

    // MARK: Translations-file mode

    private func checkAgainstTranslationsFile(
        lang: String,
        extractedByKey: [String: StringKey],
        file: TranslationsFile
    ) -> [CheckIssue] {
        var issues: [CheckIssue] = []

        let byKey: [String: (StringKey, Translation)] = Dictionary(
            uniqueKeysWithValues: file.entries.compactMap { entry -> (String, (StringKey, Translation))? in
                guard let t = entry.translations[lang] else { return nil }
                return (entry.key.key, (entry.key, t))
            }
        )

        for (key, extractedKey) in extractedByKey {
            guard let (_, translation) = byKey[key] else {
                issues.append(CheckIssue(.error, .missing, lang, key))
                continue
            }

            if !translation.approved {
                issues.append(CheckIssue(.warning, .unapproved, lang, key))
            }

            // Placeholder comparison (skip plural keys — their placeholders are in pluralForms)
            if !extractedKey.isPlural {
                let sourceFormats = extractedKey.placeholders.map { $0.format }.sorted()
                let (_, translationPlaceholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: translation.text)
                let translationFormats = translationPlaceholders.map { $0.format }.sorted()
                if sourceFormats != translationFormats {
                    issues.append(CheckIssue(.error, .placeholderMismatch(
                        expected: sourceFormats.isEmpty ? "(none)" : sourceFormats.joined(separator: " "),
                        got: translationFormats.isEmpty ? "(none)" : translationFormats.joined(separator: " ")
                    ), lang, key))
                }
            }

            // Plural forms coverage
            if extractedKey.isPlural {
                let required = Set(PluralCategory.requiredCategories(for: lang))
                let provided: Set<PluralCategory> = translation.pluralForms.map { Set($0.keys) } ?? []
                let missing = required.subtracting(provided)
                if !missing.isEmpty {
                    let sorted = missing.map { $0.rawValue }.sorted()
                    issues.append(CheckIssue(.error, .missingPluralForms(sorted), lang, key))
                }
            }
        }

        // Orphan check
        for entry in file.entries {
            if entry.translations[lang] != nil && extractedByKey[entry.key.key] == nil {
                issues.append(CheckIssue(.warning, .orphan, lang, entry.key.key))
            }
        }

        return issues
    }

    // MARK: Bundle-dir mode

    private func checkAgainstBundleDir(
        bundleDirURL: URL,
        extractedByKey: [String: StringKey],
        requestedLangs: [String]?
    ) throws -> [CheckIssue] {
        var issues: [CheckIssue] = []
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: bundleDirURL, includingPropertiesForKeys: nil) else {
            return []
        }

        // iOS: directories end in .lproj  (en.lproj, es.lproj, …)
        let lprojDirs = contents.filter { $0.pathExtension == "lproj" }
        // Android: directories start with "values-"  (values-en, values-es, values-b+zh+Hans, …)
        let valuesDirs = contents.filter { $0.lastPathComponent.hasPrefix("values-") }

        // Web: {lang}.json files directly in the bundle dir (en.json, es.json, zh-Hans.json, …)
        let jsonFiles = contents.filter { $0.pathExtension == "json" && $0.lastPathComponent != "package.json" }
        let webLangFiles = jsonFiles.filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            // Accept names that look like BCP 47 codes: 2-3 alpha chars, optionally with -region/-script
            return name.range(of: #"^[a-z]{2,3}(-[A-Za-z]{2,4}){0,4}$"#, options: .regularExpression) != nil
        }

        if !webLangFiles.isEmpty {
            for jsonFile in webLangFiles {
                let lang = jsonFile.deletingPathExtension().lastPathComponent
                if let requested = requestedLangs, !requested.contains(lang) { continue }
                var bundleKeys = Set<String>()
                if let data = try? Data(contentsOf: jsonFile),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Strip i18next plural suffixes (_one, _other, etc.) to recover base key
                    let pluralSuffixes = PluralCategory.allCases.map { "_\($0.rawValue)" }
                    for rawKey in dict.keys {
                        var base = rawKey
                        for suffix in pluralSuffixes where rawKey.hasSuffix(suffix) {
                            base = String(rawKey.dropLast(suffix.count))
                            break
                        }
                        bundleKeys.insert(base)
                    }
                }
                issues.append(contentsOf: diffBundleKeys(bundleKeys, against: extractedByKey, lang: lang))
            }
        } else if !lprojDirs.isEmpty {
            for lprojDir in lprojDirs {
                let lang = lprojDir.deletingPathExtension().lastPathComponent
                if let requested = requestedLangs, !requested.contains(lang) { continue }
                var bundleKeys = Set<String>()
                let stringsURL = lprojDir.appendingPathComponent("Localizable.strings")
                if fm.fileExists(atPath: stringsURL.path),
                   let content = try? String(contentsOf: stringsURL, encoding: .utf8) {
                    bundleKeys.formUnion(parseStringsFileKeys(content))
                }
                let stringsdictURL = lprojDir.appendingPathComponent("Localizable.stringsdict")
                if fm.fileExists(atPath: stringsdictURL.path),
                   let data = try? Data(contentsOf: stringsdictURL) {
                    bundleKeys.formUnion(parseStringsDictKeys(data))
                }
                issues.append(contentsOf: diffBundleKeys(bundleKeys, against: extractedByKey, lang: lang))
            }
        } else if !valuesDirs.isEmpty {
            for valuesDir in valuesDirs {
                let dirName = valuesDir.lastPathComponent          // "values-es", "values-b+zh+Hans"
                let lang = bcp47FromAndroidDirName(dirName)
                if let requested = requestedLangs, !requested.contains(lang) { continue }
                var bundleKeys = Set<String>()
                // Collect keys from all XML files in this locale directory
                if let xmlFiles = try? fm.contentsOfDirectory(at: valuesDir, includingPropertiesForKeys: nil) {
                    for xmlURL in xmlFiles where xmlURL.pathExtension == "xml" {
                        if let content = try? String(contentsOf: xmlURL, encoding: .utf8) {
                            bundleKeys.formUnion(parseAndroidStringsFileKeys(content))
                        }
                    }
                }
                issues.append(contentsOf: diffBundleKeys(bundleKeys, against: extractedByKey, lang: lang))
            }
        }

        return issues
    }

    private func diffBundleKeys(
        _ bundleKeys: Set<String>,
        against extractedByKey: [String: StringKey],
        lang: String
    ) -> [CheckIssue] {
        var issues: [CheckIssue] = []
        for key in extractedByKey.keys where !bundleKeys.contains(key) {
            issues.append(CheckIssue(.error, .keyNotInBundle, lang, key))
        }
        for key in bundleKeys where extractedByKey[key] == nil {
            issues.append(CheckIssue(.warning, .orphanInBundle, lang, key))
        }
        return issues
    }

    /// Reverses AndroidGenerator.androidResourceDirName: "values-es" → "es", "values-b+zh+Hans" → "zh-Hans"
    private func bcp47FromAndroidDirName(_ dirName: String) -> String {
        let suffix = String(dirName.dropFirst("values-".count))  // "es", "pt-rBR", "b+zh+Hans"
        if suffix.hasPrefix("b+") {
            return String(suffix.dropFirst(2)).replacingOccurrences(of: "+", with: "-")
        }
        // "pt-rBR" → "pt-BR"
        if let rRange = suffix.range(of: "-r") {
            return suffix.replacingCharacters(in: rRange, with: "-")
        }
        return suffix
    }

    /// Parse keys from an Android strings.xml (or any resource XML with <string name="…"> elements).
    private func parseAndroidStringsFileKeys(_ content: String) -> Set<String> {
        var keys = Set<String>()
        // Match name= attribute in <string> and <plurals> elements
        let pattern = #"<(?:string|plurals)\s[^>]*name="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return keys }
        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: content) else { return }
            keys.insert(String(content[r]))
        }
        return keys
    }

    private func parseStringsFileKeys(_ content: String) -> Set<String> {
        var keys = Set<String>()
        let pattern = "^\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*="
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return keys }
        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: content) else { return }
            keys.insert(String(content[r]))
        }
        return keys
    }

    private func parseStringsDictKeys(_ data: Data) -> Set<String> {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else { return [] }
        return Set(dict.keys)
    }
}

// MARK: - CheckIssue

private struct CheckIssue {
    enum Severity { case error, warning }
    enum Kind {
        case missing
        case orphan
        case unapproved
        case placeholderMismatch(expected: String, got: String)
        case missingPluralForms([String])
        case keyNotInBundle
        case orphanInBundle
    }

    let severity: Severity
    let kind: Kind
    let language: String
    let key: String

    init(_ severity: Severity, _ kind: Kind, _ language: String, _ key: String) {
        self.severity = severity
        self.kind = kind
        self.language = language
        self.key = key
    }

    var formatted: String {
        let tag: String
        let detail: String
        switch kind {
        case .missing:
            tag = "MISSING"; detail = "no translation"
        case .orphan:
            tag = "ORPHAN"; detail = "not in extracted strings"
        case .unapproved:
            tag = "UNAPPROVED"; detail = "not approved"
        case .placeholderMismatch(let expected, let got):
            tag = "PLACEHOLDER_MISMATCH"; detail = "expected [\(expected)] got [\(got)]"
        case .missingPluralForms(let cats):
            tag = "MISSING_PLURAL_FORMS"; detail = "missing: \(cats.joined(separator: ", "))"
        case .keyNotInBundle:
            tag = "KEY_NOT_IN_BUNDLE"; detail = "not in Localizable.strings/.stringsdict"
        case .orphanInBundle:
            tag = "ORPHAN_IN_BUNDLE"; detail = "in bundle but not in extracted strings"
        }
        return "[\(language)] \(tag): \"\(key)\" — \(detail)"
    }
}

// MARK: - Status

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check how many translations are still pending for a project"
    )

    @Option(name: .long, help: "Path to .polyglot.json config file")
    var config: String?

    @Option(name: .long, help: "Project ID (overrides config file)")
    var projectId: String?

    @Option(name: .long, help: "Backend API URL (overrides config file)")
    var apiURL: String?

    @Option(name: .long, help: "API key (overrides config file)")
    var apiKey: String?

    @Option(name: .shortAndLong, help: "Platform filter (ios, android, web)")
    var platform: String?

    func run() async throws {
        let cfg = try resolveConfig(configPath: config, projectId: projectId, apiURL: apiURL, apiKey: apiKey)
        try validateProjectId(cfg.projectId)
        let resolvedPlatform = platform?.lowercased() ?? cfg.platform

        let status = try await apiStatus(config: cfg, languages: nil, platform: resolvedPlatform)
        if status.pending == 0 {
            print("✅ All translations complete (\(status.totalKeys) strings)")
        } else {
            print("⏳ \(status.pending) translation(s) pending (\(status.totalKeys) total strings)")
        }
    }
}

// MARK: - Config Resolution

private func resolveConfig(
    configPath: String?,
    projectId: String?,
    apiURL: String?,
    apiKey: String?
) throws -> PolyglotConfig {
    // Priority: CLI flags → environment variables → config file
    let env = ProcessInfo.processInfo.environment
    let resolvedURL = apiURL     ?? env["POLYGLOT_API_URL"]
    let resolvedKey = apiKey     ?? env["POLYGLOT_API_KEY"]
    let resolvedPID = projectId  ?? env["POLYGLOT_PROJECT_ID"]

    if let url = resolvedURL, let key = resolvedKey, let pid = resolvedPID {
        return PolyglotConfig(apiURL: url, apiKey: key, projectId: pid)
    }
    var cfg = try PolyglotConfig.load(from: configPath)
    if let url = resolvedURL { cfg = PolyglotConfig(apiURL: url,        apiKey: cfg.apiKey, projectId: cfg.projectId, platform: cfg.platform, sourceDir: cfg.sourceDir, outputDir: cfg.outputDir) }
    if let key = resolvedKey { cfg = PolyglotConfig(apiURL: cfg.apiURL, apiKey: key,        projectId: cfg.projectId, platform: cfg.platform, sourceDir: cfg.sourceDir, outputDir: cfg.outputDir) }
    if let pid = resolvedPID { cfg = PolyglotConfig(apiURL: cfg.apiURL, apiKey: cfg.apiKey, projectId: pid,           platform: cfg.platform, sourceDir: cfg.sourceDir, outputDir: cfg.outputDir) }
    return cfg
}

// MARK: - Path / ID Validation

private func validateProjectId(_ projectId: String) throws {
    guard projectId.range(of: #"^[a-zA-Z0-9_\-]{1,64}$"#, options: .regularExpression) != nil else {
        throw ValidationError("Invalid project ID '\(projectId)': use only letters, digits, hyphens, and underscores (max 64 chars)")
    }
}

private func validateOutputPath(_ path: String, label: String) throws {
    let url = URL(fileURLWithPath: path).standardized
    guard !url.pathComponents.contains("..") else {
        throw ValidationError("'\(label)' contains path traversal ('..') — use an absolute path instead")
    }
    // For relative paths, reject symlinks that resolve outside CWD.
    if !path.hasPrefix("/") {
        let resolved = url.resolvingSymlinksInPath().path
        let cwd = FileManager.default.currentDirectoryPath
        guard resolved.hasPrefix(cwd) else {
            throw ValidationError("'\(label)' resolves outside the current directory via a symlink — rejected")
        }
    }
}

// MARK: - HTTP Helpers

private func apiUpload(extracted: ExtractedStrings, config: PolyglotConfig) async throws -> UploadResponse {
    let encodedPID = config.projectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.projectId
    guard let url = URL(string: "\(config.apiURL)/v1/projects/\(encodedPID)/strings") else {
        throw PolyglotError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(config.apiKey, forHTTPHeaderField: "X-Polyglot-API-Key")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let withProjectId = ExtractedStrings(
        keys: extracted.keys,
        platform: extracted.platform,
        extractedAt: extracted.extractedAt,
        projectId: config.projectId
    )
    request.httpBody = try encoder.encode(withProjectId)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw PolyglotError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
        let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw PolyglotError.apiError(statusCode: http.statusCode, message: msg)
    }
    return try JSONDecoder().decode(UploadResponse.self, from: data)
}

private struct TranslationStatus: Decodable {
    let totalKeys: Int
    let pending: Int
}

private func apiStatus(config: PolyglotConfig, languages: [String]?, platform: String? = nil) async throws -> TranslationStatus {
    let encodedPID = config.projectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.projectId
    var components = URLComponents(string: "\(config.apiURL)/v1/projects/\(encodedPID)/status")
    var queryItems: [URLQueryItem] = []
    if let languages, !languages.isEmpty {
        queryItems.append(URLQueryItem(name: "languages", value: languages.joined(separator: ",")))
    }
    if let platform {
        queryItems.append(URLQueryItem(name: "platform", value: platform))
    }
    if !queryItems.isEmpty {
        components?.queryItems = queryItems
    }
    guard let url = components?.url else { throw PolyglotError.invalidResponse }
    var request = URLRequest(url: url)
    request.setValue(config.apiKey, forHTTPHeaderField: "X-Polyglot-API-Key")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw PolyglotError.invalidResponse
    }
    return try JSONDecoder().decode(TranslationStatus.self, from: data)
}

private func apiDownload(config: PolyglotConfig, languages: [String]?, since: String? = nil, platform: String? = nil) async throws -> TranslationsFile {
    let encodedPID = config.projectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.projectId
    var components = URLComponents(string: "\(config.apiURL)/v1/projects/\(encodedPID)/translations")
    var queryItems: [URLQueryItem] = []
    if let langs = languages, !langs.isEmpty {
        queryItems.append(URLQueryItem(name: "languages", value: langs.joined(separator: ",")))
    }
    if let since {
        queryItems.append(URLQueryItem(name: "since", value: since))
    }
    if let platform {
        queryItems.append(URLQueryItem(name: "platform", value: platform))
    }
    if !queryItems.isEmpty {
        components?.queryItems = queryItems
    }
    guard let url = components?.url else { throw PolyglotError.invalidResponse }

    var request = URLRequest(url: url)
    request.setValue(config.apiKey, forHTTPHeaderField: "X-Polyglot-API-Key")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw PolyglotError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
        let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw PolyglotError.apiError(statusCode: http.statusCode, message: msg)
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(TranslationsFile.self, from: data)
}
