# Brew GUI – notes for Claude Code

Native macOS app (SwiftUI, Swift Package Manager, macOS 15+) for managing Homebrew and a Brewfile.
`Sources/BrewCore` = Brewfile parser, process runner, `brew` CLI wrapper (no UI, tested);
`Sources/BrewGUI` = the SwiftUI app. Build: `swift build`, tests: `swift test`,
app bundle: `./scripts/build-app.sh` → `build/Brew GUI.app`.

## Localization – the app is bilingual (English + Slovak)

Every change that adds or changes a user-facing text must keep **both languages** complete.

- **Code contains English only.** The English text is the localization key. Never write Slovak
  (or any other language) into string literals in `Sources/` – the check fails on Slovak diacritics.
- **Slovak goes to** `Sources/BrewGUI/Resources/sk.lproj/Localizable.strings` (key = the English text,
  exactly as in code, including punctuation and `…`). Keep the file sorted alphabetically (case-insensitive).
  `en.lproj` stays empty on purpose.
- Interpolated values become format specifiers in the key: `Text("Uninstall \(name)?")` →
  `"Uninstall %@?"`; `Int` → `%lld`, `Int32` → `%d`, `String` → `%@`. The translation must use the same
  specifiers (use `%1$@`, `%2$@` if the order has to change).
- **Which APIs translate automatically:** SwiftUI initializers that take a *string literal*
  (`Text("…")`, `Button("…")`, `Label`, `Toggle`, `Section`, `TableColumn`, `.help("…")`, `.alert("…")`…)
  use `LocalizedStringKey`. A `String` **variable** passed to them is shown verbatim (not translated).
  - For texts built in code (model, errors, `NSAlert`, `NSSavePanel`, job titles, BrewCore) use
    `String(localized: "…")`.
  - Helper functions/properties that receive or return UI texts should use `LocalizedStringKey`
    (see `SyncView.actionRow`, `PackageInfoView.row`, `SearchView.Scope.title`).
  - Text that must not be translated (package names, paths, command output): pass a `String`
    variable or use `Text(verbatim:)` / `Section("…" as String)`.
- Avoid grammar that depends on the number (Slovak has 3 plural forms): prefer
  `"Selected entries: %lld"` or `"Install Missing (%lld)"` over `"%lld entries selected"`.
- Technical Homebrew terms (formula, cask, tap, Brewfile, `brew …` commands) stay untranslated in Slovak too.
- **Always run** `./scripts/check-localization.sh` after changing texts. It lists every localizable string
  via the compiler and fails on missing translations, mismatched format specifiers, or Slovak in code;
  it warns about unused translations (delete them).
- Enforced by hooks: the Claude Code `Stop` hook (`.claude/settings.json` →
  `scripts/hooks/claude-stop-l10n.sh`) and the git pre-commit hook (`.githooks/pre-commit`,
  enable with `git config core.hooksPath .githooks`).
- To check the UI visually in a given language: build the app, then
  `"build/Brew GUI.app/Contents/MacOS/BrewGUI" -AppleLanguages '(sk)'` (or `'(en)'`).
  `swift run` has no app bundle and therefore always shows English.

## Releases

`./scripts/release.sh <version>` builds a universal (Apple silicon + Intel) app and zips it into
`build/`. `./scripts/release.sh <version> --publish` also tags `v<version>`, pushes the tag and creates
a GitHub Release with the zip; its "What's new" is the `## <version>` section of `CHANGELOG.md`
(the script refuses to publish without it), and it bumps `version`/`sha256` of `Casks/brew-gui.rb` in the
`Furcenzo/homebrew-tap` repository (users install with `brew install --cask furcenzo/tap/brew-gui`). When you make a user-facing change, add a line under
`## Unreleased` in `CHANGELOG.md`; at release time rename that heading to the version. Publishing is public and irreversible – only run `--publish` when the
user explicitly asked for it. The app is ad-hoc signed, not notarized (no Apple Developer ID), so the
release notes and README explain how to open it past Gatekeeper.

## Conventions

- Every source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later` and
  `// Copyright (C) 2026 Furcenzo` (in `Package.swift` after the `swift-tools-version` line).
- README, CLAUDE.md, commit messages and new code comments are in English.
- Bundle ID is `io.github.furcenzo.brewgui`; settings from the old `local.brewgui` are migrated once
  in `AppModel.migrateLegacyDefaults()`.
