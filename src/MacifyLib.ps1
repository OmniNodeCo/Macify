# MacifyLib.ps1 - shared helpers for all Macify components.
# Windows PowerShell 5.1 compatible. Import by dot-sourcing; defines functions only.
# Requires: Windows 10 1809+ / Windows 11.

$script:MacifyRoot = Split-Path -Parent $PSScriptRoot
$script:MacifyNativeLoaded = $false

function Get-MacifyPaths {
  $appData = Join-Path $env:APPDATA 'Macify'
  return @{
    Root     = $script:MacifyRoot
    Src      = Join-Path $script:MacifyRoot 'src'
    Config   = Join-Path $script:MacifyRoot 'config'
    Assets   = Join-Path $script:MacifyRoot 'assets'
    Tools    = Join-Path $script:MacifyRoot 'tools'
    AppData  = $appData
    UserCfg  = Join-Path $appData 'config.json'
    UserDock = Join-Path $appData 'dock.json'
    LogDir   = Join-Path $appData 'logs'
  }
}

function Write-MacifyLog {
  param([string]$Message, [string]$Level = 'INFO')
  try {
    $p = Get-MacifyPaths
    if (-not (Test-Path $p.LogDir)) { New-Item -ItemType Directory -Path $p.LogDir -Force | Out-Null }
    $line = ('[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
    Add-Content -Path (Join-Path $p.LogDir 'macify.log') -Value $line -Encoding UTF8 -ErrorAction Stop
  } catch { }
  Write-Verbose $Message
}

function Merge-MacifyObject {
  # Deep-merge $Override (PSCustomObject) over $Base (PSCustomObject). Returns $Base mutated.
  param($Base, $Override)
  if ($null -eq $Override) { return $Base }
  foreach ($prop in $Override.PSObject.Properties) {
    $b = $Base.PSObject.Properties[$prop.Name]
    if ($null -ne $b -and $b.Value -is [PSCustomObject] -and $prop.Value -is [PSCustomObject]) {
      Merge-MacifyObject -Base $b.Value -Override $prop.Value | Out-Null
    } else {
      $Base | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    }
  }
  return $Base
}

function Get-MacifyConfig {
  $p = Get-MacifyPaths
  $cfg = Get-Content (Join-Path $p.Config 'theme.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if (Test-Path $p.UserCfg) {
    try {
      $user = Get-Content $p.UserCfg -Raw -Encoding UTF8 | ConvertFrom-Json
      $cfg = Merge-MacifyObject -Base $cfg -Override $user
    } catch { Write-MacifyLog "User config invalid, using defaults: $($_.Exception.Message)" 'WARN' }
  }
  return $cfg
}

function Get-MacifyDockItems {
  $p = Get-MacifyPaths
  $file = Join-Path $p.Config 'dock-items.json'
  if (Test-Path $p.UserDock) { $file = $p.UserDock }
  try {
    return @(Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json)
  } catch {
    Write-MacifyLog "Dock items invalid, using defaults: $($_.Exception.Message)" 'WARN'
    return @(Get-Content (Join-Path $p.Config 'dock-items.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
  }
}

function Save-MacifyDockItems {
  param([Parameter(Mandatory = $true)]$Items)
  $p = Get-MacifyPaths
  if (-not (Test-Path $p.AppData)) { New-Item -ItemType Directory -Path $p.AppData -Force | Out-Null }
  ($Items | ConvertTo-Json -Depth 5) | Set-Content $p.UserDock -Encoding UTF8
}

function Confirm-MacifySTA {
  # Relaunch this script with -STA if needed (WPF requires STA).
  param([string]$ScriptPath, [string]$ExtraArgs = '')
  if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $arg = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}" {1}' -f $ScriptPath, $ExtraArgs
    $psi = New-Object System.Diagnostics.ProcessStartInfo('powershell.exe', $arg)
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    exit 0
  }
}

function Test-MacifySingleInstance {
  # Returns $true if this is the first instance; otherwise $false (caller should exit).
  param([Parameter(Mandatory = $true)][string]$Name)
  $created = $false
  $script:__macifyMutex = New-Object System.Threading.Mutex($true, ('Global\Macify_{0}' -f $Name), [ref]$created)
  return $created
}

function Ensure-MacifyNative {
  # Lazy-load P/Invoke helpers (user32/gdi32/shell32). Safe to call repeatedly.
  if ($script:MacifyNativeLoaded) { return }
  try { if ($null -ne ([System.Type]::GetType('Macify.Native'))) { $script:MacifyNativeLoaded = $true; return } } catch { }
  $code = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace Macify {
  public static class Native {
    [StructLayout(LayoutKind.Sequential)]
    public struct AccentPolicy { public int AccentState; public int AccentFlags; public uint GradientColor; public int AnimationId; }
    [StructLayout(LayoutKind.Sequential)]
    public struct WCAData { public int Attribute; public IntPtr Data; public int SizeOfData; }
    [DllImport("user32.dll")] public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WCAData data);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mod, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int idx);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int idx, int val);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int SystemParametersInfo(int act, int param, string path, int flags);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr w, string l, uint flags, uint timeout, out UIntPtr res);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr h);
    [DllImport("user32.dll")] public static extern void LockWorkStation();
    public static void Blur(IntPtr hwnd, int state, uint color) {
      AccentPolicy p = new AccentPolicy();
      p.AccentState = state; p.AccentFlags = 2; p.GradientColor = color; p.AnimationId = 0;
      int s = Marshal.SizeOf(p);
      IntPtr ptr = Marshal.AllocHGlobal(s);
      try {
        Marshal.StructureToPtr(p, ptr, false);
        WCAData d = new WCAData();
        d.Attribute = 19; d.Data = ptr; d.SizeOfData = s;
        SetWindowCompositionAttribute(hwnd, ref d);
      } finally { Marshal.FreeHGlobal(ptr); }
    }
  }
}
'@
  try {
    Add-Type -TypeDefinition $code -Language CSharp -ErrorAction Stop | Out-Null
    $script:MacifyNativeLoaded = $true
  } catch {
    Write-MacifyLog "Failed to load native helpers: $($_.Exception.Message)" 'WARN'
  }
}

