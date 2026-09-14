# MacifyDock.ps1 - macOS-style centered dock for Windows (PowerShell + WPF, zero dependencies).
# Features: hover magnification, running indicators, right-click menus, Launchpad,
# Trash with count, optional auto-hide. Pinned apps editable at runtime.

param([switch]$NoBlur)

. (Join-Path $PSScriptRoot 'MacifyLib.ps1')
Confirm-MacifySTA -ScriptPath $PSCommandPath -ExtraArgs $(if ($NoBlur) { '-NoBlur' } else { '' })
if (-not (Test-MacifySingleInstance -Name 'Dock')) { exit 0 }

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
Add-Type -AssemblyName PresentationCore -ErrorAction Stop
Add-Type -AssemblyName WindowsBase -ErrorAction Stop
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop

$cfg = Get-MacifyConfig
$paths = Get-MacifyPaths
$script:isLight = ($cfg.theme -eq 'light') -or ($cfg.theme -eq 'auto' -and -not (Get-MacifyDarkMode))
$script:baseSize = [int]$cfg.dock.iconSize
$script:maxSize = [int]$cfg.dock.maxSize
$script:marginBottom = [int]$cfg.dock.marginBottom
$script:hidden = $false
$script:iconCache = @{}
$script:items = @()
$script:launchpadWin = $null
$script:appCache = $null

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MacifyDock" SizeToContent="WidthAndHeight" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Inter, Segoe UI">
  <Border x:Name="DockBorder" CornerRadius="20" Background="#66141414" Padding="10,8,10,6" BorderBrush="#33FFFFFF" BorderThickness="1">
    <StackPanel x:Name="DockPanel" Orientation="Horizontal" VerticalAlignment="Bottom"/>
  </Border>
</Window>
"@
if ($script:isLight) { $xaml = $xaml.Replace('#66141414', '#66F2F2F7').Replace('#33FFFFFF', '#33000000') }

