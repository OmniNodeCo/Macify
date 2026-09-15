# Install-MyDockFinder.ps1 - guided setup for the MyDockFinder engine.
# MyDockFinder is closed-source and officially distributed via Steam and
# mydockfinder.com, so Macify does NOT auto-download it (no shady repacks,
# no piracy). This wizard:
#   1) points you at the official sources,
#   2) finds your install (Steam libraries + common paths + file picker),
#   3) safety-checks the binary signature + VC++ runtime,
#   4) registers it with Macify and switches the engine.
#
#   powershell -ExecutionPolicy Bypass -File tools\Install-MyDockFinder.ps1 [-ExePath "..."] [-Silent -AcceptThirdParty] [-NoStartup]
# Exit codes: 0 = engine active, 1 = failed, 2 = cancelled by user.

param(
  [string]$ExePath = '',
  [switch]$Silent,
  [switch]$AcceptThirdParty,
  [switch]$NoStartup
)

$ErrorActionPreference = 'Continue'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\MacifyLib.ps1')
$paths = Get-MacifyPaths

$steamUrl = 'https://store.steampowered.com/app/1787090/MyDockFinder/'
$homeUrl = 'https://www.mydockfinder.com'

Write-Host ''
Write-Host '=========== MyDockFinder engine setup ===========' -ForegroundColor Magenta
Write-Host 'MyDockFinder is a popular CLOSED-SOURCE macOS dock + menu bar for Windows.' -ForegroundColor Yellow
Write-Host 'Official sources ONLY: Steam and mydockfinder.com.' -ForegroundColor Yellow
Write-Host 'Never install "cracked / free activated" repacks - a common malware vector.' -ForegroundColor Yellow
Write-Host ''

if ($Silent -and -not $AcceptThirdParty) {
  Write-Host 'Silent mode requires -AcceptThirdParty (you accept third-party closed-source software).' -ForegroundColor Red
  exit 1
}
if (-not $Silent -and -not $AcceptThirdParty) {
  $ans = Read-Host 'Understand and want to continue with the official build? [y/N]'
  if ($ans -notmatch '^(y|yes)$') { Write-Host 'Cancelled - staying on the native engine.'; exit 2 }
}

function Find-MyDockFinder {
  $cands = @()
  if ($ExePath -ne '' -and (Test-Path $ExePath)) { return @($ExePath) }
  $steamRoots = @()
  foreach ($r in @('HKCU:\Software\Valve\Steam', 'HKLM:\Software\Wow6432Node\Valve\Steam', 'HKLM:\Software\Valve\Steam')) {
    try {
      $sp = (Get-ItemProperty -Path $r -Name SteamPath -ErrorAction Stop).SteamPath
      if ($sp -ne '' -and $sp -ne $null) { $steamRoots += $sp }
    } catch { }
  }
  foreach ($sr in @($steamRoots | Select-Object -Unique)) {
    $cands += (Join-Path $sr 'steamapps\common\MyDockFinder\MyDockFinder.exe')
    $vdf = Join-Path $sr 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
      foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
        $cands += (Join-Path $m.Groups[1].Value 'steamapps\common\MyDockFinder\MyDockFinder.exe')
      }
    }
  }
  foreach ($d in @("$env:ProgramFiles\MyDockFinder", "${env:ProgramFiles(x86)}\MyDockFinder",
      "$env:LOCALAPPDATA\MyDockFinder", "$env:LOCALAPPDATA\Programs\MyDockFinder")) {
    $cands += (Join-Path $d 'MyDockFinder.exe')
  }
  return @($cands | Where-Object { Test-Path $_ } | Select-Object -Unique)
}

$found = @(Find-MyDockFinder)
$exe = if ($found.Count -gt 0) { $found[0] } else { '' }

if ($exe -eq '') {
  Write-Host 'MyDockFinder was not found on this PC.' -ForegroundColor Yellow
  Write-Host "  Official site: $homeUrl"
  Write-Host "  Steam:         $steamUrl"
  if (-not $Silent) {
    $o = Read-Host 'Open the Steam page now? [Y/n]'
    if ($o -notmatch '^(n|no)$') { Start-Process $steamUrl }
    Write-Host ''
    Write-Host 'Install it from Steam (or the official site), then press Enter here to continue...' -ForegroundColor Cyan
    Read-Host | Out-Null
    $found = @(Find-MyDockFinder)
    if ($found.Count -gt 0) { $exe = $found[0] }
  }
}