function Enable-MacifyBlur {
  param([Parameter(Mandatory = $true)][IntPtr]$Hwnd, [ValidateSet('Dark', 'Light', 'Plain')][string]$Style = 'Dark')
  Ensure-MacifyNative
  if (-not $script:MacifyNativeLoaded) { return }
  try {
    if ($Style -eq 'Light') { [Macify.Native]::Blur($Hwnd, 4, 0x99F2F2F2) }
    elseif ($Style -eq 'Plain') { [Macify.Native]::Blur($Hwnd, 3, 0) }
    else { [Macify.Native]::Blur($Hwnd, 4, 0xCC141414) }
  } catch {
    try { [Macify.Native]::Blur($Hwnd, 3, 0) } catch { }
  }
}

function Show-MacifyToast {
  param([string]$Title = 'Macify', [string]$Message = '')
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop | Out-Null
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Icon = [System.Drawing.SystemIcons]::Information
    $ni.Visible = $true
    $ni.ShowBalloonTip(3500, $Title, $Message, [System.Windows.Forms.ToolTipIcon]::None)
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(5)
    $timer.Add_Tick({ $timer.Stop(); $ni.Visible = $false; $ni.Dispose() }.GetNewClosure())
    $timer.Start()
  } catch { Write-Host "${Title}: ${Message}" }
}

function Get-MacifyProcesses {
  # All powershell processes whose command line mentions $Match (case-insensitive).
  param([Parameter(Mandatory = $true)][string]$Match)
  try {
    return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop |
      Where-Object { $_.CommandLine -and $_.CommandLine.ToLower().Contains($Match.ToLower()) })
  } catch { return @() }
}

