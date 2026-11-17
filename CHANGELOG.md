# Changelog

User-facing changes in each release. `scripts/release.sh <version> --publish` copies the section of that
version into the GitHub Release notes, so add a section before publishing.

## Unreleased

- **Menu bar icon.** A mug in the menu bar shows the number of available updates; its panel has a quick `brew update`, *Upgrade All*, a search for packages (install them, optionally adding them to the Brewfile) and the apps you installed with Homebrew, ready to launch. With the icon, Brew GUI keeps running in the menu bar when you close its window. Turn it off in *Settings* (⌘,).

## 0.4.2

- Package details in the Brewfile inspector no longer start far below the entry header.

## 0.4.1

- **New app icon** – a mug of beer with a checklist (your Brewfile).

## 0.4.0

- **Automatic `brew update`.** Brew GUI fetches the latest package information when it starts and when you come back to it after it has been in the background for a while (15 minutes by default), so new versions show up under *Updates*. Change the interval or turn it off in *Settings* (⌘,).

## 0.3.1

- **Cask suggestions are more reliable.** A single cask Homebrew refuses to load (for example from a tap you don't trust, or one that was removed) no longer hides the suggestions for other apps in *Not in Brewfile → Apps*.
- Brew GUI can now be installed and updated with Homebrew: `brew install --cask furcenzo/tap/brew-gui`.

## 0.3.0

- **Apps installed outside Homebrew.** *Not in Brewfile → Apps* lists apps in Applications that Homebrew, the App Store or macOS don't manage, shows a matching cask when there is one and lets Homebrew adopt the app (`brew install --cask --adopt`) or reinstall it from the cask.

## 0.2.0

- **Brewfile stays in sync when you install or uninstall.** Installing a package that isn't in the Brewfile asks whether to add it; uninstalling a package listed in the Brewfile offers to remove it as well. The Brewfile is changed only after `brew` succeeds.
- **Start typing right away in Search Packages** – the search field is focused when the page opens.

## 0.1.0

- First public release: Brewfile table with status, sync (`brew bundle check / install / cleanup / dump`), updates, packages not in the Brewfile, package search with details and a live console.
- English and Slovak user interface.
