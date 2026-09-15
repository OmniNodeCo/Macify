# Uninstall.ps1 - remove Macify and restore original Windows settings.
#   powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1 [-Silent] [-Full]

param([switch]$Silent, [switch]$Full)

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
. (Join-Path $here 'src\MacifyLib.ps1')

Write-Host ''
Write-Host 'Macify Uninstaller' -ForegroundColor Magenta
if (-not $Silent) {
  $ok = Read-Host 'Stop Macify, remove auto-start and RESTORE your original settings? [Y/n]'
  if ($ok -match '^(n|no)$') { exit 0 }
}

# 1. Stop everything
Write-Host 'Stopping Macify components...' -ForegroundColor Cyan
Stop-MacifyComponent -Match 'MacifyBar.ps1'
Stop-MacifyComponent -Match 'MacifyDock.ps1'
Stop-MacifyComponent -Match 'MacifySpotlight.ps1'
Stop-MacifyComponent -Match 'MacifyControlCenter.ps1'
foreach ($pr in @(Get-Process -Name 'MyDockFinder*' -ErrorAction SilentlyContinue)) {
  try { Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue } catch { }
}
Start-Sleep -Milliseconds 800
Write-Host '  [ok] Stopped' -ForegroundColor Green

# 2. Remove auto-start shortcuts
Write-Host 'Removing auto-start shortcuts...' -ForegroundColor Cyan
$startup = [Environment]::GetFolderPath('Startup')
foreach ($n in @('Macify Bar.lnk', 'Macify Dock.lnk', 'Macify Spotlight.lnk', 'Macify MyDockFinder.lnk')) {
  Remove-Item (Join-Path $startup $n) -Force -ErrorAction SilentlyContinue
}
Write-Host '  [ok] Startup clean' -ForegroundColor Green

# 3. Restore registry tweaks from backup
$localTools = Join-Path $env:LOCALAPPDATA 'Macify\tools\MacifyTweaks.ps1'
$repoTools = Join-Path $here 'tools\MacifyTweaks.ps1'
$tweaks = if (Test-Path $localTools) { $localTools } elseif (Test-Path $repoTools) { $repoTools } else { '' }
if ($tweaks -ne '') {
  & $tweaks -Restore
} else {
  Write-Host 'Tweaks script not found - skipping registry restore.' -ForegroundColor Yellow
}

# 3b. Rainmeter widgets (optional add-on)
$rmSkins = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\Macify'
if (Test-Path $rmSkins) {
  $rmLocal2 = Join-Path $env:LOCALAPPDATA 'Macify\tools\Install-RainmeterWidgets.ps1'
  $rmRepo2 = Join-Path $here 'tools\Install-RainmeterWidgets.ps1'
  $rmTool = if (Test-Path $rmLocal2) { $rmLocal2 } elseif (Test-Path $rmRepo2) { $rmRepo2 } else { '' }
  $rmDel = $true
  if (-not $Silent) { $rmDel = (Read-Host 'Remove Macify Rainmeter widgets too? [Y/n]') -notmatch '^(n|no)$' }
  if ($rmDel -and $rmTool -ne '') { & $rmTool -Remove }
  elseif ($rmDel) { Remove-Item $rmSkins -Recurse -Force -ErrorAction SilentlyContinue }
}

# 4. Restore wallpaper for minimal installs
try {
  $wb = Join-Path (Get-MacifyPaths).AppData 'wallpaper-backup.txt'
  if ((Test-Path $wb) -and -not (Test-Path (Join-Path (Get-MacifyPaths).AppData 'tweaks-backup.json'))) {
    $old = (Get-Content $wb -Raw).Trim()
    if ($old -ne '' -and (Test-Path $old)) { Set-MacifyWallpaper -Path $old }
  }
} catch { }

# 5. Remove installed files
$instDir = Join-Path $env:LOCALAPPDATA 'Macify'
$runningFromInstall = $false
if (Test-Path $instDir) {
  try { $runningFromInstall = ((Resolve-Path $here -ErrorAction Stop).Path -eq (Resolve-Path $instDir -ErrorAction Stop).Path) } catch { }
}
if ((Test-Path $instDir) -and -not $runningFromInstall) {
  $del = $true
  if (-not $Silent) { $del = -not ((Read-Host ("Delete installed files at {0}? [Y/n]" -f $instDir)) -match '^(n|no)$') }
  if ($del) {
    Remove-Item $instDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '  [ok] Installed files removed' -ForegroundColor Green
  }
} elseif ($runningFromInstall) {
  Write-Host ("You ran this from {0} - deleting its contents..." -f $instDir) -ForegroundColor Yellow
  Get-ChildItem $instDir -Force | Where-Object { $_.Name -ne 'Uninstall.ps1' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host '  [ok] Cleaned. You can now delete the Macify folder itself.' -ForegroundColor Green
}

# 6. User settings
if ($Full) {
  Remove-Item (Join-Path (Get-MacifyPaths).AppData) -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host '  [ok] User settings removed (-Full)' -ForegroundColor Green
} else {
  Write-Host 'Kept your Macify settings in %APPDATA%\Macify (use -Full to remove).' -ForegroundColor Gray
}

Write-Host ''
Write-Host 'Macify uninstalled. Your Windows settings were restored.' -ForegroundColor Green
Write-Host 'Note: Extras (cursors/fonts/Store apps/Rainmeter) and MyDockFinder are your own software and stay installed.' -ForegroundColor Gray
