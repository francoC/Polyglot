//
//  Extractor.swift
//  PolyglotExtractor
//
//  Extracts translatable strings from Swift source code
//

import Foundation
import PolyglotCore
import SwiftSyntax
import SwiftParser

/// Main extractor for iOS/Swift codebases
public class Extractor {
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// Extract strings from Swift files in a directory
    public func extract(from directory: URL) throws -> ExtractedStrings {
        // Sort for stable ordering — ensures the same file "wins" on every run
        // when the same key appears in multiple files.
        let swiftFiles = try findSwiftFiles(in: directory).sorted { $0.path < $1.path }
        var allKeys: [StringKey] = []

        for fileURL in swiftFiles {
            let keys = try extractFromFile(at: fileURL, platform: .ios)
            allKeys.append(contentsOf: keys)
        }

        // Cross-file dedup: same key + same baseText from different files → merge positions,
        // keep the first file's filePath/context/hint (stable due to sorted order above).
        var merged: [String: StringKey] = [:]
        for key in allKeys {
            let dedupeKey = "\(key.key)|\(key.baseText)"
            if let existing = merged[dedupeKey] {
                let combined = (existing.positions + key.positions).sorted {
                    $0.lineNumber != $1.lineNumber ? $0.lineNumber < $1.lineNumber : $0.startPosition < $1.startPosition
                }
                merged[dedupeKey] = StringKey(
                    key: existing.key,
                    baseText: existing.baseText,
                    platform: existing.platform,
                    filePath: existing.filePath,
                    positions: combined,
                    placeholders: existing.placeholders,
                    pluralForms: existing.pluralForms ?? key.pluralForms,
                    context: existing.context,
                    hint: existing.hint ?? key.hint
                )
            } else {
                merged[dedupeKey] = key
            }
        }

        return ExtractedStrings(
            keys: Array(merged.values),
            platform: .ios,
            extractedAt: Date()
        )
    }
    
    /// Extract strings from a single Swift file
    public func extractFromFile(at url: URL, platform: Platform) throws -> [StringKey] {
        let sourceCode = try String(contentsOf: url, encoding: .utf8)
        let sourceFile = Parser.parse(source: sourceCode)
        
        // Create source location converter for line number tracking
        let converter = SourceLocationConverter(fileName: url.path, tree: sourceFile)
        
        // Extract strings using AST visitor
        // The visitor handles:
        // - Text("...") - SwiftUI strings
        // - NSLocalizedString(...) - Foundation localization
        // - Text(verbatim: ...) - skipped (not localizable)
        // - Raw strings (#"..."#) - skipped (not localizable)
        // - String interpolation - converted to placeholders
        // - Generic localization calls (methods containing "localized")
        let visitor = StringExtractionVisitor(filePath: url.path, sourceCode: sourceCode, converter: converter)
        visitor.walk(sourceFile)
        
        // Convert extracted keys to StringKey objects
        // Filter out strings that are only placeholders
        let initialKeys = visitor.extractedKeys.compactMap { key -> StringKey? in
            // Skip strings that are only placeholders (no actual text)
            if ExtractionHelper.shouldSkipString(text: key.baseText, placeholders: key.placeholders) {
                return nil
            }
            
            // Create position object if we have all position data
            var positions: [StringPosition] = []
            if let startPos = key.startPosition,
               let endPos = key.endPosition,
               let lineNum = key.lineNumber {
                positions.append(StringPosition(
                    startPosition: startPos,
                    endPosition: endPos,
                    lineNumber: lineNum
                ))
            }
            
            return StringKey(
                key: key.key,
                baseText: key.baseText,
                platform: platform,
                filePath: url.path,
                positions: positions,
                placeholders: key.placeholders,
                pluralForms: key.pluralForms,
                context: key.context,
                hint: key.hint
            )
        }
        
        // Merge duplicates: if baseText and key are the same in the same file, combine them
        // Group by (key, baseText, filePath)
        var mergedKeys: [String: StringKey] = [:]
        
        for key in initialKeys {
            let uniqueKey = "\(key.key)|\(key.baseText)|\(key.filePath)"
            
            if let existing = mergedKeys[uniqueKey] {
                // Merge: combine all positions from both keys
                var allPositions = existing.positions
                
                // Add positions from current key that aren't duplicates
                for position in key.positions {
                    // Check if this position already exists (same start, end, line)
                    let isDuplicate = allPositions.contains { existingPos in
                        existingPos.startPosition == position.startPosition &&
                        existingPos.endPosition == position.endPosition &&
                        existingPos.lineNumber == position.lineNumber
                    }
                    
                    if !isDuplicate {
                        allPositions.append(position)
                    }
                }
                
                // Sort positions by line number, then by start position
                allPositions.sort { pos1, pos2 in
                    if pos1.lineNumber != pos2.lineNumber {
                        return pos1.lineNumber < pos2.lineNumber
                    }
                    return pos1.startPosition < pos2.startPosition
                }
                
                // Update merged key with combined positions
                mergedKeys[uniqueKey] = StringKey(
                    key: existing.key,
                    baseText: existing.baseText,
                    platform: existing.platform,
                    filePath: existing.filePath,
                    positions: allPositions,
                    placeholders: existing.placeholders,
                    pluralForms: existing.pluralForms ?? key.pluralForms,
                    context: existing.context,
                    hint: existing.hint ?? key.hint // Keep first hint if available
                )
            } else {
                // First occurrence
                mergedKeys[uniqueKey] = key
            }
        }
        
        // Disambiguate colliding keys: same generated key, different baseText.
        // Sort colliders by baseText for a stable, reproducible suffix order across runs.
        var byGeneratedKey: [String: [StringKey]] = [:]
        for entry in mergedKeys.values {
            byGeneratedKey[entry.key, default: []].append(entry)
        }

        var result: [StringKey] = []
        for (_, group) in byGeneratedKey {
            if group.count == 1 {
                result.append(group[0])
            } else {
                let sorted = group.sorted { $0.baseText < $1.baseText }
                for (index, entry) in sorted.enumerated() {
                    let finalKey = index == 0 ? entry.key : "\(entry.key).\(index + 1)"
                    result.append(StringKey(
                        key: finalKey,
                        baseText: entry.baseText,
                        platform: entry.platform,
                        filePath: entry.filePath,
                        positions: entry.positions,
                        placeholders: entry.placeholders,
                        pluralForms: entry.pluralForms,
                        context: entry.context,
                        hint: entry.hint
                    ))
                }
            }
        }

        return result
    }
    
    // MARK: - Private Helpers
    
    private func findSwiftFiles(in directory: URL) throws -> [URL] {
        var swiftFiles: [URL] = []
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                swiftFiles.append(fileURL)
            }
        }
        
        return swiftFiles
    }
}
