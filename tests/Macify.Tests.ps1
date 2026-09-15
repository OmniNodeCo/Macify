# Macify.Tests.ps1 - Pester tests (run on Windows CI + locally).
#   Invoke-Pester -Path .\tests -Output Detailed

BeforeAll {
  $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
  if (-not (Test-Path (Join-Path $script:RepoRoot 'src\MacifyLib.ps1'))) {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
  }
  . (Join-Path $script:RepoRoot 'src\MacifyLib.ps1')
}

Describe 'PowerShell syntax' {
  It 'parses every script with zero errors' {
    $files = Get-ChildItem -Path $script:RepoRoot -Filter '*.ps1' -Recurse |
      Where-Object { $_.FullName -notmatch '\.git' }
    $files.Count | Should -BeGreaterThan 5
    foreach ($f in $files) {
      $tokens = $null; $errs = $null
      [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs) | Out-Null
      $errs.Count | Should -Be 0 -Because ("{0} must parse cleanly" -f $f.Name)
    }
  }
}

Describe 'Config files' {
  It 'theme.json is valid and has required sections' {
    $cfg = Get-Content (Join-Path $script:RepoRoot 'config\theme.json') -Raw | ConvertFrom-Json
    $cfg.theme | Should -Not -BeNullOrEmpty
    $cfg.bar.clockFormat | Should -Not -BeNullOrEmpty
    $cfg.dock.iconSize | Should -BeGreaterThan 0
    $cfg.spotlight.width | Should -BeGreaterThan 0
  }
  It 'dock-items.json is a non-empty array with launch targets' {
    $json = Get-Content (Join-Path $script:RepoRoot 'config\dock-items.json') -Raw -Encoding UTF8
    $items = @(ConvertFrom-MacifyJsonArray -Json $json)
    $items.Count | Should -BeGreaterThan 3
    @($items | Where-Object { $_.name -eq 'Trash' }).Count | Should -Be 1
    @($items | Where-Object { $_.name -eq 'Launchpad' }).Count | Should -Be 1
    foreach ($it in $items) {
      if ($it.name -eq '-separator-') { continue }
      $it.target | Should -Not -BeNullOrEmpty -Because ("{0} needs a launch target" -f $it.name)
    }
  }
}

