# Builds dist\ForeverPath-<version>.zip containing the addon folder.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\package.ps1
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
Compress-Archive -Path $source -DestinationPath $zip
Write-Host "Created $zip"
