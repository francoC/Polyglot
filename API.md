# Polyglot API Contract

REST API between the Polyglot CLI and the Polyglot CRM backend. All types reference the Swift models in `Sources/PolyglotCore/PolyglotCore.swift` — those are the canonical definitions.

---

## Authentication

Every request must include:

```
X-Polyglot-API-Key: <apiKey>
```

API keys are project-scoped. A key issued for `proj_abc` cannot access `proj_xyz`.

---

## Configuration (CLI side)

The CLI reads credentials from `.polyglot.json` in the working directory, falling back to `~/.polyglot.json`:

```json
{
  "apiURL": "https://api.polyglot.example.com",
  "apiKey": "pk_live_...",
  "projectId": "proj_abc123"
}
```

Individual fields can be overridden per-command with `--api-url`, `--api-key`, `--project-id`. Never commit a file containing a live API key — use `.gitignore` and inject secrets via environment variables in CI.

---

## Versioning

All endpoints are prefixed with `/v1/`. Breaking changes get a new version prefix; old versions are supported for at least one major release cycle.

---

## Endpoints

### 1. Upload Strings

```
POST /v1/projects/{projectId}/strings
Content-Type: application/json
X-Polyglot-API-Key: {apiKey}
```

Uploads the full set of extracted strings for a platform. The CRM performs deduplication across platforms using base text + key similarity. It assigns globally stable keys and returns a mapping for any key that differs from the locally generated one.

**Request body** — `ExtractedStrings`:

```json
{
  "platform": "ios",
  "extractedAt": "2024-01-15T10:00:00Z",
  "projectId": "proj_abc123",
  "keys": [
    {
      "key": "auth.login.title",
      "baseText": "Sign In",
      "platform": "ios",
      "filePath": "/App/Login/LoginView.swift",
      "positions": [{ "startPosition": 0, "endPosition": 7, "lineNumber": 14 }],
      "placeholders": [],
      "pluralForms": null,
      "context": "LoginView",
      "hint": "Button label on the login screen"
    },
    {
      "key": "items.count",
      "baseText": "items.count",
      "platform": "ios",
      "filePath": "/App/Items/ItemsView.swift",
      "positions": [],
      "placeholders": [{ "format": "%d", "type": "integer", "position": 0 }],
      "pluralForms": { "one": "%d item", "other": "%d items" },
      "context": "ItemsView",
      "hint": null
    }
  ]
}
```

**Response 200** — `UploadResponse`:

```json
{
  "uploadId": "upl_xyz789",
  "projectId": "proj_abc123",
  "stats": {
    "new": 10,
    "updated": 5,
    "unchanged": 120
  },
  "keyMappings": {
    "items.my.list.count": "items.count"
  }
}
```

`keyMappings` is empty when all local keys match the CRM keys. When non-empty, re-run `polyglot extract` on the source project to pick up the canonical keys.

---

### 2. Download Translations

```
GET /v1/projects/{projectId}/translations
X-Polyglot-API-Key: {apiKey}
```

Returns approved translations for all strings in the project.

**Query parameters:**

| Parameter  | Type   | Default    | Description |
|------------|--------|------------|-------------|
| `languages`| string | all        | Comma-separated BCP 47 codes, e.g. `en,es,fr,ru` |
| `platform` | string | all        | `ios`, `android`, or `web` |
| `since`    | string | (none)     | ISO8601 datetime — returns only entries updated after this timestamp (incremental sync) |

**Response 200** — `TranslationsFile`:

```json
{
  "projectId": "proj_abc123",
  "downloadedAt": "2024-01-15T11:00:00Z",
  "entries": [
    {
      "key": {
        "key": "auth.login.title",
        "baseText": "Sign In",
        "platform": "ios",
        "filePath": "/App/Login/LoginView.swift",
        "positions": [],
        "placeholders": [],
        "pluralForms": null,
        "context": "LoginView",
        "hint": "Button label on the login screen"
      },
      "translations": {
        "en": {
          "languageCode": "en",
          "text": "Sign In",
          "approved": true,
          "pluralForms": null
        },
        "es": {
          "languageCode": "es",
          "text": "Iniciar sesión",
          "approved": true,
          "pluralForms": null
        },
        "ru": {
          "languageCode": "ru",
          "text": "Войти",
          "approved": true,
          "pluralForms": null
        }
      }
    },
    {
      "key": {
        "key": "items.count",
        "baseText": "items.count",
        "platform": "ios",
        "filePath": "/App/Items/ItemsView.swift",
        "positions": [],
        "placeholders": [{ "format": "%d", "type": "integer", "position": 0 }],
        "pluralForms": { "one": "%d item", "other": "%d items" },
        "context": "ItemsView",
        "hint": null
      },
      "translations": {
        "en": {
          "languageCode": "en",
          "text": "%d items",
          "approved": true,
          "pluralForms": { "one": "%d item", "other": "%d items" }
        },
        "ru": {
          "languageCode": "ru",
          "text": "%d предметов",
          "approved": true,
          "pluralForms": {
            "one": "%d предмет",
            "few": "%d предмета",
            "many": "%d предметов",
            "other": "%d предмета"
          }
        }
      }
    }
  ]
}
```

