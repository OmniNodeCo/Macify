# MacifyControlCenter.ps1 - macOS-style quick-settings panel (PowerShell + WPF, zero dependencies).
# Toggles: notifications, dark mode, transparency. Sliders: brightness, volume.
# Shortcuts to Wi-Fi / Bluetooth / Nearby Share / Night Light settings + power actions.

param([switch]$NoBlur)

. (Join-Path $PSScriptRoot 'MacifyLib.ps1')
Confirm-MacifySTA -ScriptPath $PSCommandPath -ExtraArgs $(if ($NoBlur) { '-NoBlur' } else { '' })
if (-not (Test-MacifySingleInstance -Name 'ControlCenter')) { exit 0 }

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
Add-Type -AssemblyName PresentationCore -ErrorAction Stop
Add-Type -AssemblyName WindowsBase -ErrorAction Stop
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

$cfg = Get-MacifyConfig
$paths = Get-MacifyPaths
$script:isLight = ($cfg.theme -eq 'light') -or ($cfg.theme -eq 'auto' -and -not (Get-MacifyDarkMode))
$script:volStored = 50
try {
  if (Test-Path $paths.UserCfg) {
    $uc = Get-Content $paths.UserCfg -Raw | ConvertFrom-Json
    if ($uc.volume -ne $null) { $script:volStored = [int]$uc.volume }
  }
} catch { }

$fgMain = if ($script:isLight) { '#FF000000' } else { '#FFFFFFFF' }
$fgDim = if ($script:isLight) { '#FF666666' } else { '#FFAAAAAA' }
$bgMain = if ($script:isLight) { '#E6F2F2F7' } else { '#E6141414' }
$cardBg = if ($script:isLight) { '#FFFFFFFF' } else { '#FF2B2B2B' }

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MacifyControlCenter" Width="360" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True"
        Background="$bgMain" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Inter, Segoe UI" FontSize="13">
  <Border CornerRadius="16" Background="Transparent" Padding="14">
    <StackPanel>
      <TextBlock Text="Control Center" FontSize="16" FontWeight="Bold" Foreground="$fgMain" Margin="2,0,0,10"/>
      <UniformGrid Columns="2" Margin="0,0,0,10">
        <Border Background="$cardBg" CornerRadius="12" Margin="0,0,5,5" Padding="12,10">
          <StackPanel>
            <TextBlock Text="Wi-Fi" FontWeight="Bold" Foreground="$fgMain"/>
            <TextBlock x:Name="WifiStatus" Text="Off" Foreground="$fgDim" FontSize="12" Margin="0,2,0,6"/>
            <Button x:Name="WifiBtn" Content="Wi-Fi Settings"/>
          </StackPanel>
        </Border>
        <Border Background="$cardBg" CornerRadius="12" Margin="5,0,0,5" Padding="12,10">
          <StackPanel>
            <TextBlock Text="Bluetooth" FontWeight="Bold" Foreground="$fgMain"/>
            <TextBlock Text="Devices &amp; pairing" Foreground="$fgDim" FontSize="12" Margin="0,2,0,6"/>
            <Button x:Name="BtBtn" Content="Bluetooth Settings"/>
          </StackPanel>
        </Border>
        <Border Background="$cardBg" CornerRadius="12" Margin="0,0,5,0" Padding="12,10">
          <StackPanel>
            <TextBlock Text="Nearby Share" FontWeight="Bold" Foreground="$fgMain"/>
            <TextBlock Text="Mac AirDrop equivalent" Foreground="$fgDim" FontSize="12" Margin="0,2,0,6"/>
            <Button x:Name="ShareBtn" Content="Share Settings"/>
          </StackPanel>
        </Border>
        <Border Background="$cardBg" CornerRadius="12" Margin="5,0,0,0" Padding="12,10">
          <StackPanel>
            <TextBlock Text="Focus" FontWeight="Bold" Foreground="$fgMain"/>
            <TextBlock Text="Silence notifications" Foreground="$fgDim" FontSize="12" Margin="0,2,0,6"/>
            <CheckBox x:Name="FocusBox" Content="Do Not Disturb" Foreground="$fgMain"/>
          </StackPanel>
        </Border>
      </UniformGrid>
      <Border Background="$cardBg" CornerRadius="12" Padding="12,10" Margin="0,0,0,10">
        <StackPanel>
          <CheckBox x:Name="DarkBox" Content="Dark Mode" Foreground="$fgMain" Margin="0,0,0,6"/>
          <CheckBox x:Name="TransBox" Content="Transparency effects" Foreground="$fgMain" Margin="0,0,0,6"/>
          <Button x:Name="NightBtn" Content="Night Light Settings" HorizontalAlignment="Left"/>
        </StackPanel>
      </Border>
      <Border Background="$cardBg" CornerRadius="12" Padding="12,10" Margin="0,0,0,10">
        <StackPanel>
          <TextBlock Text="Display" FontWeight="Bold" Foreground="$fgMain"/>
          <Slider x:Name="BrightSlider" Minimum="5" Maximum="100" Margin="0,6,0,2"/>
          <TextBlock Text="Sound" FontWeight="Bold" Foreground="$fgMain" Margin="0,6,0,0"/>
          <Slider x:Name="VolSlider" Minimum="0" Maximum="100" Margin="0,6,0,2"/>
        </StackPanel>
      </Border>
      <TextBlock x:Name="BattText" Text="" Foreground="$fgDim" FontSize="12" Margin="2,0,0,10"/>
      <UniformGrid Columns="4">
        <Button x:Name="LockBtn" Content="Lock" Margin="0,0,4,0"/>
        <Button x:Name="SleepBtn" Content="Sleep" Margin="2,0,2,0"/>
        <Button x:Name="RestartBtn" Content="Restart" Margin="2,0,2,0"/>
        <Button x:Name="PowerBtn" Content="Shut Down" Margin="4,0,0,0"/>
      </UniformGrid>
    </StackPanel>
  </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$WifiStatus = $window.FindName('WifiStatus')
