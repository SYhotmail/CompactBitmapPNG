# Repository Guidelines

## Project Structure & Module Organization
`Sources/CompactBitmapPNG/App/` holds the app entry point. `Features/AppFeature/` contains the TCA reducer and `AppView`, `Clients/` wires dependencies, `Services/` contains the PNG/PDF processing engines, `Models/` holds shared domain types, and `Resources/` stores `Info.plist` plus the `en`/`ru`/`be` `.lproj` localization tables. `Tests/CompactBitmapPNGTests/Features/AppFeature/` covers reducer and rendering behavior with Swift Testing, while `UITests/CompactBitmapPNGUITests/Features/AppFeature/` covers macOS UI flows. This is an Xcode-only app target — no SwiftPM package — and `project.yml` (XcodeGen) is the source of truth that generates `CompactBitmapPNG.xcodeproj`.

## Build, Test, and Development Commands
Use Xcode tooling to build and test:

```bash
xcodebuild -project CompactBitmapPNG.xcodeproj -scheme CompactBitmapPNG -configuration Debug build
xcodebuild -project CompactBitmapPNG.xcodeproj -scheme CompactBitmapPNG -configuration Debug test
```

If `project.yml` changes, regenerate the project with `xcodegen generate` before opening Xcode.

## Coding Style & Naming Conventions
Follow Swift 6 conventions with 4-space indentation and small, focused types. Use `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and descriptive enum cases such as `vectorOnly` or `rasterOnly`. Prefer Swift concurrency (`async`, `await`, actors) over callback-heavy logic, and keep UI state in TCA `@ObservableState` reducers. Avoid adding dependencies unless the standard Apple frameworks are insufficient.

## Testing Guidelines
Tests use the `Testing` framework, not XCTest. Name tests with sentence-style descriptions via `@Test("...")`, and group related coverage in suites. Add tests for new optimizer branches, PDF detection behavior, and any UI-state regressions. Run the `xcodebuild ... test` command before committing.

## Commit & Pull Request Guidelines
Recent history uses short, imperative subjects, for example `Initial macOS PNG and PDF utility`. Keep commit titles brief, lower noise, and focused on one change. For pull requests, include a concise summary, note any UI-visible behavior changes, list verification commands you ran, and attach screenshots when the SwiftUI interface changes.

## Configuration Notes
The app targets macOS 14+ and Swift 6. Keep bundle identifiers and `Info.plist` settings aligned between `project.yml` and the generated Xcode project.