function Stop-MacifyComponent {
  param([Parameter(Mandatory = $true)][string]$Match)
  foreach ($proc in Get-MacifyProcesses -Match $Match) {
    try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop } catch { }
  }
}

function Start-MacifyComponent {
  param([Parameter(Mandatory = $true)][string]$ScriptPath, [string]$ExtraArgs = '')
  $arg = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}" {1}' -f $ScriptPath, $ExtraArgs
  Start-Process -FilePath 'powershell.exe' -ArgumentList $arg -WorkingDirectory (Split-Path $ScriptPath -Parent) | Out-Null
}

function Toggle-MacifyComponent {
  # If a component is running, stop it; otherwise start it.
  param([Parameter(Mandatory = $true)][string]$Match, [Parameter(Mandatory = $true)][string]$ScriptPath, [string]$ExtraArgs = '')
  if (@(Get-MacifyProcesses -Match $Match).Count -gt 0) { Stop-MacifyComponent -Match $Match }
  else { Start-MacifyComponent -ScriptPath $ScriptPath -ExtraArgs $ExtraArgs }
}

function Set-MacifyWallpaper {
  param([Parameter(Mandatory = $true)][string]$Path)
  Ensure-MacifyNative
  if (-not (Test-Path $Path)) { throw "Wallpaper not found: $Path" }
  Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10' -Force
  Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0' -Force
  $r = [Macify.Native]::SystemParametersInfo(20, 0, (Resolve-Path $Path).Path, 3)
  if ($r -eq 0) { throw 'SystemParametersInfo failed to set wallpaper.' }
}

function Get-MacifyDarkMode {
  try { return ((Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme) -eq 0) }
  catch { return $true }
}

function Set-MacifyDarkMode {
  param([ValidateSet('Dark', 'Light')][string]$Mode = 'Dark')
  Ensure-MacifyNative
  $v = if ($Mode -eq 'Dark') { 0 } else { 1 }
  $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
  Set-ItemProperty -Path $key -Name AppsUseLightTheme -Value $v -Type DWord -Force
  Set-ItemProperty -Path $key -Name SystemUsesLightTheme -Value $v -Type DWord -Force
  try {
    $res = [UIntPtr]::Zero
    [Macify.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 3000, [ref]$res) | Out-Null
  } catch { }
}

