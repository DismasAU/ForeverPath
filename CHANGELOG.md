# Changelog

## 0.19.0 (2026-10-19) - classic drops, gathering, vendors and trainers

### Added
- `ForeverPath_ClassicDB` now also carries, from CMaNGOS classic-db:
  - **where items drop** (`Loot.lua`): creature drops for 6,197 items with
    their chances (the 5 likeliest creatures each, references expanded,
    grouped loot shared out, quest-only drops flagged), 291 world drops (loot
    tables shared by 25+ creatures, with the creatures' level range),
    skinning, pickpocketing, gathering nodes and chests (2,623 items),
    fishing zones and containers;
  - **vendors** (`Vendors.lua`): who sells 1,788 items and the price per unit;
  - **trainers** (`Trainers.lua`): which trainers teach 477 profession
    recipes, the skill they need and the cost (trainer "learning" spells are
    mapped to the recipe through classic-db's `spell_template`);
  - NPCs gain the faction they deal with (from the client's
    `FactionTemplate`) and their rank; objects the skill that opens them
    (from the client's `Lock`: Herbalism, Mining, Fishing, Lockpicking).
  5,955 NPCs and 959 objects in all.
- **Classic item sources** (`ClassicDB.ItemHints`, through
  `SourceProvider.Sources`): "Buy from <vendor>", "Gathered from
  <node>" (qualified by who has the gathering skill, like every gathering
  hint), "Dropped by <creature>" with zone, chance, level and rank,
  "Skinned from", "Fished in", "Found in <container>", "Pickpocketed
  from" (rogues only) and "World drop", each marked "(classic data)". A
  vendor recorded at a merchant window hides the classic vendors; a
  creature the journal or AtlasLoot already names is not listed twice; a
  classic gathering node replaces the generic "Herbalism" class hint.
  Drops under 1% and world drops are shown but never the recommended
  route. Tags use a short form ("Drop: Wolf").
- **Classic vendor prices**: `VendorProvider.GetPrice` falls back to the
  cheapest classic vendor this faction can use, so vendor reagents have a
  price before any merchant window is visited (a recorded price wins).
- **Classic trainers**: `TrainerProvider.Requirement` falls back to the
  classic trainer (skill, rank, cost, the first trainer this faction can
  use, with its position), so trainer-taught recipes know their required
  skill before any trainer window is visited; recorded trainers win.
- `tools/DbExtract --maps` also exports `AreaTable`, skill `Lock` rows and
  `FactionTemplate` to `maps.json`.

## 0.18.0 (2026-10-19) - classic-era quests and NPCs from CMaNGOS classic-db

### Changed
- **Licence: ForeverPath is now GPL-3.0** (was MIT up to 0.17.3), so it can
  ship data generated from CMaNGOS classic-db. `LICENSE` holds the GPL text
  and the addon ships it as `LICENSE.txt`; both manifests say
  `X-License: GPL-3.0`.
- The release zip and `scripts\install_dev.ps1` carry two folders:
  `ForeverPath` and `ForeverPath_ClassicDB`.

### Added
- **`ForeverPath_ClassicDB`**, a load-on-demand data addon generated from
  CMaNGOS classic-db (pinned snapshot ec4f5961, 2026-09-22): 4,143 quests
  (title, levels, side, class, givers, turn-ins, the item that starts it,
  items and kills required, choice and fixed rewards, reputation,
  prerequisites, follow-up, objective text), 2,216 NPCs and 313 objects with
  spawn points, and zone / instance names. classic-db's `LICENSE.md` and
  `COPYRIGHT.md` ship with it.
- **`tools/ClassicDbExtract`** and `scripts\extract_classicdb.ps1`: loads the
  dump and its 387 update files into SQLite in installer order (about 1% of
  update statements are MySQL-only and skipped; counted in the report) and
  writes the Lua tables. Spawns are placed on the Forever client's zone maps
  through `UiMapAssignment` bounds, which `tools/DbExtract` now exports to
  `tools/ClassicDbExtract/maps.json` (`--maps`). Checked against Attune's
  pins: Prate Cloudseer 53.5/42.6 (Attune 53.6/42.8), Rau Cliffrunner
  46.1/51.7 (46.0/51.6), Bath'rah 80.5/66.9 (80.4/66.8).
- **`ns.ClassicDB`** (`Providers/ClassicDBProvider.lua`) loads the data addon
  at start-up (`Compat.LoadAddOn`) and serves quests in QuestProvider's
  entry shape (`source = "classic"`), NPCs and objects with their spawns,
  places (`PlaceOf`), eligibility by faction and class, reward / reputation
  / title indexes and prerequisite chains (`ChainTo`: an "any of" group
  takes the member already completed, else the first this character can
  take).
- **Quests fall back to classic data** behind everything Forever-specific:
  `QuestProvider.Get` returns the classic entry for quests no journal or
  Attune entry knows; `Giver` / `Turnin` use the classic NPC's position
  (learned facts, the shipped catalogue and journal / Attune pins still
  win; a journal giver named like the classic NPC gets its position);
  `RequiredItems` falls back to the classic items; `QuestsRewarding` adds
  classic quests this character can take; `Search` finds classic titles;
  `StateLabel` locks a quest until each prerequisite group has a completed
  member; `Describe` says "(classic data)".
- **Classic questlines**: `QuestProvider.ClassicQuestline` turns the
  prerequisite chain into the same shape as an Attune questline, so quest
  goals and quest-reward items plan along any classic chain ("First pick up
  Gather Hides from Ranger Bob in Elwynn Forest (step 1 of 4 of The Final
  Test chain, ...)"), with waypoints, the chain's items on the tree and the
  shopping list. A ForeverDungeonJournal chain still wins for its quests.
- Classic quest rewards are planned as a questline only for items that
  bind on pickup or are quest items (`Planner.BindType`), or that have no
  other route, so a potion an old quest also rewards is still bought.
- **Classic reputation quests**: `ReputationProvider.QuestsFor(name,
  factionID)` adds every classic quest this character can take that rewards
  the faction, so reputation goals and the Reputations and Quests screens
  list them.
- `/fp status` reports the classic data (or why it is not loaded).

## 0.17.3 (2026-10-18) - click any attunement step for its summary

### Added
- On the Attunements screen every step of the chain is clickable. The
  side panel then shows that step instead of the current one ("Step 6 of
  8"): for a quest its state, live objectives (or the journal's text), who
  gives it and where, who takes it back, what to bring with bag counts and
  where it drops, and the rewards; for an item step the bag count and a
  source; for a level step how far to go. "Waypoint" pins the giver or
  turn-in when a position is known; "Quests >" opens the quest on the
  Quests screen. Clicking the shown step again returns to the current one.

## 0.17.2 (2026-10-18) - source tags fit their column

### Fixed
- Long source tags ("Drop: Lost Ones, Fallow Sanctuary, Swamp of Sorrows")
  ran past the right edge of the crafting requirements and the shopping
  list. `Widgets.LayoutTags` now lays a cell's tags out inside its width:
  a tag that does not fit is cut with an ellipsis, later ones are hidden,
  and the cell clips. The Source column is 180 px wide on both tables.
  Catalogue drop hints carry a short form for tags ("Drop: Lost Ones");
  the full text stays in the row tooltip and `/fp sources`.
- The item note under a two-handed weapon read "Two": the class text is
  now cut at " - ", not at the first hyphen.

## 0.17.1 (2026-10-18) - the shaman Call of Air chain in the quest catalogue

### Added
- `Data/QuestCatalogue.lua` ships the shaman level-30 "Call of Air" chain
  for both factions (Horde: Call of Air from Searn Firewarder or Xanis
  Flameweaver, Elemental Aid, Eyes on the Sky, Storm, Earth, and Fire, Heed
  My Call, The Tempest's Weapons; Alliance: Call of Air from Eldrun
  Stormbreaker, Elemental Aid, Storm, Earth, and Fire, Heed My Call, The
  Tempest's Weapons): giver and turn-in with map positions (Prate
  Cloudseer, Rau Cliffrunner, Veyric Thunderhame, Bath'rah the Windwatcher)
  and the items each quest asks for - the Tattered Note from Charlga
  Razorflank, 5 of each Twisted Totem with the mobs and zones they drop
  from, the Eye of the Tempest from the ritual. Sources are listed at the
  top of the file; positions are unverified on the beta and a quest window
  opened in game overrides them.
- Catalogue items carry `source`; `QuestFactsProvider.ItemHints(itemID)`
  turns them into drop hints that `SourceProvider.Sources` lists, so the
  totems show "Drop: Mirefin murlocs, Dreadmurk Shore, Dustwallow Marsh" on
  the shopping list, the tree and the requirement rows.

### Fixed
- The 0.17.0 notes said Attune carries no giver pins for class-chain
  quests; it does (`AttuneClassQuests.lua` merges them into
  `Attune_Data.questGivers`), and ForeverPath already read them. The
  catalogue adds the turn-ins and the items.

## 0.17.0 (2026-10-18) - questlines: the chain behind a quest reward

Put a quest reward such as Rage of the Storm in as a goal and ForeverPath
now plans the whole chain that leads to it, lists what the chain's quests
ask you to bring, and points you at the next giver.

### Added
- **Questlines.** `AttuneProvider.QuestlineFor(questID)` finds the
  attunement or class-quest chain (Attune) that contains a quest for this
  character's faction and class, and returns the steps that lead to it
  (level gates, either/or starts, quests) with live progress; either/or
  predecessors in Attune's `FOLLOWS` ("20|25") are now understood. A quest
  goal plans along the chain ("First pick up Call of Air from Prate
  Cloudseer in Thousand Needles (step 2 of 8 of Call of Air, before The
  Tempest's Weapons)"), its progress is the chain's, and its label is
  Locked until the chain reaches it.
- **Quest rewards as goals.** An item goal whose item a known quest
  rewards (`Planner.RewardQuestline`) carries `view.questline`: the quest,
  its chain, the next step as the goal's next step, "Quest reward: <quest>"
  as its source, and the chain's name on the crafting hero. The dashboard,
  the tracker, My Goals and the overview show the step.
- **What the chain asks for.** The items the open quests of the chain
  require (`QuestProvider.RequiredItems`: the live item objectives while a
  quest is in the log, matched to item ids by name; recorded facts
  otherwise) hang below the reward in the dependency tree
  (`DependencyResolver.AttachItems`) or below a quest goal's root
  (`Resolve({ step = { kind = "quest", items } })`), so they appear on the
  requirement rows, in the tree, in the overview's missing list and on the
  shopping list with the usual routes.
- **Givers, turn-ins and map pins.** `Providers/QuestFactsProvider.lua`
  learns, account-wide (`ForeverPathDB.questFacts`), the giver's name and
  your map position when a quest window opens (`QUEST_DETAIL`), the item
  objectives when you accept (`QUEST_ACCEPTED`, re-resolved as items drop),
  and the turn-in NPC at the reward window (`QUEST_COMPLETE`).
  `Data/QuestCatalogue.lua` ships curated rows in the same shape (empty in
  this release; the shaman chain follows in 0.17.1). Next steps name the
  giver and zone; a "Set waypoint" button on the crafting hero and a
  "Waypoint" button on the Quests side panel pin the giver (or the turn-in
  once the quest is ready) with the client's map waypoint
  (`Compat.SetWaypoint`).
- The Quests side panel lists the chain's steps, "Bring N x <item>" lines
  and the giver; `/fp quest` prints the chain, the giver, the turn-in and
  the items; `/fp status` reports how many quests have facts.

### Changed
- `AttuneProvider.Steps` carries `alternative` (Attune's `OR`), attunements
  carry `class`, and `Progress` treats "a|b" predecessors as either-of.

## 0.16.2 (2026-10-18) - item search finds names anywhere

Typing "Storm" only ever showed "Storm..." items: the search already
matched anywhere in a name, but names starting with the text filled the
short suggestion list first, and the only names it knew were the
catalogue's (items recipes make or need) and items already seen.

### Changed
- `ItemProvider.SearchByName` ranks exact, then starts-with, then a word
  starting with the text ("Mace of the Storms"), then anywhere inside a
  word ("Thunderstorm Blade"), and keeps two slots of a cut list for the
  later groups (`MatchRank`, `RESERVED_SLOTS`). The New Goal popup shows
  eight suggestions.
- Item names also come from ForeverDungeonJournal's loot and quest
  rewards and from GearQuest Forever's loaded item facts
  (`ItemProvider.RegisterNameSource`; `SourceProvider.JournalNames`,
  `EquipmentProvider.ItemNames`), so boss drops and leveling gear are
  found by name before you have ever seen them.

## 0.16.1 (2026-10-18) - Shift-click links from every item row

### Added
- Shift-click an item on the shopping list, the crafting requirements,
  the dependency tree, the dashboard, the tracker or the Equipment screen
  to send its link where the client sends Shift-clicked links: the open
  chat box, the Auction House search (the default one, or Auctionator's
  shopping search, which hooks the same call), or a ForeverPath input with
  focus. The status bar confirms it; when nothing takes the link it is
  printed to chat. Item tooltips mention it (`Widgets.ShiftClickLinks`,
  `MainFrame.LinkItem`).

## 0.16.0 (2026-10-18) - type-ahead and unmet factions

Typing "Cenarion Circle Exalted" into New Goal did nothing visible: the
Reputation kind only searched the character's own reputation pane, which
lists a faction only after it has been met, and the error went to the
status bar.

### Added
- **Suggestions as you type.** The New Goal input on My Goals shows a
  popup of matches for the selected kind after two characters: items,
  recipes, enchants, professions (with your skill), quests, factions (with
  your standing, or "Not met yet") and attunements. A click adds the goal,
  with the stepper's quantity for items and enchants; a trailing standing
  ("cenarion ex") or rank ("tailoring 225") is kept. The header search
  suggests a few of every kind and opens the goal's screen on a pick
  (`GoalService.Suggest(kind, text, limit)`, `MainFrame.ShowSuggestions`).
- **Factions you have not met.** The catalogue now carries the client's
  faction table (`Catalogue.factions`: name, parent, pane index, and the
  starting reputation per race and class slot). `ReputationProvider.Get`
  and `Search` fall back to it with `unmet = true`, at the starting
  standing for the character's race and class (Timbermaw Hold Unfriendly,
  Stormwind Friendly for a Human and Hated for an Orc, Cenarion Circle
  2000 for druids), so a goal can be set before the faction appears in
  the pane; the planner's message says "not met yet". `/fp status` counts
  the table.

### Changed
- The New Goal bar drops the kind segment to a second row when the window
  is too narrow for it beside a usable input (it used to overflow).

## 0.15.1 (2026-10-18) - reputation quests feed the Quests screen

### Changed
- A reputation goal now feeds the Quests screen: every open quest that
  gives reputation with its faction appears under the goal on the "By
  goal" tab, counts for "Only quests that feed a goal", shows "+250
  Ironforge reputation for Ironforge - Honored" in the quest panel, and is
  listed by `/fp quests` (`QuestProvider.FeedsGoals` reads
  `view.reputation.quests`, or asks `ReputationProvider.QuestsFor`).

## 0.15.0 (2026-10-18) - enchant goals

Enchants (and Engineering tinkers) had no way into ForeverPath: the
catalogue only kept spells that create an item, the recipe model refused a
recipe without one, and Shift-click only accepted item links.

### Added
- **Enchants in the recipe catalogue.** `tools/DbExtract` now keeps
  profession spells whose effect enchants an item (`SpellEffect` 53 / 54)
  as recipes with item 0: 179 Enchanting enchants and 3 Engineering
  tinkers on build 1.60.1.70450, each with its reagents, skill ranks and
  the formula that teaches it. `Data/Recipes.lua` decodes them with
  `enchant = true`, no `outputItemID` and a yield of one cast
  (`Recipes.IsEnchant`, `EnchantCount`, `Search(..., kind)`); they are
  never indexed as an item's recipe. `RecipeModel.FromSchematic` accepts a
  schematic without an item when the client calls it an enchant
  (`recipeType` 3) or the catalogue does, so profession scans record the
  enchants you know; `Validate` allows `enchant` recipes without an item.
- **Enchant goals** (`/fp enchant <enchant> [casts]`, the Enchant segment
  on My Goals, or Shift-click an enchant from the Enchanting window into
  any ForeverPath input). Target `{ spellID, name, professionName,
  professionID, icon, quantity, casts }`: cast the enchant `quantity`
  times. `Planner.EvaluateEnchant` lays the enchant out as the root of a
  tree (`enchant:<spellID>`, never owned or bought) with the formula to
  get or the trainer to visit while unlearned, and the reagents for every
  cast still to do; the plan is those reagents, and it is complete only
  when the formula or training is too. Blockers (no profession, skill too
  low), the formula's sources, the recorded trainer and alts who know the
  enchant read as for learn-recipe goals. Reagents land on the shopping
  list and in CraftWise; the enchant itself never does.
- **Completion by casting.** `UNIT_SPELLCAST_SUCCEEDED` for the player
  counts each cast of the spell towards every open enchant goal for it
  (`GoalCompletion.RecordCast`); the goal completes at the cast count with
  the "Enchant applied" toast, and reopening it starts the count over.
- **Enchanting skill goals** plan enchants: reach-skill candidates now
  include item-less recipes, so "Enchanting 225" picks the enchants you
  know (or could learn) and lists their reagents. Tree nodes without an
  item carry `name` and `icon`; every screen, the Overview, CraftWise and
  `Describe` fall back to them.
- Shift-click now takes enchant and spell links as well as item links: an
  enchant becomes an enchant goal, an item recipe a goal for the item it
  makes (`GoalService.SpellIDFromText`, `AddFromInput`); `/fp learn`
  accepts the same links.

### Changed
- `/fp status` and the catalogue line report the enchant count; profession
  scans report "N recipes (M enchants)".
- The Dashboard names the first craft of a fully stocked skill plan
  ("Craft 12 x Bolt of Silk Cloth") instead of the goal.
- "Visit an Enchanting trainer" (article fixed for professions starting
  with a vowel).

## 0.14.0 (2026-10-18) - reputation goals and the Reputations screen

The last of the planned goal types; no preview modules remain.

### Added
- **Reputation goals** (`/fp rep <faction> [standing]`, the Reputation
  segment on My Goals, the button on the Reputations screen).
  `Providers/ReputationProvider.lua` reads every faction's standing through
  `C_Reputation` (the legacy `GetFactionInfo` as a fallback) with the
  classic thresholds (Neutral 0, Friendly 3000, Honored 9000, Revered
  21000, Exalted 42000), groups them under the client's headers, and knows
  two ways to earn: dungeon quests whose reward text names a faction
  ("Ironforge +250", from ForeverDungeonJournal) with their live state, and
  the items each standing unlocks (AtlasLootClassic_Factions, loaded on
  demand). A goal targets a standing (default: the next one up), its
  progress is the reputation earned since the goal was made, the next step
  is the first open quest that gives reputation, and it completes on
  `UPDATE_FACTION` when the standing is reached (toast "Reputation
  reached"). Target `{ factionID, name, standing, startValue, icon }`;
  `GoalModel.SetStanding` / `GoalStore:SetStanding` / `GoalService.SetStanding`.
- **Reputations screen** (no longer a preview): factions by group with
  standing and a bar through the current standing; a faction panel with the
  standing, the target segment (Friendly to Exalted), the reputation still
  needed, the quests that give it (click one to open it on the Quests
  screen) and the rewards the target unlocks, and an Add / Retarget / Open
  goal button.
- Items sold by reputation vendors become vendor options on item goals,
  unavailable with the reason ("needs Honored with Argent Dawn; you are
  Friendly") until the standing is reached.
- `/fp rep`, `/fp reps`; `/fp status` ends with the reputation line.

### Removed
- The preview module screen (`UI/Screens/Preview.lua`) and the "Preview
  modules" divider in the sidebar: every screen is real now.

## 0.13.0 (2026-10-18) - the Equipment screen

### Added
- **Equipment screen** (no longer a preview). `Providers/EquipmentProvider.lua`
  reads every slot (`GetInventoryItemID` / `GetInventoryItemLink`), item
  levels (`C_Item.GetDetailedItemLevelInfo`, then item info) and stats
  (`C_Item.GetItemStats`, legacy `GetItemStats`, GearQuest's scored stats as
  a fallback), and bridges GearQuest Forever's hunt data: its expanded
  entries for the player's class, spec (GearQuest's own detection or pick),
  faction and level band (its five-level grace), ranked by its curated rank
  and pipeline score, deduplicated per item, with the item facts (source
  type, instructions, zone, npc, quest, profession). The screen shows a
  summary strip (average item level, upgrades planned, tracked as goals),
  the All slots / Upgrades only segment and a source filter (quests,
  vendors, dungeons, crafted, drops), the seventeen slots in two columns
  with Best in slot / Upgrade found / Empty badges or the goal line, and a
  slot panel with the equipped item, the target card (the goal's item, else
  GearQuest's best pick), a stat comparison (item level, armor, DPS, primary
  stats, attack and spell power, healing, crit, hit, mana regen,
  resistances) with deltas, the other options with "+ Goal" buttons, and
  Open goal / + Goal for target. Targets become ordinary crafting or obtain
  goals, so the slot line shows the goal's progress.
- GearQuest's item facts feed the source hints of obtain goals (vendor and
  npc, quest reward and zone, boss, rare, world drop, containers and
  fishing) when nothing else knows the item.
- `/fp equipment` prints the slots, picks and goals; `/fp status` ends with
  the quest and equipment lines. `FP_EQUIPMENT_UPDATED` (from
  `PLAYER_EQUIPMENT_CHANGED` / `UNIT_INVENTORY_CHANGED`) refreshes the window.

## 0.12.0 (2026-10-18) - quest goals and the Quests screen

### Added
- **Quest goals** (`/fp quest <name or id>`, the Quest segment on My Goals,
  "+ Add goal" on the Quests screen). `Providers/QuestProvider.lua` indexes
  the quests other Forever addons ship: ForeverDungeonJournal's dungeon
  quests (level, required level, faction, objective, pick-up and turn-in,
  rewards, XP) with their prerequisite chains (`QUEST_PREREQ_CHAINS`) and
  quest-giver pins (`QUEST_START_MAPS`), and Attune's attunement quests
  (names, required level, group size, quest givers, rewards). Quests in
  your log are read from `C_QuestLog` whether or not an addon knows them;
  other titles are loaded by id (`RequestLoadQuestByID`). A quest goal's
  plan is its chain: prerequisites first, each with its live state
  (completed flag, in log with objectives, ready to turn in), then the
  quest. The view says what to do next ("Pick up X from Y", "Finish X:
  3/20 ...", "Turn in X at Y", "Needs level 15") and the goal completes on
  the turn-in (toast "Quest complete"). Progress counts completed quests of
  the chain plus the objectives of the one in the log.
- **Quests screen** (no longer a preview). By zone (dungeon, attunement or
  quest-log zone), by goal (quests whose rewards an open goal is missing,
  plus quest goals) or completed; the "only quests that feed a goal"
  filter; rows with the quest marker, the level in difficulty colours, the
  goals fed and a state badge (Ready, In log, Available, Locked, Done); a
  details panel with level, place and giver, live objectives with bars or
  the objective text, the chain, a "ready to turn in" callout, reward icons
  and text, which goals the rewards feed, and Add goal / Open goal, Link
  (quest link into chat) and Watch (objective tracker) buttons; footer with
  the quests feeding goals and the log capacity.
- `/fp quests` prints the quests that feed your goals with their state.
- `Status.PROFESSION_MISSING` joins `StatusLabel`; `GoalModel.COMPLETE_QUEST`
  is supported (target `{ questID, name, level, instance, icon }`).

### Changed
- The Overview, Dashboard, My Goals, tracker and Crafting screens handle
  quest goals (the Crafting screen points to the Quests screen, as it does
  for attunements). `FP_QUESTS_UPDATED` (debounced from the quest events)
  refreshes the window.

## 0.11.0 (2026-10-18) - learn-recipe and reach-skill goals

Two goal types that the catalogue and the trainer recorder made cheap.

### Added
- **Learn-recipe goals** (`/fp learn <recipe name or spell id>`, the Recipe
  segment on My Goals). The goal is done when this character knows the
  recipe (auto-completes on `NEW_RECIPE_LEARNED` / a profession scan, toast
  "Recipe learned"). Until then the plan is the pattern to get (an obtain
  tree of the teaching item, marked as a recipe, with its sources) or the
  trainer to visit (a one-node train-step tree with the trainer, zone and
  cost once recorded). The view says what blocks it: no such profession on
  this character, or skill below the requirement ("Reach Tailoring 75" as
  the next step), and names alts whose snapshot already knows it. Combines
  are refused: there is nothing to learn.
- **Reach-skill goals** (`/fp skill <profession> [rank]`, the Skill segment;
  rank defaults to the current cap, or the next 75 above it). Progress is
  the skill itself (`startRank` is remembered at creation). The new
  `Domain/SkillPlanner.lua` picks, for every point from the current skill
  to the target, the best recipe: learned recipes first, orange before
  yellow before green (classic chance: full below the yellow threshold,
  then falling linearly to zero at grey), cheapest expected cost when
  reagent prices are known, fewest reagents otherwise. Consecutive points
  with the same recipe form segments; expected crafts are rounded up. Where
  nothing learned gives a point, an unlearned recipe with a known
  requirement (a recorded trainer rank, or a pattern whose item carries it)
  fills in and brings its own "learn it" step or pattern; otherwise the
  range is reported as a gap. The plan becomes a tree: a skill root with one
  craft node per recipe, done for the points (`node.forSkill`: never owned,
  never bought, not on the shopping list), whose reagents are what the
  shopping list, the requirements table, the Overview and CraftWise see.
  Auto-completes on `SKILL_LINES_CHANGED` with the toast "Skill reached".
  Says when the profession window has not been recorded yet, and when the
  target is above the cap a trainer has to raise.
- `GoalModel.SetRank`, `GoalStore:SetRank`, `GoalService.SetRank`: the
  stepper on My Goals and the Crafting hero edits a skill goal's target.
- Catalogue helpers: `Recipes.ForProfession`, `Recipes.Professions`,
  `Recipes.FindProfession` (prefix match), `Recipes.Search` (recipe names,
  exact and prefix first). `CharacterProvider.WhoKnows(spellID)`.
  `Util.FormatMoney`. `Status.PROFESSION_MISSING`.
- Resolver roots: `{ step = {...} }` (a single step) and `{ step = { kind =
  "skill" }, crafts = { { recipe, crafts, learned, from, to } } }` (a skill
  plan); obtain roots accept `learn` / `learnFor`.

### Changed
- My Goals: the New Goal segments are Item, Recipe, Skill, Attunement (Quest
  and Reputation still disabled); the quantity stepper only applies to item
  goals and becomes the target skill for skill goals. The Crafting screen,
  Dependency Tree, CraftWise, Dashboard, tracker and shopping list render
  the new goal kinds (skill root rows, "Craft for skill" nodes, trainer
  steps as the whole plan).
- The shopping list lists a train step that is the root of a tree (it only
  listed steps below a craft before).

## 0.10.5 (2026-10-18) - housekeeping before release

### Added
- `OptionalDeps` in both manifests: Auctionator, AtlasLootClassic (and its
  DungeonsAndRaids module), ForeverDungeonJournal, Attune. ForeverPath reads
  them lazily, so this only guarantees they load first.
- `LICENSE` (MIT), matching the `X-License` field the manifests always had.
- README: a "Companion addons" table and a current opening paragraph.
- `scripts/package.ps1` writes zip entries with forward slashes;
  Compress-Archive on Windows PowerShell 5.1 stored backslashes, which macOS
  unpacks into a flat folder of oddly named files.

### Changed
- Documentation: every feature through 0.10.4 has been in daily use in game
  by the author, so the README status table, the TESTING.md checklists
  (sections 7 to 19) and the API notes no longer say "not yet verified in
  game". The function-level open questions in API_COMPATIBILITY.md stay
  listed because the branch each call takes was not recorded.

## 0.10.4 (2026-10-18) - the ForeverPath mark

### Added
- `Media/ForeverPath-Mark.png` (128 px, from the mark supplied by the author;
  the source PNG and SVG are kept under `design/`). It is the addon's
  `IconTexture` in both manifests (addon list and compartment), the window
  header emblem (32 px, replacing the placeholder diamond in a square) and
  the tracker emblem (16 px). `ns.UI.LOGO` holds the path. Not yet verified
  in game: PNG textures are used by other Forever addons (ProfessionMaster's
  icon), so the format is expected to load.

## 0.10.3 (2026-10-18) - gathering materials stay whole

Medium Leather is skinned, not made from Light Leather that was made from
scraps. The tree used to expand every learned recipe, so "Recommended next"
asked for 95 Ruined Leather Scraps when it meant 8 Medium Leather. Not yet
verified in game.

### Changed
- **Raw materials are leaves by default.** `SourceProvider.IsRawMaterial`
  marks an item whose class is gathered (leather, herbs, ore, gems,
  enchanting materials) and whose every recipe only refines a lower tier of
  the same kind (one reagent type, same gathering kind, by a profession other
  than the gathering skill itself). The resolver (`opts.isRaw`, `node.raw`)
  then never picks a craft for it by default, learned or not: the route is
  the gathering hint when someone on the account has the skill, otherwise
  the Auction House. Bolts (cloth is a drop), cured hides (salt as well) and
  smelting (Mining refines its own ore) keep expanding. Choosing "Use
  crafting route" on the node still expands it one tier; that tier is raw
  again, so each step down is a deliberate choice.
- The class heuristic is kept for such items (so Medium Leather shows
  "Skinning - you have Skinning (150)"), and item classes come from the
  catalogue when the client has not cached the item (`Recipes.ItemClass`,
  `SourceProvider.ItemClass`).
- The catalogue's item rows gain `classID, subclassID` for every referenced
  item, named or not (`tools/DbExtract` regenerated: 5,262 items).
- Dependency Tree option card for a raw item: "Gathering material: refining
  the tier below is off by default", never highlighted as best.

### Tests
- `source_provider_spec`: raw-material classification across leather tiers,
  bolts, cured hides, smelting and essences; a Dark Leather Cloak plan whose
  Medium Leather stays a leaf (buy, then gather with a skinner), with the
  override expanding exactly one tier. 203 tests pass.

## 0.10.2 (2026-10-18) - "train it" steps in the tree

When nobody on the account has learned a recipe, the dependency tree now
shows what it takes to learn it: the plans or pattern as a child item (since
0.10.0) or, for a trainer recipe, a **train step** with the trainer recorded
for it. Not yet verified in game.

### Added
- **Train step nodes** (`node.step = { kind = "train", spellID, name,
  professionName, rank, trainer, who }`): the resolver adds one under a craft
  whose recipe is unlearned, not a combine and not taught by an item. A step
  is not an item: it claims no inventory, has no options, route `train`,
  always 1 missing; it counts as a dependency in the summary and appears in
  `missingLeaves` with `step` and `name` instead of an `itemID`.
- **Dependency Tree**: the step row reads "Train - Georgio Bolero (Stormwind
  City)" with "needs Tailoring 75" and the training cost in the cost column
  (book icon, badge Train); the side panel shows where to train and the
  cost. Without a recorded trainer: "Train - Tailoring trainer" and
  "trainer requirement not recorded yet".
- **Shopping list**: new category **Recipes to learn** ("To learn" tab)
  holding train steps (row key `train:<spellID>`, cost = training cost, so
  it joins the total and the affordability verdict) and the plans items.
  Chat line "Train Bolt of Woolen Cloth - Train - Georgio Bolero (Stormwind
  City) - 5s". The tick marks a step done.
- **CraftWise**: a train step costs what the trainer charges in the craft and
  hybrid strategies, never in buy; it shows as "Train: <recipe>" with choice
  Train, and is unpriced until a trainer has been visited.
- **Dashboard**: the next step can be "Train <recipe>" (badge Train) with the
  trainer and zone; steps are never listed as missing materials.

### Tests
- `trainer_provider_spec` gains a test for the step before and after a
  trainer visit across the resolver, shopping list, overview, CraftWise and
  the Shopping screen. 202 tests pass.

## 0.10.1 (2026-10-18) - trainer recorder

Closes the one gap in the recipe catalogue: the skill a trainer requires for
a recipe is server data the client never stores, so it is now recorded from
trainer windows. Not yet verified in game.

### Added
- **`Providers/TrainerProvider.lua`**: whenever a profession trainer window
  opens, every recipe on offer (available, too advanced and already known;
  the type filters are switched on for the visit and put back on close) is
  written to `ForeverPathDB.trainers[spellID]` with the required skill and
  rank, cost, the trainer's name, zone and subzone; `ForeverPathDB.trainerNPCs`
  lists the trainers seen. Lines are identified by their spell link, or by
  recipe name against the catalogue when the link function is missing.
  Class trainers are skipped; when the client cannot say what kind of
  trainer it is, only profession skills are kept.
- **Catalogue integration**: `Data/Recipes.Get` applies the recorded rank to
  `skill.min` (`skill.source = "trainer"`) and attaches `recipe.trainer`, so
  the crafter check reads "needs Tailoring 75; Thandrel has 50", the plan
  message says "trainer Georgio Bolero, Stormwind City, needs 75", and
  `/fp recipe` prints the trainer and zone. Decoded recipes are invalidated
  when new trainer data arrives. `Recipes.SpellIDByName` for name matching.
- `/fp trainers` (trainers seen, recipes each, when); the trainer status line
  in `/fp catalogue` and `/fp status`; "Trainer window API" in the capability
  list; `TRAINER_SHOW` / `TRAINER_UPDATE` / `TRAINER_CLOSED` registered with
  pcall like every other event.

### Tests
- `trainer_provider_spec` (3 tests): recording with filters, requirement
  lookup and persistence, catalogue and planner integration, class trainers,
  missing API functions, name fallback, repeat visits, unknown trainer kinds.
  Mock: `Mock.OpenTrainer` / `Mock.CloseTrainer`. 201 tests pass.

## 0.10.0 (2026-10-18) - recipe catalogue from the client database

The addon now knows how every item in the game is made, from the client's own
tables, so a goal such as Sulfuras, Hand of Ragnaros is laid out all the way
down (combine the Eye of Sulfuras with a Sulfuron Hammer; the hammer is
Blacksmithing 300 taught by plans; its ingots, bars and cores below that)
before anyone on the account has learned a recipe. Not yet verified in game.

### Added
- **`tools/DbExtract`** (.NET 7) and **`scripts\extract_db.ps1`**: read the
  recipe tables straight out of the installed Forever client (CASC store plus
  the hotfix cache) and generate `ForeverPath/Data/RecipeCatalogue.lua`:
  2,336 profession recipes, 292 item-use combines, 4,687 item names with
  quality and binding, 14 skill lines, for build 1.60.1.70450. Tables used,
  the CascLib patch and the regeneration steps are in
  `tools/DbExtract/README.md`.
- **`Data/Recipes.lua`** decodes the catalogue into `RecipeModel` recipes
  (`Lookup`, `Get`, `GetCombine`, `IsCraftable`, `ItemName` / `ItemQuality` /
  `ItemBind` / `IsSoulbound`, `ProfessionName`, `Status`, `Lines`). A combine
  is a recipe with `combine = true`, profession "Combine", and `tools` for a
  use item that is not spent.
- **Full pathway for unlearned recipes.** `Planner.Candidates` merges
  recorded and catalogue recipes. The resolver qualifies an unlearned recipe
  through `CharacterProvider.WithProfession`: a character with the profession
  at the required skill makes it a `learn` route (ranked just above the
  Auction House) with the plans or pattern added as a child requirement
  (`node.learn`); a combine is a `combine` route anyone can take (ranked with
  alt crafting, a `node.tool` child for an unspent use item); when nobody can
  craft it the option is marked unavailable with the reason ("no Blacksmithing
  on this account", "needs Blacksmithing 300; Mira has 250") and the craft is
  still laid out when the item is soulbound and nothing else exists.
- **Soulbound awareness.** Items that bind when picked up (or quest items)
  lose the Auction House, alt and alt-craft routes; a soulbound item with no
  known source is `noRoute` ("No route (soulbound)"), listed with drops on the
  shopping list, and CraftWise never prices it as a purchase.
- **Goal typing from the catalogue.** `/fp add` and the header search make a
  crafting goal when the catalogue (or a recorded profession) has a recipe,
  otherwise an obtain goal; the "nothing scanned yet, assume crafting" rule
  only applies without the catalogue.
- **Item names before the client has them.** Item names, quality and name
  search fall back to the catalogue, so "/fp add sulfuras, hand" works on a
  fresh client.
- `/fp recipe <item>` (how an item is made) and `/fp catalogue` (build and
  counts); `/fp status` ends with the catalogue line.
- Crafting hero chips: "Combine - anyone can", "<alt> can learn it",
  "Recipe not learned - <reason>", "Needs <profession> <skill>". Dependency
  tree: "Craft - Blacksmithing (Thandrel, needs plans)", "Combine", option
  cards with who can learn the recipe. Shopping list rows: "Recipe: teaches
  <name>", "Tool for <name>", "Soulbound", "Craft - <profession> (no crafter)".
  Dashboard next steps: "Combine 1 x Sulfuras", "Get Plans: Sulfuron Hammer"
  (badge Recipe).

### Changed
- An unlearned recipe is no longer a dead end (`RECIPE_NOT_LEARNED`): the
  goal is planned as an item to get with the craft shown as information
  (`view.recipeStatus = "unlearned"`), and as the route when someone can learn
  it. The message names the crafter, the plans, or why nobody can craft it.
- `SourceProvider.GatherersFor` is now `CharacterProvider.WithProfession`.
- TOC loads `Data\RecipeCatalogue.lua` before `Data\Recipes.lua`.

### Tests
- `catalogue_spec` (10 tests) reads the generated data: Sulfuron Hammer
  300/325/350 with its seven reagents and plans, the Sulfuras combine, lookup
  by item, binding, names and search, resolver learn / unavailable /
  soulbound / combine routes, and the full Sulfuras plan through
  `Planner.Evaluate` with and without a blacksmith on the account. 198 tests
  pass.

## 0.9.0 (2026-10-18) - attunement goals

Phase 5a: the first non-crafting goal type. Not yet verified in game.

### Added
- **Attunement goals** (`COMPLETE_ATTUNEMENT`, badge "Attunement") built on
  the Attune addon's chain data (`Providers/AttuneProvider.lua`, read-only):
  attunements for your faction, raids first; every step with its type,
  name (quest names from Attune's locale table, NPCs from its table, items
  from the client), location, group size and level requirement.
- **Progress from the client**: quests from the completion flags and the
  quest log, levels from your level, items from your bags (and counted
  bank); kills, interactions and uses from Attune's own survey of your
  character; and any step is done once a later step is. The "next" step
  is the first open main-line step (side quests after it).
- **Attunements screen** (nav, no longer a preview): picker for your
  faction's attunements, header with progress, the step timeline (done /
  current / locked nodes, side quests, "in your log"), and the current
  step panel (type, location, group size, level, what to do, what else is
  open). "+ Add goal" turns it into a goal; the selected goal's attunement
  opens automatically.
- My Goals: the Attunement segment adds by name. `/fp attunements` lists
  them with progress, `/fp attune <name>` adds one. Dashboard rows show
  "Next: Quest: Jail Break! - Blackrock Depths" and "6 of 11 steps";
  Recommended Next shows the step with its type as the badge; the tracker
  shows the percentage and the next step; opening the goal lands on the
  Attunements screen.
- Attunement goals auto-complete when the chain's end is reached (checked
  after quest turn-ins, quest log changes and level-ups) with an
  "Attunement complete" toast.

## 0.8.2 (2026-10-18) - can I afford it?

### Added
- Shopping list summary cell **"Can I afford it?"**: Yes / With alts' gold /
  No, with the remaining priced cost against the gold you carry
  (`GetMoney`) and the account total (every alt's snapshotted gold). Rows
  marked bought no longer count. Each priced row is marked `+` (fits in
  your gold), `~` (an alt's gold covers it) or `!` (nobody can pay), with
  the reason in the tooltip. "Send to chat" prints a Cost line with the
  verdict. The Crafting footer's "Buy all missing" says affordable / short.
- `ShoppingList.Affordable`, `AffordabilityText`, `cost.bought`,
  `cost.remaining`, `CharacterProvider.AccountGold`.

## 0.8.1 (2026-10-18) - goals complete themselves

### Added
- **Auto-complete.** A crafting goal completes as soon as your bags (and
  counted bank) have gained its quantity since the goal was added: the count
  at creation is stored as `target.baseline` and the best gain as
  `target.peak`, so crafting two bolts and using them straight away still
  completes "Craft 2x Bolt". Obtain goals complete when you hold the
  quantity. Reopening a completed goal starts counting again; goals saved
  by older versions get their baseline on the first check, so an upgrade
  never completes anything by itself.
- **Celebration toast.** A gold-bordered toast drops in at the top of the
  screen ("GOAL COMPLETE - Bolt of Linen Cloth - Crafted 2x ... - 3 goals
  done"), holds six seconds and fades; toasts queue. Click it to open My
  Goals. The level-up fanfare plays and a chat line is printed.
- `/fp celebrate on|off` (toast + sound), `/fp celebrate test`,
  `/fp celebrate auto on|off` (auto-complete). Settings are account-wide.

## 0.8.0 (2026-10-18) - Auction House prices and CraftWise

Phase 4. Prices from Auctionator's scans feed every cost in the addon, and
CraftWise compares buying, crafting and a hybrid per component. Not yet
verified in game.

### Added
- `Providers/AuctionPriceProvider.lua`: reads Auctionator's public v1 API
  (lowest buyout seen, days since seen) plus its 7-day mean and last
  listing count behind pcall, dated by the account's last browse scan.
  Nothing is written to Auctionator; without it the source stays silent.
- `PriceProvider` now returns the cheapest of all sources (vendor record or
  Auction House) with the others as `alternatives`, `GetMarket` for the AH
  price alone, `Freshness` (fresh under 3 h, aging under 24 h, stale after,
  vendor = fixed), `Status` for the status bar and `Describe` for chat.
- `Domain/CraftWise.lua`: pure comparison over the goal's full dependency
  tree. Three strategies: buy the finished item, craft everything (buy every
  raw material), hybrid (per component the cheaper of buying or crafting,
  owned stock and alt holdings free). Unknown prices stay unknown and are
  counted ("+2 unpriced"), never priced at zero. Produces the breakdown rows,
  the route plan (`buy` overrides where buying beats crafting), presets
  (`Mode`: default / hybrid / buy all / custom) and the recommendation.
- Crafting > CraftWise tab (`UI/Screens/CraftWise.lua`): cached-scan badge
  and age, three strategy cards with RECOMMENDED on the cheapest, "Use this
  plan" (writes the route overrides; the tree, shopping list and tracker
  follow), and the Component / Buy (AH) / Craft path / Hybrid / Choice /
  Price data table with freshness dots.
- Requirements footer: "CraftWise route: 31g 62s" and a working "Open
  CraftWise" button. Dependency Tree: Est. cost column and option cards show
  real prices. Dashboard CraftWise panel: total, "Hybrid plan - saves X",
  the three strategy rows, scan freshness, Compare opens the tab. My Goals
  route dropdown: Default routes / CraftWise hybrid / Buy all materials.
- Status bar: "AH prices: cached scan - 2h ago" (or not installed / no scan
  yet). `/fp prices [item]` prints the price status or every known price
  for an item. Shopping list and requirements totals now mix vendor and AH
  prices.
- The planner keeps `view.fullTree` (no route overrides, private ledger)
  whenever a goal has overrides, so CraftWise can still compare a subtree
  the plan buys.

### Fixed
- Shopping list "Estimated total" used the coin-texture money string at
  20 px, which overlapped the "vendor and AH prices" line; it now uses the
  compact "1g 50s" form like every other summary, and the summary strip is
  76 px tall like the Dashboard's so value and sub line no longer collide.

## 0.7.0 (2026-10-18) - obtain goals and dungeon loot

Items that are not crafted (boss drops, quest rewards, vendor stock) now get
a plan instead of "No known recipe". Not yet verified in game.

### Added
- **Obtain item goals** (`OBTAIN_ITEM`, badge "Item"). `/fp add`, the
  search box and the My Goals form pick the type: crafting when a recipe is
  recorded for the item, obtain otherwise (before any profession scan every
  goal stays a crafting goal and the planner still asks for a scan).
  `/fp obtain <item> [qty]` forces an obtain goal, switching an existing
  crafting goal for the item.
- The planner routes obtain goals, and crafting goals with no recipe but at
  least one known source, through `Planner.EvaluateObtain`: the dependency
  tree's root is the item itself, claims inventory like any other node, and
  takes the best source as its route (vendor, alt, gathering, drop, quest,
  Auction House). An obtain goal for a craftable item with a learned recipe
  expands into the craft of the shortfall only.
- Crafting screen for such goals: chips "Obtain" + the source ("Dropped by
  Lord Cobrahn"), "N of M in your bags - <source>", the item as the single
  requirements row with its source tag; Dependency Tree root with Have /
  Status and the sources as option cards (AH as the alternative route).
  Dashboard rows show the source and an "Item" badge; next steps say "Obtain
  N x <item>" with a Drop / Quest / Vendor badge or "N x <item> on hand";
  the tracker and shopping list follow.
- **ForeverDungeonJournal bridge** (`SourceProvider`): when that addon is
  installed its boss loot, trash drops, shared loot and dungeon quest rewards
  are indexed once per session from its namespace (read-only). Hints read
  "Dropped by Kresh - Wailing Caverns (DungeonJournal)" and "Quest reward:
  Leaders of the Fang - Wailing Caverns - choose on turn-in
  (DungeonJournal)". AtlasLoot entries for a boss the journal already lists
  are folded in; the journal comes first because its data is Forever
  specific. New route kind `quest` (ranked after drops, before the AH; shown
  under "Gathering / drops" in the shopping list).
- `/fp vendors` reports the DungeonJournal state next to AtlasLoot.
- Gathering hints (Skinning, Mining, Herbalism, Disenchanting) are only a
  route when this character or a snapshotted alt has the skill. The hint
  then says who ("Skin beasts - Miravelle has Skinning (90)", next-step
  badge "Gather - Miravelle", requirements tag "Skinning - Miravelle");
  otherwise it is marked unavailable, stays visible as information ("no
  character has Skinning", tree card "no gatherer") and the route falls
  back to drops, quests or the Auction House.

### Changed
- `RECIPE_NOT_FOUND` only remains when no recipe *and* no source is known;
  its message says so and points at `/fp sources`.
- `DependencyResolver.Resolve` accepts `{ itemID, quantity }` for obtain
  trees (`tree.obtain`, `node.claims`); crafting trees are unchanged.
- `GoalStore:SetType` / `GoalService.SetType` switch between item goal
  types; `GoalService.AddItemGoal` updates an existing goal for the item
  whatever its type.

## 0.6.0 (2026-10-18) - item sources from the client

Phase 3b: where materials come from, without any external service. Not yet
verified in game.

### Added
- `Providers/VendorProvider.lua`: every merchant window you open is recorded
  into the account database (NPC, zone, subzone, unit price, stack, limited
  stock, item-cost flag). Vendors become resolver hints ("Buy from Tharynn
  Bouden - Elwynn Forest (Goldshire) - 10c each") and the first real price
  source: `PriceProvider` now answers with the cheapest recorded vendor.
- `Data/ItemClasses.lua` + `Providers/SourceProvider.lua`: item class
  heuristics from the client's own item data. Herbs are picked, ore and gems
  are mined, leather is skinned, cloth drops from humanoids, meat from beasts,
  elemental reagents from elementals, enchanting materials from
  disenchanting. The hint is dropped once a recipe producing the item is
  recorded.
- AtlasLootClassic bridge: when AtlasLoot is installed, its Dungeons and
  Raids module is loaded on demand and indexed once per session, so instance
  loot shows "Dropped by <boss> - <instance> (AtlasLoot)". Nothing is copied;
  without AtlasLoot the bridge is inert.
- Default route ranking in the resolver: vendor, then alt, alt crafts,
  gathering, drops, then the Auction House.
- Est. cost is real where a vendor price is known: shopping list rows and
  the Estimated total ("vendor prices only - N items unpriced"), the
  requirements table's Unit price / Subtotal and "Buy all missing",
  tooltips. Source tags "Vendor: <npc>", "Mining", "Humanoid drops" in the
  requirements table; Vendors and "Gathering / drops" tabs in the shopping
  list fill up.
- `/fp sources <item>` prints everything known about an item's sources and
  price; `/fp vendors` reports how much vendor data exists and whether the
  AtlasLoot index is ready.

### Known limits
- Vendor data only exists for merchants you (any of your characters) have
  opened since 0.6.0. World drops from ordinary mobs and quest rewards stay
  unknown unless AtlasLoot lists them.
- Class heuristics are hints by item type, not NPC lists.

## 0.5.0 (2026-10-18) - shopping list

Phase 3 of the roadmap. Not yet verified in game.

### Added
- `Domain/ShoppingList.lua`: one row per item across the goals on the list,
  built from every node of their dependency trees. Total = units the goals
  need, Owned = units physically there for the row (capped at Total),
  Reserved = the part of Owned held by goals that are not on the list (paused
  or unticked), Missing = Total minus the usable part. Rows are classified
  Auction House / Vendors / Gathering / Craftable / From alts from the
  resolver's route, carry source tags and the goals that need them, and sort
  by missing, name, total or source. A mail plan says how much of each
  missing item each alt can send.
- Shopping List screen (handoff screen 05) in the sidebar: goal chips (active
  and queued goals on by default, paused off; the choice is remembered per
  character), "Send to chat" (prints to your own chat frame with item links,
  no whispers), a summary strip (estimated total: no price data yet; Auction
  House / Vendor item counts; materials in hand with a bar), a "can mail"
  strip when alts hold something, filter tabs with counts, sort dropdown, the
  eight-column table with a bought checkbox per row (dims and sinks the row),
  the Reserved footnote and "Clear bought".
- Links into it: Dashboard "Open shopping list >", Crafting footer "Add to
  shopping list" (ticks the goal's chip and opens the list), Characters
  "Plan mail", `/fp shopping`.

### Changed
- Per-character `shopping` settings (bought, included, sort, filter) are
  filled in by defaults; no schema bump.

### Known limits
- Vendor and gathering categories stay empty until a source data file exists;
  everything without a recipe or an alt is "Auction House".
- Prices are still "?" (phase 4).

## 0.4.0 (2026-10-17) - account-wide characters

Phase 2 of the roadmap. Not yet verified in game.

### Added
- `Providers/CharacterProvider.lua`: every character writes a snapshot into
  the account database (`ForeverPathDB.characters["Name-Realm"]`): level,
  class, race, gold, professions, learned recipes, bag and bank contents and
  open goals. Snapshots refresh on login, on logout and (debounced) when bags,
  goals or recipes change. Freshness is live (this character), snapshot
  (under 24 h) or cached.
- Characters screen (handoff screen 07) replaces the preview module: a banner
  naming the alt that already holds the most of what your active goals need,
  a scope switch [This character | Account-wide], a freshness legend and one
  card per character with professions, the relevant materials it holds (gold
  outlined), its goals, what it can craft for your goals, a "log in to
  refresh" note for cached alts and a Forget button.
- "Include alts' bags" (Crafting tab checkbox, the Characters scope switch,
  `/fp alts`) sets `settings.includeAlts`. When on, alts' snapshotted bags and
  bank count as owned, drawn after your own bags and bank in the allocation
  ledger; the inventory note and tooltips say so.
- Alt hints in the dependency tree even when alts are not counted: "Alt:
  Miravelle" in Get via, option cards "Mail from Miravelle (has 6)" and
  "Craft on Thandrel (Tailoring 50)", and requirements-table tags "Alt: Name
  (n)" / "Craft - Alt: Name". Recommended Next phrases them as "Get 6 x Ore
  from Miravelle" or "Have Thandrel craft 2 x Bolt".
- `/fp characters` lists the snapshots.

### Changed
- `InventoryProvider.GetCounts` now carries `alts` and `altSources`;
  `Allocation` and `CraftingEngine` understand an alts bucket behind the
  `includeAlts` flag. No schema bump: `characters` and `includeAlts` are
  filled in by defaults.
- Sidebar: Characters moved out of "Preview modules" into the main group.

### Fixed (0.4.1, same day, from the first in-game session)
- Alt cards showed "No professions recorded": the login snapshot ran before
  the client's profession list was populated and the logout snapshot could
  overwrite a good list with an empty one. Snapshots now also run on
  `SKILL_LINES_CHANGED` and 8 s after entering the world, merge the client
  list with professions recorded from their windows, and never replace a
  non-empty list with an empty one. `/fp snapshot` saves one on demand and
  prints what was captured and where the professions came from.

- Character cards listed only two professions, sorted by name, so a primary
  profession could drop off once Cooking was known. Cards now list every
  profession (up to six), primaries first in the client's slot order, and the
  card grows to fit; "(recorded)" marks ones known only from a window scan.

### Known limits
- Snapshots are taken by the addon, so a character you have not logged in on
  since installing 0.4.0 does not appear.
- "Plan mail" is a placeholder until the shopping list (phase 3).

## 0.3.0 (2026-10-17) - recursive dependency tree

Phase 1 of the post-handoff roadmap. Not yet verified in game.

### Added
- `Domain/DependencyResolver.lua`: a crafting goal is resolved into a tree.
  Each reagent becomes a node with units needed, what the inventory covers and
  what is missing; a missing reagent with a learned recipe is expanded into its
  own reagents (Linen Bag -> Bolt of Linen Cloth -> Linen Cloth). Crafts use
  the guaranteed minimum yield. Cycles (A needs B needs A) and a depth limit
  of 6 stop expansion and are reported on the node. Static recipe hints and
  future source hints plug in through `findRecipes` / `sources`.
- `Domain/Allocation.lua`: an inventory ledger. Goals are evaluated in
  priority order and claim stacks as they go (bags before bank), so one stack
  of cloth is never counted as owned by two goals or by two branches of one
  tree. The requirements table and tooltips show how much was reserved by
  higher-priority goals.
- Per-goal route overrides: `goal.routes[itemID] = "craft" | "buy"`
  (`GoalService.SetRoute`). Unlearned recipes are offered but not expanded
  unless the player forces the crafting route.
- Crafting screen, Dependency Tree tab (handoff screen 03): toolbar with
  Expand all / Collapse all, Show [All | Unresolved only] and a legend; tree
  panel with guide lines, chevrons, Have / Status / Get via / Est. cost
  columns and a footer with "N of M dependencies resolved"; Selected Node
  panel with the have/need count, option cards (crafting route marked BEST
  when the recipe is known), "Also used by" other goals, Use crafting/buying
  route, Default route and Link buttons.
- Dashboard: Missing Materials now lists the raw materials to obtain (tree
  leaves) instead of intermediates you will craft; Recommended Next suggests
  the first intermediate whose reagents are all on hand ("Craft 3 x Bolt of
  Linen Cloth") before falling back to the biggest gap.
- `/fp tree [n]` prints a goal's dependency tree to chat.

### Changed
- `Planner.Evaluate` builds the tree first and derives the flat requirements
  plan from the tree's depth-1 allocation, so both views always agree.
- Planner views carry `tree` and plan materials carry `reserved`.
- Goal validation accepts the optional `routes` table (no schema bump; the
  field is optional and absent on existing goals).

### Known limits
- Prices are still unknown everywhere ("?" / "no price data"); CraftWise is
  phase 4.
- Alternative reagents (multi-quality slots) are allocated by their first
  candidate only.
- The Selected Node panel does not scroll; at the minimum window height the
  third option card can sit close to the buttons.

## 0.2.1 (2026-10-17) - header and hover fixes

First in-game feedback on the 0.2.0 UI.

### Fixed
- Header: the divider and character block were anchored to the right edge of
  the title, but in the client fonts the caps tagline is wider, so "Level N
  Class - Realm" was drawn over the tagline. The divider now sits after the
  wider of the two (`MainFrame.LayoutBrand`, re-run on every refresh), and the
  character lines truncate before the active-goal pill instead of running
  under it.
- Goal switcher and search suggestions: hovering a row blanked it. The hover
  colour was an opaque texture on the HIGHLIGHT draw layer, which renders
  above text. Rows now use `Widgets.HoverFill`, a BACKGROUND-layer fill
  toggled by OnEnter/OnLeave.
- Dashboard character strip: the Goals cell ("2 active - 0 done" at 20 px)
  overhung the window edge. Stat values are now bounded by their cell; the
  Goals cell shows "N active" with "M done - last ..." on the sub line, and
  the gold cell drops to a compact "12g 34s" when the coin-icon string does
  not fit.

## 0.2.0 (2026-10-17) - design handoff UI

UI rebuilt on the ForeverPath design handoff (`design/handoff/`). Not yet
verified in game; the 0.1.0 data layer underneath is unchanged apart from the
goal fields listed below.

### Added
- Design system: `UI/Theme.lua` holds the handoff's colour tokens, gradients,
  quality colours and font roles; `UI/Widgets.lua` implements the component
  sheet (panels, default/primary/close buttons, tabs, segments, badges, tags,
  chips, counters, progress bars with ticks, checkboxes, dropdown + popup
  menu, search field, stepper, item icon with quality ring, scroll area,
  empty states).
- App shell (1000x700, min 820x560, max 1400x960): 46 px header with emblem,
  title and tagline, character name in class colour, active-goal pill with a
  goal switcher, type-ahead search that accepts Shift-clicked links, settings
  menu and close; 142 px sidebar with Dashboard, My Goals, Crafting and the
  five preview modules; 24 px status bar with bag/bank and recipe freshness
  dots, an alert slot, the version and a resize grip. Window position and the
  last screen are saved per character.
- Dashboard screen: character strip (portrait, professions with bars, gold,
  goal counts), Active Goals rows with progress and missing summary,
  Recommended Next steps, Missing Materials aggregated across active goals,
  CraftWise placeholder.
- My Goals screen: new-goal bar (input, type segment, quantity, Add goal),
  Open/Completed tabs, sort menu, grouped rows (Active / Queued / Paused) with
  priority number, progress bar, tracked checkbox, and a Goal Settings panel
  (quantity, priority, status, show in tracker, mark complete / reopen,
  delete).
- Crafting screen: breadcrumb, hero panel (64 px icon, item meta line,
  profession/recipe/yield chips, quantity stepper, completion percentage and
  bar), Requirements / Dependency Tree / CraftWise / Notes tabs, sort menu,
  requirements table with Need / Have / Missing / Unit price / Subtotal /
  Source columns, row tints, source tags, footer with price placeholders.
- Compact goal tracker: separate 262 px frame, draggable, pages through
  tracked goals, collapses to one line, shows up to six requirement counters
  and the next step. `/fp tracker` and the settings menu toggle it.
- Goals gained `status` values QUEUED and COMPLETED, `tracked` and
  `priority`; schema version 2 with migrations (window layout moved to the
  character table, existing goals get tracking fields).
- Commands: `/fp complete|pause|resume <n>`, `/fp tracker`, `/fp open <screen>`.
- Domain: `Overview.Build` (missing-material aggregation and next steps),
  `Planner.Progress`, `Planner.EvaluateAll`.
- Tests: 111 (overview spec, migration spec, goal status/priority specs,
  rewritten UI spec covering the shell, three screens and the tracker).

### Not included (shown as "later version" states)
- Dependency tree, CraftWise comparison, shopping list, notes, alt inventories,
  prices, reserved materials, drag-to-reorder, Equipment / Quests /
  Reputations / Attunements / Characters modules.
- Bundled Marcellus / Alegreya Sans fonts; the client fonts FRIZQT__ and ARIALN
  are used via the handoff's fallback mapping (`Theme.FontFiles`).

## 0.1.0 (2026-10-17) - first milestone

Verified in game on WoW: Forever build 1.60.1.70450 (TESTING.md checklist,
no Lua errors). Bank counting and multi-output recipes remain offline-tested
only.

### Fixed
- Scroll bars on the goal list and material table are hidden while the
  content fits.

### Added
- Addon skeleton for WoW: Forever (`## Interface: 16001`, `ForeverPath.toc`
  plus identical `ForeverPath_Camelot.toc`), namespace, logging with error
  capture, client compatibility layer, event bus with debounce and combat
  deferral, versioned SavedVariables with migration runner.
- Slash commands: `/fp`, `/foreverpath`, `help`, `add`, `goals`, `select`,
  `remove`, `scan`, `status`, `debug`, `errors`, `reset window`.
- Main window: movable, resizable, position and size saved; section
  navigation (crafting active, other sections disabled); goal list; goal
  details with quantity controls; material table with Required / Owned /
  Missing; status line; Escape closes.
- Generic goal model with seven registered types; CRAFT_ITEM fully supported.
  Goals persist per character and are validated on load.
- Item input by ID, item link, Shift-click (hooks `ChatFrameUtil.InsertLink` /
  `ChatEdit_InsertLink`) and name search over cached names and recorded
  recipes. Async item data loading via `RequestLoadItemDataByID`.
- Profession provider: records recipes from open profession windows through
  `C_TradeSkillUI` (chunked), caches normalized recipes account-wide, learned
  flags per character, live schematic refresh, `/fp scan` opens unrecorded
  professions.
- Inventory provider: event-driven bag index, bank snapshot while the bank is
  open, client-reported bank fallback, live/cached/unknown labelling.
- Crafting engine: crafts needed (minimum yield for multi-output recipes),
  reagent requirements, missing = max(0, required - owned).
- Planner producing distinct statuses: ready, unsupported goal, invalid item,
  item unavailable, API unavailable, recipes not scanned, no known recipe,
  recipe not learned, recipe data invalid.
- Pricing provider boundary (no price source; unknown prices are nil).
- Offline test suite running on Lua 5.1 through `lupa`, with a mock of the
  Forever API surface. Documentation: README, ARCHITECTURE,
  API_COMPATIBILITY, TESTING.
