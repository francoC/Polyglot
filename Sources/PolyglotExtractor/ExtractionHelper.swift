//
//  ExtractionHelper.swift
//  PolyglotExtractor
//
//  Helper utilities for string extraction
//

import Foundation
import PolyglotCore

/// Helper utilities for string extraction
internal struct ExtractionHelper {
    /// Check if a string should be skipped (only placeholders, no actual text, only symbols/punctuation, or only numbers)
    static func shouldSkipString(text: String, placeholders: [Placeholder]) -> Bool {
        // First check: If only placeholders with no actual text, skip
        if !placeholders.isEmpty {
            // Remove all placeholders and check if anything remains
            let cleanedText = removePlaceholders(from: text)
            
            // If nothing remains except placeholders, skip it
            if cleanedText.isEmpty {
                return true
            }
        }
        
        // Second check: Skip strings that contain only symbols/punctuation/whitespace
        // Remove whitespace and check if only punctuation/symbols remain
        let textWithoutWhitespace = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty after trimming whitespace, skip it
        guard !textWithoutWhitespace.isEmpty else { return true }
        
        // Third check: Skip strings that only contain numbers, numbers + symbols, or numbers + spaces
        let cleanedText = placeholders.isEmpty ? text : removePlaceholders(from: text)
        let cleanedTrimmed = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanedTrimmed.isEmpty else { return true }
        
        // Check if string contains only numbers, numbers + symbols, or numbers + spaces
        // Remove all whitespace and check what remains
        let textWithoutWhitespace2 = cleanedTrimmed.replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )
        
        // If empty after removing whitespace, skip
        guard !textWithoutWhitespace2.isEmpty else { return true }
        
        // Check if all remaining characters are digits or symbols (no letters)
        let decimalDigits = CharacterSet.decimalDigits
        let punctuationAndSymbols = CharacterSet.punctuationCharacters.union(.symbols)
        let allowedChars = decimalDigits.union(punctuationAndSymbols)
        
        let hasLetters = textWithoutWhitespace2.unicodeScalars.contains { scalar in
            !allowedChars.contains(scalar)
        }
        
        // If no letters found, it's only numbers + symbols - skip it
        if !hasLetters {
            return true
        }
        
        // Fourth check: Skip if only punctuation/symbols (no letters or numbers after removing placeholders)
        let hasLettersOrNumbers = cleanedTrimmed.unicodeScalars.contains { scalar in
            !punctuationAndSymbols.contains(scalar) && !CharacterSet.whitespaces.contains(scalar)
        }
        
        // If no letters or numbers found, it's only symbols/punctuation - skip it
        return !hasLettersOrNumbers
    }
    
    /// Remove placeholders from text
    static func removePlaceholders(from text: String) -> String {
        var cleanedText = text
        
        // Remove Swift-style placeholders: %@, %d, %10.2f, %1$@, etc.
        cleanedText = cleanedText.replacingOccurrences(
            of: #"%(?:\d+\$)?[#0\-\+ ]*(?:\d+)?(?:\.\d+)?[hlL]*[@dDifosuxXfFeEgGcspn]"#,
            with: "",
            options: .regularExpression
        )
        
        // Remove named placeholders: {name}
        cleanedText = cleanedText.replacingOccurrences(
            of: #"\{[a-zA-Z_][a-zA-Z0-9_]*\}"#,
            with: "",
            options: .regularExpression
        )
        
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

