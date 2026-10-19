# ForeverPath

Goal-driven progression planner for **World of Warcraft: Forever**.

Pick something you want to craft. ForeverPath works out which recipe makes it,
how many crafts you need, which reagents that takes, how many you already own
in your bags and bank, and what is still missing.

It plans crafting goals, items to obtain (boss drops, quest rewards, vendor
stock) and raid attunements, across every character on the account: a
recursive dependency tree with route choices per node, a shopping list with
Auction House and vendor prices, a buy-versus-craft comparison, trainer and
vendor recorders, and a recipe catalogue generated from the client's own
database. Quests, reputations and equipment goals are next; the architecture
is built to take them without a rewrite (see `ARCHITECTURE.md`).

## Status

| Area | State |
|---|---|
| Loads on WoW: Forever (interface 16001) | Verified in game on 0.1.0, build 1.60.1.70450 |
| Crafting data: recipes from profession windows, bag counts, missing calculation | Verified in game on 0.1.0 |
| Bank counts | Verified in game by the author (2026-10-18) |
| 0.2.x shell, Dashboard, My Goals, Crafting screens, tracker | Verified in game by the author (2026-10-18) (header overlap and hover blanking fixed in 0.2.1) |
| Multi-output recipes | Implemented, offline-tested; not exercised with a multi-output recipe in game yet |
| 0.3.0 recursive dependency tree, allocation across goals, route overrides | Verified in game by the author (2026-10-18) |
| 0.4.0 account-wide character snapshots, Characters screen, include alts' bags | Verified in game by the author (2026-10-18) (profession capture fixed in 0.4.1) |
| 0.5.0 shopping list across goals, bought ticks, send to chat, mail plan | Verified in game by the author (2026-10-18) |
| 0.6.0 item sources: vendor recorder, item-class heuristics, AtlasLoot bridge, vendor prices | Verified in game by the author (2026-10-18) |
| 0.7.0 obtain-item goals (drops, quests, vendors planned instead of "No known recipe"), ForeverDungeonJournal bridge | Verified in game by the author (2026-10-18) |
| 0.8.0 Auction House prices via Auctionator, CraftWise buy / craft / hybrid comparison, route presets | Verified in game by the author (2026-10-18) |
| 0.8.1 goals auto-complete when the item lands in your bags; celebration toast, sound, chat line | Verified in game by the author (2026-10-18) |
| 0.8.2 affordability: shopping list and footer compare the remaining cost with your gold and the account's | Verified in game by the author (2026-10-18) |
| 0.9.0 attunement goals and the Attunements screen (Attune addon data, progress from quest flags, log, level, bags) | Verified in game by the author (2026-10-18) |
| 0.10.0 recipe catalogue generated from the client's own database (every profession recipe and item-use combine, skill ranks, plans, soulbound flags); full pathway for unlearned recipes, "learn" and "combine" routes | Verified in game by the author (2026-10-18) |
| 0.10.1 trainer recorder: required skill, cost and location of trainer-taught recipes, recorded from trainer windows into the catalogue | Verified in game by the author (2026-10-18) |
| 0.10.2 unlearned recipes in the tree: the plans as an item to get, or a "train it" step with the trainer, zone and cost; "Recipes to learn" on the shopping list | Verified in game by the author (2026-10-18) |
| 0.10.3 gathering materials (leather tiers, essences) are planned as their own items; refining from the tier below is an opt-in route per node | Verified in game by the author (2026-10-18) |
| 0.10.4 the ForeverPath mark as addon icon, window header and tracker emblem (`Media/ForeverPath-Mark.png`) | Verified in game by the author (2026-10-18) |
| 0.10.5 optional dependencies declared, MIT licence file | Housekeeping |
| 0.11.0 learn-recipe goals (the pattern to get or the trainer to visit, blockers, auto-complete on learning) and reach-skill goals (which recipes to craft how many times from your skill to the target, their materials, auto-complete on the skill-up) | Implemented, offline-tested against the catalogue, **not yet verified in game** |
| 0.12.0 quest goals and the Quests screen (dungeon quests from ForeverDungeonJournal with their chains, attunement quests from Attune, your quest log; by zone / by goal / completed; objectives, rewards, which goals a quest feeds; auto-complete on turn-in) | Implemented, offline-tested, **not yet verified in game** |
| 0.13.0 Equipment screen (every slot, item levels and stats from the client, GearQuest Forever's best pick per slot for your class, spec, faction and level, stat comparison, targets as goals; GearQuest's gear sources feed obtain goals) | Implemented, offline-tested, **not yet verified in game** |
| 0.14.0 reputation goals and the Reputations screen (standings from the client, quests that give reputation from ForeverDungeonJournal, rewards per standing from AtlasLoot Factions, reputation vendors on item goals, auto-complete on the standing) | Implemented, offline-tested, **not yet verified in game** |
| 0.15.0 enchant goals (enchants and tinkers in the catalogue, Shift-click from the Enchanting window, formula or trainer plus reagents per cast, auto-complete as you cast; Enchanting skill goals plan enchants) | Implemented, offline-tested, **not yet verified in game** |
| 0.15.1 quests that give reputation feed the Quests screen for reputation goals | Implemented, offline-tested, **not yet verified in game** |
| 0.16.0 type-ahead suggestions for every goal kind (New Goal bar and header search); reputation goals for factions not met yet, from the client's faction table; the New Goal bar reflows when narrow | Implemented, offline-tested, **not yet verified in game** |
| 0.16.1 Shift-click any item row to link it in chat or the Auction House search | Implemented, offline-tested, **not yet verified in game** |
| 0.20.0 the loot learner (what you loot on Forever is recorded account-wide and listed before every database), every searchable item named from the client (11,094), "New in Forever" for items classic data does not know | Implemented, offline-tested, **not yet verified in game** |
| 0.19.0 classic drops (with chances), world drops, gathering nodes, skinning, fishing, containers, vendors with prices and trainers with required skill and cost, all behind recorded Forever data | Implemented, offline-tested, **not yet verified in game** |
| 0.18.0 classic-era data from CMaNGOS classic-db (the ForeverPath_ClassicDB addon): every classic quest with its giver, turn-in and map position, the items and kills it asks for, rewards, reputation and prerequisite chains, behind everything Forever-specific; ForeverPath is now GPL-3.0 | Implemented, offline-tested, **not yet verified in game** |
| 0.17.3 click any step on the Attunements screen for its summary (state, giver, turn-in, items to bring with bag counts, rewards, waypoint, jump to the Quests screen) | Implemented, offline-tested, **not yet verified in game** |
| 0.17.1 the shaman Call of Air chain (both factions) shipped in the quest catalogue: givers, turn-ins, map positions, the items each quest asks for and where they drop | Implemented, offline-tested, **not yet verified in game** |
| 0.17.0 questlines: a quest reward or a quest plans the whole chain that leads to it (Attune's attunement and class-quest chains), the items the chain's quests ask for go on the requirement rows, the tree and the shopping list, and quest givers, turn-ins and map pins are learned at quest windows (plus a shipped catalogue) with "Set waypoint" buttons | Implemented, offline-tested, **not yet verified in game** |
| 0.16.2 item name search matches anywhere in a name (word starts ranked above inner matches, room kept for them) and knows ForeverDungeonJournal loot and GearQuest gear names | Implemented, offline-tested, **not yet verified in game** |

`TESTING.md` has the in-game checklist for 0.2.0. `API_COMPATIBILITY.md`
lists the API evidence and the remaining open questions.

## Installation

1. Copy both folders from the release zip, `ForeverPath` and
   `ForeverPath_ClassicDB`, into
   `World of Warcraft\_classic_beta_\Interface\AddOns\`.
   `_classic_beta_` is the Forever beta product folder.
   `ForeverPath_ClassicDB` is the classic-era quest and NPC data; ForeverPath
   loads it when it starts (it is load-on-demand, so it does not run on its
   own). Without it everything works except classic quests, givers and
   spawns.
2. Start the game or type `/reload`.
3. Type `/fp`.

Developers: `scripts\install_dev.ps1` copies both folders into the AddOns
directory, and `scripts\package.ps1` builds a release zip.

## Classic-era data

`ForeverPath_ClassicDB` carries the classic-era content of
[CMaNGOS classic-db](https://github.com/cmangos/classic-db): about 4,100
quests with their givers, turn-ins, required items and kills, rewards,
reputation and prerequisites; where items drop (with chances), which herb
and ore nodes, chests, fishing zones and containers give them, who sells
them and for how much, which trainers teach a recipe at what skill and
cost; and the spawn points of every NPC and object involved, placed on the
Forever client's zone maps. Rare drops (under 1%) and world drops are
listed for information but never recommended as a route. It is the
baseline under everything Forever-specific: what ForeverPath learns at quest
windows, the shipped quest catalogue, ForeverDungeonJournal and Attune all
win over it, and `/fp quest` marks classic facts as "(classic data)".
Forever's new content is not in it. Regenerate it with
`scripts\extract_classicdb.ps1` (`tools/ClassicDbExtract/README.md`).

## Companion addons (all optional)

ForeverPath has no required dependencies. When these addons are installed
it reads their data at runtime; without them the matching feature stays off
and says so in the UI.

| Addon | Used for | Without it |
|---|---|---|
| Auctionator | Auction House prices (shopping list, CraftWise, affordability); run a full browse scan so prices exist | Only recorded vendor prices; CraftWise shows "price unknown" |
| AtlasLootClassic (+ DungeonsAndRaids and Factions modules) | Boss and trash loot tables for drop sources; the items each reputation standing unlocks | Drop sources only from ForeverDungeonJournal; no faction rewards |
| ForeverDungeonJournal | Forever-specific boss loot, dungeon quests with their prerequisite chains, quest givers and rewards (quest goals, the Quests screen), quests that give reputation | Drop sources only from AtlasLoot; the Quests screen lists only your log; no quest sources for reputation goals |
| Attune | Attunement goals and the Attunements screen; attunement quests (givers, rewards) on the Quests screen | The Attunements screen explains that Attune is missing |
| GearQuest Forever (+ its class module) | Per-slot upgrade hunts on the Equipment screen (best pick, other options, sources) and gear sources for obtain goals | The Equipment screen shows what is worn and your gear goals, without picks |

## Using ForeverPath

1. **Record your recipes once.** Open each profession window (or type
   `/fp scan`, or use the settings menu in the window header). ForeverPath
   records every recipe the window lists, including ones you have not learned
   yet, and keeps recording whenever a window is open.
2. **Add a goal.** Type an item ID or name in the header search, Shift-click
   an item from your bags, or use the New Goal bar on My Goals (quantity,
   Add goal). Name search knows the catalogue's items plus items you have
   looked at; the client has no searchable item database. The New Goal bar
   also takes a **recipe** to learn ("Bolt of Woolen Cloth"), an
   **enchant** to cast ("Enchant Weapon - Crusader", or Shift-click it in
   the Enchanting window; the stepper sets how many casts), a
   **profession skill** to reach ("Tailoring 225"), a **quest** ("Leaders
   of the Fang"), a **reputation** ("Argent Dawn Exalted") and an attunement.
   After two characters a popup suggests matches for the selected kind
   (items you have seen, that the catalogue names, that drop in a dungeon
   ForeverDungeonJournal covers or that GearQuest Forever lists; recipes,
   enchants, professions, quests, factions including ones you have not met
   yet, attunements); click one to add it. Item matches can be anywhere in
   the name: "storm" finds "Storm Gauntlets", "Mace of the Storms" and
   "Thunderstorm Blade", in that order.
3. **Read the plan.**
   - **Dashboard** shows active goals with progress, the materials missing
     across all of them, and a recommended next step per goal.
   - **Crafting** shows the selected goal: recipe, profession skill, crafts
     needed, completion, and the requirements table (Need / Have / Missing /
     Source). The status chips and table message say exactly why a goal cannot
     be planned: recipes not recorded, no known recipe, recipe not learned,
     API unavailable, invalid item.
   - **My Goals** manages quantity, priority, status (active / queued /
     paused), tracker visibility, completion and deletion.
   - **Quests** lists the quests ForeverPath knows (dungeon quests with
     their chains, attunement quests, your log) by zone or by the goal
     their rewards feed, with objectives, rewards and a button to make one
     a goal.
   - **Equipment** shows every slot with what you wear, GearQuest Forever's
     best pick for it (your class, spec, faction and level), a stat
     comparison and the other options; one click makes a pick a goal.
   - **Reputations** lists your factions with their standing, the quests
     that raise each one and the rewards each standing unlocks; pick a
     target standing and make it a goal.
4. **Tracker.** A compact frame near the minimap pages through tracked goals
   and shows the next step; drag it anywhere, collapse it with "-", open the
   goal with "+". `/fp tracker` hides or shows it.
5. **Shift-click any item row** (shopping list, requirements, tree,
   dashboard, tracker, equipment) to put its link where the game puts
   Shift-clicked links: the chat box, or the Auction House search when the
   Auction House is open (Auctionator's shopping search included).
6. **Bank items** count as owned once you have opened your bank on that
   character; the inventory note says whether the figure is live, a snapshot,
   or unknown.

## Commands

| Command | Effect |
|---|---|
| `/fp`, `/foreverpath` | Open or close the window |
| `/fp help` | List commands |
| `/fp add <item> [qty]` | Add a goal by item ID or link (crafting when a recipe is known, otherwise obtain) |
| `/fp obtain <item> [qty]` | Add an obtain-item goal (boss drop, quest reward, vendor stock) even if a recipe exists |
| `/fp learn <recipe>` | Add a learn-recipe goal by recipe name or spell id: the pattern to get, or the trainer to visit |
| `/fp enchant <enchant> [casts]` | Add an enchant goal by name, spell id or Shift-clicked link: the formula or trainer, the reagents for every cast; completes as you cast it |
| `/fp skill <profession> [rank]` | Add a reach-skill goal (default: the next cap): which recipes to craft, how often, and their materials |
| `/fp quest <name or id>` / `/fp quests` | Add a quest goal (dungeon and attunement quests, or anything in your log): the chain that leads to it, the giver, the turn-in, the items it asks for; list the quests that feed your goals |
| `/fp equipment` | Every slot: what is worn, GearQuest Forever's best pick, and the goal that targets it |
| `/fp rep <faction> [standing]` / `/fp reps` | Add a reputation goal (default: the next standing); list your factions and reputation goals |
| `/fp sources <item>` / `/fp vendors` | Where an item comes from; how much vendor and loot-table data is available |
| `/fp recipe <item>` / `/fp catalogue` | How an item is made (every catalogue recipe and combine, with skill, plans and reagents); catalogue build and counts |
| `/fp trainers` | Profession trainers visited and the recipe requirements recorded from them |
| `/fp prices [item]` | Auction House price status (Auctionator), or every known price for an item |
| `/fp celebrate [on\|off\|test\|auto on\|off]` | Completion toast and sound on/off, a test toast, or auto-complete on/off |
| `/fp attunements` / `/fp attune <name>` | List your faction's attunements with progress; add one as a goal (needs Attune) |
| `/fp goals` | List open goals in chat |
| `/fp select <n>` / `/fp remove <n>` | Select (opens Crafting) or remove goal number n |
| `/fp complete <n>` / `pause <n>` / `resume <n>` | Change a goal's status |
| `/fp tracker` | Show or hide the compact tracker |
| `/fp open <dashboard\|goals\|crafting>` | Open the window on a screen |
| `/fp scan [all]` | Open unrecorded (or all) profession windows to record recipes |
| `/fp status` | Client capabilities, recorded professions, goal counts |
| `/fp debug` | Toggle diagnostic logging |
| `/fp errors` | Show errors ForeverPath captured this session |
| `/fp reset window` | Reset window and tracker positions |

## Design

The UI follows `design/handoff/README.md` (tokens, components, screens).
Fonts use the handoff's fallback mapping to the client fonts; to bundle
Marcellus and Alegreya Sans, drop the TTFs into `ForeverPath\Fonts\` and point
`Theme.FontFiles` in `UI/Theme.lua` at them (a full client restart is needed
for new font files).

## Recipe catalogue

`ForeverPath/Data/RecipeCatalogue.lua` is generated from the Forever client's
own database tables by `tools/DbExtract` (run `scripts\extract_db.ps1` after a
client patch; needs the .NET 7 SDK and git). It carries every profession
recipe and every item-use combine the client knows, with reagents, skill
ranks, the plans or pattern that teaches each one, and item names, quality and
binding. With it an item goal is laid out all the way down even when nobody on
the account has the recipe: the planner shows who could learn it (or why
nobody can), adds the plans as something to get, treats combines such as
Sulfuras as something anyone can do, and keeps soulbound items off the Auction
House. Details in `tools/DbExtract/README.md`.

The catalogue also carries every **enchant** (and Engineering tinker): a
spell that enchants an item instead of making one, with its reagents, skill
ranks and formula. Enchants are never "an item's recipe", so they have their
own goal type (below) and count as recipes for Enchanting skill goals.

Three goal types build on it. A **learn-recipe goal** plans the pattern to
get (with its sources) or the trainer to visit, says when your skill is too
low or you lack the profession, and completes itself when you learn the
recipe. A **reach-skill goal** works out which recipes to craft, how many
times, from your current skill to the target: learned recipes first, orange
before yellow before green, cheapest by reagent prices when those are known,
with unlearned recipes filling in where a trainer visit or a pattern has
recorded their requirement. Its materials go on the shopping list like any
other goal, and it completes on the skill-up. An **enchant goal** is "cast
this enchant N times": the formula to get or the trainer to visit while you
do not know it, the reagents for every cast on the shopping list, and it
completes as the casts land (each successful cast of the spell counts).

One thing the client's tables do not hold is the skill a trainer requires
for a recipe, so ForeverPath records it from trainer windows: open any
profession trainer once, on any character, and every recipe on offer is
stored with its required skill, cost and the trainer's location
(`/fp trainers`). Plans-taught recipes carry their requirement already.

## Development

- Pure Lua logic and the UI (with mock widgets) have an offline test suite
  (`python tests/run_tests.py`, details in `TESTING.md`).
- The recipe catalogue is regenerated with `scripts\extract_db.ps1`
  (`tools/DbExtract/README.md`); the classic data with
  `scripts\extract_classicdb.ps1` (`tools/ClassicDbExtract/README.md`).
- Module layout, data flow and extension points: `ARCHITECTURE.md`.
- API usage and verification status: `API_COMPATIBILITY.md`.
- Changes: `CHANGELOG.md`.

## Licence

ForeverPath is free software under the GNU General Public License, version 3
(`LICENSE`; a copy ships in the addon as `LICENSE.txt`). Copyright (C) 2026
Jacob (DismasAU). Versions up to 0.17.3 were released under MIT.

`ForeverPath_ClassicDB` is generated from CMaNGOS classic-db (GPL-3.0, its
`LICENSE.md` ships with the data). The data contains World of Warcraft
content, a trademark and copyright of Blizzard Entertainment, used here
non-commercially as described in the bundled `COPYRIGHT.md`. ForeverPath is
not affiliated with Blizzard or the CMaNGOS project.
