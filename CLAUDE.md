# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A macOS SwiftUI app with two independent workflows over user-dropped files:

- **PNG optimization**: lossless re-encode (with optional lossy adaptive color quantization) that only writes an output file if it's smaller than the original.
- **PDF vector check**: scans PDF content streams to classify pages as vector/text, raster, mixed, or empty. Text drawing operators count as "vector" content since text is stored as drawing instructions, not a raster image.

## Build, Test, and Development Commands

This is an Xcode-only app target — there is no SwiftPM package/executable here, only `project.yml` (the XcodeGen source of truth) and the generated `.xcodeproj`.

```bash
xcodebuild -project PNGCompressorPDFVectorCheck.xcodeproj -scheme PNGCompressorPDFVectorCheck -configuration Debug build
xcodebuild -project PNGCompressorPDFVectorCheck.xcodeproj -scheme PNGCompressorPDFVectorCheck -configuration Debug test
```

Run a single test (Swift Testing, not XCTest):

```bash
xcodebuild -project PNGCompressorPDFVectorCheck.xcodeproj -scheme PNGCompressorPDFVectorCheck -configuration Debug test -only-testing:PNGCompressorPDFVectorCheckTests/<TestName-or-SuiteName>
```

If `project.yml` changes, regenerate the Xcode project before opening it: `xcodegen generate`.

## Architecture

Built with **The Composable Architecture (TCA)** on Swift 6 strict concurrency. Data flows one way through a single reducer:

- `Features/AppFeature/AppFeature.swift` — the one `@Reducer`/`State`/`Action` for the whole app. All UI state (results, toggles, compression settings, processing status) lives here. `processURLs` kicks off an effect that discovers files, sends `preparationFinished` immediately with a summary, then races PNG and PDF processing concurrently (`async let`) and reports both back in a single `processingFinished` action. Effects are cancellable (`CancelID.processing`) so a new drop supersedes an in-flight run.
- `Features/AppFeature/AppView.swift` — SwiftUI view bound to the store; drag-and-drop / file-picker intake lives here.
- `Clients/ProcessingClient.swift` — a TCA `@Dependency` wrapping `ProcessingPipeline` as three async closures (`discoverSupportedFiles`, `processPNGs`, `processPDFs`). This is the seam for testing: `testValue` returns empty results with no I/O, so reducer tests never touch the filesystem.
- `Services/ProcessingPipeline.swift` — actor that does the real filesystem work: recursively enumerates folders, classifies files by extension, and fans work out per-file via `withTaskGroup`, preserving input order in the returned results (each result carries its original index, then results are re-assembled in a `nil`-padded array).
- `Services/PNGOptimizer.swift` — pure, static, no dependency on TCA. Builds one or more `PNGCompressionCandidate`s (lossless re-encode, optionally adaptive-quantized), picks the smallest one that beats the original, and writes it next to the source as `<name>-optimized.png`. Quantization is a custom bucketed-palette nearest-color algorithm (no external image library).
- `Services/PDFVectorAnalyzer.swift` — pure, static. Uses low-level `CGPDFScanner`/`CGPDFOperatorTable` callbacks (C-style, via `Unmanaged`-passed `PageScanState` context) to detect vector-drawing, text, and image-painting operators per page, then aggregates per-page state across the whole document. `Do` operator handling additionally inspects the page's `XObject` resources to distinguish image XObjects (raster) from form XObjects (vector).
- `Models/Models.swift` — all shared value types (`PNGCompressionResult`, `PDFAnalysisResult`, `ProcessingState`, `IntakeSummary`, etc.), each `Sendable`/`Equatable` for use across actor and reducer boundaries.

When adding a new file-processing capability, the pattern to follow is: pure `Services/` type → wired into `ProcessingPipeline` → exposed as a closure on `ProcessingClient` (with a no-op `testValue`) → consumed from `AppFeature`'s effects.

### Testing

- Reducer/state tests use TCA's `TestStore` against `AppFeature`, with `processingClient` overridden per test (see `Tests/.../AppFeatureTests.swift`) — no real files needed.
- Tests use the **Swift Testing** framework (`@Test("description")`, `#expect`), not XCTest.
- `UITests/.../AppFeatureUITests.swift` drives the real app process; `PNGCompressorPDFVectorCheckApp.swift` reads launch arguments (`UITestEnableQuantization`, `UITestDisablePDFCheck`) to preset state for these UI tests.

## Coding Style

- Swift 6, 4-space indentation, `UpperCamelCase` types / `lowerCamelCase` members, descriptive enum cases (`vectorOnly`, `rasterOnly`).
- Prefer Swift concurrency (`async`/`await`, actors) over callbacks.
- Keep UI state inside the TCA `@ObservableState` reducer, not in view-local `@State`, except for pure view mechanics.
- Avoid adding dependencies beyond Apple frameworks and the existing `swift-composable-architecture` family unless clearly necessary.

## Configuration Notes

Targets macOS 14+, Swift 6. Keep bundle identifiers and `Info.plist` settings aligned between `project.yml` and the generated Xcode project — `project.yml` is the source of truth and must be regenerated with `xcodegen generate` after edits.