if ($exe -eq '' -and -not $Silent) {
  Write-Host 'Still not found. Please locate MyDockFinder.exe manually.' -ForegroundColor Yellow
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = 'Locate MyDockFinder.exe'
    $dlg.Filter = 'MyDockFinder (MyDockFinder.exe)|MyDockFinder.exe|Executables (*.exe)|*.exe'
    if ($dlg.ShowDialog() -eq 'OK' -and (Test-Path $dlg.FileName)) { $exe = $dlg.FileName }
  } catch {
    $manual = Read-Host 'Paste the full path to MyDockFinder.exe (empty to cancel)'
    if ($manual -ne '' -and (Test-Path $manual)) { $exe = $manual }
  }
}

if ($exe -eq '' -or -not (Test-Path $exe)) {
  Write-Host 'No MyDockFinder executable registered. Nothing changed.' -ForegroundColor Red
  exit 1
}
Write-Host ("Found: {0}" -f $exe) -ForegroundColor Green

# Authenticode safety check (never auto-run an unverified third-party binary).
try {
  $sig = Get-AuthenticodeSignature -FilePath $exe -ErrorAction Stop
  Write-Host ("Signature: {0}" -f $sig.Status) -ForegroundColor Gray
  if ($sig.Status -eq 'HashMismatch' -or $sig.Status -eq 'NotTrusted') {
    Write-Host 'DANGER: signature is invalid - the file may be tampered with. Aborting.' -ForegroundColor Red
    exit 1
  }
  if ($sig.Status -ne 'Valid') {
    Write-Host 'Warning: binary is not digitally signed - publisher cannot be verified.' -ForegroundColor Yellow
    if ($Silent) { Write-Host 'Silent mode requires a valid signature. Aborting.' -ForegroundColor Red; exit 1 }
    $ok = Read-Host 'Run it anyway? Only say yes if you installed it yourself from Steam / the official site. [y/N]'
    if ($ok -notmatch '^(y|yes)$') { exit 2 }
  } elseif ($sig.SignerCertificate) {
    Write-Host ("Signed by: {0}" -f $sig.SignerCertificate.Subject) -ForegroundColor Gray
  }
} catch {
  Write-Host ("Signature check could not run: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

# VC++ runtime check (MyDockFinder needs the MSVC redistributable).
if (-not (Test-Path "$env:SystemRoot\System32\vcruntime140.dll")) {
  Write-Host 'MSVC runtime (vcruntime140.dll) not detected - MyDockFinder needs it.' -ForegroundColor Yellow
  $done = $false
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    $doIt = $Silent
    if (-not $Silent) { $doIt = (Read-Host 'Install Microsoft VCRedist via winget? [Y/n]') -notmatch '^(n|no)$' }
    if ($doIt) {
      try {
        winget install --id Microsoft.VCRedist.2015+.x64 --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        $done = $true
      } catch { }
    }
  }
  if (-not $done) { Write-Host 'Continuing anyway - install the VC++ redist if MyDockFinder fails to start.' -ForegroundColor Yellow }
}

# Register the engine path in user config.
try {
  $uc = $null
  if (Test-Path $paths.UserCfg) { $uc = Get-Content $paths.UserCfg -Raw -Encoding UTF8 | ConvertFrom-Json }
  if ($null -eq $uc) { $uc = New-Object PSCustomObject }
  if ($null -eq $uc.engines) { $uc | Add-Member -NotePropertyName 'engines' -NotePropertyValue (New-Object PSCustomObject) }
  $entry = [PSCustomObject]@{ path = $exe; registered = (Get-Date -Format 'o') }
  $uc.engines | Add-Member -NotePropertyName 'mydockfinder' -NotePropertyValue $entry -Force
  if (-not (Test-Path $paths.AppData)) { New-Item -ItemType Directory -Path $paths.AppData -Force | Out-Null }
  ($uc | ConvertTo-Json -Depth 8) | Set-Content $paths.UserCfg -Encoding UTF8
  Write-Host '  [ok] Registered with Macify' -ForegroundColor Green
} catch {
  Write-Host ("Failed to save config: {0}" -f $_.Exception.Message) -ForegroundColor Red
  exit 1
}

# Switch engine (rewrites auto-start + launches).
& (Join-Path $PSScriptRoot 'Set-MacifyEngine.ps1') -Engine mydockfinder -NoStartup:$NoStartup
exit $LASTEXITCODE