$reader = New-Object System.Xml.XmlNodeReader([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$DockBorder = $window.FindName('DockBorder')
$DockPanel = $window.FindName('DockPanel')

function Get-DockIcon {
  param([string]$Target)
  if ([string]::IsNullOrWhiteSpace($Target)) { return $null }
  $key = $Target.ToLower()
  if ($script:iconCache.ContainsKey($key)) { return $script:iconCache[$key] }
  $r = Resolve-MacifyTarget -Target $Target
  $src = Get-AppIconSource -Target $r.Path
  $script:iconCache[$key] = $src
  return $src
}

function Set-DockItemSize {
  param($Button, [double]$Size)
  $tag = $Button.Tag
  if ($null -eq $tag -or $tag.Kind -eq 'sep') { return }
  $tag.Box.Width = $Size
  $tag.Box.Height = $Size
  if ($tag.Glyph -ne $null) { $tag.Glyph.FontSize = $Size * 0.72 }
}

function Reset-DockSizes {
  foreach ($b in $DockPanel.Children) { Set-DockItemSize $b $script:baseSize }
}

function Test-ItemRunning {
  param($Item)
  try {
    if ($null -eq $Item.target -or $Item.target -match '^(macify:|auto:|https?:|ms-|mailto:|shell:)') { return $false }
    $r = Resolve-MacifyTarget -Target $Item.target -Args $Item.args
    if ($r.Path -match '^(https?:|ms-|mailto:|shell:)') { return $false }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($r.Path)
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    return (@(Get-Process -Name $name -ErrorAction SilentlyContinue).Count -gt 0)
  } catch { return $false }
}

function Invoke-DockItem {
  param($Item)
  if ($null -eq $Item -or $null -eq $Item.target) { return }
  switch -Regex ($Item.target) {
    '^macify:launchpad$' { Show-Launchpad; return }
    '^macify:trash$' { Start-Process "$env:SystemRoot\explorer.exe" 'shell:RecycleBinFolder'; return }
    default { Start-MacifyTarget -Target $Item.target -Args $Item.args }
  }
}

function Remove-DockItem {
  param([string]$Name)
  $script:items = @($script:items | Where-Object { $_.name -ne $Name })
  Save-MacifyDockItems -Items $script:items
  Build-DockItems
}

function Add-DockItem {
  param([string]$Name, [string]$Target, [string]$Args = '')
  if ($script:items | Where-Object { $_.name -eq $Name }) {
    Show-MacifyToast -Title 'Macify Dock' -Message ('"' + $Name + '" is already in the Dock.')
    return
  }
  $sepIdx = -1
  for ($i = 0; $i -lt $script:items.Count; $i++) { if ($script:items[$i].name -eq '-separator-') { $sepIdx = $i } }
  $newItem = [PSCustomObject]@{ name = $Name; target = $Target; args = $Args }
  if ($sepIdx -ge 0) {
    $before = @()
    if ($sepIdx -gt 0) { $before = @($script:items[0..($sepIdx - 1)]) }
    $after = @($script:items[$sepIdx..($script:items.Count - 1)])
    $script:items = @($before + @($newItem) + $after)
  } else { $script:items = @($script:items + @($newItem)) }
  Save-MacifyDockItems -Items $script:items
  Build-DockItems
  Show-MacifyToast -Title 'Macify Dock' -Message ('Added "' + $Name + '" to the Dock.')
}

function New-DockButton {
  param($Item)
  $btn = New-Object Windows.Controls.Button
  $btn.Background = [Windows.Media.Brushes]::Transparent
  $btn.BorderBrush = [Windows.Media.Brushes]::Transparent
  $btn.BorderThickness = '0'
  $btn.Padding = '4,2'
  $btn.Margin = '2,0'
  $btn.Cursor = [Windows.Input.Cursors]::Hand
  $btn.Focusable = $false
  $btn.VerticalAlignment = 'Bottom'
  $tpl = '<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}"><ContentPresenter VerticalAlignment="Bottom" HorizontalAlignment="Center"/></Border></ControlTemplate>'
  $btn.Template = ([Windows.Markup.XamlReader]::Parse($tpl))

  $stack = New-Object Windows.Controls.StackPanel
  $stack.VerticalAlignment = 'Bottom'
  $box = New-Object Windows.Controls.Grid
  $box.Width = $script:baseSize
  $box.Height = $script:baseSize

  $glyph = $null
  if ($Item.target -eq 'macify:trash') {
    $glyph = New-Object Windows.Controls.TextBlock
    $glyph.Text = ([char]0xD83D).ToString() + ([char]0xDDD1).ToString()
    $glyph.FontSize = $script:baseSize * 0.72
    $glyph.HorizontalAlignment = 'Center'; $glyph.VerticalAlignment = 'Center'
    $box.Children.Add($glyph) | Out-Null
    $btn.ToolTip = 'Trash'
  } elseif ($Item.target -eq 'macify:launchpad') {
    $glyph = New-Object Windows.Controls.TextBlock
    $glyph.Text = ([char]0xD83D).ToString() + ([char]0xDE80).ToString()
    $glyph.FontSize = $script:baseSize * 0.72
    $glyph.HorizontalAlignment = 'Center'; $glyph.VerticalAlignment = 'Center'
    $box.Children.Add($glyph) | Out-Null
    $btn.ToolTip = 'Launchpad'
  } else {
    $img = New-Object Windows.Controls.Image
    $img.Stretch = 'Uniform'
    $src = Get-DockIcon $Item.target
    if ($src -ne $null) { $img.Source = $src }
    else {
      $glyph = New-Object Windows.Controls.TextBlock
      $glyph.Text = $Item.name.Substring(0, 1).ToUpper()
      $glyph.FontSize = $script:baseSize * 0.55
      $glyph.FontWeight = 'Bold'
      $glyph.Foreground = if ($script:isLight) { [Windows.Media.Brushes]::Black } else { [Windows.Media.Brushes]::White }
      $glyph.HorizontalAlignment = 'Center'; $glyph.VerticalAlignment = 'Center'
      $box.Children.Add($glyph) | Out-Null
    }
    if ($img.Source -ne $null) { $box.Children.Add($img) | Out-Null }
    $btn.ToolTip = $Item.name
  }
  $stack.Children.Add($box) | Out-Null
  $dot = New-Object Windows.Shapes.Ellipse
  $dot.Width = 5; $dot.Height = 5
  $dot.Fill = if ($script:isLight) { [Windows.Media.Brushes]::Black } else { [Windows.Media.Brushes]::White }
  $dot.HorizontalAlignment = 'Center'; $dot.Margin = '0,3,0,0'
  $dot.Visibility = 'Hidden'
  $stack.Children.Add($dot) | Out-Null
  $btn.Content = $stack
  $btn.Tag = @{ Kind = 'app'; Item = $Item; Box = $box; Glyph = $glyph; Dot = $dot }

  $btn.Add_Click({ Invoke-DockItem $Item }.GetNewClosure())

  $menu = New-Object Windows.Controls.ContextMenu
  $openMi = New-Object Windows.Controls.MenuItem; $openMi.Header = 'Open'
  $openMi.Add_Click({ Invoke-DockItem $Item }.GetNewClosure())
  $menu.Items.Add($openMi) | Out-Null
  try {
    $r = Resolve-MacifyTarget -Target $Item.target -Args $Item.args
    if ($r.Path -and (Test-Path $r.Path -ErrorAction SilentlyContinue)) {
      $showMi = New-Object Windows.Controls.MenuItem; $showMi.Header = 'Show in Explorer'
      $showMi.Add_Click({ Start-Process "$env:SystemRoot\explorer.exe" ('/select,"{0}"' -f $r.Path) }.GetNewClosure())
      $menu.Items.Add($showMi) | Out-Null
    }
  } catch { }
  if ($Item.target -eq 'macify:trash') {
    $emptyMi = New-Object Windows.Controls.MenuItem; $emptyMi.Header = 'Empty Trash'
    $emptyMi.Add_Click({
      try { Clear-MacifyTrash; Show-MacifyToast -Title 'Trash' -Message 'Trash emptied.' }
      catch { Show-MacifyToast -Title 'Trash' -Message 'Could not empty Trash.' }
    }.GetNewClosure())
    $menu.Items.Add($emptyMi) | Out-Null
  }
  if ($Item.target -notmatch '^macify:') {
    $menu.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
    $rmMi = New-Object Windows.Controls.MenuItem; $rmMi.Header = 'Remove from Dock'
    $rmMi.Add_Click({ Remove-DockItem $Item.name }.GetNewClosure())
    $menu.Items.Add($rmMi) | Out-Null
    $quitMi = New-Object Windows.Controls.MenuItem; $quitMi.Header = ('Quit {0}' -f $Item.name)
    $quitMi.Add_Click({
      try {
        $rr = Resolve-MacifyTarget -Target $Item.target -Args $Item.args
        $n = [System.IO.Path]::GetFileNameWithoutExtension($rr.Path)
        Get-Process -Name $n -ErrorAction Stop | ForEach-Object { try { if (-not $_.CloseMainWindow()) { $_.Kill() } } catch { $_.Kill() } }
      } catch { }
    }.GetNewClosure())
    $menu.Items.Add($quitMi) | Out-Null
  }
  $btn.ContextMenu = $menu
  return $btn
}

function Build-DockItems {
  $DockPanel.Children.Clear()
  $script:items = @(Get-MacifyDockItems)
  foreach ($it in $script:items) {
    if ($it.name -eq '-separator-') {
      $sep = New-Object Windows.Controls.Border
      $sep.Width = 1
      $sep.Height = $script:baseSize
      $sep.Margin = '6,4'
      $sep.VerticalAlignment = 'Center'
      $sep.Background = if ($script:isLight) { '#66000000' } else { '#66FFFFFF' }
      $sep.Tag = @{ Kind = 'sep' }
      $DockPanel.Children.Add($sep) | Out-Null
    } else {
      $DockPanel.Children.Add((New-DockButton $it)) | Out-Null
    }
  }
  Update-RunningDots
}

function Update-RunningDots {
  foreach ($b in $DockPanel.Children) {
    if ($b.Tag -eq $null -or $b.Tag.Kind -eq 'sep') { continue }
    $running = Test-ItemRunning $b.Tag.Item
    $b.Tag.Dot.Visibility = if ($running) { 'Visible' } else { 'Hidden' }
    $base = $b.Tag.Item.name
    $b.ToolTip = if ($running) { "$base (running)" } else { $base }
    if ($b.Tag.Item.target -eq 'macify:trash') {
      $n = Get-TrashCount
      $b.ToolTip = if ($n -gt 0) { "Trash ($n items)" } else { 'Trash (empty)' }
    }
  }
}

# ---- Launchpad ----
function Show-Launchpad {
  if ($null -ne $script:launchpadWin -and $script:launchpadWin.IsVisible) {
    $script:launchpadWin.Hide(); return
  }
  if ($null -eq $script:launchpadWin) {
    $lw = New-Object Windows.Window
    $lw.Title = 'Launchpad'
    $lw.Width = 760; $lw.Height = 500
    $lw.WindowStyle = 'None'; $lw.AllowsTransparency = $true
    $lw.Background = if ($script:isLight) { '#E6F2F2F7' } else { '#E6141414' }
    $lw.Topmost = $true; $lw.ShowInTaskbar = $false
    $lw.FontFamily = 'Inter, Segoe UI'
    $grid = New-Object Windows.Controls.Grid
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{ Height = 'Auto' })) | Out-Null
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
    $search = New-Object Windows.Controls.TextBox
    $search.Margin = '200,18,200,12'; $search.Height = 32; $search.FontSize = 14
    $search.HorizontalContentAlignment = 'Center'; $search.VerticalContentAlignment = 'Center'
    $search.Text = 'Search'
    $search.Foreground = [Windows.Media.Brushes]::Gray
    [Windows.Controls.Grid]::SetRow($search, 0)
    $grid.Children.Add($search) | Out-Null
    $scroll = New-Object Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    [Windows.Controls.Grid]::SetRow($scroll, 1)
    $wrap = New-Object Windows.Controls.WrapPanel
    $wrap.Margin = '24,8,24,24'
    $wrap.HorizontalAlignment = 'Center'
    $scroll.Content = $wrap
    $grid.Children.Add($scroll) | Out-Null
    $lw.Content = $grid
    $lw.Add_SourceInitialized({
      try {
        $h = (New-Object Windows.Interop.WindowInteropHelper($lw)).Handle
        if (-not $NoBlur) { Enable-MacifyBlur -Hwnd $h -Style (($(if ($script:isLight) { 'Light' } else { 'Dark' }))) }
      } catch { }
    }.GetNewClosure())
    $lw.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $lw.Hide(); $e.Handled = $true } }.GetNewClosure())
    $search.Add_GotFocus({ if ($search.Text -eq 'Search') { $search.Text = ''; $search.Foreground = [Windows.Media.Brushes]::Black } }.GetNewClosure())
    $search.Add_TextChanged({
      $q = $search.Text
      if ($q -eq 'Search') { $q = '' }
      Fill-Launchpad $wrap $q
    }.GetNewClosure())
    $lw.Tag = @{ Search = $search; Wrap = $wrap }
    $script:launchpadWin = $lw
  }
  $wa = [Windows.SystemParameters]::WorkArea
  $script:launchpadWin.Left = ($wa.Width - $script:launchpadWin.Width) / 2
  $script:launchpadWin.Top = ($wa.Height - $script:launchpadWin.Height) / 2 - 20
  if ($null -eq $script:appCache) {
    $script:launchpadWin.Tag.Search.Text = 'Loading...'
    $script:launchpadWin.Show()
    $script:launchpadWin.Activate() | Out-Null
    $script:appCache = @(Get-StartMenuApps)
    $script:launchpadWin.Tag.Search.Text = 'Search'
  }
  Fill-Launchpad $script:launchpadWin.Tag.Wrap ''
  $script:launchpadWin.Show()
  $script:launchpadWin.Activate() | Out-Null
  $script:launchpadWin.Tag.Search.Focus() | Out-Null
}

