# MacifySpotlight.ps1 - Spotlight-style launcher for Windows (PowerShell + WPF, zero dependencies).
# Alt+Space / Ctrl+Space anywhere to toggle. Searches apps, files, actions + calculator.

param([switch]$Hidden, [switch]$NoBlur)

. (Join-Path $PSScriptRoot 'MacifyLib.ps1')
$reArgs = @()
if ($NoBlur) { $reArgs += '-NoBlur' }
if ($Hidden) { $reArgs += '-Hidden' }
Confirm-MacifySTA -ScriptPath $PSCommandPath -ExtraArgs ($reArgs -join ' ')
if (-not (Test-MacifySingleInstance -Name 'Spotlight')) {
  try {
    $ev = [System.Threading.EventWaitHandle]::OpenExisting('Macify_Spotlight_Show')
    $ev.Set() | Out-Null
  } catch { }
  exit 0
}

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
Add-Type -AssemblyName PresentationCore -ErrorAction Stop
Add-Type -AssemblyName WindowsBase -ErrorAction Stop
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop

$cfg = Get-MacifyConfig
$script:isLight = ($cfg.theme -eq 'light') -or ($cfg.theme -eq 'auto' -and -not (Get-MacifyDarkMode))
$script:appCache = $null
$script:fileCache = $null
$script:results = @()

$fgMain = '#FFFFFFFF'
$fgDim = '#FFAAAAAA'
$bgMain = '#E6141414'
$sepBrush = '#33FFFFFF'
if ($script:isLight) { $fgMain = '#FF000000'; $fgDim = '#FF666666'; $bgMain = '#E6F2F2F7'; $sepBrush = '#33000000' }

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MacifySpotlight" Width="680" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True"
        Background="$bgMain" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Inter, Segoe UI">
  <Border CornerRadius="12" Background="Transparent">
    <StackPanel>
      <Grid Margin="18,14,18,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition/>
        </Grid.ColumnDefinitions>
        <TextBlock Text="&#x1F50D;" FontSize="20" VerticalAlignment="Center" Margin="0,0,12,0"/>
        <TextBox x:Name="QueryBox" Grid.Column="1" FontSize="22" Background="Transparent" BorderThickness="0"
                 Foreground="$fgMain" CaretBrush="$fgMain"/>
      </Grid>
      <Border x:Name="SepLine" Height="1" Background="$sepBrush" Margin="16,0" Visibility="Collapsed"/>
      <ListBox x:Name="ResultList" Background="Transparent" BorderThickness="0" Margin="8,6,8,10"
               MaxHeight="380" Visibility="Collapsed" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
    </StackPanel>
  </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$QueryBox = $window.FindName('QueryBox')
$ResultList = $window.FindName('ResultList')
$SepLine = $window.FindName('SepLine')
$window.Width = [int]$cfg.spotlight.width

function Get-SpotScore {
  param([string]$Name, [string]$Query)
  $n = $Name.ToLower()
  $q = $Query.ToLower()
  if ($q -eq '') { return -1 }
  if ($n -eq $q) { return 10000 }
  if ($n.StartsWith($q)) { return 5000 - $n.Length }
  $idx = $n.IndexOf($q)
  if ($idx -ge 0) { return 3000 - $idx * 10 - $n.Length }
  $qi = 0; $score = 0; $last = -2
  for ($i = 0; $i -lt $n.Length -and $qi -lt $q.Length; $i++) {
    if ($n[$i] -eq $q[$qi]) {
      $score += 10
      if ($last -eq ($i - 1)) { $score += 6 }
      if ($i -eq 0 -or $n[$i - 1] -eq ' ' -or $n[$i - 1] -eq '-') { $score += 8 }
      $last = $i; $qi++
    }
  }
  if ($qi -eq $q.Length) { return $score }
  return -1
}

