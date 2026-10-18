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
| Equipment, Reputations | Preview modules with "coming later" states |

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

## Companion addons (all optional)

ForeverPath has no required dependencies. When these addons are installed
it reads their data at runtime; without them the matching feature stays off
and says so in the UI.

| Addon | Used for | Without it |
|---|---|---|
| Auctionator | Auction House prices (shopping list, CraftWise, affordability); run a full browse scan so prices exist | Only recorded vendor prices; CraftWise shows "price unknown" |
| AtlasLootClassic (+ DungeonsAndRaids module) | Boss and trash loot tables for drop sources | Drop sources only from ForeverDungeonJournal |
| ForeverDungeonJournal | Forever-specific boss loot, dungeon quests with their prerequisite chains, quest givers and rewards (quest goals, the Quests screen) | Drop sources only from AtlasLoot; the Quests screen lists only your log |
| Attune | Attunement goals and the Attunements screen; attunement quests (givers, rewards) on the Quests screen | The Attunements screen explains that Attune is missing |

## Using ForeverPath

1. **Record your recipes once.** Open each profession window (or type
   `/fp scan`, or use the settings menu in the window header). ForeverPath
   records every recipe the window lists, including ones you have not learned
   yet, and keeps recording whenever a window is open.
2. **Add a goal.** Type an item ID or name in the header search, Shift-click
   an item from your bags, or use the New Goal bar on My Goals (quantity,
   Add goal). Name search knows the catalogue's items plus items you have
   looked at; the client has no searchable item database. The New Goal bar
   also takes a **recipe** to learn ("Bolt of Woolen Cloth"), a
   **profession skill** to reach ("Tailoring 225"), a **quest** ("Leaders
   of the Fang") and an attunement.
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
| `/fp learn <recipe>` | Add a learn-recipe goal by recipe name or spell id: the pattern to get, or the trainer to visit |
| `/fp skill <profession> [rank]` | Add a reach-skill goal (default: the next cap): which recipes to craft, how often, and their materials |
| `/fp quest <name or id>` / `/fp quests` | Add a quest goal (dungeon and attunement quests, or anything in your log); list the quests that feed your goals |
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

Two goal types build on it. A **learn-recipe goal** plans the pattern to
get (with its sources) or the trainer to visit, says when your skill is too
low or you lack the profession, and completes itself when you learn the
recipe. A **reach-skill goal** works out which recipes to craft, how many
times, from your current skill to the target: learned recipes first, orange
before yellow before green, cheapest by reagent prices when those are known,
with unlearned recipes filling in where a trainer visit or a pattern has
recorded their requirement. Its materials go on the shopping list like any
other goal, and it completes on the skill-up.

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

License: MIT (see `LICENSE`).
