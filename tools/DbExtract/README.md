# DbExtract: the recipe catalogue generator

Builds `ForeverPath/Data/RecipeCatalogue.lua` from the installed World of
Warcraft: Forever client. The catalogue is what lets ForeverPath lay out the
whole path to an item (Sulfuras -> Sulfuron Hammer + Eye of Sulfuras -> plans,
ingots, bars...) before anyone on the account has learned the recipe.

Run it after every client patch:

```
powershell -ExecutionPolicy Bypass -File scripts\extract_db.ps1
python tests\run_tests.py
powershell -ExecutionPolicy Bypass -File scripts\install_dev.ps1
```

Options: `-WowPath "D:\Blizzard Games\World of Warcraft"`, `-Product wow_classic_beta`,
`-Locale enUS`, `-NoHotfix`.

## Where the data comes from

Every number in the catalogue is read from the client's own database tables
(DB2 files in the CASC store under `<install>\Data`), with the server's
hotfixes applied from the cache the client writes after a login
(`_classic_beta_\Cache\ADB\enUS\DBCache.bin`). Nothing is copied from another
addon or a website.

| Table | Used for |
|---|---|
| `SkillLine` | profession names, categories (11 primary, 9 secondary), parent lines |
| `SkillLineAbility` | which spells belong to a profession; trivial ranks (yellow, grey); acquire method |
| `SpellEffect` | effect 24 / 157 "create item": the item a spell makes and how many |
| `SpellReagents` | reagents and counts |
| `SpellName`, `SpellMisc` | recipe names and icons |
| `ItemEffect` + `ItemXItemEffect` | trigger 6 "learn": the plans / pattern that teaches a spell; trigger 0 "on use": item-use combines |
| `ItemSparse` | item names, quality, binding, and the skill a plans item requires |
| `Item` | every item id the client still has (recipes whose item or reagents are gone are dropped), plus class and subclass for every referenced item |

Two things the client does not know and the catalogue therefore does not
carry: the skill a **trainer** requires for a recipe (server-side; such recipes
show `minSkill` 1 and the yellow rank is the guide), and where a plans item
drops or who sells it (ForeverPath's vendor recorder, DungeonJournal and
AtlasLoot bridges cover that at runtime).

`ItemSparse` is partial on this client: the server streams item rows into the
hotfix cache as the client sees them, so a few hundred items have no cached
name at extraction time. ForeverPath names those through the client at
runtime; the count is printed when the tool runs.

## How it works

- `DbExtract.csproj` / `Program.cs`: a .NET 7 console program. It opens the
  local CASC store with CascLib, reads each table by file data id (ids from the
  WoWDBDefs manifest), decodes it with DBCD using the community table layouts
  (WoWDBDefs `.dbd` files, fetched once into `definitions/`), applies
  `DBCache.bin`, joins the tables and writes the Lua file plus `last-run.json`.
- `casclib-forever.patch`: CascLib on NuGet predates the root manifest format
  the Forever client uses and the GitHub master targets .NET 8+. The script
  clones https://github.com/WoW-Tools/CascLib at a pinned commit into
  `external/` and applies this two-line patch (target .NET 7, accept root
  blocks without locale flags, as TACTSharp does). CascLib has no licence
  file, so it is used only as a build-time dependency and never shipped.
- `definitions/`, `external/`, `bin/`, `obj/`, `last-run.json` are build
  products; the only output that ships is `ForeverPath/Data/RecipeCatalogue.lua`.

## Checking a run

The tool prints per-profession counts and two spot checks:

```
check Sulfuron Hammer: skill 300/325/350 -> item 17193 x1, taught by 18592, reagents 17203x8 11371x20 12360x50 7078x25 11382x10 17011x10 17010x10
check Eye of Sulfuras: -> 17182 from 17193x1 17204x1
```

`tests/spec/catalogue_spec.lua` asserts the same facts against the generated
file, so a bad extraction fails the offline suite.

## Output format

Documented at the top of `RecipeCatalogue.lua`. Rows are positional to keep
the file small (about 540 KB for 2,300 recipes); `Data/Recipes.lua` decodes
them into the `RecipeModel` shape the planner uses.
