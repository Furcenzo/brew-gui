# Brew GUI

Natívna macOS aplikácia (SwiftUI) na správu Homebrew a Brewfile.

## Čo vie

- **Brewfile** – tabuľka všetkých `tap` / `brew` / `cask` / `mas` / … záznamov so stavom
  (nainštalované, chýba, zastarané), popisom a verziou; filter podľa typu, vyhľadávanie,
  označenie duplicít. Pridanie / úprava / odstránenie položky, zoradenie súboru, textový režim.
  Komentáre, prázdne riadky aj neznámy Ruby kód ostávajú pri ukladaní nedotknuté.
- **Synchronizácia** – `brew bundle check`, `install` (voliteľne bez upgradu),
  `cleanup` s náhľadom pred odinštalovaním, `dump` do nového súboru.
- **Aktualizácie** – `brew outdated` (aj `--greedy`), upgrade vybraných alebo všetkého, `brew update`.
- **Mimo Brewfile** – balíky, tapy a App Store aplikácie nainštalované mimo Brewfile; jedným klikom ich pridáte.
- **Hľadanie** – okamžité hľadanie vo všetkých formulae a casks s detailom (`brew info`).
- **Konzola** – živý výstup každej operácie, možnosť zastaviť, história.

Zmeny v Brewfile sa ukladajú automaticky, poslednú úpravu vrátite cez ⌘Z (Úpravy → Späť).
Pred prvým uložením v každej session sa pôvodný súbor zálohuje do `~/Library/Application Support/BrewGUI/Backups`.
Ak Brewfile medzitým zmení iný program, aplikácia sa spýta, či ho načítať, alebo prepísať.
Ak cask potrebuje heslo správcu, zobrazí sa systémový dialóg (cez `SUDO_ASKPASS`).

## Spustenie

```bash
swift run BrewGUI
```

Zostavenie samostatnej aplikácie do `build/Brew GUI.app`:

```bash
./scripts/build-app.sh
```

Testy:

```bash
swift test
```

## Štruktúra

- `Sources/BrewCore` – parser Brewfile, spúšťanie procesov, obal nad `brew` CLI (bez UI, testované).
- `Sources/BrewGUI` – SwiftUI aplikácia (`AppModel` + obrazovky).
- `Tests/BrewCoreTests` – testy parsera a spúšťania procesov.

## Ladenie

`BREWGUI_SNAPSHOT=/cesta.png [BREWGUI_PAGE=sync|outdated|unmanaged|search|missing|casks|check]`
uloží po načítaní obrázok okna a aplikáciu ukončí (užitočné bez povolenia na nahrávanie obrazovky).
`BREWGUI_FILE=/cesta/Brewfile` otvorí iný súbor, `BREWGUI_DEBUG_ADD=nazov [BREWGUI_DEBUG_UNDO=1]`
nasimuluje pridanie položky (a ⌘Z) – testujte len na kópii Brewfile.
