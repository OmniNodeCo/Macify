# Stop-Macify.ps1 - stop all running Macify components (settings are kept).
. (Join-Path $PSScriptRoot 'src\MacifyLib.ps1')
Stop-MacifyComponent -Match 'MacifyBar.ps1'
Stop-MacifyComponent -Match 'MacifyDock.ps1'
Stop-MacifyComponent -Match 'MacifySpotlight.ps1'
Stop-MacifyComponent -Match 'MacifyControlCenter.ps1'
Write-Host 'Macify stopped.' -ForegroundColor Yellow
