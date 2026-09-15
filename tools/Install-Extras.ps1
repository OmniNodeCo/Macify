# Install-Extras.ps1 - optional Macify extras. Everything here is best-effort and safe to skip.
#   1) Handy Store apps via winget (PowerToys, TranslucentTB, Terminal, FlowLauncher)
#   2) macOS-style cursor theme (open-source apple_cursor, per-user install)
#   3) Inter font (open OFL alternative to San Francisco, per-user install)

param([switch]$Silent)

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\MacifyLib.ps1')

function Install-WingetApps {
  Write-Host ''
  Write-Host '--- Recommended apps (winget) ---' -ForegroundColor Cyan
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'winget not found (needs Windows 10 1809+ with App Installer). Skipping.' -ForegroundColor Yellow
    Write-Host 'Get it from the Microsoft Store: "App Installer".'
    return
  }
  $apps = @(
    @{ Id = 'Microsoft.PowerToys';            Name = 'PowerToys (Peek = Quick Look, keyboard remap)' },
    @{ Id = 'TranslucentTB.TranslucentTB';    Name = 'TranslucentTB (glass taskbar)' },
    @{ Id = 'Microsoft.WindowsTerminal';      Name = 'Windows Terminal' },
    @{ Id = 'FlowLauncher.FlowLauncher';      Name = 'Flow Launcher (extra Spotlight alt)' }
  )
  foreach ($a in $apps) {
    $doIt = $true
    if (-not $Silent) {
      $ans = Read-Host ("Install {0}? [Y/n]" -f $a.Name)
      if ($ans -match '^(n|no)$') { $doIt = $false }
    }
    if (-not $doIt) { continue }
    try {
      Write-Host ("Installing {0}..." -f $a.Name) -ForegroundColor Yellow
      winget install --id $a.Id --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
      Write-Host ("  [ok] {0}" -f $a.Name) -ForegroundColor Green
    } catch { Write-Host ("  [!!] {0} failed" -f $a.Name) -ForegroundColor Red }
  }
  Write-Host ''
  Write-Host 'Tip: in PowerToys Keyboard Manager you can swap Alt/Win to get Mac-style Cmd key.' -ForegroundColor Cyan
}

function Install-MacCursors {
  Write-Host ''
  Write-Host '--- macOS cursor theme ---' -ForegroundColor Cyan
  if (-not $Silent) {
    $ans = Read-Host 'Download + install open-source macOS cursors (per-user, reversible)? [Y/n]'
    if ($ans -match '^(n|no)$') { return }
  }
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod 'https://api.github.com/repos/ful1e5/apple_cursor/releases/latest' -TimeoutSec 30
    $asset = @($rel.assets | Where-Object { $_.name -match '(?i)windows|win\.zip|\.zip' } | Select-Object -First 1)
    if ($asset.Count -eq 0) { $asset = @($rel.assets | Select-Object -First 1) }
    if ($asset.Count -eq 0) { throw 'no downloadable asset found' }
    $tmp = Join-Path $env:TEMP 'macify-cursors'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp $asset[0].name
    Write-Host ("Downloading {0}..." -f $asset[0].name) -ForegroundColor Yellow
    Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $zip -TimeoutSec 120
    $ext = Join-Path $tmp 'extracted'
    if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
    if ($zip -match '\.zip$') { Expand-Archive -Path $zip -DestinationPath $ext -Force }
    else { Write-Host 'Archive format not supported automatically. Opening releases page instead.' -ForegroundColor Yellow; Start-Process $rel.html_url; return }
    $curs = @(Get-ChildItem -Path $ext -Include '*.cur', '*.ani' -Recurse)
    if ($curs.Count -eq 0) { throw 'no cursor files in archive' }
    $dest = Join-Path $env:LOCALAPPDATA 'Macify\Cursors'
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item $curs.FullName -Destination $dest -Force
    $map = @{
      Arrow = @('arrow', 'default', 'normal'); Hand = @('hand', 'link', 'pointer')
      IBeam = @('ibeam', 'text'); Wait = @('wait', 'busy'); AppStarting = @('working', 'appstart')
      Crosshair = @('cross', 'precision'); SizeNS = @('ns-resize', 'size_ns', 'top_bottom')
      SizeWE = @('ew-resize', 'size_we', 'left_right'); UpArrow = @('up', 'alternate')
      No = @('unavailable', 'not-allowed', 'no_drop'); SizeNWSE = @('nwse', 'diagonal_1')
      SizeNESW = @('nesw', 'diagonal_2'); SizeAll = @('move', 'all-scroll', 'fleur')
    }
    $files = Get-ChildItem -Path $dest -Include '*.cur', '*.ani'
    $applied = 0
    foreach ($role in $map.Keys) {
      $best = $null
      foreach ($hint in $map[$role]) {
        $best = @($files | Where-Object { $_.BaseName.ToLower().Contains($hint) } | Select-Object -First 1)
        if ($best.Count -gt 0) { break }
      }
      if ($best.Count -gt 0) {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Cursors' -Name $role -Value $best[0].FullName -Force
        $applied++
      }
    }
    $res = [UIntPtr]::Zero
    Ensure-MacifyNative
    [Macify.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'TraySettings', 2, 3000, [ref]$res) | Out-Null
    Start-Process rundll32.exe 'user32.dll,UpdatePerUserSystemParameters' -ErrorAction SilentlyContinue
    Write-Host ("  [ok] Applied {0} cursor roles. Sign out/in if some apps keep old cursors." -f $applied) -ForegroundColor Green
  } catch {
    Write-Host ("  [!!] Auto-install failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    Write-Host 'Manual: https://github.com/ful1e5/apple_cursor -> download, right-click Install.inf -> Install'
  }
}