function Fill-Launchpad {
  param($Wrap, [string]$Query = '')
  $Wrap.Children.Clear()
  $q = $Query.Trim().ToLower()
  $apps = @($script:appCache | Where-Object { $q -eq '' -or $_.Name.ToLower().Contains($q) } | Select-Object -First 60)
  $fgBrush = if ($script:isLight) { [Windows.Media.Brushes]::Black } else { [Windows.Media.Brushes]::White }
  foreach ($a in $apps) {
    $b = New-Object Windows.Controls.Button
    $b.Width = 104; $b.Height = 96
    $b.Margin = '6'
    $b.Background = [Windows.Media.Brushes]::Transparent
    $b.BorderBrush = [Windows.Media.Brushes]::Transparent
    $b.Cursor = [Windows.Input.Cursors]::Hand
    $sp = New-Object Windows.Controls.StackPanel
    $img = New-Object Windows.Controls.Image
    $img.Width = 44; $img.Height = 44; $img.Stretch = 'Uniform'
    $icon = Get-AppIconSource -Target $a.Target
    if ($icon -ne $null) { $img.Source = $icon }
    $sp.Children.Add($img) | Out-Null
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $a.Name; $tb.Foreground = $fgBrush; $tb.FontSize = 11
    $tb.TextAlignment = 'Center'; $tb.TextWrapping = 'Wrap'; $tb.MaxHeight = 32
    $tb.TextTrimming = 'CharacterEllipsis'
    $sp.Children.Add($tb) | Out-Null
    $b.Content = $sp
    $b.ToolTip = $a.Target
    $b.Add_Click({
      try {
        if ([string]::IsNullOrWhiteSpace($a.Args)) { Start-Process $a.Target }
        else { Start-Process $a.Target -ArgumentList $a.Args }
      } catch { Show-MacifyToast -Title 'Launchpad' -Message ("Could not open " + $a.Name) }
      $script:launchpadWin.Hide()
    }.GetNewClosure())
    $cm = New-Object Windows.Controls.ContextMenu
    $addMi = New-Object Windows.Controls.MenuItem; $addMi.Header = 'Add to Dock'
    $addMi.Add_Click({ Add-DockItem -Name $a.Name -Target $a.Target -Args $a.Args }.GetNewClosure())
    $cm.Items.Add($addMi) | Out-Null
    $b.ContextMenu = $cm
    $Wrap.Children.Add($b) | Out-Null
  }
}

