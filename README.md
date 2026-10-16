# Latch Screenshots

Manual GitHub Actions job that:

1. Downloads the **latest Latch release APK** (or builds from `wized2/Latch` if no release)
2. Boots an **Android emulator**
3. Installs Latch, opens key screens
4. Captures PNG screenshots into `screenshots/`
5. Commits them back to this repo

## Run

Actions → **Capture Latch screenshots** → **Run workflow**

## Output

- `screenshots/01_home.png`
- `screenshots/02_settings.png`
- `screenshots/03_settings_scrolled.png`
- `screenshots/04_fab_or_edit.png`

Used by [Latch](https://github.com/wized2/Latch) website and docs.
