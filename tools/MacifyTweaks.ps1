# MacifyTweaks.ps1 - macOS-style Windows tweaks with full backup + restore.
# Everything is HKCU (current user) only: no admin rights needed, fully reversible.
#
#   powershell -ExecutionPolicy Bypass -File tools\MacifyTweaks.ps1 -Apply
#   powershell -ExecutionPolicy Bypass -File tools\MacifyTweaks.ps1 -Restore
#
# -Apply [-WallpaperPath <jpg>] [-NoAutoHide] [-NoSounds] [-NoExplorerRestart]

param(
  [switch]$Apply,
  [switch]$Restore,
  [string]$BackupPath = '',
  [string]$WallpaperPath = '',
  [switch]$NoAutoHide,
  [switch]$NoSounds,
  [switch]$NoExplorerRestart
)

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\MacifyLib.ps1')

if ($BackupPath -eq '') {
  $BackupPath = Join-Path (Get-MacifyPaths).AppData 'tweaks-backup.json'
}

function Get-TweakList {
  # macOS blue #0A84FF as ABGR DWORD = 0xFFFF840A
  $accentBlue = 4294946314
  return @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme';   Type = 'DWord'; Value = 0;          Label = 'Apps dark mode' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Type = 'DWord'; Value = 0;          Label = 'System dark mode' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency';   Type = 'DWord'; Value = 1;          Label = 'Transparency effects' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'ColorPrevalence';      Type = 'DWord'; Value = 0;          Label = 'Neutral title bars' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AccentColor';          Type = 'DWord'; Value = $accentBlue; Label = 'macOS blue accent' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'TaskbarAl';            Type = 'DWord'; Value = 1;          Label = 'Centered taskbar icons (Win11)' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'TaskbarDa';            Type = 'DWord'; Value = 0;          Label = 'Hide Widgets button' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'TaskbarMn';            Type = 'DWord'; Value = 0;          Label = 'Hide Chat button' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'ShowTaskViewButton';    Type = 'DWord'; Value = 0;          Label = 'Hide Task View button' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'SearchboxTaskbarMode';  Type = 'DWord'; Value = 0;          Label = 'Hide taskbar search box' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'HideIcons';            Type = 'DWord'; Value = 1;          Label = 'Hide desktop icons' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'LaunchTo';             Type = 'DWord'; Value = 1;          Label = 'Explorer opens to This PC' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'HideFileExt';          Type = 'DWord'; Value = 0;          Label = 'Show file extensions' },
    @{ Path = 'HKCU:\Control Panel\Desktop';                                        Name = 'MenuShowDelay';         Type = 'String'; Value = '100';     Label = 'Snappy menus' }
  )
}

