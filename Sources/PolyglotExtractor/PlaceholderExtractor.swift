//
//  PlaceholderExtractor.swift
//  PolyglotExtractor
//
//  Handles placeholder detection and extraction from strings
//

import Foundation
import PolyglotCore

/// Handles placeholder detection and extraction from strings
public struct PlaceholderExtractor {
    // Cache regex patterns to avoid recompiling on every call
    private static let swiftPlaceholderRegex: NSRegularExpression? = {
        // Flags bounded to {0,4}: a printf format spec never has more than a handful of flags
        // (e.g. "-0+# "), bounding prevents catastrophic backtracking on pathological input.
        let pattern = #"(%(?:\d+\$)?[#0\+\- ]{0,4}(?:\d+)?(?:\.\d+)?[hlL]{0,2}[@dDifosuxXfFeEgGcspn])"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()
    
    private static let namedPlaceholderRegex: NSRegularExpression? = {
        let pattern = #"\{([a-zA-Z_][a-zA-Z0-9_]*)\}"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()
    
    /// Extract text and placeholders from a string
    /// Returns the text (unchanged) and an array of detected placeholders
    public static func extractTextAndPlaceholders(from string: String) -> (text: String, placeholders: [Placeholder]) {
        var allPlaceholders: [(format: String, type: String, location: Int, explicitOrder: Int?)] = []
        let text = string
        let nsString = string as NSString
        
        // Detect Swift-style placeholders with full format specifier support:
        // - Simple: %@, %d, %f, %s
        // - With width/precision: %10.2f, %0.2d, %-5d
        // - With flags: %+d, %#x, % d
        // - Positional: %1$@, %2$d, %3$10.2f
        if let regex = swiftPlaceholderRegex {
            let matches = regex.matches(in: string, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                if match.numberOfRanges > 0 {
                    // Get the captured group (range at index 1 - the parentheses capture group)
                    let matchRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
                    
                    if matchRange.location != NSNotFound {
                        let placeholderString = nsString.substring(with: matchRange)
                        
                        // Skip if placeholder is empty or just "%"
                        guard placeholderString.count > 1, placeholderString.hasPrefix("%") else { continue }
                        
                        // Extract positional order if present (e.g., "1$" from "%1$@")
                        var explicitOrder: Int? = nil
                        if let orderMatch = placeholderString.range(of: #"\d+\$"#, options: .regularExpression) {
                            let orderString = String(placeholderString[orderMatch])
                            if let order = Int(orderString.dropLast()) { // Remove the '$'
                                explicitOrder = order - 1 // Convert to 0-based
                            }
                        }
                        
                        allPlaceholders.append((
                            format: placeholderString,
                            type: getPlaceholderType(placeholderString),
                            location: matchRange.location,
                            explicitOrder: explicitOrder
                        ))
                    }
                }
            }
        }
        
        // Detect named placeholders: {name}, {userName}, etc.
        if let regex = namedPlaceholderRegex {
            let matches = regex.matches(in: string, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                if match.numberOfRanges > 1 && match.range.location != NSNotFound {
                    let fullMatch = nsString.substring(with: match.range(at: 0))
                    allPlaceholders.append((
                        format: fullMatch,
                        type: "named",
                        location: match.range.location,
                        explicitOrder: nil
                    ))
                }
            }
        }
        
        // Sort all placeholders by their position in the string (character location)
        allPlaceholders.sort { $0.location < $1.location }
        
        // Assign position (character location) and order (sequential index)
        let placeholders = allPlaceholders.enumerated().map { index, item in
            Placeholder(
                format: item.format,
                type: item.type,
                position: item.location, // Actual character position in string
                order: item.explicitOrder ?? index // Use explicit order if specified (Android-style), otherwise sequential
            )
        }
        
        return (text: text, placeholders: placeholders)
    }
    
    /// Get placeholder type from format string
    private static func getPlaceholderType(_ format: String) -> String {
        if format.contains("@") { return "string" }
        if format.contains("d") || format.contains("i") { return "integer" }
        if format.contains("f") { return "double" }
        if format.contains("s") { return "string" }
        return "unknown"
    }
}

