# Build-Release.ps1 - package Macify into a distributable ZIP.
#
#   powershell -ExecutionPolicy Bypass -File tools\Build-Release.ps1 [-Version 1.2.0] [-OutDir dist]
#   powershell -ExecutionPolicy Bypass -File tools\Build-Release.ps1 -ListOnly
#
# Output: dist\Macify-<version>.zip (top-level Macify\ folder) + dist\checksums.txt.
# -ListOnly prints the repo-relative file manifest without building (used by tests).
# Self-contained on purpose (no MacifyLib dependency) so it runs on any clean
# checkout. Windows PowerShell 5.1 compatible.

param(
  [string]$Version = '',
  [string]$OutDir = '',
  [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Split-Path $PSScriptRoot -Parent)).Path

function Get-ReleaseManifest {
  # Repo-relative paths shipped in the release ZIP. Directories expand to files.
  return @(
    'Setup.bat', 'Install.ps1', 'Uninstall.ps1', 'Start-Macify.ps1', 'Stop-Macify.ps1',
    'README.md', 'LICENSE',
    'src', 'config', 'assets', 'tools', 'docs'
  )
}

function Get-ReleaseExclusions {
  # Repo-relative files (exact match, '\' separators) left OUT of the ZIP.
  return @('tools\Build-Release.ps1')
}

function Get-ReleaseFiles {
  $root = $repoRoot.TrimEnd('\')
  $excl = Get-ReleaseExclusions
  $files = @()
  foreach ($rel in Get-ReleaseManifest) {
    $full = Join-Path $repoRoot $rel
    if (-not (Test-Path $full)) { throw "Release manifest entry missing: $rel" }
    if ((Get-Item $full -Force) -is [System.IO.DirectoryInfo]) {
      $kids = @(Get-ChildItem $full -File -Recurse -Force | Where-Object {
          $_.FullName -notmatch '\.git[\\/]' -and $_.Name -ne 'desktop.ini' -and $_.Name -ne 'Thumbs.db'
        })
      foreach ($f in $kids) {
        $r = $f.FullName
        if ($r.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
          $r = $r.Substring($root.Length).TrimStart('\')
        }
        if ($excl -notcontains $r) { $files += $r }
      }
    } elseif ($excl -notcontains $rel) {
      $files += $rel
    }
  }
  return @($files | Sort-Object -Unique)
}

function Get-ReleaseVersion {
  param([string]$Wanted)
  if ($Wanted.Trim() -ne '') { return $Wanted.Trim().TrimStart('v') }
  try {
    $t = git -C $repoRoot describe --tags --abbrev=0 2>$null | Select-Object -First 1
    if ($t -and "$t".Trim() -ne '') { return "$t".Trim().TrimStart('v') }
  } catch { }
  return '0.0.0-dev'
}

if ($ListOnly) {
  Get-ReleaseFiles
  return
}

$version = (Get-ReleaseVersion -Wanted $Version) -replace '[\\/:*?"<>|]', '-'
if ($OutDir.Trim() -eq '') { $OutDir = Join-Path $repoRoot 'dist' }
$zipName = "Macify-$version.zip"
$zipPath = Join-Path $OutDir $zipName
$stage = Join-Path $OutDir 'stage'
$stageRoot = Join-Path $stage 'Macify'

Write-Host "Building Macify $version ..." -ForegroundColor Cyan
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

$files = Get-ReleaseFiles
foreach ($rel in $files) {
  $dest = Join-Path $stageRoot $rel
  $ddir = Split-Path $dest -Parent
  if (-not (Test-Path $ddir)) { New-Item -ItemType Directory -Path $ddir -Force | Out-Null }
  Copy-Item (Join-Path $repoRoot $rel) -Destination $dest -Force
}

$sha = ''
try { $sha = git -C $repoRoot rev-parse --short HEAD 2>$null | Select-Object -First 1 } catch { }
$stamp = "Macify $version`r`nCommit: $sha`r`nBuilt: $(Get-Date -Format 'o')`r`n"
$stamp | Set-Content (Join-Path $stageRoot 'version.txt') -Encoding UTF8

Compress-Archive -Path $stageRoot -DestinationPath $zipPath
$hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
"{0}  {1}" -f $hash, $zipName | Set-Content (Join-Path $OutDir 'checksums.txt') -Encoding UTF8
Remove-Item $stage -Recurse -Force

Write-Host "  [ok] $zipPath" -ForegroundColor Green
Write-Host "  [ok] SHA256 $hash" -ForegroundColor Green
