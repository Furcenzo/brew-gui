# Brew GUI – notes for Claude Code

Native macOS app (SwiftUI, Swift Package Manager, macOS 15+) for managing Homebrew and a Brewfile.
`Sources/BrewCore` = Brewfile parser, process runner, `brew` CLI wrapper (no UI, tested);
`Sources/BrewGUI` = the SwiftUI app. Build: `swift build`, tests: `swift test`,
app bundle: `./scripts/build-app.sh` → `build/Brew GUI.app`, build + restart: `./scripts/run.sh [sk|en]`.

App icon: drawn by `scripts/icon/AppIcon.swift`; `./scripts/make-icon.sh` regenerates `scripts/icon/AppIcon.png`
and `Sources/BrewGUI/Resources/AppIcon.icns` (commit both).

## Shared scripts (mac-app-kit)

`scripts/` (except `scripts/icon/`, `scripts/screenshots.sh` and `scripts/release-notes.md`), `.githooks/` and
`.claude/settings.json` are copies from mac-app-kit (`../mac-app-kit`, shared with Lineup and the author's other
Mac apps). Don't edit them here: change them in the kit and run its `./sync.sh` (`./sync.sh --check` lists
differences). Brew GUI's settings for them (name, bundle ID, repository, cask, dev.furian.sk slug…) are in `app.conf`.
**Development builds are "Brew GUI Dev"** (bundle ID `io.github.furcenzo.brewgui.dev`, `CHANNEL=dev`, the default
of `build-app.sh`); only `release.sh` and `install-local.sh` build the real `io.github.furcenzo.brewgui`
(`CHANNEL=release`) and they delete their staging copies afterwards. Reason: the login item ("Open at login"),
Spotlight and LaunchServices pick an app by bundle ID, so a second copy with the real ID could stand in for the
installed app. "Brew GUI Dev" has its own settings (last Brewfile, window size…) and its own login item;
`./scripts/run.sh` quits only the dev build, the installed Brew GUI keeps running next to it.
`build-app.sh` signs with a local
"Brew GUI Local Dev" certificate when it exists (created once by the user with `./scripts/setup-dev-signing.sh`,
which needs the login password – never run it for the user), otherwise ad-hoc with a warning.

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

`./scripts/release.sh <version>` builds a universal (Apple silicon + Intel), ad-hoc signed app into
`build/release/` and zips it into `build/`. `./scripts/release.sh <version> --publish` also tags `v<version>`, pushes the tag and creates
a GitHub Release with the zip; its "What's new" is the `## <version>` section of `CHANGELOG.md`
(the script refuses to publish without it), the download instructions come from `scripts/release-notes.md`, and it bumps `version`/`sha256` of `Casks/brew-gui.rb` in the
`Furcenzo/homebrew-tap` repository (users install with `brew install --cask furcenzo/tap/brew-gui`). When you make a user-facing change, add a line under
`## Unreleased` in `CHANGELOG.md`; at release time rename that heading to the version. Publishing is public and irreversible – only run `--publish` when the
user explicitly asked for it. The app is ad-hoc signed, not notarized (no Apple Developer ID), so the
release notes and README explain how to open it past Gatekeeper.
At the end, `--publish` also runs `~/Projects/Private/dev.furian.sk/scripts/update-site.sh brew-gui` (if that
repository is on this Mac): it copies a changed icon or screenshots to the showroom site https://dev.furian.sk and
deploys it. Version and download link there follow the latest GitHub Release by themselves. New or renamed
screenshots and changed feature texts have to be edited in that site's `public/index.html` by hand.

## Conventions

- Every source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later` and
  `// Copyright (C) 2026 Furcenzo` (in `Package.swift` after the `swift-tools-version` line).
- README, CLAUDE.md, commit messages and new code comments are in English.
- Bundle ID is `io.github.furcenzo.brewgui`; settings from the old `local.brewgui` are migrated once
  in `AppModel.migrateLegacyDefaults()`.
