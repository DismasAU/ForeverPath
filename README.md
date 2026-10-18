# ForeverPath

Goal-driven progression planner for **World of Warcraft: Forever**.

Pick something you want to craft. ForeverPath works out which recipe makes it,
how many crafts you need, which reagents that takes, how many you already own
in your bags and bank, and what is still missing.

Version 0.2.0 implements the UI from the design handoff in `design/handoff/`
on top of the 0.1.0 crafting data layer. The architecture is built to grow
into quests, reputation, attunements, equipment planning and a craft-versus-buy
engine without a rewrite (see `ARCHITECTURE.md`).

## Status

| Area | State |
|---|---|
| Loads on WoW: Forever (interface 16001) | Verified in game on 0.1.0, build 1.60.1.70450 |
| Crafting data: recipes from profession windows, bag counts, missing calculation | Verified in game on 0.1.0 |
| Bank counts | Bank detected and scanned live in game; counting of real bank stacks not yet seen |
| 0.2.x shell, Dashboard, My Goals, Crafting screens, tracker | Implemented from the handoff; loads in game on 0.2.0 (header overlap and hover blanking fixed in 0.2.1), remaining checklist **not yet verified in game** |
| Multi-output recipes | Implemented, offline-tested |
| 0.3.0 recursive dependency tree, allocation across goals, route overrides | Implemented, offline-tested; in-game checklist reported good by the author |
| 0.4.0 account-wide character snapshots, Characters screen, include alts' bags | Verified in game by the author (profession capture fixed in 0.4.1) |
| 0.5.0 shopping list across goals, bought ticks, send to chat, mail plan | Implemented, offline-tested, **not yet verified in game** |
| 0.6.0 item sources: vendor recorder, item-class heuristics, AtlasLoot bridge, vendor prices | Implemented, offline-tested, **not yet verified in game** |
| 0.7.0 obtain-item goals (drops, quests, vendors planned instead of "No known recipe"), ForeverDungeonJournal bridge | Implemented, offline-tested, **not yet verified in game** |
| 0.8.0 Auction House prices via Auctionator, CraftWise buy / craft / hybrid comparison, route presets | Implemented, offline-tested, **not yet verified in game** |
| 0.8.1 goals auto-complete when the item lands in your bags; celebration toast, sound, chat line | Implemented, offline-tested, **not yet verified in game** |
| 0.8.2 affordability: shopping list and footer compare the remaining cost with your gold and the account's | Implemented, offline-tested, **not yet verified in game** |
| 0.9.0 attunement goals and the Attunements screen (Attune addon data, progress from quest flags, log, level, bags) | Implemented, offline-tested, **not yet verified in game** |
| 0.10.0 recipe catalogue generated from the client's own database (every profession recipe and item-use combine, skill ranks, plans, soulbound flags); full pathway for unlearned recipes, "learn" and "combine" routes | Implemented, offline-tested against the generated data, **not yet verified in game** |
| 0.10.1 trainer recorder: required skill, cost and location of trainer-taught recipes, recorded from trainer windows into the catalogue | Implemented, offline-tested, **not yet verified in game** |
| 0.10.2 unlearned recipes in the tree: the plans as an item to get, or a "train it" step with the trainer, zone and cost; "Recipes to learn" on the shopping list | Implemented, offline-tested, **not yet verified in game** |
| 0.10.3 gathering materials (leather tiers, essences) are planned as their own items; refining from the tier below is an opt-in route per node | Implemented, offline-tested, **not yet verified in game** |
| 0.10.4 the ForeverPath mark as addon icon, window header and tracker emblem (`Media/ForeverPath-Mark.png`) | Installed, **not yet verified in game** |
| Equipment, Quests, Reputations | Preview modules with "coming later" states |

`TESTING.md` has the in-game checklist for 0.2.0. `API_COMPATIBILITY.md`
lists the API evidence and the remaining open questions.

## Installation

1. Copy the `ForeverPath` folder (the one containing `ForeverPath.toc`) into
   `World of Warcraft\_classic_beta_\Interface\AddOns\`.
   `_classic_beta_` is the Forever beta product folder.
2. Start the game or type `/reload`.
3. Type `/fp`.

Developers: `scripts\install_dev.ps1` copies the folder into the AddOns
directory, and `scripts\package.ps1` builds a release zip.

## Using ForeverPath

1. **Record your recipes once.** Open each profession window (or type
   `/fp scan`, or use the settings menu in the window header). ForeverPath
   records every recipe the window lists, including ones you have not learned
   yet, and keeps recording whenever a window is open.
2. **Add a goal.** Type an item ID or name in the header search, Shift-click
   an item from your bags, or use the New Goal bar on My Goals (quantity,
   Add goal). Name search only knows items ForeverPath has seen (recipe outputs
   and items you have looked at); the client has no searchable item database.
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
4. **Tracker.** A compact frame near the minimap pages through tracked goals
   and shows the next step; drag it anywhere, collapse it with "-", open the
   goal with "+". `/fp tracker` hides or shows it.
5. **Bank items** count as owned once you have opened your bank on that
   character; the inventory note says whether the figure is live, a snapshot,
   or unknown.

## Commands

| Command | Effect |
|---|---|
| `/fp`, `/foreverpath` | Open or close the window |
| `/fp help` | List commands |
| `/fp add <item> [qty]` | Add a goal by item ID or link (crafting when a recipe is known, otherwise obtain) |
| `/fp obtain <item> [qty]` | Add an obtain-item goal (boss drop, quest reward, vendor stock) even if a recipe exists |
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

One thing the client's tables do not hold is the skill a trainer requires
for a recipe, so ForeverPath records it from trainer windows: open any
profession trainer once, on any character, and every recipe on offer is
stored with its required skill, cost and the trainer's location
(`/fp trainers`). Plans-taught recipes carry their requirement already.

## Development

- Pure Lua logic and the UI (with mock widgets) have an offline test suite
  (`python tests/run_tests.py`, details in `TESTING.md`).
- The recipe catalogue is regenerated with `scripts\extract_db.ps1`
  (`tools/DbExtract/README.md`).
- Module layout, data flow and extension points: `ARCHITECTURE.md`.
- API usage and verification status: `API_COMPATIBILITY.md`.
- Changes: `CHANGELOG.md`.

License: MIT (see `ForeverPath.toc`; adjust if you prefer another license).
