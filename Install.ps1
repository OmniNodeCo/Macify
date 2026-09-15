# Install.ps1 - Macify one-click installer. No admin rights needed.
#
#   Double-click Setup.bat, or run:
#     powershell -ExecutionPolicy Bypass -File .\Install.ps1
#
# Flags: -Silent (defaults, no prompts)  -Minimal (bar+dock only)  -NoTweaks  -NoStartup
#        -Engine native|mydockfinder  (-AcceptThirdParty required for silent third-party setup)

param(
  [switch]$Silent,
  [switch]$Minimal,
  [switch]$NoTweaks,
  [switch]$NoStartup,
  [ValidateSet('native', 'mydockfinder')][string]$Engine = 'native',
  [switch]$AcceptThirdParty,
  [string]$InstallPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
. (Join-Path $repoRoot 'src\MacifyLib.ps1')

function Write-Banner {
  Write-Host ''
  Write-Host '  __  __            _  __       ' -ForegroundColor Magenta
  Write-Host ' |  \/  | __ _  ___(_)/ _|_   _ ' -ForegroundColor Magenta
  Write-Host ' | |\/| |/ _` |/ __| | |_| | | |' -ForegroundColor Magenta
  Write-Host ' | |  | | (_| | (__| |  _| |_| |' -ForegroundColor Magenta
  Write-Host ' |_|  |_|\__,_|\___|_|_|  \__, |' -ForegroundColor Magenta
  Write-Host '                          |___/ ' -ForegroundColor Magenta
  Write-Host '  macOS look for Windows 10/11 - free, open-source, reversible' -ForegroundColor Gray
  Write-Host ''
}

function Copy-MacifyFiles {
  param([string]$Dest)
  $destResolved = ''
  try { $destResolved = (Resolve-Path $Dest -ErrorAction Stop).Path } catch { }
  if ((Resolve-Path $repoRoot).Path.TrimEnd('\') -eq $destResolved.TrimEnd('\')) {
    Write-Host 'Already running from the install folder - skipping file copy.' -ForegroundColor Gray
    return $Dest
  }
  Write-Host ("Installing Macify files to {0} ..." -f $Dest) -ForegroundColor Cyan
  foreach ($d in @('src', 'config', 'assets', 'tools', 'extras')) {
    $from = Join-Path $repoRoot $d
    $to = Join-Path $Dest $d
    if (Test-Path $from) {
      New-Item -ItemType Directory -Path $to -Force | Out-Null
      Copy-Item (Join-Path $from '*') -Destination $to -Recurse -Force
    }
  }
  Copy-Item (Join-Path $repoRoot 'Start-Macify.ps1') -Destination $Dest -Force -ErrorAction SilentlyContinue
  Copy-Item (Join-Path $repoRoot 'Stop-Macify.ps1') -Destination $Dest -Force -ErrorAction SilentlyContinue
  Copy-Item (Join-Path $repoRoot 'Uninstall.ps1') -Destination $Dest -Force -ErrorAction SilentlyContinue
  return $Dest
}

function New-MacifyShortcut {
  param([string]$Name, [string]$Script, [string]$ExtraArgs = '', [string]$Icon = '')
  $startup = [Environment]::GetFolderPath('Startup')
  $lnk = Join-Path $startup ("Macify {0}.lnk" -f $Name)
  $sh = New-Object -ComObject WScript.Shell
  $sc = $sh.CreateShortcut($lnk)
  $sc.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $sc.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}" {1}' -f $Script, $ExtraArgs
  $sc.WorkingDirectory = Split-Path $Script -Parent
  $sc.WindowStyle = 7
  $sc.Description = "Macify $Name (auto-start, delete this shortcut to disable)"
  if ($Icon -ne '' -and (Test-Path $Icon)) { $sc.IconLocation = $Icon }
  $sc.Save()
  try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null } catch { }
  Write-Host ("  [ok] Start Menu Startup: Macify {0}" -f $Name) -ForegroundColor Green
}