function Install-InterFont {
  Write-Host ''
  Write-Host '--- Inter font (San Francisco lookalike, OFL licensed) ---' -ForegroundColor Cyan
  if (-not $Silent) {
    $ans = Read-Host 'Download + install Inter font (per-user)? [Y/n]'
    if ($ans -match '^(n|no)$') { return }
  }
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod 'https://api.github.com/repos/rsms/inter/releases/latest' -TimeoutSec 30
    $asset = @($rel.assets | Where-Object { $_.name -match '(?i)\.zip$' } | Select-Object -First 1)
    if ($asset.Count -eq 0) { throw 'no zip asset found' }
    $tmp = Join-Path $env:TEMP 'macify-font'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp $asset[0].name
    Write-Host ("Downloading {0}..." -f $asset[0].name) -ForegroundColor Yellow
    Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $zip -TimeoutSec 120
    $ext = Join-Path $tmp 'extracted'
    if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $ext -Force
    $fonts = @(Get-ChildItem -Path $ext -Include '*.otf', '*.ttf', '*.ttc' -Recurse |
      Where-Object { $_.Name -match '(?i)^Inter(-(Regular|Medium|SemiBold|Bold|Light))?\.(otf|ttf|ttc)$' } |
      Select-Object -First 8)
    if ($fonts.Count -eq 0) {
      $fonts = @(Get-ChildItem -Path $ext -Include '*.otf', '*.ttf', '*.ttc' -Recurse | Select-Object -First 4)
    }
    if ($fonts.Count -eq 0) { throw 'no font files in archive' }
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    foreach ($f in $fonts) {
      Copy-Item $f.FullName -Destination (Join-Path $fontDir $f.Name) -Force
      $regName = 'Inter ({0})' -f $f.BaseName
      Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -Name $regName -Value $f.Name -Force
    }
    $res = [UIntPtr]::Zero
    Ensure-MacifyNative
    [Macify.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1d, [UIntPtr]::Zero, 0, 2, 3000, [ref]$res) | Out-Null
    Write-Host ("  [ok] Installed {0} Inter font files. Restart Macify to use them." -f $fonts.Count) -ForegroundColor Green
  } catch {
    Write-Host ("  [!!] Auto-install failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    Write-Host 'Manual: https://rsms.me/inter/ -> download, right-click font files -> Install'
  }
}

Write-Host ''
function Install-RainmeterWidgetPart {
  Write-Host ''
  Write-Host '--- Rainmeter desktop widgets (macOS clock + stats) ---' -ForegroundColor Cyan
  & (Join-Path $PSScriptRoot 'Install-RainmeterWidgets.ps1') -Silent:$Silent
}

Write-Host '==================== Macify Extras ====================' -ForegroundColor Magenta
Install-WingetApps
Install-MacCursors
Install-InterFont
Install-RainmeterWidgetPart
Write-Host ''
Write-Host 'Extras done.' -ForegroundColor Green
