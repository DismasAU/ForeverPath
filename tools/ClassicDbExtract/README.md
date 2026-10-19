# ClassicDbExtract

Builds the `ForeverPath_ClassicDB` addon (classic-era quests, quest givers and
turn-ins, NPC and object spawns) from [CMaNGOS classic-db](https://github.com/cmangos/classic-db).

```
powershell -ExecutionPolicy Bypass -File scripts\extract_classicdb.ps1 [-Commit <sha>] [-Refresh]
```

- `scripts\extract_classicdb.ps1` downloads the pinned classic-db snapshot into
  `cache/` (git-ignored), then runs `extract.py` with Python 3 (standard
  library only, run isolated with `python -I`).
- `extract.py` loads `Full_DB/*.sql.gz` into SQLite and applies `Updates/*.sql`
  then `Updates/Instances/*.sql`, the order `InstallFullDB.sh` uses. MySQL
  strings, `&&` / `||`, user variables (`SET @GUID := ...`), `INSERT IGNORE`,
  `TRUNCATE` and `ALTER TABLE ... ADD COLUMN` are translated; about 1% of
  update statements still fail (temporary tables, multi-table deletes,
  spawn bookkeeping) and are counted in `last-run.json`.
- World positions are placed on zone maps with `maps.json`: the Forever
  client's `UiMap`, `UiMapAssignment` (world bounds per zone map) and `Map`
  tables, written by `tools/DbExtract` (`scripts\extract_db.ps1 --maps`).
  Spawns inside instances keep the instance (map id) instead of a position.
- Output: `ForeverPath_ClassicDB/Quests.lua`, `Npcs.lua`, `Objects.lua`,
  `Maps.lua`, `Meta.lua` (layouts in each file's header and in
  `ForeverPath/Providers/ClassicDBProvider.lua`). Quests without any giver or
  turn-in, and placeholder titles (`<...>`, `[UNUSED]`, ...), are left out.
  Spawns are clustered on a 2% grid, at most 10 points per NPC.

## Licence

classic-db is GPL-3.0; its `LICENSE.md` is copied into the addon and must
ship with it. It contains Blizzard Entertainment content used
non-commercially (`COPYRIGHT.md`, also copied). ForeverPath is GPL-3.0 since
0.18.0 for this reason.
