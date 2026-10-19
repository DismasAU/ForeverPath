# Copies the ForeverPath addon folders (ForeverPath and ForeverPath_ClassicDB)
# into the WoW: Forever AddOns directory.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\install_dev.ps1 [-AddOnsPath <path>]
param(
    [string]$AddOnsPath = "D:\Blizzard Games\World of Warcraft\_classic_beta_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $AddOnsPath)) {
    throw "AddOns folder not found: $AddOnsPath (pass -AddOnsPath)"
}

foreach ($folder in @("ForeverPath", "ForeverPath_ClassicDB")) {
    $source = Join-Path $repoRoot $folder
    $target = Join-Path $AddOnsPath $folder
    if (-not (Test-Path $source)) {
        throw "Addon folder not found: $source"
    }
    if (Test-Path $target) {
        Remove-Item -Recurse -Force $target
    }
    Copy-Item -Recurse -Path $source -Destination $target
    $count = (Get-ChildItem -Recurse -File $target | Measure-Object).Count
    Write-Host "Installed $folder ($count files) to $target"
}
Write-Host "In game: /reload, then /fp"