function Get-SpotFiles {
  if ($null -ne $script:fileCache) { return $script:fileCache }
  $out = @()
  $dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'),
    (Join-Path $env:USERPROFILE 'Downloads'))
  foreach ($d in $dirs) {
    if (-not (Test-Path $d)) { continue }
    foreach ($f in (Get-ChildItem -Path $d -File -ErrorAction SilentlyContinue | Select-Object -First 200)) {
      if ($f.Attributes -band [System.IO.FileAttributes]::Hidden) { continue }
      $out += [PSCustomObject]@{ Name = $f.BaseName; Path = $f.FullName }
    }
  }
  $script:fileCache = $out
  return $out
}

function Get-SpotActions {
  return @(
    [PSCustomObject]@{ Name = 'Sleep'; Run = { Start-Process rundll32.exe 'powrprof.dll,SetSuspendState 0,1,0' } },
    [PSCustomObject]@{ Name = 'Shut Down'; Run = { Start-Process shutdown.exe '/s /t 5' } },
    [PSCustomObject]@{ Name = 'Restart'; Run = { Start-Process shutdown.exe '/r /t 5' } },
    [PSCustomObject]@{ Name = 'Lock Screen'; Run = { [Macify.Native]::LockWorkStation() } },
    [PSCustomObject]@{ Name = 'Log Out'; Run = { Start-Process shutdown.exe '/l' } },
    [PSCustomObject]@{ Name = 'Empty Trash'; Run = { Clear-MacifyTrash } },
    [PSCustomObject]@{ Name = 'Turn Dark Mode On'; Run = { Set-MacifyDarkMode Dark } },
    [PSCustomObject]@{ Name = 'Turn Dark Mode Off'; Run = { Set-MacifyDarkMode Light } },
    [PSCustomObject]@{ Name = 'Open System Settings'; Run = { Start-Process 'ms-settings:' } },
    [PSCustomObject]@{ Name = 'Take Screenshot'; Run = { Start-Process 'ms-screenclip:' } }
  )
}

function Update-SpotResults {
  $q = $QueryBox.Text.Trim()
  $ResultList.Items.Clear()
  $script:results = @()
  if ($q -eq '') { $ResultList.Visibility = 'Collapsed'; $SepLine.Visibility = 'Collapsed'; return }
  $max = [int]$cfg.spotlight.maxResults
  $cands = @()

  if ($q -match '^[0-9+\-*/().\s%^,]+$' -and $q -match '\d' -and $q -match '[+\-*/%^]') {
    $val = Invoke-SafeMath $q
    if ($null -ne $val) {
      $disp = if ($val -eq [Math]::Floor($val) -and [Math]::Abs($val) -lt 1e15) { '{0:N0}' -f $val } else { "$val" }
      $cands += [PSCustomObject]@{ Score = 20000; Kind = 'calc'; Label = "$q = $disp"; Value = "$val"; Glyph = '=' }
    }
  }

  if ($null -eq $script:appCache) { $script:appCache = @(Get-StartMenuApps) }
  foreach ($a in $script:appCache) {
    $s = Get-SpotScore $a.Name $q
    if ($s -ge 0) { $cands += [PSCustomObject]@{ Score = $s; Kind = 'app'; Label = $a.Name; Value = $a; Glyph = '' } }
  }
  foreach ($f in (Get-SpotFiles)) {
    $s = Get-SpotScore $f.Name $q
    if ($s -ge 0) { $cands += [PSCustomObject]@{ Score = $s - 500; Kind = 'file'; Label = $f.Name; Value = $f.Path; Glyph = '' } }
  }
  foreach ($a in (Get-SpotActions)) {
    $s = Get-SpotScore $a.Name $q
    if ($s -ge 0) { $cands += [PSCustomObject]@{ Score = $s - 200; Kind = 'action'; Label = $a.Name; Value = $a; Glyph = '>' } }
  }

  $top = @($cands | Sort-Object Score -Descending | Select-Object -First $max)
  $kindBrush = if ($script:isLight) { [Windows.Media.Brushes]::DarkGray } else { [Windows.Media.Brushes]::LightGray }
  $mainBrush = if ($script:isLight) { [Windows.Media.Brushes]::Black } else { [Windows.Media.Brushes]::White }
  foreach ($c in $top) {
    $li = New-Object Windows.Controls.ListBoxItem
    $li.Padding = '10,7'
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    if ($c.Kind -eq 'app') {
      $img = New-Object Windows.Controls.Image
      $img.Width = 26; $img.Height = 26; $img.Margin = '0,0,12,0'
      $icon = Get-AppIconSource -Target $c.Value.Target
      if ($icon -ne $null) { $img.Source = $icon }
      $sp.Children.Add($img) | Out-Null
    } else {
      $g = New-Object Windows.Controls.TextBlock
      $g.Width = 26; $g.Margin = '0,0,12,0'
      $g.Text = if ($c.Kind -eq 'calc') { '=' } elseif ($c.Kind -eq 'file') { 'Doc' } else { 'Cmd' }
      $g.Foreground = $kindBrush; $g.VerticalAlignment = 'Center'; $g.FontSize = 12
      $sp.Children.Add($g) | Out-Null
    }
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $c.Label; $tb.FontSize = 15; $tb.Foreground = $mainBrush; $tb.VerticalAlignment = 'Center'
    $sp.Children.Add($tb) | Out-Null
    $li.Content = $sp
    $li.Tag = $c
    $li.Add_MouseDoubleClick({ Invoke-SpotResult $li.Tag }.GetNewClosure())
    $li.Add_MouseLeftButtonUp({ Invoke-SpotResult $li.Tag }.GetNewClosure())
    $ResultList.Items.Add($li) | Out-Null
    $script:results += $c
  }
  if ($top.Count -eq 0) {
    $li = New-Object Windows.Controls.ListBoxItem
    $li.Padding = '10,7'
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = "Search the web for '$q'"; $tb.FontSize = 15; $tb.Foreground = $mainBrush
    $li.Content = $tb
    $li.Tag = [PSCustomObject]@{ Kind = 'web'; Label = $q; Value = $q }
    $li.Add_MouseLeftButtonUp({ Invoke-SpotResult $li.Tag }.GetNewClosure())
    $ResultList.Items.Add($li) | Out-Null
    $script:results += $li.Tag
  }
  $ResultList.Visibility = 'Visible'
  $SepLine.Visibility = 'Visible'
  if ($ResultList.Items.Count -gt 0) { $ResultList.SelectedIndex = 0 }
}

