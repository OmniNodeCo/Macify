# Start-Macify.ps1 - launch the Macify menu bar, dock and Spotlight.
# Works from the repo or from %LOCALAPPDATA%\Macify.
param([switch]$Bar, [switch]$Dock, [switch]$Spotlight)

. (Join-Path $PSScriptRoot 'src\MacifyLib.ps1')
$src = Join-Path $PSScriptRoot 'src'
$all = -not ($Bar -or $Dock -or $Spotlight)
if ($all -or $Bar) { Start-MacifyComponent -ScriptPath (Join-Path $src 'MacifyBar.ps1') }
if ($all -or $Dock) { Start-MacifyComponent -ScriptPath (Join-Path $src 'MacifyDock.ps1') }
if ($all -or $Spotlight) { Start-MacifyComponent -ScriptPath (Join-Path $src 'MacifySpotlight.ps1') -ExtraArgs '-Hidden' }
Write-Host 'Macify started. (Alt+Space = Spotlight)' -ForegroundColor Green
