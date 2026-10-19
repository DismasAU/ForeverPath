# Builds the ForeverPath_ClassicDB addon from CMaNGOS classic-db.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\extract_classicdb.ps1 [-Commit <sha>] [-Refresh]
#
# Downloads the pinned classic-db snapshot into tools\ClassicDbExtract\cache
# (git-ignored), loads the full dump and its updates into SQLite and writes
# the Lua tables into ForeverPath_ClassicDB\. Zone-map bounds come from
# tools\ClassicDbExtract\maps.json, which scripts\extract_db.ps1 writes from
# the Forever client. Needs Python 3 (standard library only).
param(
  [string]$Commit = "ec4f596146be6467ea93c57397858e329e2db852",
  [switch]$Refresh
)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $repoRoot "tools\ClassicDbExtract"
$cache = Join-Path $tool "cache"
$src = Join-Path $cache "src"
$out = Join-Path $repoRoot "ForeverPath_ClassicDB"
$stamp = Join-Path $cache "commit.txt"

New-Item -ItemType Directory -Force $cache | Out-Null
$current = if (Test-Path $stamp) { (Get-Content $stamp -Raw).Trim() } else { "" }
if ($Refresh -or $current -ne $Commit -or -not (Test-Path (Join-Path $src "Full_DB"))) {
  $tarball = Join-Path $cache "classicdb.tar.gz"
  Write-Host "Fetching cmangos/classic-db $Commit"
  Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/cmangos/classic-db/tar.gz/$Commit" -OutFile $tarball
  if (Test-Path $src) { Remove-Item -Recurse -Force $src }
  New-Item -ItemType Directory -Force $src | Out-Null
  tar -xzf $tarball -C $src --strip-components=1
  if ($LASTEXITCODE -ne 0) { throw "tar failed" }
  Set-Content -Path $stamp -Value $Commit -Encoding ascii
}

$maps = Join-Path $tool "maps.json"
if (-not (Test-Path $maps)) { throw "Missing $maps; run scripts\extract_db.ps1 first (it reads the zone maps from the Forever client)." }

& python -I (Join-Path $tool "extract.py") --src $src --maps $maps --out $out --sqlite (Join-Path $cache "classic.sqlite") `
  --commit $Commit --report (Join-Path $tool "last-run.json")
if ($LASTEXITCODE -ne 0) { throw "extract.py failed with exit code $LASTEXITCODE" }

# classic-db's licence must ship with anything built from it.
Copy-Item (Join-Path $src "LICENSE.md") (Join-Path $out "LICENSE.md") -Force
Copy-Item (Join-Path $src "COPYRIGHT.md") (Join-Path $out "COPYRIGHT.md") -Force
Copy-Item (Join-Path $src "AUTHORS") (Join-Path $out "AUTHORS.txt") -Force
Write-Host "Done. Run python tests\run_tests.py, then scripts\install_dev.ps1."