function Invoke-SpotResult {
  param($R)
  if ($null -eq $R) { return }
  try {
    switch ($R.Kind) {
      'app' {
        if ([string]::IsNullOrWhiteSpace($R.Value.Args)) { Start-Process $R.Value.Target }
        else { Start-Process $R.Value.Target -ArgumentList $R.Value.Args }
      }
      'file' { Start-Process $R.Value }
      'action' { & ($R.Value.Run) }
      'calc' { [System.Windows.Forms.Clipboard]::SetText($R.Value) }
      'web' { Start-Process ('https://www.google.com/search?q=' + [Uri]::EscapeDataString($R.Value)) }
    }
  } catch { Show-MacifyToast -Title 'Spotlight' -Message 'Could not open that item.' }
  Hide-Spotlight
}

function Show-Spotlight {
  $wa = [Windows.SystemParameters]::WorkArea
  $window.Left = ($wa.Width - $window.Width) / 2
  $window.Top = $wa.Height * 0.22
  if ($window.Visibility -ne 'Visible') { $window.Show() }
  $window.Activate() | Out-Null
  $QueryBox.Focus() | Out-Null
  $QueryBox.SelectAll()
}

function Hide-Spotlight {
  $QueryBox.Text = ''
  $window.Hide()
}

function Toggle-Spotlight {
  if ($window.Visibility -eq 'Visible' -and $window.IsActive) { Hide-Spotlight } else { Show-Spotlight }
}

