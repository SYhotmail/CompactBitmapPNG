# Repository Guidelines

## Project Structure & Module Organization
`Sources/PNGCompressorPDFVectorCheck/App/` holds the app entry point. `Features/AppFeature/` contains the TCA reducer and `AppView`, `Clients/` wires dependencies, `Services/` contains the PNG/PDF processing engines, `Models/` holds shared domain types, and `Resources/Info.plist` stores bundle metadata. `Tests/PNGCompressorPDFVectorCheckTests/Features/AppFeature/` covers reducer and rendering behavior with Swift Testing, while `UITests/PNGCompressorPDFVectorCheckUITests/Features/AppFeature/` covers macOS UI flows. `Package.swift` supports SwiftPM builds, and `project.yml` generates `PNGCompressorPDFVectorCheck.xcodeproj`.

## Build, Test, and Development Commands
Use SwiftPM for fast iteration:

```bash
swift build
swift test
```

Use Xcode tooling when validating the app target:

```bash
xcodebuild -project PNGCompressorPDFVectorCheck.xcodeproj -scheme PNGCompressorPDFVectorCheck -configuration Debug build
xcodebuild -project PNGCompressorPDFVectorCheck.xcodeproj -scheme PNGCompressorPDFVectorCheck -configuration Debug test
```

If `project.yml` changes, regenerate the project with `xcodegen generate` before opening Xcode.

## Coding Style & Naming Conventions
Follow Swift 6 conventions with 4-space indentation and small, focused types. Use `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and descriptive enum cases such as `vectorOnly` or `rasterOnly`. Prefer Swift concurrency (`async`, `await`, actors) over callback-heavy logic, and keep UI state in TCA `@ObservableState` reducers. Avoid adding dependencies unless the standard Apple frameworks are insufficient.

## Testing Guidelines
Tests use the `Testing` framework, not XCTest. Name tests with sentence-style descriptions via `@Test("...")`, and group related coverage in suites. Add tests for new optimizer branches, PDF detection behavior, and any UI-state regressions. Run `swift test` before committing; run the `xcodebuild ... test` command when app wiring or bundle behavior changes.

## Commit & Pull Request Guidelines
Recent history uses short, imperative subjects, for example `Initial macOS PNG and PDF utility`. Keep commit titles brief, lower noise, and focused on one change. For pull requests, include a concise summary, note any UI-visible behavior changes, list verification commands you ran, and attach screenshots when the SwiftUI interface changes.

## Configuration Notes
The app targets macOS 14+ and Swift tools 6.3. Keep bundle identifiers and `Info.plist` settings aligned across `Package.swift`, `project.yml`, and the generated Xcode project.
