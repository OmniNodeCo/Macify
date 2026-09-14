<div align="center">

<img src="assets/logo.png" width="120" alt="Macify logo"/>

# Macify

**Make Windows 10/11 look and feel like macOS — in one click.**

[![CI](https://github.com/OmniNodeCo/Macify/actions/workflows/ci.yml/badge.svg)](https://github.com/OmniNodeCo/Macify/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue)](https://github.com/OmniNodeCo/Macify)
[![PowerShell](https://img.shields.io/badge/powershell-5.1%20(built--in)-5391FE)](https://github.com/OmniNodeCo/Macify)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

No system-file patching · No admin needed · Fully reversible · 100% open source

[Install in 60 seconds](#-install) · [What you get](#-what-you-get) · [Shortcuts](docs/KEYBOARD.md) · [FAQ](docs/FAQ.md)

</div>

---

## ✨ What you get

| | macOS feature | Windows equivalent Macify gives you |
|---|---|---|
| 🍎 | Menu bar | Blurred top bar: ⌘ menu, active-app menus that **actually send shortcuts**, battery, Wi-Fi, clock + calendar |
| 🚀 | Dock | Centered glass Dock with **hover magnification**, running dots, right-click menus, Launchpad, Trash |
| 🔍 | Spotlight | `Alt+Space` launcher: fuzzy app/file search, calculator, power actions, web fallback |
| 🎛 | Control Center | Dark mode, Focus, transparency, brightness/volume sliders, Wi-Fi/Bluetooth shortcuts |
| 🖥 | Fit & finish | macOS-style wallpaper, sounds, accent color, centered taskbar, hidden desktop icons |

**[Try the interactive preview](preview/index.html)** — a clickable mockup of the bar, Dock, Spotlight and Launchpad (runs in any browser, no install).

## 🚀 Install

**Requirements:** Windows 10 (1809+) or 11. That's it — no admin, no Store apps, no downloads.

1. Download the [latest release ZIP](https://github.com/OmniNodeCo/Macify/releases) and unzip it — or clone the repo:
   ```powershell
   git clone https://github.com/OmniNodeCo/Macify.git
   cd Macify
   ```
2. **Double-click `Setup.bat`** and pick *Full install*.
3. Done. Your old settings are backed up automatically.

> If SmartScreen pops up: it's just because the file came from the internet.
> Everything is readable PowerShell — inspect it, then *More info > Run anyway*.

Prefer the terminal?

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1        # interactive
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Silent # defaults, no prompts
```

### Install modes

| Mode | Bar + Dock + Spotlight | Wallpaper | Windows tweaks | Asks questions |
|------|---|---|---|---|
| **Full** (recommended) | ✅ | ✅ | ✅ | a couple |
| Minimal (`-Minimal`) | ✅ | ✅ | ❌ | no |
| Tweaks only | ❌ | ✅ | ✅ | one |
| Extras only | ❌ | ❌ | optional apps/cursors/font | yes |

Optional extras (offered during Full install, or run `tools\Install-Extras.ps1`):
PowerToys, TranslucentTB, Windows Terminal, Flow Launcher, open-source
[macOS cursors](https://github.com/ful1e5/apple_cursor) and the Inter font (an OFL lookalike of San Francisco).

## ⌨️ Everyday use

- **`Alt+Space`** (or `Ctrl+Space`) — Spotlight from anywhere
- **Click 🔍 / 🎛 top-right** — Spotlight / Control Center
- **Right-click the Dock** — magnification + auto-hide options
- **🚀 Launchpad → right-click any app** — *Add to Dock*

Full list: [docs/KEYBOARD.md](docs/KEYBOARD.md)

## ⚙️ Customize

Create `%APPDATA%\Macify\config.json` and override anything from [config/theme.json](config/theme.json):

```json
{
  "theme": "dark",
  "dock": { "iconSize": 56, "maxSize": 84, "magnify": true, "autohide": true },
  "bar": { "clockFormat": "ddd HH:mm" }
}
```

Then restart: run `Stop-Macify.ps1`, then `Start-Macify.ps1`.
(`theme` can be `auto` — follows Windows dark mode — `dark`, or `light`.)

## ↩️ Uninstall (back to stock Windows)

```powershell
powershell -ExecutionPolicy Bypass -File Uninstall.ps1
```

Stops everything, removes auto-start, and **restores every changed setting +
your old wallpaper** from the automatic backup. Add `-Full` to also wipe settings.

## 🛡 Why this one actually works

Most "Windows to Mac" packs break because they patch system theme files
(`UltraUXThemePatcher`), which Windows Update loves to destroy. Macify takes the
boring-reliable route:

- **Pure PowerShell 5.1 + WPF** — preinstalled on every Windows 10/11. Zero
  dependencies for the bar, Dock, Spotlight and Control Center.
- **Current-user only** — every tweak is an `HKCU` registry value. No admin, no
  protected files, Update-proof.
- **Backup-first** — `tools\MacifyTweaks.ps1` snapshots each value (including the
  taskbar binary blob) before touching it.
- **Tested** — CI parses every script on real PowerShell 5.1, runs
  [Pester tests](tests/Macify.Tests.ps1), and structural checks run anywhere via
  `python3 tests/validate.py`.

Honest limitations (see [FAQ](docs/FAQ.md)): bar/Dock live on the primary monitor,
Store-app icons fall back to letter tiles, and window traffic lights aren't skinned
(Windows draws those itself — Windhawk mods are suggested in Extras for the brave).

## 🗂 Project layout

```
Macify/
├── Setup.bat                 # double-click installer
├── Install.ps1 / Uninstall.ps1 / Start-Macify.ps1 / Stop-Macify.ps1
├── src/
│   ├── MacifyLib.ps1         # shared library (blur, hotkeys, icons, safe math…)
│   ├── MacifyBar.ps1         # top menu bar
│   ├── MacifyDock.ps1        # dock + Launchpad + trash
│   ├── MacifySpotlight.ps1   # Alt+Space launcher
│   └── MacifyControlCenter.ps1
├── tools/
│   ├── MacifyTweaks.ps1      # registry tweaks with backup/restore
│   ├── Install-Extras.ps1    # winget apps, cursors, font (optional)
│   └── Build-Release.ps1     # packages the release ZIP (used by release.yml)
├── config/                   # default theme + dock items
├── assets/                   # wallpapers, sounds (generated), icons
├── docs/                     # FAQ, keyboard shortcuts
├── tests/ + .github/         # Pester tests, validator, CI
└── preview/                  # interactive browser mockup
```

## 🤝 Contributing

Bug reports with Windows version + `%APPDATA%\Macify\logs\macify.log` excerpts are
gold. PRs welcome — please keep scripts **PowerShell 5.1-compatible** (CI enforces it)
and side-effect-free on import.

To build a distributable ZIP locally: `powershell -ExecutionPolicy Bypass -File tools\Build-Release.ps1`
(output lands in `dist/`). To cut a release: `git tag v1.0.0; git push origin v1.0.0` —
[.github/workflows/release.yml](.github/workflows/release.yml) runs the tests, builds the
ZIP, and publishes it on the [Releases page](https://github.com/OmniNodeCo/Macify/releases).

## ❤️ Credits & license

- Wallpapers, logo and sounds are original creations for this repo (CC0 — do anything).
- Optional extras belong to their authors: [apple_cursor](https://github.com/ful1e5/apple_cursor)
  (check its license), [Inter](https://rsms.me/inter/) (OFL), PowerToys, TranslucentTB.
- Not affiliated with Apple Inc. macOS look used for inspiration only.

MIT — see [LICENSE](LICENSE).
