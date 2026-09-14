# Macify FAQ

## Is this safe? Will it break Windows?

Macify is designed to be the safest Windows-to-Mac theme out there:

- **No system files are patched.** Unlike UltraUXThemePatcher-style themes, Macify never
  touches `system32` or theme signature checks, so Windows Updates can't brick you.
- **No admin rights needed.** The installer, bar, dock and tweaks all run as a normal
  user and only write to `HKCU` (your own registry hive) plus `%APPDATA%` / `%LOCALAPPDATA%`.
- **Everything is backed up.** Before changing a single setting, the installer saves your
  original values to `%APPDATA%\Macify\tweaks-backup.json`. `Uninstall.ps1` restores them.
- **It's just scripts.** Every line is PowerShell you can read. No compiled EXEs, no
  obfuscation, no network calls except the optional Extras downloads.

## My antivirus / SmartScreen complains. Is Macify a virus?

Unsigned PowerShell scripts often trigger heuristic warnings simply because they *can*
change settings. Macify is 100% open source — you can read every line before running it.
If SmartScreen appears on `Setup.bat`, that's just because the file came from the
internet: right-click it > Properties > check **Unblock** (or click *More info > Run anyway*).

## Do I need to be an admin?

No. Install, run and uninstall all work as a standard user.

## Windows 10 or 11?

Both, version 1809 and newer. Windows 11 looks the most Mac-like out of the box
(centered taskbar icons, rounded corners). On Windows 10 everything works too.

## How do I uninstall / go back to normal?

Run `Uninstall.ps1` (it's also copied to `%LOCALAPPDATA%\Macify`):

```powershell
powershell -ExecutionPolicy Bypass -File Uninstall.ps1
```

It stops the bar/dock/Spotlight, removes auto-start shortcuts, and restores every
registry setting + your old wallpaper from the backup. Add `-Full` to also delete
your Macify settings.

## Alt+Space doesn't open Spotlight

Another app (e.g. some launchers, remote-desktop tools) may already own that hotkey.
Try **Ctrl+Space**, or click the magnifier in the menu bar. If neither works, check the
log at `%APPDATA%\Macify\logs\macify.log` — Spotlight toasts a warning when hotkey
registration fails.

## The Dock doesn't show my app's real icon

Icons are extracted from the app's `.exe` at runtime. Microsoft Store (UWP) apps don't
expose classic icons the same way, so they get a letter tile. Pin the desktop version
of the app if one exists.

## Can I move the Dock to the side, or resize things?

Today the Dock is bottom-centered (like a real Mac). You can change in
`%APPDATA%\Macify\config.json` (create it, override what you need):

```json
{
  "dock": { "iconSize": 56, "maxSize": 84, "magnify": true, "autohide": true },
  "bar": { "clockFormat": "HH:mm" },
  "theme": "dark"
}
```

Restart Macify after editing (`Stop-Macify.ps1`, then `Start-Macify.ps1`).
Side-positioned docks are on the roadmap.

## Does it slow down my PC?

Each component is a small PowerShell process (~50–80 MB RAM, ~0% CPU idle).
If you want minimum footprint, run only the Dock: `Start-Macify.ps1 -Dock`.

## Multiple monitors?

The bar and Dock live on the primary display (like macOS's menu bar). Multi-monitor
support is on the roadmap.

## Will Windows Update break it?

Updates can't break Macify's approach (no patched files). At worst, a major update
resets a taskbar setting — just re-run `Install.ps1`.

## I found a bug / have an idea

Open an issue with your Windows version (`winver`), the component (bar/dock/Spotlight),
and the last lines of `%APPDATA%\Macify\logs\macify.log`. PRs welcome!
