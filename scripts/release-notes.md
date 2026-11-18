## What's new

@CHANGES@

## Download

**[@ZIP@](@ZIP_URL@)** – universal app (Apple silicon + Intel), macOS 15 or later, English and Slovak.

1. Unzip it and move **Brew GUI.app** to /Applications.
2. Open it. The app is not notarized by Apple, so macOS may refuse to open it. If it does, open
   **System Settings → Privacy & Security** and click **Open Anyway** next to “Brew GUI”, or run:
   `xattr -dr com.apple.quarantine "/Applications/Brew GUI.app"`

Or install it with Homebrew: `brew install --cask furcenzo/tap/brew-gui`

Requires [Homebrew](https://brew.sh).

SHA-256: `@SHA@`
