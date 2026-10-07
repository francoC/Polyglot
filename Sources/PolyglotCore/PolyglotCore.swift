//
//  PolyglotCore.swift
//  PolyglotCore
//
//  Shared models, protocols, and utilities for the Polyglot localization system.
//

import Foundation

// MARK: - Core Models

/// CLDR plural categories as defined by Unicode Common Locale Data Repository.
/// https://unicode.org/reports/tr35/tr35-numbers.html#Language_Plural_Rules
public enum PluralCategory: String, Codable, CaseIterable, Hashable, CodingKey {
    case zero
    case one
    case two
    case few
    case many
    case other

    // CodingKey — lets JSONEncoder use the rawValue as a JSON object key
    public var stringValue: String { rawValue }
    public init?(stringValue: String) { self.init(rawValue: stringValue) }
    public var intValue: Int? { nil }
    public init?(intValue: Int) { nil }
}

extension PluralCategory {
    /// Returns the CLDR plural categories required for a given BCP 47 language code.
    /// Falls back to base tag, then to [.one, .other] as default.
    public static func requiredCategories(for languageCode: String) -> [PluralCategory] {
        if let cats = cldrTable[languageCode] { return cats }
        let base = String(languageCode.prefix(while: { $0 != "-" }))
        if base != languageCode, let cats = cldrTable[base] { return cats }
        return [.one, .other]
    }

    private static let cldrTable: [String: [PluralCategory]] = [
        "ar": [.zero, .one, .two, .few, .many, .other],
        "he": [.one, .two, .many, .other],
        "ru": [.one, .few, .many, .other],
        "uk": [.one, .few, .many, .other],
        "be": [.one, .few, .many, .other],
        "pl": [.one, .few, .many, .other],
        "cs": [.one, .few, .many, .other],
        "sk": [.one, .few, .many, .other],
        "hr": [.one, .few, .many, .other],
        "sr": [.one, .few, .many, .other],
        "zh": [.other],
        "zh-Hans": [.other],
        "zh-Hant": [.other],
        "ja": [.other],
        "ko": [.other],
        "th": [.other],
        "vi": [.other],
        "tr": [.other],
        "id": [.other],
        "lo": [.other],
        "my": [.other],
    ]
}

/// Position information for a string occurrence in source code
public struct StringPosition: Codable, Equatable, Hashable {
    public let startPosition: Int
    public let endPosition: Int
    public let lineNumber: Int

    public init(startPosition: Int, endPosition: Int, lineNumber: Int) {
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.lineNumber = lineNumber
    }
}

/// Represents a translatable string key with its context
public struct StringKey: Codable, Equatable, Hashable {
    /// The localization key (e.g., "auth.login.title")
    public let key: String

    /// The base English text
    public let baseText: String

    /// The platform this string belongs to
    public let platform: Platform

    /// File path where the string was found
    public let filePath: String

    /// All positions where this string appears in the source file
    public let positions: [StringPosition]

    /// Variable placeholders found in the string (e.g., "%@", "{userName}")
    public let placeholders: [Placeholder]

    /// Source-language plural forms keyed by CLDR category.
    /// nil = not a plural string. Non-nil (including empty dict) = plural string;
    /// the dict holds known source forms (e.g. [.one: "%d item", .other: "%d items"]).
    public let pluralForms: [PluralCategory: String]?

    /// True when this key represents a plural string.
    public var isPlural: Bool { pluralForms != nil }

    /// Usage context (e.g., "LoginScreen", "SettingsView")
    public let context: String?

    /// Hint for translators (from // Polyglot: comments)
    public let hint: String?

