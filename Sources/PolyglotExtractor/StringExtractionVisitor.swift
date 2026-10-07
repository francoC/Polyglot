//
//  StringExtractionVisitor.swift
//  PolyglotExtractor
//
//  SwiftSyntax visitor that extracts strings from Swift source code
//

import Foundation
import PolyglotCore
import SwiftSyntax

/// SwiftSyntax visitor that extracts strings from Swift source
internal class StringExtractionVisitor: SyntaxVisitor {
    private let filePath: String
    private let sourceCode: String
    private let converter: SourceLocationConverter
    var extractedKeys: [(key: String, baseText: String, lineNumber: Int?, placeholders: [Placeholder], pluralForms: [PluralCategory: String]?, context: String?, hint: String?, startPosition: Int?, endPosition: Int?)] = []
    
    init(filePath: String, sourceCode: String, converter: SourceLocationConverter) {
        self.filePath = filePath
        self.sourceCode = sourceCode
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Get the function name
        let functionName = node.calledExpression.trimmedDescription
        
        // Handle Text() - SwiftUI
        if functionName == "Text" || functionName.hasPrefix("Text(") {
            processTextCall(node)
        }
        // Handle NSLocalizedString - Foundation
        else if functionName == "NSLocalizedString" || functionName.hasPrefix("NSLocalizedString(") {
            processNSLocalizedStringCall(node)
        }
        // Pattern 1: String.localizedStringWithFormat(NSLocalizedString("key", comment: ""), count)
        else if functionName == "String.localizedStringWithFormat" {
            processLocalizedStringWithFormatCall(node)
        }
        // Pattern 2: String(format: NSLocalizedString("key", comment: ""), count)
        else if functionName == "String" {
            processStringFormatNSLocalizedStringCall(node)
        }
        // Handle other potential localization calls
        else {
            if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
                let baseName = memberAccess.declName.baseName.trimmedDescription
                if baseName.contains("localized") || baseName.contains("Localized") {
                    processGenericLocalizationCall(node, functionName: baseName)
                }
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Processing Methods
    
    /// Process SwiftUI Text("...") calls
    private func processTextCall(_ node: FunctionCallExprSyntax) {
        // Check if this is Text(verbatim:) - skip it
        if let argument = node.arguments.first,
           let label = argument.label?.text,
           label == "verbatim" {
            // Skip verbatim strings
            return
        }
        
        let hint = extractPolyglotHint(at: node.positionAfterSkippingLeadingTrivia)

        // Pattern 3: Text("^[\(count) noun](inflect: true)") — SwiftUI automatic grammar agreement
        if let firstArg = node.arguments.first,
           let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
           let inner = extractInflectString(from: stringLiteral) {
            let (text, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: inner)
            let key = generateKey(for: text, context: getContext(from: node))
            let (startPos, endPos) = getStringPositions(from: stringLiteral)
            extractedKeys.append((
                key: key,
                baseText: text,
                lineNumber: getLineNumber(from: node),
                placeholders: placeholders,
                pluralForms: [:],
                context: getContext(from: node),
                hint: hint,
                startPosition: startPos,
                endPosition: endPos
            ))
            return
        }

        // Extract string literal from arguments
        for argument in node.arguments {
            if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                // Check if this has string interpolation in the middle
                let segments = stringLiteral.segments
                let hasInterpolation = segments.contains { $0.is(ExpressionSegmentSyntax.self) }
                
                // Check if this has format placeholders (%@, %d, etc.) that should cause splitting
                let extractedText = extractStringLiteral(from: argument.expression)
                let hasFormatPlaceholders = extractedText.flatMap { text in
                    let (_, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: text)
                    return !placeholders.isEmpty
                } ?? false
                
                // Always extract Text() as a single string.
                // For interpolated strings, extractStringFromLiteral already converts
                // \(expr) → %@/%d/%f, giving us the full translatable string with placeholders.
                if let text = extractedText {
                    let (normalizedText, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: text)
                    guard !ExtractionHelper.shouldSkipString(text: normalizedText, placeholders: placeholders) else { continue }
                    let key = generateKey(for: normalizedText, context: getContext(from: node))
                    let lineNumber = getLineNumber(from: node)
                    let (startPos, endPos) = getStringPositions(from: stringLiteral)
                    extractedKeys.append((
                        key: key,
                        baseText: normalizedText,
                        lineNumber: lineNumber,
                        placeholders: placeholders,
                        pluralForms: nil,
                        context: getContext(from: node),
                        hint: hint,
                        startPosition: startPos,
                        endPosition: endPos
                    ))
                }
            } else if let stringLiteralExpr = argument.expression.as(StringLiteralExprSyntax.self),
                      let extractedText = extractStringLiteral(from: argument.expression) {
                // Fallback for other string literal types
                let (text, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: extractedText)
                let key = generateKey(for: text, context: getContext(from: node))
                let lineNumber = getLineNumber(from: node)
                let (startPos, endPos) = getStringPositions(from: stringLiteralExpr)
                
                extractedKeys.append((
                    key: key,
                    baseText: text,
                    lineNumber: lineNumber,
                    placeholders: placeholders,
                    pluralForms: nil,
                    context: getContext(from: node),
                    hint: hint,
                    startPosition: startPos,
                    endPosition: endPos
                ))
            }
        }
    }
    
    /// Returns true when this NSLocalizedString call is the format argument of a
    /// plural pattern (Pattern 1 or 2) — those handlers own extraction for this node.
    private func isNestedInsidePluralPattern(_ node: FunctionCallExprSyntax) -> Bool {
        guard let argExpr = node.parent?.as(LabeledExprSyntax.self),
              let argList = argExpr.parent?.as(LabeledExprListSyntax.self),
              let outer = argList.parent?.as(FunctionCallExprSyntax.self) else { return false }
        let name = outer.calledExpression.trimmedDescription
        if name == "String.localizedStringWithFormat" { return true }
        if name == "String",
           let first = outer.arguments.first,
           first.label?.text == "format" { return true }
        return false
    }

    /// Process NSLocalizedString(...) calls
    private func processNSLocalizedStringCall(_ node: FunctionCallExprSyntax) {
        // Skip nodes that are the format-argument of a plural pattern — those handlers extract them.
        guard !isNestedInsidePluralPattern(node) else { return }
        let arguments = Array(node.arguments)
        guard !arguments.isEmpty else { return }
        
        let keyArgument = arguments[0]
        let commentArgument = arguments.count > 1 ? arguments[1] : nil
        // Note: bundleArgument and tableNameArgument are intentionally not extracted
        // as they're not part of the translatable string itself
        
        if let keyString = extractStringLiteral(from: keyArgument.expression),
           let keyStringLiteral = keyArgument.expression.as(StringLiteralExprSyntax.self) {
            let (text, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: keyString)
            let comment = commentArgument.flatMap { extractStringLiteral(from: $0.expression) }
            let lineNumber = getLineNumber(from: node)
            let (startPos, endPos) = getStringPositions(from: keyStringLiteral)
            
            let localizedKey = text
            let hint = extractPolyglotHint(at: node.positionAfterSkippingLeadingTrivia) ?? comment

            extractedKeys.append((
                key: localizedKey,
                baseText: localizedKey,
                lineNumber: lineNumber,
                placeholders: placeholders,
                pluralForms: nil,
                context: getContext(from: node),
                hint: hint,
                startPosition: startPos,
                endPosition: endPos
            ))
        }
    }
    
    /// Process generic localization calls
    private func processGenericLocalizationCall(_ node: FunctionCallExprSyntax, functionName: String) {
        let hint = extractPolyglotHint(at: node.positionAfterSkippingLeadingTrivia)
        
        // Extract string from first argument
        if let argument = node.arguments.first,
           let stringLiteral = extractStringLiteral(from: argument.expression),
           let stringLiteralExpr = argument.expression.as(StringLiteralExprSyntax.self) {
            let (text, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: stringLiteral)
            let key = generateKey(for: text, context: getContext(from: node))
            let lineNumber = getLineNumber(from: node)
            let (startPos, endPos) = getStringPositions(from: stringLiteralExpr)
            
            extractedKeys.append((
                key: key,
                baseText: text,
                lineNumber: lineNumber,
                placeholders: placeholders,
                pluralForms: (functionName.contains("plural") || functionName.contains("Plural")) ? [:] : nil,
                context: getContext(from: node),
                hint: hint,
                startPosition: startPos,
                endPosition: endPos
            ))
        }
    }
    
    // MARK: - Plural Pattern Handlers

    /// Pattern 1: String.localizedStringWithFormat(NSLocalizedString("key", comment: ""), count, ...)
    private func processLocalizedStringWithFormatCall(_ node: FunctionCallExprSyntax) {
        let arguments = Array(node.arguments)
        guard let firstArg = arguments.first,
              let nestedCall = firstArg.expression.as(FunctionCallExprSyntax.self),
              nestedCall.calledExpression.trimmedDescription == "NSLocalizedString" else { return }

        let nestedArgs = Array(nestedCall.arguments)
        guard !nestedArgs.isEmpty,
              let keyString = extractStringLiteral(from: nestedArgs[0].expression),
              let keyStringLiteral = nestedArgs[0].expression.as(StringLiteralExprSyntax.self) else { return }

        let comment = nestedArgs.count > 1 ? extractStringLiteral(from: nestedArgs[1].expression) : nil
        let hint = extractPolyglotHint(at: node.positionAfterSkippingLeadingTrivia) ?? comment
        let (text, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: keyString)
        let (startPos, endPos) = getStringPositions(from: keyStringLiteral)

        extractedKeys.append((
            key: text,
            baseText: text,
            lineNumber: getLineNumber(from: node),
            placeholders: placeholders,
            pluralForms: [:],
            context: getContext(from: node),
            hint: hint,
            startPosition: startPos,
            endPosition: endPos
        ))
    }

    /// Pattern 2: String(format: NSLocalizedString("key", comment: ""), count, ...)
    /// Only triggers when the format: argument is literally NSLocalizedString(…).
    /// Treated as a plain format string — plural forms must be defined via a source
    /// .stringsdict file and picked up by Pattern 1 / the plurals extractor.
    private func processStringFormatNSLocalizedStringCall(_ node: FunctionCallExprSyntax) {
        let arguments = Array(node.arguments)
        guard let firstArg = arguments.first,
              firstArg.label?.text == "format",
              let nestedCall = firstArg.expression.as(FunctionCallExprSyntax.self),
              nestedCall.calledExpression.trimmedDescription == "NSLocalizedString" else { return }

        let nestedArgs = Array(nestedCall.arguments)
        guard !nestedArgs.isEmpty,
              let keyString = extractStringLiteral(from: nestedArgs[0].expression),
              let keyStringLiteral = nestedArgs[0].expression.as(StringLiteralExprSyntax.self) else { return }

        let comment = nestedArgs.count > 1 ? extractStringLiteral(from: nestedArgs[1].expression) : nil
        let hint = extractPolyglotHint(at: node.positionAfterSkippingLeadingTrivia) ?? comment
        let (text, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: keyString)
        let (startPos, endPos) = getStringPositions(from: keyStringLiteral)

        extractedKeys.append((
            key: text,
            baseText: text,
            lineNumber: getLineNumber(from: node),
            placeholders: placeholders,
            pluralForms: nil,
            context: getContext(from: node),
            hint: hint,
            startPosition: startPos,
            endPosition: endPos
        ))
    }

    /// Detect SwiftUI automatic grammar agreement: Text("^[\(count) noun](inflect: true)")
    /// Returns the inner text (e.g. "%@ noun") or nil if the pattern doesn't match.
    private func extractInflectString(from literal: StringLiteralExprSyntax) -> String? {
        guard let fullText = extractStringFromLiteral(literal) else { return nil }
        let prefix = "^["
        let suffix = "](inflect: true)"
        guard fullText.hasPrefix(prefix) && fullText.hasSuffix(suffix) else { return nil }
        let inner = String(fullText.dropFirst(prefix.count).dropLast(suffix.count))
        return inner.isEmpty ? nil : inner
    }

    // MARK: - Helper Methods
    
    /// Remove placeholders from text
    private func removePlaceholders(from text: String) -> String {
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
        
        // Note: Android-style placeholders (%1$s, %2$d) are now covered by the Swift-style pattern above
        
        // Trim whitespace and clean up multiple spaces
        cleanedText = cleanedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        return cleanedText
    }
    
    /// Extract string literal from an expression
    private func extractStringLiteral(from expression: ExprSyntax) -> String? {
        // Handle string literals: "text", #"text"#, etc.
        if let stringLiteral = expression.as(StringLiteralExprSyntax.self) {
            // Check if this is a raw string (has opening delimiter like #)
            // Raw strings in Swift use # as delimiters: #"text"#
            // Raw strings are detected by checking if opening quote contains #
            let openingQuote = stringLiteral.openingQuote.text
            
            // Skip raw strings - they're typically not localizable
            // Raw strings use # as delimiter: #"text"#
            if openingQuote.contains("#") {
                // This is a raw string - skip it as it's explicitly not localizable
                // (raw strings are used when you want literal text without escaping)
                return nil
            }
            
            return extractStringFromLiteral(stringLiteral)
        }
        
        return nil
    }
    
    /// Extract each text segment separately from a string literal with format placeholders
    /// Splits on placeholder boundaries to allow flexible translation
    /// Example: "Width 5: %5s" -> ["Width 5: ", ""]
    /// Example: "%1$@ has %2$d items" -> ["", " has ", " items"]
    private func extractSegmentsFromFormatPlaceholders(stringLiteral: StringLiteralExprSyntax, node: FunctionCallExprSyntax, hint: String?) {
        guard let fullString = extractStringFromLiteral(stringLiteral) else { return }
        
        // Get line number from the node (all segments from same Text() call are on same line)
        let lineNumber = getLineNumber(from: node)
        let context = getContext(from: node)
        
        // Extract all placeholders with their positions
        let (_, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: fullString)
        
        guard !placeholders.isEmpty else { return }
        
        // Build segments by splitting on placeholder boundaries
        var segments: [(text: String, startPos: Int, endPos: Int)] = []
        var currentIndex = 0
        
        for placeholder in placeholders.sorted(by: { 
            ($0.position ?? Int.max) < ($1.position ?? Int.max) 
        }) {
            guard let placeholderStart = placeholder.position else { continue }
            let placeholderEnd = placeholderStart + placeholder.format.utf8.count - 1
            
            // Extract text before this placeholder
            if placeholderStart > currentIndex {
                let segmentStart = fullString.utf8.index(fullString.utf8.startIndex, offsetBy: currentIndex)
                let segmentEnd = fullString.utf8.index(fullString.utf8.startIndex, offsetBy: placeholderStart)
                
                if let startIdx = String.Index(segmentStart, within: fullString),
                   let endIdx = String.Index(segmentEnd, within: fullString) {
                    let segmentText = String(fullString[startIdx..<endIdx])
                    if !segmentText.isEmpty {
                        segments.append((
                            text: segmentText,
                            startPos: currentIndex,
                            endPos: placeholderStart - 1
                        ))
                    }
                }
            }
            
            currentIndex = placeholderEnd + 1
        }
        
        // Extract text after last placeholder
        if currentIndex < fullString.utf8.count {
            let segmentStart = fullString.utf8.index(fullString.utf8.startIndex, offsetBy: currentIndex)
            let segmentEnd = fullString.utf8.endIndex
            
            if let startIdx = String.Index(segmentStart, within: fullString) {
                let segmentText = String(fullString[startIdx..<segmentEnd])
                if !segmentText.isEmpty {
                    segments.append((
                        text: segmentText,
                        startPos: currentIndex,
                        endPos: fullString.utf8.count - 1
                    ))
                }
            }
        }
        
        // If string starts with placeholder, add empty segment at start
        if let firstPlaceholder = placeholders.sorted(by: { 
            ($0.position ?? Int.max) < ($1.position ?? Int.max) 
        }).first,
           let firstPos = firstPlaceholder.position,
           firstPos == 0 {
            segments.insert((text: "", startPos: 0, endPos: -1), at: 0)
        }
        
        // Extract each segment as a separate key
        var segmentIndex = 0
        for segment in segments {
                    let (text, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: segment.text)
            
            // Skip if segment is empty, only whitespace, or only symbols/punctuation
            if ExtractionHelper.shouldSkipString(text: text, placeholders: placeholders) {
                segmentIndex += 1
                continue
            }
            
            let key = generateKey(for: text, context: context)
            
            extractedKeys.append((
                key: key,
                baseText: text,
                lineNumber: lineNumber,
                placeholders: placeholders,
                pluralForms: nil,
                context: context,
                hint: segmentIndex == 0 ? hint : nil, // Only add hint to first segment
                startPosition: segment.startPos,
                endPosition: segment.endPos
            ))
            
            segmentIndex += 1
        }
    }
    
    /// Extract each text segment separately from a string literal with interpolation
    /// Splits on interpolation boundaries to allow flexible translation
    /// Example: "some string \(count) other stuff" -> extracts ["some string ", " other stuff"] as separate strings
    private func extractSegmentsFromStringLiteral(_ literal: StringLiteralExprSyntax, node: FunctionCallExprSyntax, hint: String?) {
        // Get base line number from the node as fallback
        let fallbackLineNumber = getLineNumber(from: node)
        let context = getContext(from: node)
        var segmentIndex = 0
        
        for segment in literal.segments {
            if let stringSegment = segment.as(StringSegmentSyntax.self) {
                // Get the raw text (preserve whitespace - don't trim)
                let text = stringSegment.content.text
                
                // Only extract non-empty text segments that aren't just symbols/punctuation
                // Note: We keep whitespace as-is so translators know the context
                if !text.isEmpty {
                    let (text, placeholders) = PlaceholderExtractor.extractTextAndPlaceholders(from: text)
                    
                    // Skip if this segment is only symbols/punctuation/whitespace
                    if ExtractionHelper.shouldSkipString(text: text, placeholders: placeholders) {
                        segmentIndex += 1
                        continue
                    }
                    
                    // Use the node's line number (all segments from same Text() call are on same line)
                    let segmentLineNumber = fallbackLineNumber
                    
                    let key = generateKey(for: text, context: context)
                    let (startPos, endPos) = getSegmentPositions(from: stringSegment, in: literal)
                    
                    extractedKeys.append((
                        key: key,
                        baseText: text,
                        lineNumber: segmentLineNumber,
                        placeholders: placeholders,
                        pluralForms: nil,
                        context: context,
                        hint: segmentIndex == 0 ? hint : nil, // Only add hint to first segment
                        startPosition: startPos,
                        endPosition: endPos
                    ))
                    
                    segmentIndex += 1
                }
            }
            // Skip ExpressionSegmentSyntax (interpolations) - they're not translatable
        }
    }
    
    /// Extract string content from StringLiteralExprSyntax
    private func extractStringFromLiteral(_ literal: StringLiteralExprSyntax) -> String? {
        // Handle segments (regular strings, interpolations, etc.)
        var result = ""
        for segment in literal.segments {
            if let stringSegment = segment.as(StringSegmentSyntax.self) {
                result += stringSegment.content.text
            } else if let expressionSegment = segment.as(ExpressionSegmentSyntax.self) {
                // String interpolation - extract placeholder info
                // Example: "Hello \(name)" -> placeholder
                if let expression = expressionSegment.expressions.first {
                    // Try to determine the type from the expression
                    let exprDescription = expression.trimmedDescription
                    
                    // Default to %@ for most cases
                    if exprDescription.contains("Int") || exprDescription.contains("integer") {
                        result += "%d"
                    } else if exprDescription.contains("Double") || exprDescription.contains("Float") {
                        result += "%f"
                    } else {
                        result += "%@"
                    }
                } else {
                    result += "%@"
                }
            }
        }
        
        return result.isEmpty ? nil : result
    }
    
    
    /// Generate a key from text (fallback when no explicit key is provided)
    /// Removes placeholders from the key generation
    private func generateKey(for text: String, context: String?) -> String {
        // Remove placeholders from text before generating key
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
        
        // Note: Android-style placeholders (%1$s, %2$d) are now covered by the Swift-style pattern above
        
        // Create a key from the cleaned text (slugified)
        // Remove all symbols and punctuation, keeping only letters, numbers, and spaces
        let slugified = cleanedText
            .lowercased()
            .replacingOccurrences(of: " ", with: ".")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(
                of: #"[^\w\s\.]"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\.+"#, with: ".", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Truncate at segment boundary (never mid-word) up to 50 chars
        var key = ""
        for segment in slugified.split(separator: ".", omittingEmptySubsequences: true) {
            let candidate = key.isEmpty ? String(segment) : "\(key).\(segment)"
            guard candidate.count <= 50 else { break }
            key = candidate
        }
        
        // If context provided, use it as prefix
        if let context = context, !context.isEmpty {
            let contextKey = context
                .lowercased()
                // Remove symbols from context too
                .replacingOccurrences(
                    of: #"[^\w\s]"#,
                    with: "",
                    options: .regularExpression
                )
                .replacingOccurrences(of: " ", with: ".")
                .prefix(30)
            return "\(contextKey).\(key)"
        }
        
        return String(key)
    }
    
    /// Get line number from a syntax node
    /// Attempts to get line number from the first argument (string literal) if available,
    /// otherwise falls back to the node position
    private func getLineNumber(from node: FunctionCallExprSyntax) -> Int? {
        // Try to get line number from the first argument (usually the string literal)
        // This is more accurate than using the node position (which points to "Text(")
        if let firstArgument = node.arguments.first,
           let stringLiteral = firstArgument.expression.as(StringLiteralExprSyntax.self) {
            let position = stringLiteral.position
            let location = converter.location(for: position)
            return location.line
        }
        
        // Fallback: use node position if we can't find a string literal
        let position = node.position
        let location = converter.location(for: position)
        return location.line
    }
    
    /// Get start and end character positions (0-based) for a string literal node
    /// Returns positions relative to the string content itself (0 to string.length)
    /// For simple strings: startPosition = 0, endPosition = string.length
    private func getStringPositions(from stringLiteral: StringLiteralExprSyntax) -> (start: Int?, end: Int?) {
        // Extract the full string content to calculate its length
        guard let fullString = extractStringFromLiteral(stringLiteral) else {
            return (start: 0, end: 0) // Empty string
        }
        
        // Positions are relative to the string content itself
        // startPosition is always 0 for the full string
        // endPosition is the length of the string (0-based, so last character is length - 1)
        let stringLength = fullString.utf8.count
        return (start: 0, end: stringLength > 0 ? stringLength - 1 : 0)
    }
    
    /// Get start and end character positions for a string segment (used when splitting interpolated strings)
    /// Returns positions relative to the original full string content (including actual interpolation expressions)
    /// Example: "\(count) image(s) attached" -> segment " image(s) attached" starts after the actual interpolation
    private func getSegmentPositions(from segment: StringSegmentSyntax, in stringLiteral: StringLiteralExprSyntax) -> (start: Int?, end: Int?) {
        // Build the full string progressively using actual source text (including interpolations)
        // and track where each segment starts
        let segments = stringLiteral.segments
        var builtString = ""
        var foundSegment = false
        var segmentStartPos = 0
        let segmentText = segment.content.text
        
        for seg in segments {
            if seg.id == segment.id {
                // Found our segment - record its start position in the built string
                segmentStartPos = builtString.utf8.count
                foundSegment = true
                break
            }
            
            // Add previous segments to built string using actual source text
            if let stringSeg = seg.as(StringSegmentSyntax.self) {
                builtString += stringSeg.content.text
            } else if let exprSeg = seg.as(ExpressionSegmentSyntax.self) {
                // For interpolations, get the actual source text from the file
                // The interpolation appears as \(expression) in source
                let interpolationStart = exprSeg.position.utf8Offset
                let interpolationEnd = exprSeg.endPosition.utf8Offset
                
                // Extract the actual interpolation text from source code
                if let startIndex = sourceCode.utf8.index(sourceCode.utf8.startIndex, offsetBy: interpolationStart, limitedBy: sourceCode.utf8.endIndex),
                   let endIndex = sourceCode.utf8.index(sourceCode.utf8.startIndex, offsetBy: interpolationEnd, limitedBy: sourceCode.utf8.endIndex),
                   let strStart = String.Index(startIndex, within: sourceCode),
                   let strEnd = String.Index(endIndex, within: sourceCode) {
                    let interpolationText = String(sourceCode[strStart..<strEnd])
                    builtString += interpolationText
                } else {
                    // Fallback: use trimmed description if we can't extract from source
                    builtString += exprSeg.trimmedDescription
                }
            }
        }
        
        guard foundSegment else {
            return (start: nil, end: nil)
        }
        
        // Positions are relative to the original full string (with actual interpolations)
        // endPosition is inclusive (last character)
        let segmentEndPos = segmentText.isEmpty ? segmentStartPos : segmentStartPos + segmentText.utf8.count - 1
        
        return (start: segmentStartPos, end: segmentEndPos)
    }
    
    /// Get context from a node (e.g., surrounding function/struct name)
    private func getContext(from node: FunctionCallExprSyntax) -> String? {
        // Walk up the tree to find enclosing declaration
        var current: Syntax? = node.parent
        while let parent = current {
            if let function = parent.as(FunctionDeclSyntax.self) {
                return function.name.text
            }
            if let structDecl = parent.as(StructDeclSyntax.self) {
                return structDecl.name.text
            }
            if let classDecl = parent.as(ClassDeclSyntax.self) {
                return classDecl.name.text
            }
            if let extensionDecl = parent.as(ExtensionDeclSyntax.self) {
                if let extendedType = extensionDecl.extendedType.as(IdentifierTypeSyntax.self) {
                    return extendedType.name.text
                }
            }
            current = parent.parent
        }
        return nil
    }
    
    /// Extract Polyglot hint from the same line as the node
    /// Looks for: //Polyglot: hint text on the same line
    /// Optimized: accepts position directly to avoid expensive Syntax() conversion
    private func extractPolyglotHint(at position: AbsolutePosition) -> String? {
        let location = converter.location(for: position)
        
        // Get the source code lines
        let lines = sourceCode.components(separatedBy: .newlines)
        guard location.line >= 1, location.line <= lines.count else { return nil }
        
        // Check the same line as the node (line - 1 because lines are 0-indexed)
        let lineIndex = location.line - 1
        guard lineIndex >= 0 && lineIndex < lines.count else { return nil }
        let line = lines[lineIndex]
        
        // Look for // Polyglot: comment anywhere on the same line (case-insensitive).
        let searchPatterns = ["// Polyglot:", "//Polyglot:"]

        for pattern in searchPatterns {
            if let range = line.range(of: pattern, options: .caseInsensitive) {
                // Extract everything after the pattern
                guard range.upperBound <= line.endIndex else { continue }
                
                let hintText = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !hintText.isEmpty {
                    return hintText
                }
            }
        }
        
        return nil
    }
}
