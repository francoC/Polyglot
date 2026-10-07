# SwiftSyntax Compilation Optimization

SwiftSyntax is a large package (~38,000 lines) that can significantly slow down build times. This document outlines optimizations we've applied and additional options available.

## Optimizations Applied

### 1. Removed Expensive `Syntax()` Conversions
- **Issue**: Wrapping specific syntax node types (e.g., `FunctionCallExprSyntax`) in `Syntax()` was causing compilation slowdowns.
- **Solution**: Changed `extractPolyglotHint(before:)` to accept `AbsolutePosition` directly instead of `Syntax`, eliminating unnecessary type conversions.
- **Impact**: Reduced compile-time overhead when extracting hints from code.

### 2. Cached Regex Patterns
- **Issue**: Recompiling `NSRegularExpression` patterns on every call was slow.
- **Solution**: Moved regex patterns to static cached properties in `PlaceholderExtractor`.
- **Impact**: Significant reduction in placeholder extraction overhead.

### 3. Optimized Type Inference
- **Issue**: Complex closures with nested property access caused slow type inference.
- **Solution**: Added explicit type annotations to `sorted` closures in `Generator.swift`.
- **Impact**: Faster compilation of generator code.

## Additional Optimization Options

### Enable Precompiled SwiftSyntax Binaries (Xcode 16.4+)

Starting with Xcode 16.4, Apple provides precompiled SwiftSyntax binaries that can significantly reduce build times.

#### Option 1: Enable for Command-Line Builds

```bash
swift build -c release --enable-experimental-prebuilts
```

#### Option 2: Enable for Xcode

```bash
defaults write com.apple.dt.Xcode IDEPackageEnablePrebuilts YES
```

Then restart Xcode. This will use precompiled SwiftSyntax binaries when available, avoiding compilation from source.

#### Option 3: Use in Build Scripts

Add `--enable-experimental-prebuilts` to your build commands:

```bash
swift build -c release --enable-experimental-prebuilts
```

### Whole Module Optimization

Swift Package Manager automatically applies whole-module optimization in release builds. For development builds, you can enable it manually by adding build settings, though this is typically not necessary.

### Build Active Architecture Only

For debug builds in Xcode, enable "Build Active Architecture Only" to speed up compilation during development.

## Expected Performance

With these optimizations:
- **Clean build**: Should complete in 2-5 seconds (depending on hardware)
- **Incremental build**: Should complete in <1 second for most changes
- **With precompiled binaries**: Can reduce clean build time by 50-80% if SwiftSyntax needs to be rebuilt

## Monitoring Build Times

To identify specific bottlenecks:

1. **Xcode Build Timeline**: View the build timeline in Xcode to see which modules take the longest
2. **Swift Build with Timing**: Use `swift build --build-tests` and check build logs
3. **Profile Specific Files**: Use Xcode's "Report Navigator" to see per-file compile times

## References

- [SwiftSyntax Build Time Mitigation](https://www.pointfree.co/blog/posts/171-mitigating-swiftsyntax-build-times)
- [Swift Compile Time Optimization](https://www.swiftbysundell.com/articles/improving-swift-compile-times)