# ---- Magnification ----
$DockPanel.Add_MouseMove({
  param($s, $e)
  if (-not [bool]$cfg.dock.magnify) { return }
  try {
    $mp = $e.GetPosition($DockPanel)
    foreach ($b in $DockPanel.Children) {
      if ($b.Tag -eq $null -or $b.Tag.Kind -eq 'sep') { continue }
      $pos = $b.TransformToAncestor($DockPanel).Transform((New-Object Windows.Point(($b.ActualWidth / 2), 0)))
      $d = [Math]::Abs($pos.X - $mp.X)
      $size = $script:baseSize + ($script:maxSize - $script:baseSize) * [Math]::Exp(-($d / 110) * ($d / 110))
      Set-DockItemSize $b $size
    }
  } catch { }
}.GetNewClosure())
$DockPanel.Add_MouseLeave({ Reset-DockSizes }.GetNewClosure())

# ---- Dock background menu ----
$DockBorder.Add_MouseRightButtonUp({
  param($s, $e)
  $src = $e.OriginalSource
  $dep = $src -as [Windows.DependencyObject]
  while ($dep -ne $null) {
    if ($dep -is [Windows.Controls.Button]) { return }
    $dep = [Windows.Media.VisualTreeHelper]::GetParent($dep)
  }
  $m = New-Object Windows.Controls.ContextMenu
  $magMi = New-Object Windows.Controls.MenuItem
  $magMi.Header = if ([bool]$cfg.dock.magnify) { 'Turn Magnification Off' } else { 'Turn Magnification On' }
  $magMi.Add_Click({
    $cfg.dock.magnify = -not [bool]$cfg.dock.magnify
    Save-DockPref -Key 'magnify' -Value ([bool]$cfg.dock.magnify)
    if (-not [bool]$cfg.dock.magnify) { Reset-DockSizes }
  }.GetNewClosure())
  $m.Items.Add($magMi) | Out-Null
  $hideMi = New-Object Windows.Controls.MenuItem
  $hideMi.Header = if ([bool]$cfg.dock.autohide) { 'Turn Hiding Off' } else { 'Turn Hiding On' }
  $hideMi.Add_Click({
    $cfg.dock.autohide = -not [bool]$cfg.dock.autohide
    Save-DockPref -Key 'autohide' -Value ([bool]$cfg.dock.autohide)
  }.GetNewClosure())
  $m.Items.Add($hideMi) | Out-Null
  $m.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
  $quitMi = New-Object Windows.Controls.MenuItem; $quitMi.Header = 'Quit Macify'
  $quitMi.Add_Click({
    Stop-MacifyComponent -Match 'MacifyBar.ps1'
    Stop-MacifyComponent -Match 'MacifySpotlight.ps1'
    Stop-MacifyComponent -Match 'MacifyControlCenter.ps1'
    $window.Close()
  }.GetNewClosure())
  $m.Items.Add($quitMi) | Out-Null
  $m.IsOpen = $true
  $e.Handled = $true
}.GetNewClosure())