    public init(
        key: String,
        baseText: String,
        platform: Platform,
        filePath: String,
        positions: [StringPosition] = [],
        placeholders: [Placeholder] = [],
        pluralForms: [PluralCategory: String]? = nil,
        context: String? = nil,
        hint: String? = nil
    ) {
        self.key = key
        self.baseText = baseText
        self.platform = platform
        self.filePath = filePath
        self.positions = positions
        self.placeholders = placeholders
        self.pluralForms = pluralForms
        self.context = context
        self.hint = hint
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key,          forKey: .key)
        try c.encode(baseText,     forKey: .baseText)
        try c.encode(platform,     forKey: .platform)
        try c.encode(filePath,     forKey: .filePath)
        try c.encode(positions,    forKey: .positions)
        try c.encode(placeholders, forKey: .placeholders)
        if let forms = pluralForms {
            var fc = c.nestedContainer(keyedBy: PluralCategory.self, forKey: .pluralForms)
            for (cat, text) in forms { try fc.encode(text, forKey: cat) }
        }
        try c.encodeIfPresent(context, forKey: .context)
        try c.encodeIfPresent(hint,    forKey: .hint)
    }

    // Decodes both new object format {"one":"…"} and legacy array format ["one","…"]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key          = try c.decode(String.self,          forKey: .key)
        baseText     = try c.decode(String.self,          forKey: .baseText)
        platform     = try c.decode(Platform.self,        forKey: .platform)
        filePath     = try c.decode(String.self,          forKey: .filePath)
        positions    = try c.decodeIfPresent([StringPosition].self, forKey: .positions)    ?? []
        placeholders = try c.decodeIfPresent([Placeholder].self,    forKey: .placeholders) ?? []
        context      = try c.decodeIfPresent(String.self, forKey: .context)
        hint         = try c.decodeIfPresent(String.self, forKey: .hint)
        // Legacy "isPlural" key is intentionally ignored — pluralForms != nil serves that role.
        if c.contains(.pluralForms) {
            // Try new object format first, fall back to legacy array encoding
            if let fc = try? c.nestedContainer(keyedBy: PluralCategory.self, forKey: .pluralForms) {
                var forms: [PluralCategory: String] = [:]
                for cat in fc.allKeys { forms[cat] = try fc.decode(String.self, forKey: cat) }
                pluralForms = forms
            } else {
                pluralForms = try c.decodeIfPresent([PluralCategory: String].self, forKey: .pluralForms)
            }
        } else {
            pluralForms = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case key, baseText, platform, filePath, positions, placeholders, pluralForms, context, hint
    }
}

// MARK: - Placeholder Normalization

extension StringKey {
    /// Replaces platform-native placeholder tokens with positional {0}, {1}, … markers.
    /// Processes right-to-left so earlier character offsets stay valid during replacement.
    public static func normalize(text: String, placeholders: [Placeholder]) -> String {
        guard !placeholders.isEmpty else { return text }
        // Sort left-to-right: index 0 = leftmost. Each placeholder gets its own
        // sequential index so two "%@" tokens become {0} and {1}, not both {0}.
        let sorted = placeholders.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        var result = text
        // Process right-to-left so replacing a token at offset N doesn't shift
        // the character offsets of unprocessed tokens to the left.
        for (idx, placeholder) in sorted.enumerated().reversed() {
            let token = "{\(idx)}"
            if let pos = placeholder.position,
               let startIdx = result.index(result.startIndex, offsetBy: pos, limitedBy: result.endIndex),
               let range = result.range(of: placeholder.format, range: startIdx..<result.endIndex) {
                result.replaceSubrange(range, with: token)
            } else if let range = result.range(of: placeholder.format) {
                result.replaceSubrange(range, with: token)
            }
        }
        return result
    }

    /// Replaces positional {0}, {1}, … markers back to platform-native placeholder tokens.
    /// No-op when placeholders is empty (safe for plain strings).
    /// Throws `StringKeyError.unreplacedPlaceholders` if any `{N}` tokens survive substitution,
    /// which means the translation dropped or added a placeholder — visible in CI as a hard failure.
    public static func denormalize(text: String, placeholders: [Placeholder]) throws -> String {
        guard !placeholders.isEmpty else { return text }
        var result = text
        let ordered = placeholders.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        for (idx, placeholder) in ordered.enumerated() {
            result = result.replacingOccurrences(of: "{\(idx)}", with: placeholder.format)
        }
        if result.range(of: #"\{\d+\}"#, options: .regularExpression) != nil {
            throw StringKeyError.unreplacedPlaceholders(result)
        }
        return result
    }
}

public enum StringKeyError: Error, CustomStringConvertible {
    case unreplacedPlaceholders(String)
    public var description: String {
        switch self {
        case .unreplacedPlaceholders(let text):
            return "denormalize: unreplaced placeholder token(s) remain in '\(text)'"
        }
    }
}

/// Supported platforms for localization
public enum Platform: String, Codable, CaseIterable {
    case ios
    case android
    case web

    public var displayName: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        case .web: return "Web"
        }
    }
}

/// Variable placeholder type and position
public struct Placeholder: Codable, Equatable, Hashable {
    public let format: String
    public let type: String?
    public let position: Int?
    public let order: Int?

    public init(format: String, type: String? = nil, position: Int? = nil, order: Int? = nil) {
        self.format = format
        self.type = type
        self.position = position
        self.order = order
    }
}

/// A translation for a specific language
public struct Translation: Codable, Equatable {
    public let languageCode: String
    public let text: String
    public let version: String?
    public let approved: Bool

    /// Translated plural forms keyed by CLDR category. nil for non-plural translations.
    public let pluralForms: [PluralCategory: String]?

