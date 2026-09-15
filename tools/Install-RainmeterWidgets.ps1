# Install-RainmeterWidgets.ps1 - macOS-style desktop widgets via Rainmeter.
# Installs Rainmeter (open-source, via winget) and activates Macify's shipped
# skins (extras/rainmeter/Macify): a desktop clock + a system stats widget.
#   powershell -ExecutionPolicy Bypass -File tools\Install-RainmeterWidgets.ps1 [-Silent] [-Remove]

param([switch]$Silent, [switch]$Remove)

$ErrorActionPreference = 'Continue'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\MacifyLib.ps1')
$repoRoot = (Get-MacifyPaths).Root
$skinSrc = Join-Path $repoRoot 'extras\rainmeter\Macify'
$skinDest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\Macify'

function Get-RainmeterExe {
  $c = Get-Command Rainmeter.exe -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  foreach ($p in @("$env:ProgramFiles\Rainmeter\Rainmeter.exe",
      "${env:ProgramFiles(x86)}\Rainmeter\Rainmeter.exe",
      "$env:LOCALAPPDATA\Programs\Rainmeter\Rainmeter.exe")) {
    if (Test-Path $p) { return $p }
  }
  return ''
}

if ($Remove) {
  Write-Host 'Removing Macify Rainmeter widgets...' -ForegroundColor Cyan
  $rmGone = Get-RainmeterExe
  if ($rmGone -ne '') {
    foreach ($cfg in @('Macify\Clock', 'Macify\Stats')) {
      Start-Process -FilePath $rmGone -ArgumentList '!DeactivateConfig', $cfg -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    }
    Start-Sleep -Seconds 1
  }
  Remove-Item $skinDest -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host '  [ok] Widgets removed (Rainmeter itself left installed).' -ForegroundColor Green
  exit 0
}

Write-Host ''
Write-Host '=========== Macify Rainmeter widgets ===========' -ForegroundColor Magenta
$rm = Get-RainmeterExe
if ($rm -eq '') {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'Rainmeter is not installed and winget is missing. Install it from https://www.rainmeter.net, then re-run.' -ForegroundColor Red
    exit 1
  }
  if (-not $Silent) {
    $ans = Read-Host 'Install Rainmeter via winget (open-source, ~10MB)? [Y/n]'
    if ($ans -match '^(n|no)$') { exit 0 }
  }
  try {
    Write-Host 'Installing Rainmeter...' -ForegroundColor Yellow
    winget install --id Rainmeter.Rainmeter --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
  } catch { }
  Start-Sleep -Seconds 2
  $rm = Get-RainmeterExe
}
if ($rm -eq '') {
  Write-Host 'Rainmeter still not found - install it from https://www.rainmeter.net and re-run.' -ForegroundColor Red
  exit 1
}
Write-Host ("Rainmeter: {0}" -f $rm) -ForegroundColor Green

if (-not (Test-Path $skinSrc)) { Write-Host ("Skin source missing: {0}" -f $skinSrc) -ForegroundColor Red; exit 1 }
New-Item -ItemType Directory -Path $skinDest -Force | Out-Null
Copy-Item (Join-Path $skinSrc '*') -Destination $skinDest -Recurse -Force
Write-Host '  [ok] Skins copied' -ForegroundColor Green

foreach ($w in @(@{ Cfg = 'Macify\Clock'; Ini = 'Clock.ini' }, @{ Cfg = 'Macify\Stats'; Ini = 'Stats.ini' })) {
  Start-Process -FilePath $rm -ArgumentList '!ActivateConfig', $w.Cfg, $w.Ini -WindowStyle Hidden | Out-Null
}
Write-Host '  [ok] Clock + Stats widgets activated (drag them anywhere; right-click for settings).' -ForegroundColor Green

$hasStart = (Test-Path (Join-Path ([Environment]::GetFolderPath('Startup')) 'Rainmeter.lnk')) -or
  ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name Rainmeter -ErrorAction SilentlyContinue) -ne $null)
if (-not $hasStart) {
  $doIt = $Silent
  if (-not $Silent) { $doIt = (Read-Host 'Auto-start Rainmeter with Windows? [Y/n]') -notmatch '^(n|no)$' }
  if ($doIt) {
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'Rainmeter.lnk'))
    $sc.TargetPath = $rm
    $sc.Description = 'Rainmeter (created by Macify - delete to disable)'
    $sc.Save()
    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null } catch { }
    Write-Host '  [ok] Rainmeter auto-start enabled' -ForegroundColor Green
  }
}
