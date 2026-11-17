# Brew GUI

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A native macOS app (SwiftUI) for managing Homebrew packages and your Brewfile.
The user interface is currently in Slovak.

## Features

- **Brewfile** – a table of every `tap` / `brew` / `cask` / `mas` / … entry with its status
  (installed, missing, outdated), description and version; filtering by type, search,
  duplicate highlighting. Add / edit / remove entries, sort the file, plain-text mode.
  Comments, blank lines and unrecognized Ruby code are preserved untouched when saving.
- **Sync** – `brew bundle check`, `install` (optionally without upgrading),
  `cleanup` with a preview before anything is uninstalled, `dump` to a new file.
- **Updates** – `brew outdated` (including `--greedy`), upgrade selected packages or everything, `brew update`.
- **Not in Brewfile** – packages, taps and App Store apps installed outside your Brewfile; add them with one click.
- **Search** – instant search across all formulae and casks with details (`brew info`).
- **Console** – live output of every operation, with the option to stop it, and a history.

Brewfile changes are saved automatically; undo the last edit with ⌘Z (Edit → Undo).
Before the first save in each session, the original file is backed up to `~/Library/Application Support/BrewGUI/Backups`.
If another program changes the Brewfile in the meantime, the app asks whether to reload it or overwrite it.
The state of installed packages is refreshed every time you switch to the app (at most once every 10 s), after each
operation, and manually with ⌘R – so it also picks up a `brew install` run in Terminal.
If a cask needs an administrator password, a system dialog is shown (via `SUDO_ASKPASS`).

## Requirements

- macOS 15 or later
- [Homebrew](https://brew.sh)
- Swift 6 toolchain (Xcode 16 or later) to build from source

## Running

```bash
swift run BrewGUI
```

Build a standalone app into `build/Brew GUI.app`:

```bash
./scripts/build-app.sh
```

Tests:

```bash
swift test
```

## Project structure

- `Sources/BrewCore` – Brewfile parser, process runner, wrapper around the `brew` CLI (no UI, tested).
- `Sources/BrewGUI` – the SwiftUI app (`AppModel` + screens).
- `Tests/BrewCoreTests` – tests for the parser and the process runner.

## Debugging

`BREWGUI_SNAPSHOT=/path.png [BREWGUI_PAGE=sync|outdated|unmanaged|search|missing|casks|check]`
saves an image of the window once loaded and quits the app (useful without screen recording permission).
`BREWGUI_FILE=/path/to/Brewfile` opens a different file, `BREWGUI_DEBUG_ADD=name [BREWGUI_DEBUG_UNDO=1]`
simulates adding an entry (and ⌘Z) – only test this on a copy of your Brewfile.

## License

Copyright (C) 2026 Furcenzo

This program is free software: you can redistribute it and/or modify it under the terms of the
[GNU General Public License](LICENSE) as published by the Free Software Foundation, either version 3
of the License, or (at your option) any later version (`GPL-3.0-or-later`).
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY.
See the [LICENSE](LICENSE) file for the full text.