function Get-SoundTweaks {
  param([string]$SoundDir)
  return @(
    @{ Sub = '.Default\SystemAsterisk\.Current';     File = 'chime.wav' },
    @{ Sub = '.Default\SystemExclamation\.Current';  File = 'pop.wav' },
    @{ Sub = '.Default\SystemNotification\.Current'; File = 'glass.wav' }
  ) | ForEach-Object {
    [PSCustomObject]@{
      Path  = ('HKCU:\AppEvents\Schemes\Apps' + '\' + $_.Sub)
      Name  = '(Default)'
      Type  = 'String'
      Value = (Join-Path $SoundDir $_.File)
      Label = ('System sound: ' + $_.File)
    }
  }
}

function Read-RegValue {
  param([string]$Path, [string]$Name)
  try {
    $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
    return @{ Existed = $true; Value = $prop.$Name }
  } catch { return @{ Existed = $false; Value = $null } }
}

function Write-RegValue {
  param([string]$Path, [string]$Name, [string]$Type, $Value)
  if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
  if ($Name -eq '(Default)') {
    Set-ItemProperty -Path $Path -Name '(Default)' -Value ([string]$Value) -Force
    return
  }
  switch ($Type) {
    'DWord'  { Set-ItemProperty -Path $Path -Name $Name -Value ([uint32]$Value) -Type DWord -Force }
    'String' { Set-ItemProperty -Path $Path -Name $Name -Value ([string]$Value) -Type String -Force }
    'Binary' { Set-ItemProperty -Path $Path -Name $Name -Value ([byte[]]$Value) -Type Binary -Force }
    default  { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force }
  }
}

function Backup-TweakValues {
  param($Tweaks)
  $vals = @()
  foreach ($t in $Tweaks) {
    $cur = Read-RegValue -Path $t.Path -Name $t.Name
    $old = $cur.Value
    if ($t.Type -eq 'Binary' -and $cur.Existed) { $old = [Convert]::ToBase64String([byte[]]$cur.Value) }
    if ($t.Type -eq 'DWord' -and $cur.Existed) { $old = [uint32]$cur.Value }
    $vals += [PSCustomObject]@{
      path = $t.Path; name = $t.Name; type = $t.Type
      existed = [bool]$cur.Existed; old = $old
    }
  }
  return $vals
}

function Restart-MacExplorer {
  Write-Host 'Restarting Explorer to apply taskbar changes...' -ForegroundColor Yellow
  try { Stop-Process -Name explorer -Force -ErrorAction Stop } catch { }
  Start-Sleep -Seconds 3
  if (@(Get-Process -Name explorer -ErrorAction SilentlyContinue).Count -eq 0) {
    Start-Process explorer.exe
  }
}

function Invoke-Apply {
  $tweaks = Get-TweakList
  $soundDir = Join-Path (Get-MacifyPaths).Root 'assets\sounds'
  if (-not $NoSounds -and (Test-Path $soundDir)) {
    $tweaks += @(Get-SoundTweaks -SoundDir $soundDir)
  }
  if (-not $NoAutoHide) {
    $tweaks += [PSCustomObject]@{
      Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
      Name = 'Settings'; Type = 'Binary'; Value = '__AUTOHIDE__'; Label = 'Auto-hide taskbar'
    }
  }

  Write-Host ''
  Write-Host 'Backing up current settings...' -ForegroundColor Cyan
  $backup = [PSCustomObject]@{
    created   = (Get-Date -Format 'o')
    values    = @(Backup-TweakValues -Tweaks $tweaks)
    wallpaper = ''
  }
  try { $backup.wallpaper = (Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction Stop) } catch { }
  $bdir = Split-Path $BackupPath -Parent
  if (-not (Test-Path $bdir)) { New-Item -ItemType Directory -Path $bdir -Force | Out-Null }
  ($backup | ConvertTo-Json -Depth 6) | Set-Content $BackupPath -Encoding UTF8
  Write-Host ("Backup saved: {0}" -f $BackupPath) -ForegroundColor Green

  Write-Host ''
  Write-Host 'Applying macOS-style tweaks:' -ForegroundColor Cyan
  foreach ($t in $tweaks) {
    try {
      if ($t.Value -eq '__AUTOHIDE__') {
        $cur = (Get-ItemProperty -Path $t.Path -Name $t.Name -ErrorAction Stop).Settings
        $bytes = [byte[]]$cur.Clone()
        if ($bytes.Length -gt 8) { $bytes[8] = ($bytes[8] -band 0xFE) -bor 0x01 }
        Write-RegValue -Path $t.Path -Name $t.Name -Type 'Binary' -Value $bytes
      } else {
        Write-RegValue -Path $t.Path -Name $t.Name -Type $t.Type -Value $t.Value
      }
      Write-Host ("  [ok] {0}" -f $t.Label) -ForegroundColor Green
    } catch {
      Write-Host ("  [!!] {0}: {1}" -f $t.Label, $_.Exception.Message) -ForegroundColor Red
    }
  }

  if ($WallpaperPath -ne '' -and (Test-Path $WallpaperPath)) {
    try {
      Set-MacifyWallpaper -Path $WallpaperPath
      Write-Host '  [ok] Wallpaper' -ForegroundColor Green
    } catch { Write-Host ("  [!!] Wallpaper: {0}" -f $_.Exception.Message) -ForegroundColor Red }
  }

  try {
    Ensure-MacifyNative
    $res = [UIntPtr]::Zero
    [Macify.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 3000, [ref]$res) | Out-Null
    [Macify.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Policy', 2, 3000, [ref]$res) | Out-Null
  } catch { }

  if (-not $NoExplorerRestart -and -not $NoAutoHide) { Restart-MacExplorer }
  Write-MacifyLog 'Tweaks applied.'
  Write-Host ''
  Write-Host 'Done. If anything looks off, run:  .\Uninstall.ps1  (it restores this backup)' -ForegroundColor Cyan
}

function Invoke-Restore {
  if (-not (Test-Path $BackupPath)) {
    Write-Host ("No backup found at {0} - nothing to restore." -f $BackupPath) -ForegroundColor Yellow
    return
  }
  $backup = Get-Content $BackupPath -Raw -Encoding UTF8 | ConvertFrom-Json
  Write-Host ''
  Write-Host 'Restoring your original Windows settings...' -ForegroundColor Cyan
  $needExplorer = $false
  foreach ($v in $backup.values) {
    try {
      if (-not $v.existed) {
        Remove-ItemProperty -Path $v.path -Name $v.name -Force -ErrorAction SilentlyContinue
      } else {
        $val = $v.old
        if ($v.type -eq 'Binary') { $val = [Convert]::FromBase64String($v.old) }
        if ($v.type -eq 'DWord') { $val = [uint32]$v.old }
        Write-RegValue -Path $v.path -Name $v.name -Type $v.type -Value $val
      }
      if ($v.path -match 'StuckRects3|Explorer\\Advanced') { $needExplorer = $true }
      Write-Host ("  [ok] {0}\{1}" -f $v.path, $v.name) -ForegroundColor Green
    } catch {
      Write-Host ("  [!!] {0}: {1}" -f $v.name, $_.Exception.Message) -ForegroundColor Red
    }
  }
  if ($backup.wallpaper -ne '' -and (Test-Path $backup.wallpaper)) {
    try { Set-MacifyWallpaper -Path $backup.wallpaper; Write-Host '  [ok] Wallpaper restored' -ForegroundColor Green }
    catch { Write-Host '  [!!] Wallpaper restore failed (file may be gone)' -ForegroundColor Yellow }
  }
  try {
    Ensure-MacifyNative
    $res = [UIntPtr]::Zero
    [Macify.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 3000, [ref]$res) | Out-Null
  } catch { }
  if ($needExplorer -and -not $NoExplorerRestart) { Restart-MacExplorer }
  Write-MacifyLog 'Tweaks restored from backup.'
  Write-Host ''
  Write-Host 'Restore complete.' -ForegroundColor Green
}

if ($Restore) { Invoke-Restore; exit 0 }
if ($Apply) { Invoke-Apply; exit 0 }
Write-Host 'Usage: MacifyTweaks.ps1 -Apply [-WallpaperPath x] [-NoAutoHide] [-NoSounds] | -Restore'
exit 1
