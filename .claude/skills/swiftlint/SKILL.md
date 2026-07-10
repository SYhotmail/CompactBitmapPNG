---
name: swiftlint
description: Lint and auto-fix Swift source in this repo with SwiftLint. Use whenever Swift files under Sources/, Tests/, or UITests/ are added or edited, before reporting a Swift change as complete, or when the user asks to lint/clean up Swift style.
---

# SwiftLint in CompactBitmapPNG

This repo has SwiftLint wired in two places:

- `.swiftlint.yml` at the repo root — the rule configuration.
- An Xcode "SwiftLint" run-script build phase on the `CompactBitmapPNG` target (defined in `project.yml`, regenerate with `xcodegen generate` after editing) — runs on every build and surfaces warnings inline in Xcode.

## Running it

Lint the whole repo (respects `.swiftlint.yml` excludes: `.build`, `.swiftpm`, `CompactBitmapPNG.xcodeproj`):

```bash
swiftlint lint --quiet
```

Lint only what changed:

```bash
swiftlint lint --quiet $(git diff --name-only --diff-filter=ACMR -- '*.swift')
```

Auto-fix the mechanical violations (whitespace, import sorting, shorthand sugar, etc.):

```bash
swiftlint --fix --quiet
```

`--fix` only handles rules that are safely auto-correctable; re-run `swiftlint lint` afterward to see what's left. If `swiftlint` isn't on `PATH`, install it with `brew install swiftlint` — the Xcode build phase already tolerates it being absent (prints a warning instead of failing).

## Workflow for this repo

1. After editing or adding Swift files, run `swiftlint lint --quiet` scoped to those files.
2. Run `swiftlint --fix` for mechanical fixes, then re-lint to confirm they're gone.
3. For violations that aren't auto-fixable (`file_length`, `type_body_length`, `cyclomatic_complexity`, `identifier_name`, `nesting`, `for_where`, etc.), fix by hand, matching the existing style in `CLAUDE.md`: 4-space indentation, `UpperCamelCase` types, `lowerCamelCase` members, descriptive enum cases.
4. Don't silence a violation by editing `.swiftlint.yml` unless the rule is actually wrong for this codebase — prefer fixing the code. If a rule genuinely doesn't fit, ask before changing the shared config, since it affects every contributor's build.
5. A few pre-existing violations are tracked as lint debt (e.g. `AppView.swift` currently exceeds `file_length`); don't feel obligated to fix unrelated debt while making an unrelated change, but don't add to it either.

## Adjusting rules

Rule thresholds (line length, function/type/file length, cyclomatic complexity, etc.) live in `.swiftlint.yml`. `opt_in_rules` lists rules that are off by default in SwiftLint but enabled here. Changes to this file affect every build via the Xcode run-script phase — no `xcodegen generate` needed for `.swiftlint.yml` edits alone, only for changes to `project.yml` itself.