$WifiBtn = $window.FindName('WifiBtn')
$BtBtn = $window.FindName('BtBtn')
$ShareBtn = $window.FindName('ShareBtn')
$FocusBox = $window.FindName('FocusBox')
$DarkBox = $window.FindName('DarkBox')
$TransBox = $window.FindName('TransBox')
$NightBtn = $window.FindName('NightBtn')
$BrightSlider = $window.FindName('BrightSlider')
$VolSlider = $window.FindName('VolSlider')
$BattText = $window.FindName('BattText')
$LockBtn = $window.FindName('LockBtn')
$SleepBtn = $window.FindName('SleepBtn')
$RestartBtn = $window.FindName('RestartBtn')
$PowerBtn = $window.FindName('PowerBtn')

# ---- Init states ----
try {
  $ssid = Get-WifiSsid
  $WifiStatus.Text = if ($ssid) { $ssid } else { 'Not connected' }
} catch { }
try {
  $toast = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -Name ToastEnabled
  $FocusBox.IsChecked = ($toast -eq 0)
} catch { $FocusBox.IsChecked = $false }
$DarkBox.IsChecked = (Get-MacifyDarkMode)
try {
  $TransBox.IsChecked = ((Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name EnableTransparency) -eq 1)
} catch { $TransBox.IsChecked = $true }
try {
  $bl = @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop)[0].CurrentBrightness
  $BrightSlider.Value = [int]$bl
  $BrightSlider.ToolTip = "Brightness: $bl%"
} catch {
  $BrightSlider.IsEnabled = $false
  $BrightSlider.ToolTip = 'Brightness control is not available on this display.'
}
$VolSlider.Value = $script:volStored
try {
  $b = Get-BatteryInfo
  $up = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
  $upTxt = '{0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes
  $BattText.Text = if ($b.Present) { "Battery: $($b.Percent)%  |  Uptime: $upTxt" } else { "Uptime: $upTxt" }
} catch { }

# ---- Wire up ----
$WifiBtn.Add_Click({ Start-Process 'ms-settings:network-wifi' })
$BtBtn.Add_Click({ Start-Process 'ms-settings:bluetooth' })
$ShareBtn.Add_Click({ Start-Process 'ms-settings:nearsharing' })
$NightBtn.Add_Click({ Start-Process 'ms-settings:nightlight' })

$FocusBox.Add_Checked({
  Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -Name ToastEnabled -Value 0 -Type DWord -Force
}.GetNewClosure())
$FocusBox.Add_Unchecked({
  Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -Name ToastEnabled -Value 1 -Type DWord -Force
}.GetNewClosure())
$DarkBox.Add_Checked({ Set-MacifyDarkMode Dark }.GetNewClosure())
$DarkBox.Add_Unchecked({ Set-MacifyDarkMode Light }.GetNewClosure())
$TransBox.Add_Checked({
  Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name EnableTransparency -Value 1 -Type DWord -Force
}.GetNewClosure())
$TransBox.Add_Unchecked({
  Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name EnableTransparency -Value 0 -Type DWord -Force
}.GetNewClosure())

