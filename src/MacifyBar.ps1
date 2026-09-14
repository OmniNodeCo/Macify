# MacifyBar.ps1 - macOS-style top menu bar for Windows (PowerShell + WPF, zero dependencies).
# Shows: command menu, active app + menus (File/Edit/View/Window/Help send real shortcuts),
# battery, wifi, Spotlight + Control Center buttons, live clock with calendar popup.

param([switch]$NoBlur)

. (Join-Path $PSScriptRoot 'MacifyLib.ps1')
Confirm-MacifySTA -ScriptPath $PSCommandPath -ExtraArgs $(if ($NoBlur) { '-NoBlur' } else { '' })
if (-not (Test-MacifySingleInstance -Name 'Bar')) { exit 0 }

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
Add-Type -AssemblyName PresentationCore -ErrorAction Stop
Add-Type -AssemblyName WindowsBase -ErrorAction Stop
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop

$cfg = Get-MacifyConfig
$paths = Get-MacifyPaths
$script:lastHwnd = [IntPtr]::Zero
$script:isLight = $false
if ($cfg.theme -eq 'light') { $script:isLight = $true }
elseif ($cfg.theme -eq 'auto') { $script:isLight = -not (Get-MacifyDarkMode) }

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MacifyBar" Height="30" WindowStyle="None" AllowsTransparency="True"
        Background="#CC000000" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Inter, Segoe UI" FontSize="12">
  <Window.Resources>
    <Style x:Key="BarBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Padding" Value="10,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#33FFFFFF"/>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>
  <Grid>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
      <Button x:Name="AppleBtn" Style="{StaticResource BarBtn}" Content="&#x2318;" FontSize="15" FontWeight="Bold"/>
      <TextBlock x:Name="AppNameText" Text="Finder" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" Margin="4,0,4,0" Cursor="Hand"/>
      <Button x:Name="FileBtn" Style="{StaticResource BarBtn}" Content="File"/>
      <Button x:Name="EditBtn" Style="{StaticResource BarBtn}" Content="Edit"/>
      <Button x:Name="ViewBtn" Style="{StaticResource BarBtn}" Content="View"/>
      <Button x:Name="WindowBtn" Style="{StaticResource BarBtn}" Content="Window"/>
      <Button x:Name="HelpBtn" Style="{StaticResource BarBtn}" Content="Help"/>
    </StackPanel>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <TextBlock x:Name="BatteryText" Text="" Foreground="White" VerticalAlignment="Center" Margin="0,0,10,0"/>
      <TextBlock x:Name="WifiText" Text="&#xE701;" FontFamily="Segoe MDL2 Assets" Foreground="White" VerticalAlignment="Center" Margin="0,0,10,0" FontSize="13"/>
      <Button x:Name="SearchBtn" Style="{StaticResource BarBtn}" Content="&#x1F50D;" FontSize="12"/>
      <Button x:Name="CCBtn" Style="{StaticResource BarBtn}" Content="&#x1F39B;" FontSize="12"/>
      <Button x:Name="ClockBtn" Style="{StaticResource BarBtn}" Content=""/>
    </StackPanel>
  </Grid>
</Window>
"@

if ($script:isLight) {
  $xaml = $xaml.Replace('#CC000000', '#CCF2F2F7').Replace('Foreground="White"', 'Foreground="Black"').Replace('#33FFFFFF', '#33000000')
}