function Start-AllComponents {
  param([string]$Root)
  $src = Join-Path $Root 'src'
  Stop-MacifyComponent -Match 'MacifyBar.ps1'
  Stop-MacifyComponent -Match 'MacifyDock.ps1'
  Stop-MacifyComponent -Match 'MacifySpotlight.ps1'
  Stop-MacifyComponent -Match 'MacifyControlCenter.ps1'
  Start-Sleep -Milliseconds 600
  Start-MacifyComponent -ScriptPath (Join-Path $src 'MacifyBar.ps1')
  Start-MacifyComponent -ScriptPath (Join-Path $src 'MacifyDock.ps1')
  Start-MacifyComponent -ScriptPath (Join-Path $src 'MacifySpotlight.ps1') -ExtraArgs '-Hidden'
  Write-Host '  [ok] Menu bar, Dock and Spotlight started' -ForegroundColor Green
}

Write-Banner

$os = [Environment]::OSVersion.Version
if ($os.Major -lt 10) { Write-Host 'Macify needs Windows 10 or 11.' -ForegroundColor Red; exit 1 }
Write-Host ("Detected: Windows {0} (build {1})" -f $os.Major, $os.Build) -ForegroundColor Gray

$mode = 'full'
if ($Minimal -or $NoTweaks) { $mode = 'minimal' }
if (-not $Silent -and -not $Minimal -and -not $NoTweaks) {
  Write-Host ''
  Write-Host 'Choose install mode:' -ForegroundColor Cyan
  Write-Host '  [1] Full    - bar + dock + Spotlight + wallpaper + Windows tweaks (recommended)'
  Write-Host '  [2] Minimal - bar + dock + Spotlight + wallpaper, no system tweaks'
  Write-Host '  [3] Tweaks only (no bar/dock)'
  Write-Host '  [4] Extras only (Store apps, cursors, font)'
  Write-Host '  [5] Exit'
  $pick = Read-Host 'Pick [1-5]'
  switch ($pick) {
    '2' { $mode = 'minimal' }
    '3' { $mode = 'tweaksonly' }
    '4' { $mode = 'extrasonly' }
    '5' { exit 0 }
    default { $mode = 'full' }
  }
}

if (($mode -eq 'full' -or $mode -eq 'minimal') -and -not $Silent -and $Engine -eq 'native') {
  Write-Host ''
  Write-Host 'Choose your dock + menu bar engine:' -ForegroundColor Cyan
  Write-Host '  [1] Native (default) - built-in Macify bar + dock, open-source, no downloads'
  Write-Host '  [2] MyDockFinder - popular third-party dock + menu bar (closed-source, uses your own install from Steam)'
  $epick = Read-Host 'Pick [1-2]'
  if ($epick -eq '2') { $Engine = 'mydockfinder' }
}
if ($Engine -eq 'mydockfinder' -and $Silent -and -not $AcceptThirdParty) {
  Write-Host '-Engine mydockfinder with -Silent requires -AcceptThirdParty. Aborting.' -ForegroundColor Red
  exit 1
}

if ($InstallPath -eq '') { $InstallPath = Join-Path $env:LOCALAPPDATA 'Macify' }
if ($mode -ne 'extrasonly') { $InstallPath = Copy-MacifyFiles -Dest $InstallPath }

$paths = Get-MacifyPaths
$iconFile = Join-Path $InstallPath 'assets\macify.ico'

if ($mode -eq 'extrasonly') {
  & (Join-Path $repoRoot 'tools\Install-Extras.ps1') -Silent:$Silent
  exit 0
}

