# Builds dist\ForeverPath-<version>.zip containing the addon folders
# (ForeverPath and the load-on-demand ForeverPath_ClassicDB).
# Usage: powershell -ExecutionPolicy Bypass -File scripts\package.ps1
#
# Entries are written with forward slashes. Compress-Archive on Windows
# PowerShell 5.1 stores backslashes, which macOS unpacks into a flat folder
# of files named "ForeverPath\Core\Bootstrap.lua".
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot "ForeverPath"
$toc = Get-Content (Join-Path $source "ForeverPath.toc")
$versionLine = $toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | Select-Object -First 1
$version = if ($versionLine -match '^## Version:\s*(.+)$') { $Matches[1].Trim() } else { "dev" }

$dist = Join-Path $repoRoot "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "ForeverPath-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  $files = @()
  foreach ($folder in @("ForeverPath", "ForeverPath_ClassicDB")) {
    $path = Join-Path $repoRoot $folder
    if (Test-Path $path) { $files += Get-ChildItem -Path $path -Recurse -File }
  }
  $files = $files | Sort-Object FullName
  foreach ($file in $files) {
    $relative = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $archive, $file.FullName, $relative, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
  Write-Host "Created $zip ($($files.Count) files)"
} finally {
  $archive.Dispose()
}
