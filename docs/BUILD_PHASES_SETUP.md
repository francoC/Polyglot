# Polyglot Build Phases Setup Guide

This guide will walk you through setting up Polyglot to extract strings during your Xcode build process.

## Step 1: Add Local SPM Package to Your Xcode Project

1. **Open your iOS project in Xcode**
   - Navigate to your iOS app project (or create a test project)

2. **Add Package Dependency**
   - In Xcode, go to **File** → **Add Package Dependencies...**
   - Click **Add Local...** button
   - Navigate to: `/path/to/Polyglot`
   - Click **Add Package**

3. **Verify Package Added**
   - In Xcode Project Navigator, you should see:
     - `Package Dependencies` section
     - `Polyglot` package listed

## Step 2: Build the Polyglot Executable

The executable needs to be built so we can reference it in build phases.

### Option A: Build via Xcode (Easier)

1. Open the Polyglot package in Xcode:
   - Double-click `Package.swift` in the Polyglot folder
   - Or: **File** → **Open** → Select `Package.swift`

2. Build the package:
   - Select the `polyglot` scheme (top bar, next to Play button)
   - Press **⌘+B** (Command + B) to build
   - Executable will be at: `.build/debug/polyglot` (or `.build/release/polyglot`)

### Option B: Build via Terminal

```bash
cd /path/to/Polyglot
swift build -c release
# Executable will be at: .build/release/polyglot
```

## Step 3: Locate the Executable Path

The executable path will be:
- **Release build** (recommended, faster): `{POLYGLOT_PATH}/.build/release/polyglot`
- **Debug build** (slower): `{POLYGLOT_PATH}/.build/debug/polyglot`

**Note:** Debug builds are slow due to `BashCompletionsGenerator.swift` from ArgumentParser. Use release builds (`-c release`) for faster compilation.

Where `{POLYGLOT_PATH}` is the absolute path to the Polyglot package.

## Step 4: Create a Test Swift File (Optional)

Create a test Swift file in your iOS project to extract strings from:

```swift
// TestLocalization.swift
import SwiftUI

struct TestView: View {
    var body: some View {
        VStack {
            Text("Hello, World!")
            Text("Welcome to the app")
            Text("Sign In")
        }
    }
}

// Foundation localization
let title = NSLocalizedString("auth.title", comment: "Authentication title")
let message = NSLocalizedString("auth.message", value: "Please sign in", comment: "Auth message")

// Raw string - should be skipped
let rawString = #"This is raw"#

// Verbatim - should be skipped  
Text(verbatim: "Not localizable")
```

## Step 5: Add Build Phase Script

1. **In your iOS Xcode project:**
   - Select your project in the Project Navigator
   - Select your app target
   - Go to **Build Phases** tab
   - Click **+** button → **New Run Script Phase**

2. **Configure the script:**
   - Name it: `Extract Localizable Strings`
   - Move it **before** "Compile Sources" (drag it up)
   - Add this script:

```bash
# Polyglot String Extraction
# This script extracts localizable strings from your Swift source code

# Set paths
POLYGLOT_PATH="${HOME}/Desktop/Projects/Polyglot"
POLYGLOT_EXEC="${POLYGLOT_PATH}/.build/release/polyglot"
SOURCE_DIR="${SRCROOT}"
OUTPUT_DIR="${DERIVED_FILE_DIR}/PolyglotExtracted"
OUTPUT_FILE="${OUTPUT_DIR}/extracted_strings.json"

# Check if polyglot executable exists
if [ ! -f "${POLYGLOT_EXEC}" ]; then
    echo "⚠️  Polyglot executable not found at ${POLYGLOT_EXEC}"
    echo "Building Polyglot in release mode (faster compilation)..."
    cd "${POLYGLOT_PATH}" && swift build -c release
    swift build
    if [ $? -ne 0 ]; then
        echo "❌ Failed to build Polyglot"
        exit 1
    fi
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Run extraction
echo "🔍 Extracting localizable strings from ${SOURCE_DIR}..."
"${POLYGLOT_EXEC}" extract \
    --path "${SOURCE_DIR}" \
    --platform ios \
    --output "${OUTPUT_FILE}"

if [ $? -eq 0 ]; then
    echo "✅ String extraction completed: ${OUTPUT_FILE}"
    echo "📄 Extracted strings saved to: ${OUTPUT_FILE}"
else
    echo "❌ String extraction failed"
    exit 1
fi
```

3. **For Release builds**, change the path:
```bash
POLYGLOT_EXEC="${POLYGLOT_PATH}/.build/release/polyglot"
```

## Step 6: Test the Build Phase

1. **Clean build folder:**
   - Press **⌘+Shift+K** (Product → Clean Build Folder)

2. **Build the project:**
   - Press **⌘+B** (Product → Build)

3. **Check the output:**
   - Look for the extraction messages in the build log
   - Check the extracted file at: `DerivedData/YourProject-*/Build/Intermediates.noindex/PrecompiledHeaders/PolyglotExtracted/extracted_strings.json`

## Step 7: Verify Output

The extracted JSON should look like:

```json
{
  "keys": [
    {
      "key": "hello.world",
      "baseText": "Hello, World!",
      "platform": "ios",
      "filePath": "/path/to/TestLocalization.swift",
      "lineNumber": 5,
      "placeholders": [],
      "isPlural": false,
      "context": "TestView"
    },
    {
      "key": "auth.title",
      "baseText": "auth.title",
      "platform": "ios",
      "filePath": "/path/to/TestLocalization.swift",
      "lineNumber": 15,
      "placeholders": [],
      "isPlural": false,
      "context": null
    }
  ],
  "platform": "ios",
  "extractedAt": "2025-01-20T12:00:00Z"
}
```

## Troubleshooting

### Executable not found
- Make sure you've built the Polyglot package first
- Check the path is correct in the script
- Try absolute path: `/path/to/Polyglot/.build/release/polyglot`
- **Note:** Use `-c release` flag for faster builds (debug builds are slow due to ArgumentParser)

### Build fails
- Check the build log for specific errors
- Make sure SwiftSyntax dependency is resolved
- Verify the source directory path is correct

### No strings extracted
- Verify your Swift files contain `Text()` or `NSLocalizedString()` calls
- Check the source directory path in the script
- Make sure the files have `.swift` extension

## Next Steps

After extraction works:
1. Integrate with your translation backend (upload command)
2. Generate `.strings` files (generate command)
3. Add to Xcode project resources
4. Use `NSLocalizedString()` in your app