function Invoke-SafeMath {
  # Tiny safe expression evaluator (+ - * / % ^ and parens). Returns [double] or $null.
  param([string]$Expr = '')
  $s = ($Expr -replace '\s+', '')
  if ($s -notmatch '^[0-9+\-*/().%^,]+$' -or $s -eq '') { return $null }
  $s = $s -replace ',', '.'
  try {
    $script:__toks = @()
    $i = 0
    while ($i -lt $s.Length) {
      $ch = $s[$i]
      if ($ch -match '[0-9.]') {
        $num = ''
        while ($i -lt $s.Length -and $s[$i] -match '[0-9.]') { $num += $s[$i]; $i++ }
        $v = 0.0
        if (-not [double]::TryParse($num, [ref]$v)) { return $null }
        $script:__toks += @{ T = 'n'; V = $v }
      } elseif ('+-*/%^()'.Contains($ch)) {
        $script:__toks += @{ T = 'o'; V = [string]$ch }; $i++
      } else { return $null }
    }
    $script:__pos = 0
    $peek = { if ($script:__pos -lt $script:__toks.Count) { $script:__toks[$script:__pos] } else { $null } }
    $next = { $t = & $peek; $script:__pos++; $t }
    $parseExpr = $null; $parseTerm = $null; $parseFactor = $null; $parsePow = $null
    $parseExpr = {
      $v = & $parseTerm; if ($null -eq $v) { return $null }
      while (($t = & $peek) -and $t.T -eq 'o' -and ($t.V -eq '+' -or $t.V -eq '-')) {
        $op = (& $next).V; $r = & $parseTerm; if ($null -eq $r) { return $null }
        if ($op -eq '+') { $v += $r } else { $v -= $r }
      }
      return $v
    }
    $parseTerm = {
      $v = & $parsePow; if ($null -eq $v) { return $null }
      while (($t = & $peek) -and $t.T -eq 'o' -and ($t.V -eq '*' -or $t.V -eq '/' -or $t.V -eq '%')) {
        $op = (& $next).V; $r = & $parsePow; if ($null -eq $r) { return $null }
        if ($op -eq '*') { $v *= $r }
        elseif ($op -eq '/') { if ($r -eq 0) { return $null }; $v /= $r }
        else { if ($r -eq 0) { return $null }; $v = $v % $r }
      }
      return $v
    }
    $parsePow = {
      $v = & $parseFactor; if ($null -eq $v) { return $null }
      $t = & $peek
      if ($t -and $t.T -eq 'o' -and $t.V -eq '^') { & $next | Out-Null; $r = & $parsePow; if ($null -eq $r) { return $null }; $v = [Math]::Pow($v, $r) }
      return $v
    }
    $parseFactor = {
      $t = & $peek; if ($null -eq $t) { return $null }
      if ($t.T -eq 'o' -and $t.V -eq '(') {
        & $next | Out-Null; $v = & $parseExpr
        $c = & $peek
        if ($null -eq $c -or $c.T -ne 'o' -or $c.V -ne ')') { return $null }
        & $next | Out-Null; return $v
      }
      if ($t.T -eq 'o' -and ($t.V -eq '-' -or $t.V -eq '+')) {
        $op = (& $next).V; $v = & $parseFactor; if ($null -eq $v) { return $null }
        if ($op -eq '-') { return -$v } else { return $v }
      }
      if ($t.T -eq 'n') { & $next | Out-Null; return $t.V }
      return $null
    }
    $out = & $parseExpr
    if ($script:__pos -ne $script:__toks.Count) { return $null }
    return $out
  } catch { return $null }
}

function Get-StartMenuApps {
  # Enumerate Start Menu shortcuts. Returns Name/Target/Args/Lnk sorted, de-duplicated.
  $dirs = @(
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
  )
  $seen = @{}
  $out = @()
  $shell = $null
  try { $shell = New-Object -ComObject WScript.Shell -ErrorAction Stop } catch { return @() }
  foreach ($d in $dirs) {
    if (-not (Test-Path $d)) { continue }
    foreach ($lnk in (Get-ChildItem -Path $d -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue)) {
      try {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($lnk.Name)
        if ($name -match 'uninstall|remove|help|readme|documentation|privacy|terms' -or $seen.ContainsKey($name.ToLower())) { continue }
        $sc = $shell.CreateShortcut($lnk.FullName)
        $target = $sc.TargetPath
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        $seen[$name.ToLower()] = $true
        $out += [PSCustomObject]@{ Name = $name; Target = $target; Args = $sc.Arguments; Icon = $sc.IconLocation; Lnk = $lnk.FullName }
      } catch { }
    }
  }
  try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null } catch { }
  return @($out | Sort-Object Name)
}