$script:brightPending = $null
$BrightSlider.Add_ValueChanged({
  param($s, $e)
  $script:brightPending = [int]$s.Value
}.GetNewClosure())
$brightTimer = New-Object Windows.Threading.DispatcherTimer
$brightTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$brightTimer.Add_Tick({
  if ($null -eq $script:brightPending) { return }
  $v = $script:brightPending
  $script:brightPending = $null
  try {
    $mc = @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop)[0]
    Invoke-CimMethod -InputObject $mc -MethodName WmiSetBrightness -Arguments @{ Timeout = 1; Brightness = [byte]$v } | Out-Null
    $BrightSlider.ToolTip = "Brightness: $v%"
  } catch { Write-MacifyLog "Brightness set failed: $($_.Exception.Message)" 'WARN' }
}.GetNewClosure())
$brightTimer.Start()

$script:volPending = $null
$VolSlider.Add_ValueChanged({
  param($s, $e)
  $script:volPending = [int]$s.Value
}.GetNewClosure())
$volTimer = New-Object Windows.Threading.DispatcherTimer
$volTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$volTimer.Add_Tick({
  if ($null -eq $script:volPending) { return }
  $target = $script:volPending
  $script:volPending = $null
  try {
    Ensure-MacifyNative
    $diff = $target - $script:volStored
    $presses = [Math]::Round([Math]::Abs($diff) / 2)
    $vk = if ($diff -ge 0) { 0xAF } else { 0xAE }
    for ($i = 0; $i -lt $presses; $i++) {
      [Macify.Native]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero)
      [Macify.Native]::keybd_event([byte]$vk, 0, 2, [UIntPtr]::Zero)
    }
    $script:volStored = $target
    $VolSlider.ToolTip = "Volume: $target%"
    $uc2 = $null
    if (Test-Path $paths.UserCfg) { try { $uc2 = Get-Content $paths.UserCfg -Raw | ConvertFrom-Json } catch { } }
    if ($null -eq $uc2) { $uc2 = New-Object PSCustomObject }
    $uc2 | Add-Member -NotePropertyName 'volume' -NotePropertyValue $target -Force
    ($uc2 | ConvertTo-Json -Depth 6) | Set-Content $paths.UserCfg -Encoding UTF8
  } catch { Write-MacifyLog "Volume set failed: $($_.Exception.Message)" 'WARN' }
}.GetNewClosure())
$volTimer.Start()

function Confirm-CCPower([string]$verb) {
  return ([Windows.MessageBox]::Show("Are you sure you want to $verb now?", 'Macify',
    [Windows.MessageBoxButton]::YesNo, [Windows.MessageBoxImage]::Question) -eq 'Yes')
}
$LockBtn.Add_Click({ [Macify.Native]::LockWorkStation() })
$SleepBtn.Add_Click({ if (Confirm-CCPower 'sleep') { Start-Process rundll32.exe 'powrprof.dll,SetSuspendState 0,1,0' } })
$RestartBtn.Add_Click({ if (Confirm-CCPower 'restart') { Start-Process shutdown.exe '/r /t 5' } })
$PowerBtn.Add_Click({ if (Confirm-CCPower 'shut down') { Start-Process shutdown.exe '/s /t 5' } })

$window.Add_ContentRendered({
  try {
    $wa = [Windows.SystemParameters]::WorkArea
    $window.Left = $wa.Width - $window.ActualWidth - 10
    $window.Top = [int]$cfg.bar.height + 8
  } catch { }
}.GetNewClosure())
$window.Add_SourceInitialized({
  try {
    $hwnd = (New-Object Windows.Interop.WindowInteropHelper($window)).Handle
    $ex = [Macify.Native]::GetWindowLong($hwnd, -20)
    [Macify.Native]::SetWindowLong($hwnd, -20, ($ex -bor 0x80)) | Out-Null
    if (-not $NoBlur) { Enable-MacifyBlur -Hwnd $hwnd -Style (($(if ($script:isLight) { 'Light' } else { 'Dark' }))) }
  } catch { Write-MacifyLog "CC init: $($_.Exception.Message)" 'WARN' }
}.GetNewClosure())
$window.Add_PreviewKeyDown({
  param($s, $e)
  if ($e.Key -eq 'Escape') { $window.Close() }
}.GetNewClosure())
$window.Add_Deactivated({ try { $window.Close() } catch { } }.GetNewClosure())

Write-MacifyLog 'MacifyControlCenter started.'
$app = New-Object Windows.Application
[void]$app.Run($window)