function Save-DockPref {
  param([string]$Key, $Value)
  try {
    $uc = $null
    if (Test-Path $paths.UserCfg) { $uc = Get-Content $paths.UserCfg -Raw | ConvertFrom-Json }
    if ($null -eq $uc) { $uc = New-Object PSCustomObject }
    if ($null -eq $uc.dock) { $uc | Add-Member -NotePropertyName 'dock' -NotePropertyValue (New-Object PSCustomObject) }
    $uc.dock | Add-Member -NotePropertyName $Key -NotePropertyValue $Value -Force
    if (-not (Test-Path $paths.AppData)) { New-Item -ItemType Directory -Path $paths.AppData -Force | Out-Null }
    ($uc | ConvertTo-Json -Depth 6) | Set-Content $paths.UserCfg -Encoding UTF8
  } catch { Write-MacifyLog "Save pref failed: $($_.Exception.Message)" 'WARN' }
}

# ---- Positioning: bottom-center, above taskbar ----
$window.Add_ContentRendered({
  $wa = [Windows.SystemParameters]::WorkArea
  $window.Left = ($wa.Width - $window.ActualWidth) / 2
  $window.Top = $wa.Height - $window.ActualHeight - $script:marginBottom
}.GetNewClosure())
$window.Add_LayoutUpdated({
  try {
    if ($script:hidden) { return }
    $wa = [Windows.SystemParameters]::WorkArea
    $t = $wa.Height - $window.ActualHeight - $script:marginBottom
    $l = ($wa.Width - $window.ActualWidth) / 2
    if ([Math]::Abs($window.Top - $t) -gt 1) { $window.Top = $t }
    if ([Math]::Abs($window.Left - $l) -gt 1) { $window.Left = $l }
  } catch { }
}.GetNewClosure())

