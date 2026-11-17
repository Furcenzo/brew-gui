# Changelog

User-facing changes in each release. `scripts/release.sh <version> --publish` copies the section of that
version into the GitHub Release notes, so add a section before publishing.

## Unreleased

## 0.2.0

- **Brewfile stays in sync when you install or uninstall.** Installing a package that isn't in the Brewfile asks whether to add it; uninstalling a package listed in the Brewfile offers to remove it as well. The Brewfile is changed only after `brew` succeeds.
- **Start typing right away in Search Packages** – the search field is focused when the page opens.

## 0.1.0

- First public release: Brewfile table with status, sync (`brew bundle check / install / cleanup / dump`), updates, packages not in the Brewfile, package search with details and a live console.
- English and Slovak user interface.
