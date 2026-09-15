# Start-Macify.ps1 - launch Macify using the configured engine (native by default).
# Works from the repo or from %LOCALAPPDATA%\Macify.
# -Bar/-Dock/-Spotlight force-start individual native components.
param([switch]$Bar, [switch]$Dock, [switch]$Spotlight)

. (Join-Path $PSScriptRoot 'src\MacifyLib.ps1')
$src = Join-Path $PSScriptRoot 'src'
$paths = Get-MacifyPaths

function Start-NativeComponents {
  param([bool]$All, [bool]$B, [bool]$D, [bool]$S)
  if ($All -or $B) { Start-MacifyComponent -ScriptPath (Join-Path $src 'MacifyBar.ps1') }
  if ($All -or $D) { Start-MacifyComponent -ScriptPath (Join-Path $src 'MacifyDock.ps1') }
  if ($All -or $S) { Start-MacifyComponent -ScriptPath (Join-Path $src 'MacifySpotlight.ps1') -ExtraArgs '-Hidden' }
}

if ($Bar -or $Dock -or $Spotlight) {
  Start-NativeComponents -All $false -B ([bool]$Bar) -D ([bool]$Dock) -S ([bool]$Spotlight)
  Write-Host 'Macify native component(s) started.' -ForegroundColor Green
  exit 0
}

$engine = 'native'
$uc = $null
try {
  if (Test-Path $paths.UserCfg) { $uc = Get-Content $paths.UserCfg -Raw -Encoding UTF8 | ConvertFrom-Json }
  if ($uc -and $uc.engine -ne $null -and $uc.engine -ne '') { $engine = [string]$uc.engine }
} catch { }

if ($engine -eq 'mydockfinder') {
  $exe = ''
  try { $exe = $uc.engines.mydockfinder.path } catch { }
  if ($exe -ne '' -and (Test-Path $exe)) {
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe -Parent) | Out-Null
    Start-MacifyComponent -ScriptPath (Join-Path $src 'MacifySpotlight.ps1') -ExtraArgs '-Hidden'
    Write-Host 'Macify started (MyDockFinder engine + native Spotlight).' -ForegroundColor Green
  } else {
    Write-Host 'MyDockFinder engine selected but its .exe is missing - starting native instead.' -ForegroundColor Yellow
    Write-Host 'Repair: tools\Install-MyDockFinder.ps1  |  or switch: tools\Set-MacifyEngine.ps1 -Engine native' -ForegroundColor Yellow
    Start-NativeComponents -All $true -B $false -D $false -S $false
  }
} else {
  Start-NativeComponents -All $true -B $false -D $false -S $false
  Write-Host 'Macify started. (Alt+Space = Spotlight)' -ForegroundColor Green
}