$QueryBox.Add_TextChanged({ try { Update-SpotResults } catch { } }.GetNewClosure())
$QueryBox.Add_PreviewKeyDown({
  param($s, $e)
  if ($e.Key -eq 'Escape') { Hide-Spotlight; $e.Handled = $true }
  elseif ($e.Key -eq 'Enter') {
    if ($ResultList.SelectedItem -ne $null) { Invoke-SpotResult $ResultList.SelectedItem.Tag }
    elseif ($script:results.Count -gt 0) { Invoke-SpotResult $script:results[0] }
    $e.Handled = $true
  } elseif ($e.Key -eq 'Down') {
    if ($ResultList.Items.Count -gt 0) {
      $ResultList.Focus() | Out-Null
      if ($ResultList.SelectedIndex -lt 0) { $ResultList.SelectedIndex = 0 }
    }
    $e.Handled = $true
  }
}.GetNewClosure())
$ResultList.Add_PreviewKeyDown({
  param($s, $e)
  if ($e.Key -eq 'Escape') { Hide-Spotlight; $e.Handled = $true }
  elseif ($e.Key -eq 'Enter' -and $ResultList.SelectedItem -ne $null) { Invoke-SpotResult $ResultList.SelectedItem.Tag; $e.Handled = $true }
  elseif ($e.Key -eq 'Up' -and $ResultList.SelectedIndex -le 0) { $QueryBox.Focus() | Out-Null; $e.Handled = $true }
}.GetNewClosure())
$window.Add_Deactivated({ if ($window.Visibility -eq 'Visible') { Hide-Spotlight } }.GetNewClosure())

# Show-signal from second instances (e.g. menu-bar search button)
$script:showEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Macify_Spotlight_Show')
$sigTimer = New-Object Windows.Threading.DispatcherTimer
$sigTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$sigTimer.Add_Tick({ if ($script:showEvent.WaitOne(0)) { Show-Spotlight } }.GetNewClosure())
$sigTimer.Start()

$window.Add_SourceInitialized({
  try {
    $hwnd = (New-Object Windows.Interop.WindowInteropHelper($window)).Handle
    $ex = [Macify.Native]::GetWindowLong($hwnd, -20)
    [Macify.Native]::SetWindowLong($hwnd, -20, ($ex -bor 0x80)) | Out-Null
    if (-not $NoBlur) { Enable-MacifyBlur -Hwnd $hwnd -Style (($(if ($script:isLight) { 'Light' } else { 'Dark' }))) }
    $ok1 = $ok2 = $false
    foreach ($hk in @([string[]]$cfg.spotlight.hotkeys)) {
      if ($hk -eq 'Alt+Space') { $ok1 = [Macify.Native]::RegisterHotKey($hwnd, 1, 1, 0x20) }
      if ($hk -eq 'Ctrl+Space') { $ok2 = [Macify.Native]::RegisterHotKey($hwnd, 2, 2, 0x20) }
    }
    if (-not ($ok1 -or $ok2)) {
      Show-MacifyToast -Title 'Spotlight' -Message 'Could not register Alt+Space / Ctrl+Space (another app uses it).'
    }
    $src = [Windows.Interop.HwndSource]::FromHwnd($hwnd)
    $hook = [Windows.Interop.HwndSourceHook]{
      param($h, $msg, $wp, $lp, [ref]$handled)
      if ($msg -eq 0x0312) { Toggle-Spotlight; $handled.Value = $true; return [IntPtr]::Zero }
      return [IntPtr]::Zero
    }
    $src.AddHook($hook)
  } catch { Write-MacifyLog "Spotlight init: $($_.Exception.Message)" 'WARN' }
}.GetNewClosure())

$window.Add_Closed({
  try {
    $h = (New-Object Windows.Interop.WindowInteropHelper($window)).Handle
    [Macify.Native]::UnregisterHotKey($h, 1) | Out-Null
    [Macify.Native]::UnregisterHotKey($h, 2) | Out-Null
  } catch { }
  [Windows.Application]::Current.Shutdown()
}.GetNewClosure())

Write-MacifyLog 'MacifySpotlight started.'
$app = New-Object Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
if ($Hidden) { $window.Visibility = 'Hidden'; [void]$app.Run() }
else {
  $wa0 = [Windows.SystemParameters]::WorkArea
  $window.Left = ($wa0.Width - $window.Width) / 2
  $window.Top = $wa0.Height * 0.22
  [void]$app.Run($window)
}
