# Polyglot — Developer Guide

## Vision

Polyglot is a self-hosted, multi-platform localization suite. The goal is a single system that handles the entire lifecycle of translatable strings across iOS, Android, and Web projects:

1. **Extract** — scan source code and pull out every string that needs translation.
2. **Upload** — push extracted strings to a central CRM/backend that assigns stable unique keys and manages translation state.
3. **Translate** — translations happen inside the CRM (human translators, external service, or AI).
4. **Download** — pull completed translations from the CRM back into the project.
5. **Generate** — produce the platform-native string resource files (`.strings`/`.stringsdict` for iOS, `strings.xml` for Android, `i18n JSON` for Web).

The CLI runs locally or in CI. For iOS it is designed to be wired in as an Xcode Build Phase. The same binary (or sibling binaries) would run in Android and Web pipelines.

## Repository Layout

```
Sources/
  PolyglotCore/       Shared models, enums, protocols — no platform deps
  PolyglotExtractor/  Swift/iOS source parser (SwiftSyntax)
  PolyglotGenerator/  .strings / .stringsdict file writer
  polyglot/           CLI entry point (ArgumentParser)
Tests/
  PolyglotCoreTests/
  PolyglotExtractorTests/
  PolyglotGeneratorTests/
```

## Module Responsibilities

### PolyglotCore
Single source of truth for all shared types. Keep it dependency-free.

Key types:
- `StringKey` — one extractable string: key, base English text, platform, file path, positions, placeholders, context, translator hint.
- `TranslationEntry` — a `StringKey` plus a `[languageCode: Translation]` map.
- `Placeholder` — format specifier metadata (`%@`, `%1$d`, `{name}`, etc.).
- `Platform` — `.ios`, `.android`, `.web`.
- `ExtractedStrings` — output of an extraction run.

### PolyglotExtractor
Parses Swift source with SwiftSyntax. Never touches file I/O beyond reading source text.

Extraction targets:
- `Text("…")` — SwiftUI localizable string.
- `NSLocalizedString("key", comment: "…")` — Foundation.
- Any method call where the member name contains `localized` / `Localized`.

Skipped patterns:
- `Text(verbatim: "…")` — explicitly not localizable.
- Raw strings `#"…"#` — treated as developer-only literals.

String interpolation (`"Hello \(name)"`) and format placeholders (`%@`, `%1$d`, `{name}`) are split into separate extractable segments.

Inline translator hints: `// Polyglot: hint text` on the same line as the call.

### PolyglotGenerator
Writes platform-native resource files.

- `Localizable.strings` — `"key" = "translation";` format, one per `.lproj`.
- `Localizable.stringsdict` — XML plist for plural strings.

Android (`strings.xml`) and Web (i18n JSON) generators live in `PolyglotAndroidGenerator` and `PolyglotWebGenerator`.

### polyglot CLI

| Command   | Status      | Description                                        |
|-----------|-------------|----------------------------------------------------|
| `extract` | Implemented | Parse source dir, output JSON of extracted strings |
| `generate`| Implemented | Read `ExtractedStrings` or `TranslationsFile` JSON, write `.lproj` bundles |
| `upload`  | Implemented | POST extracted JSON to CRM; reads `.polyglot.json` for credentials |
| `download`| Implemented | GET translations from CRM; writes `TranslationsFile` JSON |
| `sync`    | Implemented | Full pipeline: extract → upload → download → generate |
| `check`   | Implemented | Compare extracted keys against translations file or .lproj bundles; CI-safe exit codes |

## CRM Backend (external)

The CRM is the central hub. Responsibilities:
- Receive extracted strings from any platform project.
- Assign a globally unique, stable key per logical string (dedup across platforms if the same string appears in iOS and Android).
- Store translation state per language per key (untranslated / in-review / approved).
- Expose an API for `upload` and `download` CLI commands.
- Surface a UI for translators and project managers.

**The HTTP API contract is fully specified in [`API.md`](API.md).** The server is not part of this repository.

## Platforms

iOS, Android and Web each have their own `Extractor` and `Generator` module; `PolyglotCore` models are platform-agnostic.

## Conventions

- All modules target **macOS 13+**, **Swift 6**, strict concurrency.
- Extractors are pure functions of source text — no network, no disk writes.
- Generators are pure functions of `[TranslationEntry]` — no network, no source parsing.
- The CLI layer owns all I/O (file reads, file writes, HTTP).
- Keys are auto-generated from base text if not explicitly provided (slugified, max 50 chars, prefixed with Swift context name). Do not change the key generation algorithm without considering CRM key stability.
- Translator hints come from `// Polyglot: …` inline comments. Preserve them through upload/download round-trips.

## Known Issues / Next Steps

- Plural handling in `.stringsdict` is placeholder-level only (emits `one`/`other` rules with identical text) — needs real CLDR rule support.
- No CRM server in this repo; only the CLI HTTP client (see `API.md`).
- No Homebrew/binary distribution.