    public init(
        languageCode: String,
        text: String,
        version: String? = nil,
        approved: Bool = false,
        pluralForms: [PluralCategory: String]? = nil
    ) {
        self.languageCode = languageCode
        self.text = text
        self.version = version
        self.approved = approved
        self.pluralForms = pluralForms
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(languageCode, forKey: .languageCode)
        try c.encode(text,         forKey: .text)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encode(approved,     forKey: .approved)
        if let forms = pluralForms {
            var fc = c.nestedContainer(keyedBy: PluralCategory.self, forKey: .pluralForms)
            for (cat, t) in forms { try fc.encode(t, forKey: cat) }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        languageCode = try c.decode(String.self,  forKey: .languageCode)
        text         = try c.decode(String.self,  forKey: .text)
        version      = try c.decodeIfPresent(String.self, forKey: .version)
        approved     = try c.decodeIfPresent(Bool.self,   forKey: .approved) ?? false
        if c.contains(.pluralForms) {
            if let fc = try? c.nestedContainer(keyedBy: PluralCategory.self, forKey: .pluralForms) {
                var forms: [PluralCategory: String] = [:]
                for cat in fc.allKeys { forms[cat] = try fc.decode(String.self, forKey: cat) }
                pluralForms = forms
            } else {
                pluralForms = try c.decodeIfPresent([PluralCategory: String].self, forKey: .pluralForms)
            }
        } else {
            pluralForms = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case languageCode, text, version, approved, pluralForms
    }
}

/// Complete translation entry with key and all language translations
public struct TranslationEntry: Codable, Equatable {
    public let key: StringKey
    public let translations: [String: Translation]

    public init(key: StringKey, translations: [String: Translation] = [:]) {
        self.key = key
        self.translations = translations
    }
}

/// Collection of extracted strings
public struct ExtractedStrings: Codable {
    public let keys: [StringKey]
    public let platform: Platform
    public let extractedAt: Date
    public let projectId: String?

    public init(
        keys: [StringKey],
        platform: Platform,
        extractedAt: Date = Date(),
        projectId: String? = nil
    ) {
        self.keys = keys
        self.platform = platform
        self.extractedAt = extractedAt
        self.projectId = projectId
    }
}

// MARK: - API Contract

public enum PolyglotError: Error, LocalizedError {
    case configNotFound
    case apiError(statusCode: Int, message: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "No .polyglot.json config found. Create one with apiURL, apiKey, projectId."
        case .apiError(let code, let msg):
            return "API error \(code): \(msg)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

public struct PolyglotConfig: Codable {
    public let apiURL: String
    public let apiKey: String
    public let projectId: String
    /// Platform hint (ios, android, web). Default for --platform when not passed as a flag.
    public let platform: String?
    /// Source directory for extraction. Default for the sourcePath argument when not passed.
    public let sourceDir: String?
    /// Output directory for generated files. Default for --output when not passed as a flag.
    public let outputDir: String?
    /// Maximum seconds to wait for translations during sync. 0 = no limit. Default: 3600 (1 hour).
    public let syncTimeout: Int?

    public init(apiURL: String, apiKey: String, projectId: String,
                platform: String? = nil, sourceDir: String? = nil, outputDir: String? = nil,
                syncTimeout: Int? = nil) {
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.projectId = projectId
        self.platform = platform
        self.sourceDir = sourceDir
        self.outputDir = outputDir
        self.syncTimeout = syncTimeout
    }

    /// Loads from the given path, or searches .polyglot.json in CWD then ~/.polyglot.json.
    public static func load(from path: String? = nil) throws -> PolyglotConfig {
        let candidates: [URL]
        if let path = path {
            candidates = [URL(fileURLWithPath: path)]
        } else {
            candidates = [
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".polyglot.json"),
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".polyglot.json")
            ]
        }
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(PolyglotConfig.self, from: data)
            }
        }
        throw PolyglotError.configNotFound
    }
}

public struct UploadStats: Codable, Equatable {
    public let new: Int
    public let updated: Int
    public let unchanged: Int

    public init(new: Int, updated: Int, unchanged: Int) {
        self.new = new
        self.updated = updated
        self.unchanged = unchanged
    }
}

public struct UploadResponse: Codable {
    public let uploadId: String
    public let projectId: String
    public let stats: UploadStats
    /// localKey → CRM-assigned stable key (populated when the CRM remaps a key)
    public let keyMappings: [String: String]

    public init(uploadId: String, projectId: String, stats: UploadStats, keyMappings: [String: String] = [:]) {
        self.uploadId = uploadId
        self.projectId = projectId
        self.stats = stats
        self.keyMappings = keyMappings
    }
}

/// Container written by `download`, read by `generate` and `check`.
public struct TranslationsFile: Codable {
    public let projectId: String?
    public let downloadedAt: Date
    public let entries: [TranslationEntry]

    public init(projectId: String? = nil, downloadedAt: Date = Date(), entries: [TranslationEntry]) {
        self.projectId = projectId
        self.downloadedAt = downloadedAt
        self.entries = entries
    }
}