# ---- System tweaks (with automatic backup) ----
if ($mode -eq 'full' -or $mode -eq 'tweaksonly') {
  Write-Host ''
  Write-Host 'Your current settings will be backed up first (one click to undo).' -ForegroundColor Cyan
  if (-not $Silent) {
    Write-Host 'Explorer will restart once to apply the taskbar change. Save open work!' -ForegroundColor Yellow
    $ok = Read-Host 'Apply Windows tweaks? [Y/n]'
    if ($ok -match '^(n|no)$') { $mode = 'minimal' }
  }
}
if ($mode -eq 'full' -or $mode -eq 'tweaksonly') {
  try {
    $wp = Join-Path $InstallPath 'assets\wallpapers\sonoma-dark.jpg'
    & (Join-Path $InstallPath 'tools\MacifyTweaks.ps1') -Apply -WallpaperPath $wp
  } catch {
    Write-Host ("Tweaks step had a problem ({0}) - continuing with components." -f $_.Exception.Message) -ForegroundColor Yellow
    Write-MacifyLog "Tweaks failed during install: $($_.Exception.Message)" 'WARN'
  }
} elseif ($mode -eq 'minimal') {
  try {
    $old = Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue
    if ($old) { $old | Set-Content (Join-Path $paths.AppData 'wallpaper-backup.txt') -Encoding UTF8 }
    Set-MacifyWallpaper -Path (Join-Path $InstallPath 'assets\wallpapers\sonoma-dark.jpg')
    Write-Host '  [ok] Wallpaper' -ForegroundColor Green
  } catch { Write-Host ("  [!!] Wallpaper: {0}" -f $_.Exception.Message) -ForegroundColor Yellow }
}

# ---- Engine setup (native vs MyDockFinder) ----
$engineExternal = ($Engine -eq 'mydockfinder' -and ($mode -eq 'full' -or $mode -eq 'minimal'))
if ($engineExternal) {
  & (Join-Path $InstallPath 'tools\Install-MyDockFinder.ps1') -Silent:$Silent -AcceptThirdParty:$AcceptThirdParty -NoStartup:$NoStartup
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'MyDockFinder setup did not complete - falling back to the native engine.' -ForegroundColor Yellow
    $Engine = 'native'
    $engineExternal = $false
  }
}

# ---- Auto-start shortcuts (native engine; external engines manage their own) ----
if (($mode -eq 'full' -or $mode -eq 'minimal') -and -not $NoStartup -and -not $engineExternal) {
  Write-Host ''
  Write-Host 'Creating auto-start shortcuts...' -ForegroundColor Cyan
  New-MacifyShortcut -Name 'Bar' -Script (Join-Path $InstallPath 'src\MacifyBar.ps1') -Icon $iconFile
  New-MacifyShortcut -Name 'Dock' -Script (Join-Path $InstallPath 'src\MacifyDock.ps1') -Icon $iconFile
  New-MacifyShortcut -Name 'Spotlight' -Script (Join-Path $InstallPath 'src\MacifySpotlight.ps1') -ExtraArgs '-Hidden' -Icon $iconFile
}

# ---- Launch (external engines were already started by their own setup) ----
if (($mode -eq 'full' -or $mode -eq 'minimal') -and -not $engineExternal) {
  Write-Host ''
  Write-Host 'Starting Macify...' -ForegroundColor Cyan
  Start-AllComponents -Root $InstallPath
}

# ---- Extras ----
if ($mode -eq 'full' -and -not $Silent) {
  $ans = Read-Host 'Install optional extras (Store apps, macOS cursors, Inter font)? [y/N]'
  if ($ans -match '^(y|yes)$') { & (Join-Path $InstallPath 'tools\Install-Extras.ps1') }
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' Macify is installed! A few tips:' -ForegroundColor Green
Write-Host '   Alt+Space (or Ctrl+Space) ... Spotlight search'
Write-Host '   Click the magnifier / sliders (top-right) ... Spotlight / Control Center'
Write-Host '   Right-click the Dock ... magnification + auto-hide options'
Write-Host '   Right-click any Launchpad app ... Add to Dock'
Write-Host '   Switch engines: tools\Set-MacifyEngine.ps1 -Engine native|mydockfinder'
Write-Host ''
Write-Host '   Uninstall any time:  right-click Setup folder > Uninstall.ps1,'
Write-Host '   or run:  powershell -ExecutionPolicy Bypass -File Uninstall.ps1'
Write-Host '============================================================' -ForegroundColor Magenta
Write-MacifyLog "Installed (mode=$mode) to $InstallPath."
