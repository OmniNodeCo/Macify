# Macify keyboard shortcuts

Macify doesn't steal your Windows shortcuts — it adds Mac-style ones on top.

## Spotlight (`MacifySpotlight.ps1`)

| Keys | Action |
|------|--------|
| `Alt+Space` or `Ctrl+Space` | Show / hide Spotlight (from anywhere) |
| `Down` / `Up` | Move through results |
| `Enter` | Open selected result (copies calculator answers) |
| `Esc` | Dismiss Spotlight |

Spotlight understands app names (fuzzy), file names on Desktop/Documents/Downloads,
math like `(12+7)*3`, power actions (`sleep`, `shut down`, `empty trash`...),
and falls back to a Google search.

Change the hotkeys in `%APPDATA%\Macify\config.json`:

```json
{ "spotlight": { "hotkeys": ["Alt+Space"] } }
```

Supported values: `"Alt+Space"`, `"Ctrl+Space"` (pick one or both).

## Menu-bar menus

The **File / Edit / View / Window / Help** menus send the equivalent Windows
shortcuts to the active app (`Ctrl+N`, `Ctrl+S`, `Ctrl+C`, `F11`, ...), so they
work in almost every program.

The window underneath keeps focus while you click the bar (macOS-style
click-through), so shortcuts land in the right place.

## Dock

| Action | How |
|--------|-----|
| Open app | Click its icon |
| Options (Quit, Remove...) | Right-click its icon |
| Dock options (magnification, auto-hide) | Right-click empty Dock area |
| Launchpad | Click the 🚀 icon (or right-click any app there to pin it) |
| Trash | Click 🗑 to open, right-click to empty |

## macOS muscle memory on a Windows keyboard

| Mac | Windows equivalent |
|-----|--------------------|
| `Cmd+Space` | `Alt+Space` (Spotlight) |
| `Cmd+Q` | `Alt+F4` |
| `Cmd+W` | `Ctrl+W` |
| `Cmd+Tab` | `Alt+Tab` |
| `Cmd+,` (Settings) | `Win+I` |

Want the physical keys swapped too (Alt ⇄ Win like a real Mac keyboard)?
Install PowerToys (offered by `tools\Install-Extras.ps1`) and remap them in
*Keyboard Manager* — no reboot, reversible in one click.
