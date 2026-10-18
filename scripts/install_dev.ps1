# Copies the ForeverPath addon folder into the WoW: Forever AddOns directory.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\install_dev.ps1 [-AddOnsPath <path>]
param(
    [string]$AddOnsPath = "D:\Blizzard Games\World of Warcraft\_classic_beta_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot "ForeverPath"
$target = Join-Path $AddOnsPath "ForeverPath"

if (-not (Test-Path $source)) {
    throw "Addon folder not found: $source"
}
if (-not (Test-Path $AddOnsPath)) {
    throw "AddOns folder not found: $AddOnsPath (pass -AddOnsPath)"
}

if (Test-Path $target) {
    Remove-Item -Recurse -Force $target
}
Copy-Item -Recurse -Path $source -Destination $target
$count = (Get-ChildItem -Recurse -File $target | Measure-Object).Count
Write-Host "Installed ForeverPath ($count files) to $target"
Write-Host "In game: /reload, then /fp"