# ---- Auto-hide watcher ----
$hideTimer = New-Object Windows.Threading.DispatcherTimer
$hideTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$hideTimer.Add_Tick({
  try {
    if (-not [bool]$cfg.dock.autohide) { if ($script:hidden) { $script:hidden = $false } return }
    $pos = [System.Windows.Forms.Cursor]::Position
    $src2 = [Windows.PresentationSource]::FromVisual($window)
    $my = $pos.Y
    if ($src2 -ne $null -and $src2.CompositionTarget -ne $null) {
      $pt = $src2.CompositionTarget.TransformFromDevice.Transform((New-Object Windows.Point($pos.X, $pos.Y)))
      $my = $pt.Y
    }
    $wa = [Windows.SystemParameters]::WorkArea
    $nearBottom = ($my -ge ($wa.Height - 6))
    $overDock = ($my -ge $window.Top - 4 -and $my -le ($window.Top + $window.ActualHeight + 4))
    if ($script:hidden -and ($nearBottom -or $overDock)) {
      $script:hidden = $false
      $window.Top = $wa.Height - $window.ActualHeight - $script:marginBottom
    } elseif (-not $script:hidden -and -not $nearBottom -and -not $overDock) {
      $menuOpen = $false
      foreach ($b in $DockPanel.Children) {
        if ($b -is [Windows.Controls.Button] -and $b.ContextMenu -ne $null -and $b.ContextMenu.IsOpen) { $menuOpen = $true }
      }
      if (-not $menuOpen -and ($null -eq $script:launchpadWin -or -not $script:launchpadWin.IsVisible)) {
        $script:hidden = $true
        $window.Top = $wa.Height - 4
      }
    }
  } catch { }
}.GetNewClosure())
$hideTimer.Start()

# ---- Running-indicator refresh ----
$runTimer = New-Object Windows.Threading.DispatcherTimer
$runTimer.Interval = [TimeSpan]::FromSeconds(3)
$runTimer.Add_Tick({ try { Update-RunningDots } catch { } }.GetNewClosure())
$runTimer.Start()

$window.Add_SourceInitialized({
  try {
    $hwnd = (New-Object Windows.Interop.WindowInteropHelper($window)).Handle
    $ex = [Macify.Native]::GetWindowLong($hwnd, -20)
    [Macify.Native]::SetWindowLong($hwnd, -20, ($ex -bor 0x80)) | Out-Null
    if (-not $NoBlur) { Enable-MacifyBlur -Hwnd $hwnd -Style (($(if ($script:isLight) { 'Light' } else { 'Dark' }))) }
    $src = [Windows.Interop.HwndSource]::FromHwnd($hwnd)
    $hook = [Windows.Interop.HwndSourceHook]{
      param($h, $msg, $wp, $lp, [ref]$handled)
      if ($msg -eq 0x21) { $handled.Value = $true; return [IntPtr]3 }
      return [IntPtr]::Zero
    }
    $src.AddHook($hook)
  } catch { Write-MacifyLog "Dock init hook: $($_.Exception.Message)" 'WARN' }
}.GetNewClosure())

Build-DockItems
Write-MacifyLog 'MacifyDock started.'
$app = New-Object Windows.Application
[void]$app.Run($window)