function Get-AppIconSource {
  # Extract an .exe/.lnk icon as a WPF ImageSource. Returns $null on failure.
  param([string]$Target = '', [int]$Size = 48)
  if ([string]::IsNullOrWhiteSpace($Target)) { return $null }
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop | Out-Null
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($Target)
    if ($null -eq $icon) { return $null }
    $bmp = $icon.ToBitmap()
    $h = $bmp.GetHbitmap()
    try {
      return [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap(
        $h, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty,
        [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
    } finally {
      Ensure-MacifyNative
      try { [Macify.Native]::DeleteObject($h) | Out-Null } catch { }
      $bmp.Dispose(); $icon.Dispose()
    }
  } catch { return $null }
}

function Get-ForegroundApp {
  Ensure-MacifyNative
  if (-not $script:MacifyNativeLoaded) { return $null }
  try {
    $hwnd = [Macify.Native]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return $null }
    $fgPid = 0
    [Macify.Native]::GetWindowThreadProcessId($hwnd, [ref]$fgPid) | Out-Null
    $sb = New-Object System.Text.StringBuilder(512)
    [Macify.Native]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    $proc = Get-Process -Id $fgPid -ErrorAction Stop
    $label = $proc.ProcessName
    try {
      $desc = $proc.MainModule.FileVersionInfo.FileDescription
      if (-not [string]::IsNullOrWhiteSpace($desc)) { $label = $desc }
    } catch { }
    return [PSCustomObject]@{ Hwnd = $hwnd; Pid = $fgPid; Process = $proc.ProcessName; Label = $label; Title = $sb.ToString() }
  } catch { return $null }
}

function Get-BatteryInfo {
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
    $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
    $pct = [int][Math]::Round($ps.BatteryLifePercent * 100)
    return [PSCustomObject]@{ Percent = $pct; Charging = ($ps.PowerLineStatus -eq 'Online'); Present = ($ps.BatteryChargeStatus -ne 'NoSystemBattery') }
  } catch { return [PSCustomObject]@{ Percent = -1; Charging = $false; Present = $false } }
}

function Get-WifiSsid {
  try {
    $lines = netsh wlan show interfaces 2>$null
    foreach ($ln in $lines) {
      if ($ln -match '^\s*SSID\s*:\s*(.+?)\s*$') {
        $v = $Matches[1].Trim()
        if ($v -ne '') { return $v }
      }
    }
  } catch { }
  return $null
}

function Get-TrashCount {
  try {
    $sh = New-Object -ComObject Shell.Application -ErrorAction Stop
    $n = $sh.Namespace(0xA).Items().Count
    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null } catch { }
    return $n
  } catch { return 0 }
}

function Clear-MacifyTrash {
  try { Clear-RecycleBin -Force -ErrorAction Stop }
  catch {
    try {
      $sh = New-Object -ComObject Shell.Application
      $items = $sh.Namespace(0xA).Items()
      for ($i = $items.Count - 1; $i -ge 0; $i--) { $items.Item($i).InvokeVerb('delete') }
    } catch { throw }
  }
}

function Resolve-MacifyTarget {
  # Expand env vars + handle auto: pseudo targets. Returns @{ Path; Args }.
  param([string]$Target = '', [string]$Args = '')
  $t = [System.Environment]::ExpandEnvironmentVariables($Target)
  if ($t -eq 'auto:browser') {
    foreach ($c in @("$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe")) {
      if (Test-Path $c) { return @{ Path = $c; Args = '' } }
    }
    return @{ Path = 'https://www.google.com/'; Args = '' }
  }
  if ($t -eq 'auto:terminal') {
    $wt = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
    if (Test-Path $wt) { return @{ Path = $wt; Args = '' } }
    return @{ Path = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"; Args = '' }
  }
  return @{ Path = $t; Args = $Args }
}

function Start-MacifyTarget {
  param([string]$Target = '', [string]$Args = '')
  $r = Resolve-MacifyTarget -Target $Target -Args $Args
  if ($r.Path -match '^(macify:|auto:)') { return }
  try {
    if ([string]::IsNullOrWhiteSpace($r.Args)) { Start-Process -FilePath $r.Path -ErrorAction Stop }
    else { Start-Process -FilePath $r.Path -ArgumentList $r.Args -ErrorAction Stop }
  } catch {
    Write-MacifyLog "Launch failed ($($r.Path)): $($_.Exception.Message)" 'WARN'
    Show-MacifyToast -Title 'Macify' -Message ("Could not open: " + $r.Path)
  }
}
