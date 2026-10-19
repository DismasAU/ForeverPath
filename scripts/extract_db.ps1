# Regenerates ForeverPath\Data\RecipeCatalogue.lua from the installed Forever client.
#
# Reads the client's own database tables (CASC store plus the hotfix cache the
# client writes after a login) and writes the recipe catalogue the addon ships.
# Run it after every client patch, then run the tests and reinstall.
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\extract_db.ps1 [-WowPath "D:\Blizzard Games\World of Warcraft"] [-Product wow_classic_beta] [-Locale enUS] [-NoHotfix]
#
# Needs: .NET SDK 7 or newer (dotnet), git, and the game installed. The first
# run clones CascLib (https://github.com/WoW-Tools/CascLib, no licence file,
# used only as a build-time dependency and never shipped) into
# tools\DbExtract\external and applies tools\DbExtract\casclib-forever.patch
# so it reads the root manifest the Forever client uses. Table layouts come
# from WoWDBDefs and are cached in tools\DbExtract\definitions.
param(
  [string]$WowPath = "D:\Blizzard Games\World of Warcraft",
  [string]$Product = "wow_classic_beta",
  [string]$Locale = "enUS",
  [switch]$NoHotfix
)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $repoRoot "tools\DbExtract"
$external = Join-Path $tool "external\CascLib"
$cascCommit = "3f8be478177802de4ae7ebae24fb25ab860ef104"

foreach ($exe in @("dotnet", "git")) {
  if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { throw "$exe is not on PATH" }
}
if (-not (Test-Path (Join-Path $WowPath ".build.info"))) { throw "No .build.info under $WowPath; pass -WowPath <World of Warcraft install folder>" }

if (-not (Test-Path (Join-Path $external "CascLib\CascLib.csproj"))) {
  Write-Host "Fetching CascLib $cascCommit"
  New-Item -ItemType Directory -Force (Split-Path -Parent $external) | Out-Null
  git clone --quiet https://github.com/WoW-Tools/CascLib $external
  if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
  git -C $external checkout --quiet $cascCommit
  if ($LASTEXITCODE -ne 0) { throw "git checkout failed" }
  git -C $external apply --whitespace=nowarn (Join-Path $tool "casclib-forever.patch")
  if ($LASTEXITCODE -ne 0) { throw "patch failed" }
}

$outDir = Join-Path $repoRoot "ForeverPath\Data"
$args = @("run", "--project", (Join-Path $tool "DbExtract.csproj"), "-c", "Release", "--",
  "--wow", $WowPath, "--product", $Product, "--locale", $Locale,
  "--out", $outDir, "--defs", (Join-Path $tool "definitions"), "--report", (Join-Path $tool "last-run.json"),
  "--maps", (Join-Path $repoRoot "tools\ClassicDbExtract\maps.json"))
if ($NoHotfix) { $args += "--no-hotfix" }
& dotnet @args
if ($LASTEXITCODE -ne 0) { throw "DbExtract failed with exit code $LASTEXITCODE" }
Write-Host "Done (RecipeCatalogue.lua, ItemIndex.lua, tools\ClassicDbExtract\maps.json). Run python tests\run_tests.py, then scripts\install_dev.ps1."
