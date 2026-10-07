# Polyglot

[![CI](https://github.com/francoC/Polyglot/actions/workflows/ci.yml/badge.svg)](https://github.com/francoC/Polyglot/actions/workflows/ci.yml)

A multi-platform localization CLI written in Swift 6. It extracts translatable strings from iOS, Android and Web projects, syncs them with a translation backend, and generates the platform-native resource files.

```
extract → upload → (translate in CRM) → download → generate
```

## Quick start

```bash
swift build -c release
.build/release/polyglot extract ./MyApp --platform ios -o strings.json
.build/release/polyglot generate strings.json -o ./Resources --languages es,fr,de
.build/release/polyglot check strings.json --lproj ./Resources
```

| Command    | What it does |
|------------|--------------|
| `extract`  | Parse a source tree and emit JSON of translatable strings |
| `upload`   | POST extracted strings to a backend (see [`API.md`](API.md)) |
| `download` | Fetch translations, optionally incrementally with `--since` |
| `generate` | Write `.lproj` (`.strings`/`.stringsdict`), `strings.xml`, or i18n JSON |
| `sync`     | Full pipeline in one command, suitable for CI |
| `check`    | Find missing keys and placeholder mismatches; CI-safe exit codes |
| `status`   | Show how many translations are still pending |

Credentials come from `.polyglot.json` (CWD, then `~/.polyglot.json`), CLI flags, or environment variables. For Xcode Build Phase setup see [`docs/BUILD_PHASES_SETUP.md`](docs/BUILD_PHASES_SETUP.md).

## Architecture

```
Sources/
  PolyglotCore/              Shared models (StringKey, TranslationEntry, Placeholder…), no dependencies
  PolyglotExtractor/         Swift/iOS extraction via SwiftSyntax
  PolyglotGenerator/         .strings / .stringsdict writer
  PolyglotAndroid{Extractor,Generator}/
  PolyglotWeb{Extractor,Generator}/
  polyglot/                  CLI (ArgumentParser)
```

Design decisions:

- **Pure core, impure shell.** Extractors map source text to models and generators map models to files. Neither touches the network. Only the CLI layer does I/O, so every module is trivially testable.
- **AST, not regex.** Swift extraction walks a SwiftSyntax tree. It handles `Text("…")`, `NSLocalizedString`, `*localized*` calls, interpolation, and plural patterns. It skips `Text(verbatim:)` and raw strings.
- **Platform-neutral placeholders.** `%@`, `%1$d` and `{name}` are normalized to positional `{N}` markers on the way out and denormalized per platform on the way in, so one translation serves iOS, Android and Web.
- **Stable keys.** Keys are slugified from the base text and prefixed with the Swift context name, so re-extraction doesn't churn backend keys.
- **Translator hints** (`// Polyglot: …`) round-trip through upload and download.
- **Strict concurrency** (Swift 6) throughout.

## Backend

The CLI talks to any server implementing the HTTP contract in [`API.md`](API.md). No server is included in this repository.

## Tests

```bash
swift test
```

## License

MIT
