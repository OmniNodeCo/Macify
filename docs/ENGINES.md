# Macify engines & add-ons

Macify's dock + menu bar can be powered by different **engines**. The native
engine is built in and is the default; third-party engines are opt-in
integrations. Switch anytime without reinstalling.

## Engines

### Native (default)

- Built-in PowerShell + WPF menu bar, dock, Spotlight and Control Center.
- 100% open-source, zero downloads, no admin, fully reversible.
- Best for: everyone — especially if you value safety and reversibility.

### MyDockFinder

- The popular third-party macOS dock + menu bar for Windows (**closed-source**).
- Provides: dock, top menu bar, Launchpad. Window previews, weather icons,
  minimize animations and lots of preferences.
- Macify keeps its native Spotlight running alongside it (complementary — delete
  `Macify Spotlight.lnk` from Startup if you don't want it).
- Official sources **only**:
  - Steam: <https://store.steampowered.com/app/1787090/MyDockFinder/>
  - Official site: <https://www.mydockfinder.com>
- Macify **never auto-downloads it**: the setup wizard finds *your* official
  install (Steam libraries + common paths + file picker), checks the binary's
  digital signature, makes sure the VC++ runtime is present, registers it and
  switches the engine. Switching back to native is one command.

## Switching engines

```powershell
# Guided MyDockFinder setup (finds your official install, safety-checks it)
powershell -ExecutionPolicy Bypass -File tools\Install-MyDockFinder.ps1

# Back to native anytime
powershell -ExecutionPolicy Bypass -File tools\Set-MacifyEngine.ps1 -Engine native

# Re-select MyDockFinder later (uses the registered path)
powershell -ExecutionPolicy Bypass -File tools\Set-MacifyEngine.ps1 -Engine mydockfinder
```

You can also pick the engine during `Install.ps1` (`-Engine native|mydockfinder`
for scripted installs; silent MyDockFinder setup additionally requires
`-AcceptThirdParty`).

How it works: `Set-MacifyEngine` stops every engine, rewrites the Startup
shortcuts for the chosen one, persists the choice in
`%APPDATA%\Macify\config.json` (`engine` + `engines.mydockfinder.path`), and
launches it. `Start-Macify.ps1` respects the saved engine and falls back to
native with a warning if the registered `.exe` ever goes missing.

## Safety notes (please read)

- MyDockFinder is closed-source with mixed public reviews: most users love it,
  but there are reports of antivirus false-positives — and, more importantly,
  **unofficial "cracked / free activated" repacks are a known malware vector**.
  Only ever install it from Steam or mydockfinder.com.
- Macify refuses to run a binary whose signature check reports tampering
  (`HashMismatch`/`NotTrusted`), warns loudly on unsigned builds, and in silent
  mode requires a valid signature.
- Uninstalling Macify does **not** uninstall MyDockFinder (it's your software —
  remove it via Steam / Settings if you want it gone). It does stop it and
  remove Macify's auto-start shortcut for it.

## Add-ons (stack on top of any engine)

### Rainmeter widgets

macOS-style desktop clock + system stats, using your Rainmeter install:

```powershell
powershell -ExecutionPolicy Bypass -File tools\Install-RainmeterWidgets.ps1 [-Silent]
powershell -ExecutionPolicy Bypass -File tools\Install-RainmeterWidgets.ps1 -Remove
```

Rainmeter itself is installed via winget (`Rainmeter.Rainmeter`, open-source);
the skins are Macify's own (`extras/rainmeter/Macify/`) — no third-party skin
downloads. Also offered as part of `tools\Install-Extras.ps1`.

## Files

- `config/engines.json` — the engine registry (ids, what each provides, links).
- `%APPDATA%\Macify\config.json` — your `engine` choice + registered paths.