---

## Error Responses

All errors return JSON with `error` (human-readable) and `code` (machine-readable):

```json
{
  "error": "Project not found",
  "code": "PROJECT_NOT_FOUND"
}
```

| HTTP Status | Code                    | Meaning |
|-------------|-------------------------|---------|
| 400         | `INVALID_PAYLOAD`       | Malformed JSON or missing required field |
| 400         | `INVALID_PLATFORM`      | Unrecognized platform value |
| 401         | `UNAUTHORIZED`          | Missing or invalid API key |
| 403         | `FORBIDDEN`             | API key does not have access to this project |
| 404         | `PROJECT_NOT_FOUND`     | Project ID does not exist |
| 422         | `UNPROCESSABLE`         | Valid JSON but semantic error |
| 429         | `RATE_LIMITED`          | Too many requests — back off and retry |
| 500         | `INTERNAL_ERROR`        | Server fault |

---

## Data Type Reference

All types are Codable Swift structs in `Sources/PolyglotCore/PolyglotCore.swift`. The JSON shapes above are derived directly from those struct definitions.

| Type               | Description |
|--------------------|-------------|
| `StringKey`        | One extractable string: key, base text, platform, file path, positions, placeholders, plural forms, context, hint |
| `Placeholder`      | Format specifier: `format` (`%@`, `%d`), `type`, `position`, `order` |
| `PluralCategory`   | CLDR enum: `zero`, `one`, `two`, `few`, `many`, `other` |
| `Platform`         | `ios`, `android`, `web` |
| `Translation`      | Translated text for one language: `languageCode`, `text`, `approved`, `pluralForms` |
| `TranslationEntry` | A `StringKey` + `[languageCode: Translation]` map |
| `ExtractedStrings` | Upload payload: `keys`, `platform`, `extractedAt`, `projectId` |
| `UploadResponse`   | Upload result: `uploadId`, `projectId`, `stats`, `keyMappings` |
| `TranslationsFile` | Download payload: `projectId`, `downloadedAt`, `entries` |

---

## Plural Forms

Plural strings use CLDR categories. The CLI determines required categories per language via `Generator.requiredCategories(for:)`. The CRM must validate that translations for plural keys cover all required categories for their language before marking them `approved: true`.

CLDR category requirements by language family:

| Language(s)                             | Required categories |
|-----------------------------------------|---------------------|
| Arabic (`ar`)                           | zero, one, two, few, many, other |
| Hebrew (`he`)                           | one, two, many, other |
| Russian, Ukrainian, Polish, Czech, etc. | one, few, many, other |
| Chinese, Japanese, Korean, Thai, etc.   | other |
| All others (English, Spanish, etc.)     | one, other |

---

## Full CLI Workflow

```
# 1. Extract strings from source
polyglot extract ./MyApp --output extracted.json

# 2. Upload to CRM (assigns stable keys, queues for translation)
polyglot upload extracted.json

# 3. Download approved translations
polyglot download --languages en,es,fr,ru --output translations.json

# 4. Generate .lproj bundles
polyglot generate translations.json --output ./MyApp/Localizations

# 5. Validate (run in CI before merging)
polyglot check extracted.json \
  --translations translations.json \
  --languages es,fr,ru \
  --strict

# Or check generated bundles directly
polyglot check extracted.json \
  --bundle-dir ./MyApp/Localizations \
  --languages es,fr,ru
```

One-shot sync (steps 1–4):

```
polyglot sync ./MyApp --languages en,es,fr,ru --output ./MyApp/Localizations
```
