# Stop-Macify.ps1 - stop all running Macify components and engines (settings are kept).
. (Join-Path $PSScriptRoot 'src\MacifyLib.ps1')
Stop-MacifyComponent -Match 'MacifyBar.ps1'
Stop-MacifyComponent -Match 'MacifyDock.ps1'
Stop-MacifyComponent -Match 'MacifySpotlight.ps1'
Stop-MacifyComponent -Match 'MacifyControlCenter.ps1'
foreach ($pr in @(Get-Process -Name 'MyDockFinder*' -ErrorAction SilentlyContinue)) {
  try { Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue } catch { }
}
Write-Host 'Macify stopped.' -ForegroundColor Yellow