Describe 'Engines' {
  It 'engines.json registry is valid' {
    $reg = Get-Content (Join-Path $script:RepoRoot 'config\engines.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $reg.default | Should -Not -BeNullOrEmpty
    $ids = @($reg.engines | ForEach-Object { $_.id })
    $ids | Should -Contain $reg.default
    $ids | Should -Contain 'native'
    ($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
    foreach ($e in $reg.engines) {
      $e.name | Should -Not -BeNullOrEmpty
      @($e.provides).Count | Should -BeGreaterThan 0
    }
  }
  It 'Rainmeter skins are present and well-formed' {
    foreach ($rel in @('extras\rainmeter\Macify\Clock\Clock.ini', 'extras\rainmeter\Macify\Stats\Stats.ini')) {
      $full = Join-Path $script:RepoRoot $rel
      (Test-Path $full) | Should -BeTrue -Because "$rel must exist"
      $txt = Get-Content $full -Raw
      $txt | Should -Match '\[Rainmeter\]'
      $txt | Should -Match 'Meter=String'
    }
  }
}

Describe 'MacifyLib' {
  It 'exposes expected helper functions' {
    foreach ($fn in @('Get-MacifyPaths', 'Get-MacifyConfig', 'Invoke-SafeMath', 'Merge-MacifyObject', 'ConvertFrom-MacifyJsonArray',
        'Test-MacifySingleInstance', 'Get-StartMenuApps', 'Resolve-MacifyTarget')) {
      (Get-Command $fn -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty -Because "$fn must exist"
    }
  }
  It 'Get-MacifyPaths points at real folders' {
    $p = Get-MacifyPaths
    (Test-Path $p.Src) | Should -BeTrue
    (Test-Path $p.Config) | Should -BeTrue
  }
  It 'Get-MacifyConfig merges defaults' {
    $cfg = Get-MacifyConfig
    $cfg.bar.height | Should -BeGreaterThan 0
    $cfg.spotlight.hotkeys.Count | Should -BeGreaterThan 0
  }
  It 'Invoke-SafeMath evaluates expressions' {
    (Invoke-SafeMath '2+3*4') | Should -Be 14
    (Invoke-SafeMath '(2+3)*4') | Should -Be 20
    (Invoke-SafeMath '2^10') | Should -Be 1024
    (Invoke-SafeMath '10%3') | Should -Be 1
    (Invoke-SafeMath '-5+2') | Should -Be -3
  }
  It 'Invoke-SafeMath rejects unsafe input' {
    (Invoke-SafeMath 'Get-Process') | Should -BeNullOrEmpty
    (Invoke-SafeMath '1/0') | Should -BeNullOrEmpty
    (Invoke-SafeMath '') | Should -BeNullOrEmpty
    (Invoke-SafeMath '2+') | Should -BeNullOrEmpty
  }
  It 'ConvertFrom-MacifyJsonArray normalizes top-level arrays' {
    $a = ConvertFrom-MacifyJsonArray -Json '[{"n":1},{"n":2},{"n":3}]'
    $a.Count | Should -Be 3
    $a[2].n | Should -Be 3
    $b = @(ConvertFrom-MacifyJsonArray -Json '{"n":1}')
    $b.Count | Should -Be 1
  }
  It 'Merge-MacifyObject overlays user settings' {
    $base = '{"a":1,"bar":{"x":1,"y":2}}' | ConvertFrom-Json
    $over = '{"bar":{"y":9}}' | ConvertFrom-Json
    $m = Merge-MacifyObject -Base $base -Override $over
    $m.bar.y | Should -Be 9
    $m.bar.x | Should -Be 1
    $m.a | Should -Be 1
  }
  It 'Resolve-MacifyTarget expands environment variables' {
    $r = Resolve-MacifyTarget -Target '%SystemRoot%\explorer.exe'
    $r.Path | Should -Match 'explorer\.exe$'
    $r.Path | Should -Not -Match '%SystemRoot%'
  }
}

Describe 'Installer wiring' {
  It 'scripts referenced by Install.ps1 exist' {
    foreach ($rel in @('src\MacifyBar.ps1', 'src\MacifyDock.ps1', 'src\MacifySpotlight.ps1',
        'tools\MacifyTweaks.ps1', 'tools\Install-Extras.ps1')) {
      (Test-Path (Join-Path $script:RepoRoot $rel)) | Should -BeTrue -Because "$rel must exist"
    }
  }
  It 'release manifest lists files that exist' {
    $list = @(& (Join-Path $script:RepoRoot 'tools\Build-Release.ps1') -ListOnly)
    $list.Count | Should -BeGreaterThan 10
    $list | Should -Contain 'Setup.bat'
    @($list | Where-Object { $_ -match 'MacifyDock\.ps1$' }).Count | Should -Be 1
    @($list | Where-Object { $_ -match '^(tests|preview|\.github)[\\/]' }).Count | Should -Be 0
    $list | Should -Not -Contain 'tools\Build-Release.ps1'
    foreach ($rel in $list) {
      (Test-Path (Join-Path $script:RepoRoot $rel)) | Should -BeTrue -Because "$rel must exist"
    }
  }
  It 'Setup.bat launches Install.ps1' {
    (Get-Content (Join-Path $script:RepoRoot 'Setup.bat') -Raw) | Should -Match 'Install\.ps1'
  }
  It 'bundled assets exist' {
    foreach ($rel in @('assets\wallpapers\sonoma-dark.jpg', 'assets\macify.ico',
        'assets\sounds\chime.wav', 'assets\sounds\pop.wav', 'assets\sounds\glass.wav')) {
      (Test-Path (Join-Path $script:RepoRoot $rel)) | Should -BeTrue -Because "$rel must exist"
    }
  }
}
