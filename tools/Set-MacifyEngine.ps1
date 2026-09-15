# Set-MacifyEngine.ps1 - switch Macify's dock/menu-bar engine.
#   powershell -ExecutionPolicy Bypass -File tools\Set-MacifyEngine.ps1 -Engine native
#   powershell -ExecutionPolicy Bypass -File tools\Set-MacifyEngine.ps1 -Engine mydockfinder [-NoStart] [-NoStartup]
# Stops every engine, rewrites Startup shortcuts for the chosen one, starts it.

param(
  [Parameter(Mandatory = $true)][ValidateSet('native', 'mydockfinder')][string]$Engine,
  [switch]$NoStart,
  [switch]$NoStartup
)

$ErrorActionPreference = 'Continue'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\MacifyLib.ps1')
$paths = Get-MacifyPaths
$repoRoot = $paths.Root

function Get-EngineDef {
  param([string]$Id)
  $reg = Get-Content (Join-Path $repoRoot 'config\engines.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $def = @($reg.engines | Where-Object { $_.id -eq $Id })
  if ($def.Count -eq 0) { throw "Unknown engine: $Id" }
  return $def[0]
}

function Remove-EngineShortcuts {
  $startup = [Environment]::GetFolderPath('Startup')
  foreach ($n in @('Macify Bar.lnk', 'Macify Dock.lnk', 'Macify Spotlight.lnk', 'Macify MyDockFinder.lnk')) {
    Remove-Item (Join-Path $startup $n) -Force -ErrorAction SilentlyContinue
  }
}

function New-EngineShortcut {
  param([string]$Name, [string]$Target, [string]$Args = '', [string]$WorkDir = '', [int]$WinStyle = 7, [string]$Icon = '')
  $sh = New-Object -ComObject WScript.Shell
  $sc = $sh.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) $Name))
  $sc.TargetPath = $Target
  if ($Args -ne '') { $sc.Arguments = $Args }
  if ($WorkDir -ne '') { $sc.WorkingDirectory = $WorkDir }
  $sc.WindowStyle = $WinStyle
  if ($Icon -ne '' -and (Test-Path $Icon)) { $sc.IconLocation = $Icon }
  $sc.Save()
  try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null } catch { }
}

function Stop-AllEngines {
  Stop-MacifyComponent -Match 'MacifyBar.ps1'
  Stop-MacifyComponent -Match 'MacifyDock.ps1'
  Stop-MacifyComponent -Match 'MacifySpotlight.ps1'
  Stop-MacifyComponent -Match 'MacifyControlCenter.ps1'
  foreach ($pr in @(Get-Process -Name 'MyDockFinder*' -ErrorAction SilentlyContinue)) {
    try { $pr.CloseMainWindow() | Out-Null } catch { }
  }
  Start-Sleep -Milliseconds 800
  foreach ($pr in @(Get-Process -Name 'MyDockFinder*' -ErrorAction SilentlyContinue)) {
    try { Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue } catch { }
  }
}

function Save-EngineChoice {
  param([string]$Id)
  $uc = $null
  if (Test-Path $paths.UserCfg) { try { $uc = Get-Content $paths.UserCfg -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
  if ($null -eq $uc) { $uc = New-Object PSCustomObject }
  $uc | Add-Member -NotePropertyName 'engine' -NotePropertyValue $Id -Force
  if (-not (Test-Path $paths.AppData)) { New-Item -ItemType Directory -Path $paths.AppData -Force | Out-Null }
  ($uc | ConvertTo-Json -Depth 8) | Set-Content $paths.UserCfg -Encoding UTF8
}

$def = Get-EngineDef -Id $Engine
Write-Host ("Switching to engine: {0}" -f $def.name) -ForegroundColor Cyan
Write-Host 'Stopping all engines...' -ForegroundColor Gray
Stop-AllEngines
Remove-EngineShortcuts

$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$icon = Join-Path $repoRoot 'assets\macify.ico'
if (-not (Test-Path $icon)) { $icon = '' }

if ($Engine -eq 'native') {
  if (-not $NoStartup) {
    New-EngineShortcut -Name 'Macify Bar.lnk' -Target $psExe -Args ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f (Join-Path $paths.Src 'MacifyBar.ps1')) -WorkDir $paths.Src -Icon $icon
    New-EngineShortcut -Name 'Macify Dock.lnk' -Target $psExe -Args ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f (Join-Path $paths.Src 'MacifyDock.ps1')) -WorkDir $paths.Src -Icon $icon
    New-EngineShortcut -Name 'Macify Spotlight.lnk' -Target $psExe -Args ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}" -Hidden' -f (Join-Path $paths.Src 'MacifySpotlight.ps1')) -WorkDir $paths.Src -Icon $icon
    Write-Host '  [ok] Native auto-start configured (bar + dock + Spotlight)' -ForegroundColor Green
  }
  if (-not $NoStart) {
    Start-MacifyComponent -ScriptPath (Join-Path $paths.Src 'MacifyBar.ps1')
    Start-MacifyComponent -ScriptPath (Join-Path $paths.Src 'MacifyDock.ps1')
    Start-MacifyComponent -ScriptPath (Join-Path $paths.Src 'MacifySpotlight.ps1') -ExtraArgs '-Hidden'
  }
} else {
  $exe = ''
  try {
    if (Test-Path $paths.UserCfg) {
      $uc = Get-Content $paths.UserCfg -Raw -Encoding UTF8 | ConvertFrom-Json
      $exe = $uc.engines.mydockfinder.path
    }
  } catch { }
  if ([string]::IsNullOrWhiteSpace($exe) -or -not (Test-Path $exe)) {
    Write-Host 'MyDockFinder is not registered yet.' -ForegroundColor Yellow
    Write-Host 'Run:  powershell -ExecutionPolicy Bypass -File tools\Install-MyDockFinder.ps1' -ForegroundColor Yellow
    exit 1
  }
  if (-not $NoStartup) {
    New-EngineShortcut -Name 'Macify MyDockFinder.lnk' -Target $exe -WorkDir (Split-Path $exe -Parent) -WinStyle 1
    New-EngineShortcut -Name 'Macify Spotlight.lnk' -Target $psExe -Args ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}" -Hidden' -f (Join-Path $paths.Src 'MacifySpotlight.ps1')) -WorkDir $paths.Src -Icon $icon
    Write-Host '  [ok] MyDockFinder auto-start configured (+ native Spotlight as complement)' -ForegroundColor Green
  }
  if (-not $NoStart) {
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe -Parent) | Out-Null
    Start-MacifyComponent -ScriptPath (Join-Path $paths.Src 'MacifySpotlight.ps1') -ExtraArgs '-Hidden'
  }
}

Save-EngineChoice -Id $Engine
Write-MacifyLog "Engine switched to $Engine."
Write-Host ("Engine is now: {0}" -f $def.name) -ForegroundColor Green