$reader = New-Object System.Xml.XmlNodeReader([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$AppleBtn = $window.FindName('AppleBtn')
$AppNameText = $window.FindName('AppNameText')
$FileBtn = $window.FindName('FileBtn')
$EditBtn = $window.FindName('EditBtn')
$ViewBtn = $window.FindName('ViewBtn')
$WindowBtn = $window.FindName('WindowBtn')
$HelpBtn = $window.FindName('HelpBtn')
$BatteryText = $window.FindName('BatteryText')
$WifiText = $window.FindName('WifiText')
$SearchBtn = $window.FindName('SearchBtn')
$CCBtn = $window.FindName('CCBtn')
$ClockBtn = $window.FindName('ClockBtn')

$window.Left = 0
$window.Top = 0
$window.Width = [Windows.SystemParameters]::WorkArea.Width
$window.Height = [int]$cfg.bar.height

function Send-MacKeys([string]$keys) {
  try {
    if ($script:lastHwnd -ne [IntPtr]::Zero) {
      [Macify.Native]::SetForegroundWindow($script:lastHwnd) | Out-Null
      Start-Sleep -Milliseconds 80
    }
    [System.Windows.Forms.SendKeys]::SendWait($keys)
  } catch { Write-MacifyLog "SendKeys($keys) failed: $($_.Exception.Message)" 'WARN' }
}

function New-MacMenuItem {
  param([string]$Header, [scriptblock]$Action = $null, [string]$Gesture = '')
  $mi = New-Object Windows.Controls.MenuItem
  $mi.Header = $Header
  if ($Gesture -ne '') { $mi.InputGestureText = $Gesture }
  if ($null -ne $Action) { $mi.Add_Click($Action.GetNewClosure()) }
  return $mi
}

function Show-AboutMac {
  try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cpu = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name
    $ram = [Math]::Round($cs.TotalPhysicalMemory / 1GB)
    $msg = "macOS (Macify for Windows)`n`nModel: $($cs.Manufacturer) $($cs.Model)`nChip: $cpu`nMemory: $ram GB`nWindows: $($os.Caption) ($($os.BuildNumber))"
  } catch { $msg = 'macOS (Macify for Windows)' }
  [Windows.MessageBox]::Show($msg, 'About This Mac') | Out-Null
}

function Confirm-Power([string]$verb) {
  return ([Windows.MessageBox]::Show("Are you sure you want to $verb now?", 'Macify',
    [Windows.MessageBoxButton]::YesNo, [Windows.MessageBoxImage]::Question) -eq 'Yes')
}

# ---- Apple / command menu ----
$appleMenu = New-Object Windows.Controls.ContextMenu
$appleMenu.Items.Add((New-MacMenuItem 'About This Mac' { Show-AboutMac })) | Out-Null
$appleMenu.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
$appleMenu.Items.Add((New-MacMenuItem 'System Settings...' { Start-Process 'ms-settings:' })) | Out-Null
$appleMenu.Items.Add((New-MacMenuItem 'App Store...' { Start-Process 'ms-windows-store:' })) | Out-Null
$appleMenu.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
$appleMenu.Items.Add((New-MacMenuItem 'Force Quit...' { Start-Process taskmgr.exe })) | Out-Null
$appleMenu.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
$appleMenu.Items.Add((New-MacMenuItem 'Sleep' { if (Confirm-Power 'sleep') { Start-Process rundll32.exe 'powrprof.dll,SetSuspendState 0,1,0' } })) | Out-Null
$appleMenu.Items.Add((New-MacMenuItem 'Restart...' { if (Confirm-Power 'restart') { Start-Process shutdown.exe '/r /t 5' } })) | Out-Null
$appleMenu.Items.Add((New-MacMenuItem 'Shut Down...' { if (Confirm-Power 'shut down') { Start-Process shutdown.exe '/s /t 5' } })) | Out-Null
$appleMenu.Items.Add((New-MacMenuItem 'Lock Screen' { [Macify.Native]::LockWorkStation() })) | Out-Null
$appleMenu.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
$appleMenu.Items.Add((New-MacMenuItem 'Quit Macify' {
  Stop-MacifyComponent -Match 'MacifyDock.ps1'
  Stop-MacifyComponent -Match 'MacifySpotlight.ps1'
  Stop-MacifyComponent -Match 'MacifyControlCenter.ps1'
  $window.Close()
}.GetNewClosure())) | Out-Null
$AppleBtn.Add_Click({ $appleMenu.IsOpen = $true })

# ---- App menu (click the bold app name) ----
$AppNameText.Add_MouseLeftButtonUp({
  $fg = Get-ForegroundApp
  $m = New-Object Windows.Controls.ContextMenu
  $label = if ($fg) { $fg.Label } else { 'Finder' }
  $m.Items.Add((New-MacMenuItem "About $label" { Show-AboutMac }.GetNewClosure())) | Out-Null
  $m.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
  $m.Items.Add((New-MacMenuItem "Quit $label" {
    try {
      $p = Get-Process -Id $fg.Pid -ErrorAction Stop
      if (-not $p.CloseMainWindow()) { throw 'no main window' }
    } catch { Show-MacifyToast -Title 'Macify' -Message "Could not quit $label." }
  }.GetNewClosure())) | Out-Null
  $m.IsOpen = $true
}.GetNewClosure())

# ---- Standard menus (send real shortcuts to the active app) ----
function New-ShortcutMenu($items) {
  $m = New-Object Windows.Controls.ContextMenu
  foreach ($it in $items) {
    if ($it[0] -eq '-') { $m.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null; continue }
    $keys = $it[2]
    $m.Items.Add((New-MacMenuItem $it[0] { Send-MacKeys $keys }.GetNewClosure() -Gesture $it[1])) | Out-Null
  }
  return $m
}
$fileMenu = New-ShortcutMenu @(@('New Window', 'Ctrl+N', '^n'), @('Open...', 'Ctrl+O', '^o'), '-', @('Save', 'Ctrl+S', '^s'), @('Close Window', 'Ctrl+W', '^w'))
$editMenu = New-ShortcutMenu @(@('Undo', 'Ctrl+Z', '^z'), '-', @('Cut', 'Ctrl+X', '^x'), @('Copy', 'Ctrl+C', '^c'), @('Paste', 'Ctrl+V', '^v'), @('Select All', 'Ctrl+A', '^a'))
$viewMenu = New-ShortcutMenu @(@('Refresh', 'F5', '{F5}'), @('Full Screen', 'F11', '{F11}'))
$windowMenu = New-ShortcutMenu @(@('Minimize', 'Win+Down', '%{ }n'), @('Next Window', 'Ctrl+Tab', '^{TAB}'))
$helpMenu = New-ShortcutMenu @(@('Help', 'F1', '{F1}'))
$FileBtn.Add_Click({ $fileMenu.IsOpen = $true })
$EditBtn.Add_Click({ $editMenu.IsOpen = $true })
$ViewBtn.Add_Click({ $viewMenu.IsOpen = $true })
$WindowBtn.Add_Click({ $windowMenu.IsOpen = $true })
$HelpBtn.Add_Click({ $helpMenu.IsOpen = $true })

# ---- Right side ----
$SearchBtn.Add_Click({ Start-MacifyComponent -ScriptPath (Join-Path $paths.Src 'MacifySpotlight.ps1') })
$SearchBtn.ToolTip = 'Spotlight (Alt+Space)'
$CCBtn.Add_Click({ Toggle-MacifyComponent -Match 'MacifyControlCenter.ps1' -ScriptPath (Join-Path $paths.Src 'MacifyControlCenter.ps1') })
$CCBtn.ToolTip = 'Control Center'

$calWin = $null
$ClockBtn.Add_Click({
  if ($null -ne $calWin -and $calWin.IsVisible) { $calWin.Hide(); return }
  if ($null -eq $calWin) {
    $calWin = New-Object Windows.Window
    $calWin.Title = 'Calendar'
    $calWin.Width = 300; $calWin.Height = 320
    $calWin.WindowStyle = 'ToolWindow'; $calWin.Topmost = $true; $calWin.ShowInTaskbar = $false
    $calWin.WindowStartupLocation = 'Manual'
    $cal = New-Object Windows.Controls.Calendar
    $calWin.Content = $cal
  }
  $calWin.Left = [Windows.SystemParameters]::WorkArea.Width - $calWin.Width - 8
  $calWin.Top = $window.Height + 6
  $calWin.Show()
  $calWin.Activate() | Out-Null
}.GetNewClosure())

# ---- Timers ----
$clockTimer = New-Object Windows.Threading.DispatcherTimer
$clockTimer.Interval = [TimeSpan]::FromSeconds(1)
$clockTimer.Add_Tick({
  try { $ClockBtn.Content = (Get-Date -Format ([string]$cfg.bar.clockFormat)) } catch { $ClockBtn.Content = (Get-Date -Format 'HH:mm') }
}.GetNewClosure())
$clockTimer.Start()
try { $ClockBtn.Content = (Get-Date -Format ([string]$cfg.bar.clockFormat)) } catch { $ClockBtn.Content = (Get-Date -Format 'HH:mm') }

$slowTimer = New-Object Windows.Threading.DispatcherTimer
$slowTimer.Interval = [TimeSpan]::FromSeconds(3)
$slowTimer.Add_Tick({
  try {
    $fg = Get-ForegroundApp
    if ($fg -and $fg.Pid -ne $PID) {
      $script:lastHwnd = $fg.Hwnd
      $short = $fg.Label
      if ($short.Length -gt 32) { $short = $short.Substring(0, 32) + '...' }
      $AppNameText.Text = $short
      $AppNameText.ToolTip = $fg.Title
    }
    if ([bool]$cfg.bar.showBattery) {
      $b = Get-BatteryInfo
      if ($b.Present -and $b.Percent -ge 0) {
        $BatteryText.Text = if ($b.Charging) { "$($b.Percent)% +" } else { "$($b.Percent)%" }
        $BatteryText.Visibility = 'Visible'
      } else { $BatteryText.Visibility = 'Collapsed' }
    } else { $BatteryText.Visibility = 'Collapsed' }
    if ([bool]$cfg.bar.showWifi) {
      $ssid = Get-WifiSsid
      if ($ssid) { $WifiText.Visibility = 'Visible'; $WifiText.ToolTip = $ssid } else { $WifiText.Visibility = 'Collapsed' }
    } else { $WifiText.Visibility = 'Collapsed' }
    if ($cfg.theme -eq 'auto') {
      $nowLight = -not (Get-MacifyDarkMode)
      if ($nowLight -ne $script:isLight) {
        $script:isLight = $nowLight
        $window.Background = if ($nowLight) { '#CCF2F2F7' } else { '#CC000000' }
        $fg2 = if ($nowLight) { [Windows.Media.Brushes]::Black } else { [Windows.Media.Brushes]::White }
        foreach ($el in @($AppleBtn, $AppNameText, $FileBtn, $EditBtn, $ViewBtn, $WindowBtn, $HelpBtn, $BatteryText, $WifiText, $SearchBtn, $CCBtn, $ClockBtn)) { $el.Foreground = $fg2 }
      }
    }
  } catch { Write-MacifyLog "Bar tick: $($_.Exception.Message)" 'WARN' }
}.GetNewClosure())
$slowTimer.Start()

# ---- Window behavior: blur, click-through focus, hide from Alt-Tab ----
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
  } catch { Write-MacifyLog "Bar init hook: $($_.Exception.Message)" 'WARN' }
}.GetNewClosure())

try {
  [Microsoft.Win32.SystemEvents]::DisplaySettingsChanged += {
    $window.Dispatcher.Invoke([action]{ $window.Width = [Windows.SystemParameters]::WorkArea.Width }, [Windows.Threading.DispatcherPriority]::Normal)
  }.GetNewClosure()
} catch { }

Write-MacifyLog 'MacifyBar started.'
$app = New-Object Windows.Application
[void]$app.Run($window)
