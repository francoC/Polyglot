# Quick Start: Test Polyglot in Xcode Build Phases

## Step 1: Build the Polyglot Executable

```bash
cd /path/to/Polyglot

# For faster compilation (recommended):
swift build -c release
# Executable at: .build/release/polyglot

# For debugging (slower due to ArgumentParser's BashCompletionsGenerator):
swift build
# Executable at: .build/debug/polyglot
```

**Note:** Debug builds can be slow because `BashCompletionsGenerator.swift` from ArgumentParser is very slow to compile. Use release builds (`-c release`) for much faster compilation.

## Step 2: Add Local Package to Your Xcode Project

1. Open your iOS project in Xcode
2. **File** → **Add Package Dependencies...**
3. Click **Add Local...**
4. Navigate to: `/path/to/Polyglot`
5. Click **Add Package**

✅ Package should now appear in "Package Dependencies" section

## Step 3: Add Build Phase Script

1. In Xcode: Select your **Project** → Select your **Target** → **Build Phases** tab
2. Click **+** → **New Run Script Phase**
3. Drag the new phase **above** "Compile Sources"
4. Name it: `Extract Localizable Strings`
5. Paste this script:

```bash
#!/bin/bash

# Polyglot String Extraction Build Phase
POLYGLOT_PATH="${HOME}/Desktop/Projects/Polyglot"
POLYGLOT_EXEC="${POLYGLOT_PATH}/.build/release/polyglot"
OUTPUT_FILE="${DERIVED_FILE_DIR}/extracted_strings.json"

# Build if needed
if [ ! -f "${POLYGLOT_EXEC}" ]; then
    echo "🔨 Building Polyglot..."
    cd "${POLYGLOT_PATH}" && swift build -c release
fi

# Extract strings
echo "🔍 Extracting localizable strings..."
"${POLYGLOT_EXEC}" extract \
    --path "${SRCROOT}" \
    --platform ios \
    --output "${OUTPUT_FILE}"

if [ $? -eq 0 ]; then
    echo "✅ Extracted to: ${OUTPUT_FILE}"
else
    echo "❌ Extraction failed"
fi
```

## Step 4: Test It!

1. **Clean Build**: ⌘+Shift+K
2. **Build**: ⌘+B
3. Check build log for extraction messages
4. Find extracted file in: `DerivedData/.../extracted_strings.json`

## What Gets Extracted?

✅ `Text("Hello")` - SwiftUI strings  
✅ `NSLocalizedString("key", comment: "...")` - Foundation localization  
❌ `Text(verbatim: "...")` - Skipped (not localizable)  
❌ `#"raw"#` - Skipped (raw strings)  

## Next Steps

- View extracted JSON to see what was found
- Implement `generate` command to create `.strings` files
- Integrate with your translation workflow

