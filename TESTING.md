# Testing

## Automated tests (no game client)

The suite exercises every non-UI module with real logic and the UI with mock
widgets. It runs on Lua 5.1, the version embedded in WoW.

```
python -m pip install lupa
python tests/run_tests.py
```

A native interpreter works too: `lua5.1 tests/runner.lua .`

Layout:

- `tests/harness.lua` - `describe` / `it` / `before_each`, assertions,
  TOC-driven addon loader (files execute in manifest order, each receiving
  `(addonName, ns)` like in the client).
- `tests/mocks/wow_api.lua` - the Forever API surface ForeverPath touches:
  `C_Item`, `C_Container`, `C_Bank`, `C_TradeSkillUI`, `C_Timer`, `C_AddOns`,
  `GetProfessions`, slash commands, `hooksecurefunc`, widget objects. Legacy
  globals are absent and registering an unknown event throws, matching the
  real client.
- `tests/spec/*_spec.lua` - specs, listed in `tests/spec_list.lua`.

What is covered:

| Spec | Covers |
|---|---|
| `toc_spec` | Both manifests identical, Interface 16001 first, every file exists and compiles, single global |
| `util_spec` | Integer parsing, defaults merge, relative time, serializability |
| `database_spec` | Migration order, skip, refuse-downgrade, failure reporting, first run, preserved settings |
| `goal_model_spec` | Creation, validation, unique ids, unsupported types, titles, quantity |
| `goal_store_spec` | Create/list/select/remove, malformed data dropped, SavedVariables round trip, type switching between item goals |
| `recipe_model_spec` | Schematic normalization (basic vs optional slots, alternatives, multi-output), malformed input, merge |
| `crafting_engine_spec` | Crafts needed, multi-output yield, quantities, missing with zero / exact / surplus inventory, bank inclusion, broken lookups |
| `allocation_spec` | Count normalization, bags-before-bank claims, reserved amounts, bank exclusion, release, alts bucket last and only on request |
| `dependency_resolver_spec` | Direct reagents, learned intermediates expanded to raw materials, minimum-yield crafts, no double counting in one tree, route overrides (buy / forced craft / no recipe), cycle and depth guards, flatten with collapse/filter/guides, uses across goals, chat description, direct counts, obtain roots (claiming leaf with best source, craft of the shortfall through a learned recipe) |
| `planner_spec` | Every status, learned-over-unlearned preference, live vs cached, inventory notes, tree attached, shared ledger across goals, route overrides, no-recipe goals planned from sources, obtain goals (craftable, complete, unlearned, unscanned) |
| `item_provider_spec` | Input parsing, invalid IDs, async load and failure, name cache, search ranking |
| `profession_provider_spec` | Missing API, scan recording, chunked scans, NPC/linked views skipped, parent profession keys, live refresh, learned updates, `/fp scan` queue, combat deferral |
| `inventory_provider_spec` | Bag counts, dirty rescans, bank live/cached, client fallback, missing APIs |
| `vendor_provider_spec` | Merchant scan (unit price from stacks, limited stock, item costs, zone), cheapest-first hints, price source, rescans on update, nameless merchants, missing API |
| `trainer_provider_spec` | Trainer windows: filters switched on for the visit and restored, every recipe recorded with skill, rank, cost, trainer and zone, persistence, status and `/fp trainers`; the catalogue picks up the rank (crafter check, plan message, `/fp recipe`); class trainers skipped, missing requirement or link functions, name matching against the catalogue, repeat visits, unknown trainer kinds |
| `attune_provider_spec` | Faction listing and order, name search, step resolution (names, spacers, follows, quest level and group), progress from flags / log / level / bags / survey, inference from later steps, side quests, item counts, multi-end chains |
| `catalogue_spec` | The generated recipe catalogue: build info and counts, Sulfuron Hammer decoded (skill 300/325/350, plans, seven reagents), the Sulfuras and essence combines, lookup by item, binding and names, item-name fallback and search; resolver learn / unavailable / soulbound / combine routes with injected crafters; the full Sulfuras plan through the planner with and without a blacksmith, shopping-list recipe and soulbound rows, `/fp recipe`, `/fp catalogue` |
| `price_provider_spec` | Auctionator adapter (price, age, mean, listings, scan time), cheapest-of-sources with alternatives, freshness grades, status texts, `/fp prices`, missing addon / scan / database |
| `goal_completion_spec` | Baseline and peak gain, crafting goal completes on the gained quantity, consumed-at-once crafts, obtain goals on hand, settings off, reopen re-bases, old goals baseline first, toast queue and click, `/fp celebrate` |
| `goal_types_spec` | SkillPlanner (chance and difficulty per point, segments with learned recipes first, expected crafts rounded up, gaps, learnable recipes only with a known requirement, price-aware choice); learn-recipe goals (model and titles, catalogue search and profession lookup, a trainer recipe as a train-step tree blocked by profession or skill, trainer visit filling in trainer and cost, alts who know it, completion on learning with its toast, a pattern recipe as the pattern to get then to read, combine and unknown spells refused); reach-skill goals (default target, unknown and missing professions, the Tailoring 100-150 plan over the real catalogue: segments, skill root and `forSkill` tree, merged materials, shopping rows without outputs, Overview craft step, CraftWise, progress and completion on the skill-up, reopening with a higher target above the cap, unscanned profession, `/fp skill`, `/fp learn`, every screen and the tracker rendering both kinds) |
| `quest_goals_spec` | QuestProvider (index from the journal and Attune: chains, prerequisite entries, starts, rewards, faction filter, search, difficulty colours; log, objectives, readiness, zone headers, capacity, titles loaded by id, `Describe`); quest goals (a six-quest chain planned step by step: locked, level gate, pick up, finish, turn in, available, in log, ready; progress; Overview steps; completion on the turn-in with its toast; log-only quests; refusals); feeds (`FeedsGoals`, `/fp quests`, `/fp quest`) and the Quests screen (selection from the goal, details, feeds, rewards, groups, filter, By goal and Completed tabs, Link and Watch, Add goal, other screens and the tracker) |
| `equipment_spec` | EquipmentProvider (worn items, item levels, stats, slot keys, average, status; GearQuest hunts filtered by class, spec, faction, level band and source, ranked and deduplicated, facts, hints into the source provider and the planner's route); `Analyze` statuses and goal mapping; `/fp equipment`; the Equipment screen (strip, badges, selection, target card, stat deltas, other options, goal buttons, filter, equipment change refresh, without GearQuest) |
| `reputation_spec` | ReputationProvider (standings, thresholds, groups, search, standing names, progress anchored at the start, status; quest rewards parsed from the journal with live states; AtlasLoot faction tiers loaded on demand, rewards per standing, vendor hints available or unavailable below the standing, into the source provider and the planner's route; `Describe`); reputation goals (input forms, default and retargeted standings, planner view and messages, Overview, progress on reputation gained, next open quest, completion on the standing with its toast, reopening; `/fp reps`, `/fp rep`); the Reputations screen (selection from the goal, panel, target segment, rewards, quests with the jump to the Quests screen, retargeting, My Goals segment, other screens and the tracker) |
| `questline_spec` | The shipped quest catalogue (every row well-formed, givers / turn-ins / items without Attune, drop hints through SourceProvider, a quest goal from the shipped facts on the shopping list); questlines from Attune chains (class and faction filters, either/or starts, the part of a chain before a quest, progress, the mage chain); a quest-reward item planned as its chain (source, next step, messages, overview, shipped giver facts and map pin, waypoint success and refusal, the step moving through pick-up / finish / turn-in, the reward in the bags, a character outside the chain); the chain's quest items on the tree, requirement rows, shopping list, overview and feeds, a quest goal with the same items and `Describe`; the learner (objective parsing, giver position and zone at `QUEST_DETAIL`, items at `QUEST_ACCEPTED` with names resolved from the bags later, shipped and learned facts merged, turn-in at `QUEST_COMPLETE`, waypoints by state); the crafting hero chips and waypoint button, requirement rows and tree, My Goals and dashboard rows, the Quests side panel chain lines and waypoint button |
| `classic_db_spec` | The generated ForeverPath_ClassicDB loaded on demand (copper from copper veins, Peacebloom nodes needing Herbalism, skinned leather, Coarse Thread's classic price, Red Linen Shirt's trainer requirement reaching the catalogue recipe; every quest and NPC row in shape, Call of Air's side, class, giver and turn-in, Prate Cloudseer's position, Leaders of the Fang's chain for a Horde character) and the missing-addon status; with a fixture: classic entries behind Get, givers / turn-ins / waypoints / items, catalogue precedence, rewards and search filtered by faction and class, prerequisite locking, "(classic data)", `/fp status`; classic questlines (any-of groups, the option taken, journal chains winning, journal giver text with the classic position); a classic quest-reward item and a classic quest goal planned along the chain with their items on the shopping list; classic reputation quests by faction; classic sources (drop chance, zone, level, rank, quest-only drops, world drops, the 1% routing threshold, gathering nodes qualified by skill, chests, fishing, containers, rogue-only pickpocketing, faction-friendly vendors, recorded vendors and journal bosses taking precedence), classic vendor prices and trainers |
| `loot_learner_spec` | GUID parsing; a corpse, area loot from two corpses, skinning a looted corpse, a herb node, fishing, each loot window counted once; hints by observed chance, through SourceProvider and the planner's route; observations ahead of classic data for the same creature; "New in Forever" from the classic item ranges and the client item index; the item index naming, ranking and binding items no recipe touches |
| `farming_spec` | Estimates for kills, units per loot, skins, nodes, casts, chests, one kill; the estimate and zone on the tree's leaves, the overview step and shopping rows, zone sorting on the screen; trainer planning (known recipes left out, now / soon window, total cost, classic trainers, `/fp train`, unknown profession) |
| `enchant_goals_spec` | Enchants in the catalogue (decoded with `enchant`, no output item, skill ranks, formula, never indexed by item, search by kind, enchant and spell links, schematics without an item accepted by `recipeType` or the catalogue, the goal model); enchant goals from a link, a name, `/fp enchant` and `/fp learn`, item recipes routed to their item, refusals; the plan with no profession, too low a skill, the formula to get then read, learned with the reagents to obtain, every reagent in hand, casts counted only for the player, completion on the last cast with its toast, reopening; a trainer enchant as a train step with the recorded trainer, the crafting screen, the tree and the goals list for an enchant goal, and an Enchanting skill goal planned over enchants |
| `craftwise_spec` | Buy vs craft vs hybrid per component, savings and recommendation, unknown prices stay unknown, owned and alt stock free, route plan and presets, obtain trees |
| `source_provider_spec` | Class heuristics, hint dropped once a recipe exists unless it only refines a lower tier (raw materials: leather tiers, essences vs bolts, cured hides, smelting), a plan whose Medium Leather stays a leaf with crafting as a one-tier opt-in, vendor > AtlasLoot > heuristic ordering, AtlasLoot on-demand index and cap, planner default route, DungeonJournal boss/trash/shared loot and quest rewards, AtlasLoot duplicates folded, `/fp vendors` status |
| `character_provider_spec` | Login/logout/change snapshots, serializability, a second character reading alts' stock (bags + bank), crafters, sources, coverage, freshness aging, forget, planner with and without includeAlts |
| `overview_spec` | Missing-material aggregation across active goals, next-step rules, percentages and summaries, tree leaves and "craft next" steps, obtain goals (on hand / obtain with source badge) |
| `shopping_list_spec` | Rows across two goals sharing a ledger, owned/reserved/missing with a paused goal, membership overrides, craft/alt categories, mail plan, bought rows, sorting, filters, chat lines with links, an obtain goal's own item as a row |
| `bootstrap_spec` | ADDON_LOADED, unknown events, error capture, every slash command, reload persistence |
| `ui_spec` | Shell (header, sidebar, status bar, screen switching and persistence), header search, Crafting screen (hero, chips, table, sorting, tabs, empty states), Dependency Tree tab (rows, guides, selection, route switching, collapse, filter), Characters screen (cards, banner, scope switch, include-alts checkbox, forget), Shopping List (chips, rows, bought, clear, send to chat, links from Dashboard and Crafting, vendor prices and tags), CraftWise tab (cards, breakdown, use plan, empty states), Dashboard (strip, goals, next steps, missing materials, CraftWise panel), Goals route presets, price status bar, My Goals (add, status, tracking, complete, tabs), tracker (paging, collapse, hide), Shift-click targets, inventory/item refresh, window bounds |

Add a spec by creating `tests/spec/<name>_spec.lua` and listing it in
`tests/spec_list.lua`.

## In-game validation checklist (WoW: Forever)

Nothing below has been run yet. Install the addon (`scripts\install_dev.ps1`
or copy the folder), log in on a character with at least one crafting
profession, and work through the list. Note the result of every step; `/fp
status` and `/fp debug` output are the most useful things to report.

### 1. Load
- [ ] No Lua error at login. The AddOns list shows ForeverPath 0.1.0 (not "out of date").
- [ ] `/fp status` prints "Forever client: yes", interface 16001, and every API row says "available".
- [ ] `/fp help` lists the commands. `/fp bogus` prints "Unknown command".

### 2. Window
- [ ] `/fp` opens the window; `/fp` again and the close button close it; Escape closes it.
- [ ] Drag by the title area, resize by the bottom-right grip (minimum 560x380).
- [ ] `/reload`: the window reopens at the saved position and size. `/fp reset window` recentres it.
- [ ] Nav buttons: Crafting highlighted; the others disabled with a "Planned" tooltip.

### 3. Recipe recording
- [ ] Open a profession window. Chat shows "Recorded <Profession>: N item recipes (M learned)". With `/fp debug` on, a "Scanning" line appears first.
- [ ] `/fp status` lists the profession with counts and "just now".
- [ ] Open a second profession; it is recorded as well.
- [ ] Open a profession window linked by another player: nothing is recorded (debug log says "linked profession").
- [ ] `/fp scan` on a character with an unrecorded profession: either the window opens and recording happens (question 2 in API_COMPATIBILITY.md answered "yes") or chat says "Could not open ... manually".
- [ ] Learn a new recipe: it becomes "learned" without rescanning (NEW_RECIPE_LEARNED).

### 4. Goals
- [ ] Type the item ID of something a recorded, learned recipe makes (for example the output of your first recipe), quantity 2, press Add goal. The goal appears in the list, selected, titled "Craft 2x <name>".
- [ ] Details show the recipe name and profession, "N crafts needed", and a material row per reagent with Required = reagent quantity x crafts.
- [ ] Owned matches what is in your bags; Missing = Required - Owned, never negative.
- [ ] Hover a material: item tooltip plus "Per craft" and "Bags" lines.
- [ ] Change quantity with +, -, and by typing in the box; required amounts update.
- [ ] Shift-click an item in your bags with the window open: the link lands in the item field. With the chat edit box open instead, the link goes to chat, not ForeverPath.
- [ ] Type part of a recorded item's name and press Add goal: the goal is created for that item (or the status line lists the matches it chose between).
- [ ] Add an item whose recipe you have recorded but not learned: status "Recipe not learned" naming the profession.
- [ ] Add a random non-craftable item ID (for example a quest item): status "No known recipe" listing your recorded professions.
- [ ] Add item ID 999999999: status "Invalid item".
- [ ] On a fresh character with no professions recorded: status "Recipes not scanned".
- [ ] Remove removes the selected goal and selects the next one. `/fp goals`, `/fp select 1`, `/fp remove 1` work from chat.
- [ ] `/reload` and relog: goals, selection and recorded recipes survive. Switch character: goals are per character, recipe data is shared, learned flags are per character.

### 5. Inventory
- [ ] Move reagents into or out of your bags (buy, mail, destroy): Owned updates within a second.
- [ ] Before visiting a bank: the inventory note says bank contents are unknown (or "as reported by the client" if question 3 is "yes").
- [ ] Open the bank: Owned includes bank stacks and the note says "bank open, live". Close it: the note says "snapshot (just now)". `/reload`: the snapshot is still used.
- [ ] A recipe whose output stacks (for example a bolt from 2 cloth): quantity 3 needs 3 crafts; a recipe producing several items per craft (if you have one) needs ceil(quantity / yield) crafts and the details line says "x per craft".

### 6. Robustness
- [ ] Enter combat with the window open; the window stays usable; `/fp scan` during combat prints nothing harmful and runs after combat.
- [ ] `/fp errors` is empty after the session (or report what it shows).
- [ ] Disable another addon that hooks chat links (Auctionator) and confirm Shift-click still works; re-enable it and confirm both coexist.

### 7. 0.2.0 design handoff UI (verified in game by the author, 2026-10-18)
- [ ] After `/reload` with 0.1.0 saved data: no Lua error, window opens at the old position, goals still listed (schema 2 migration).
- [ ] Window: bronze border with rings and corner rivets, 46 px header, sidebar, status bar; resizes between 820x560 and 1400x960; drag by the header.
- [ ] Header: character name in class colour, "Level N Class - Realm"; active-goal pill shows the selected goal's icon, name and %; clicking it lists open goals.
- [ ] Header search: typing two letters of a recorded item name shows suggestions; clicking one adds the goal and opens Crafting; Enter on an item ID does the same; Shift-click fills the field.
- [ ] Settings menu ("..."): tracker toggle, record recipes, debug toggle, reset positions all work.
- [ ] Sidebar: active item highlighted; preview modules open their "coming later" panel; the last screen is restored after `/reload`.
- [ ] Status bar: bag/bank dot and text; recipe dot turns green after a scan; alerts appear after actions; version shown; grip resizes.
- [ ] Dashboard: portrait, professions with bars, gold, goal counts; goal rows show %, bar and "Missing: ..." line; clicking a row opens Crafting; Missing Materials lists aggregated counts with "Craft - Profession" where applicable; Recommended Next shows a sensible first step.
- [ ] My Goals: New Goal bar adds with the chosen quantity; rows grouped Active / Queued / Paused with priority numbers; TRK checkbox toggles tracker membership; settings panel changes quantity, priority, status; Mark complete moves the goal to the Completed tab; Reopen brings it back; Delete removes it.
- [ ] Crafting: hero chips (profession - you have N, Recipe known / not learned, Makes N per craft); completion % and "X of Y reagents"; table columns align; Have colours green/amber/red; missing rows tinted; source tags (In bags / Bank / Craft - Profession); sort menu reorders; other tabs show "later version" text.
- [ ] Tracker: appears near the minimap with tracked goals; pager cycles; "-" collapses to one line; "+" opens the goal in the window; drag and `/reload` keeps its position; `/fp tracker` hides and shows it.
- [ ] Fonts: headings in FRIZQT, body in ARIALN; nothing renders as empty boxes (no missing glyphs).

### 8. 0.2.1 fixes (reported from the first 0.2.0 session)
- [ ] Header: "Level N Class - Realm" sits right of a divider that clears the tagline; nothing overlaps. Shrink the window to 820 wide: the character lines truncate with "..." before the active-goal pill.
- [ ] Goal switcher (click the active-goal pill): hovering a row shows a raised background and the goal name stays readable.
- [ ] Header search suggestions: same hover behaviour.
- [ ] Dashboard character strip: all four stat cells stay inside the panel at 1000 and at 820 wide; Goals shows "N active" with the done count underneath; gold shows coin icons or the short "12g 34s" form, never clipped.

### 9. 0.3.0 dependency tree (verified in game by the author, 2026-10-18)
Use a goal whose recipe has a craftable intermediate, for example a Leatherworking item that needs Light Leather you can make from Ruined Leather Scraps, or any item needing a bolt/bar you can craft. Record both professions first.
- [ ] `/fp tree` prints the tree in chat: the goal line with crafts, each reagent with have/need, intermediates indented under their parent, "N of M dependencies resolved".
- [ ] Crafting > Dependency Tree tab: the intermediate shows "Craft - <Profession>" in Get via, its own reagents sit under it with guide lines and an elbow; Have shows your bag count in green/amber/red; Status badges match.
- [ ] Have fewer raw materials than the intermediates need: the raw material row is Partial/Missing and the Dashboard's Missing Materials lists the raw material, not the intermediate. Recommended Next says "Obtain N x <raw>".
- [ ] Put enough raw materials in your bags: the intermediate's row stays (it still has to be crafted) but Recommended Next becomes "Craft N x <intermediate>" with a "Craft - <Profession>" badge.
- [ ] Two goals needing the same material with fewer stacks than both need: the priority-1 goal shows them as Have; the priority-2 goal shows them Missing and the tooltip says "Reserved by higher-priority goals: N". Swap priorities in My Goals and the numbers swap.
- [ ] Click the intermediate row: Selected Node shows have / need, "N missing", the crafting card marked BEST and the Auction House card. "Use buying route" collapses the branch and Get via says "AH"; "Default route" restores it. `/reload` keeps the override.
- [ ] A reagent whose recipe you recorded but have not learned: default Get via "AH, learn recipe"; forcing "Use crafting route" expands it with "(not learned)".
- [ ] Chevrons collapse and expand a branch; Expand all / Collapse all; Show > Unresolved only hides rows you already have.
- [ ] "Also used by" lists another goal needing the same item, with its quantity.
- [ ] Link inserts the item link into an open chat box, or prints it to chat when none is open.
- [ ] Resize to the minimum height: the Selected Node panel stays usable (known tight spot).

### 10. 0.4.0 characters (verified in game by the author, 2026-10-18)
Needs two characters on the account. Log in on the alt first, then on your main.
- [ ] On the alt: `/fp characters` lists it as "(you) ... live". `/fp snapshot` prints its professions with their source ("client list", "recorded windows only" or "kept"); if it says "none", wait ten seconds and run it again, then report which it was. Log out normally and log in on the main.
- [ ] On the main: `/fp characters` lists both; the alt says "snapshot" with its level, class, professions and bag item count ("+ bank" if you visited a bank on it).
- [ ] Characters screen: two cards; the main is LIVE with your portrait, the alt is SNAPSHOT with its class icon, level/race/class, gold, profession bars and its open goals.
- [ ] With an active goal missing something the alt carries: the banner says "<Alt> already has N of the required materials" and lists them; the alt's card shows those items with counts and a gold outline; "Can craft for your goals" lists needed items the alt knows a recipe for.
- [ ] Scope > Account-wide (or the Crafting checkbox "Include alts' bags", or `/fp alts`): the goal's % rises, the requirements row for that material shows the alt's units in Have, the tooltip lists "<Alt> has N (snapshot, counted)", Get via in the tree says "Alt: <Alt>". Switch back: counts drop and tags say "Alt: <Alt> (n)" for information only.
- [ ] Recommended Next phrases an alt-held leaf as "Get N x <item> from <Alt>" and an alt-craftable one as "Have <Alt> craft N x <item>".
- [ ] Dismiss hides the banner until `/reload`; Forget removes the alt card and its data; logging in on the alt again recreates it.
- [ ] After 24 h without logging in on the alt, its badge becomes CACHED with "N days" and "Log in on <Alt> to refresh".
- [ ] No Lua errors on logout/login; `ForeverPathDB.characters` in the SavedVariables file holds both entries.

### 11. 0.5.0 shopping list (verified in game by the author, 2026-10-18)
- [ ] Sidebar > Shopping List: goal chips for every open goal, active/queued ticked, paused unticked. Unticking a chip removes its materials; `/reload` remembers the choice.
- [ ] Rows: one per missing item across the ticked goals, biggest gap first. An intermediate you will craft shows "via craft" and a "Craft - <Profession>" tag; a raw material shows "?" and "AH".
- [ ] Pause a goal that holds materials another goal needs: the other goal's row shows Owned = what is in your bags, Reserved = the part the paused goal holds, Missing = Total - (Owned - Reserved). The tooltip repeats it.
- [ ] Tick the bought box: the row dims, says "(bought)" and sinks to the bottom; Clear bought resets; both survive `/reload`.
- [ ] Filter tabs show counts; a tab with 0 falls back to All. Sort: Missing / Name / Total / Source.
- [ ] Send to chat prints the list to your own chat frame with clickable item links, one line per item, plus "Mail from <Alt>: ..." lines when an alt holds something. Nothing is whispered or sent to a channel. `/fp shopping` prints the same.
- [ ] Dashboard "Open shopping list >", Crafting "Add to shopping list" (ticks that goal and opens the list) and Characters "Plan mail" all land on the screen.
- [ ] With an alt holding a missing item: the blue strip under the summary says "<Alt> can mail N <item>".

### 12. 0.6.0 item sources (verified in game by the author, 2026-10-18)
- [ ] Open any merchant that sells a trade good (Coarse Thread at a tailoring or trade supplies vendor). `/fp vendors` counts it; `/fp sources 2320` prints "Vendor: Buy from <npc> - <zone> - <price> each" and "Price: ... (vendor)".
- [ ] A goal needing that item: the requirements row shows the unit price and subtotal, the Source tag says "Vendor: <npc>", the footer "Buy all missing" shows a total with "(+N unpriced)", and the tree's Get via says "Vendor: <npc>".
- [ ] Shopping list: the row moves to the Vendors tab with a cost; Estimated total shows the vendor total and "N items unpriced".
- [ ] `/fp sources` on Ruined Leather Scraps says Skinning; on Linen Cloth "Humanoid drops"; on Copper Ore "Mining"; on Copper Bar nothing once the smelting recipe is recorded.
- [ ] With AtlasLootClassic enabled: `/fp vendors` says "AtlasLoot: installed, index ready" after the first `/fp sources` or tree evaluation; `/fp sources 14149` (Subterranean Cape) prints "Dropped by Taragaman the Hungerer - Ragefire Chasm (AtlasLoot)". Disable AtlasLoot: everything still works, the line just disappears.
- [ ] An item with an extended cost (sold for other items) records "costs other items" and no price.
- [ ] `/reload` and switching characters keep the vendor data (account-wide).

### 13. 0.7.0 obtain goals and DungeonJournal (verified in game by the author, 2026-10-18)
- [ ] With ForeverDungeonJournal enabled: `/fp vendors` says "DungeonJournal: installed, N items indexed" (N in the hundreds). `/fp sources 10411` (Footpads of the Fang) prints "Drop: Dropped by Kresh - Wailing Caverns (DungeonJournal)"; a quest reward from a journal dungeon prints "Quest: Quest reward: <quest> - <dungeon> ... (DungeonJournal)".
- [ ] Shift-click a dungeon drop into the search box or `/fp add` it: the goal is created as "Obtain 1x <item>" (badge Item). The Crafting screen shows chips "Obtain" and "Dropped by <boss>", "0 of 1 in your bags - Dropped by <boss> - <dungeon> (DungeonJournal)", and one requirements row with the drop as its source tag. No "No known recipe" dead end.
- [ ] An existing crafting goal for a drop (the "Footpads of the Fang - No known recipe" case): after `/reload` it is planned the same way, with a third chip "No known recipe"; `/fp obtain <item>` switches it to an obtain goal.
- [ ] Dependency Tree tab: the root row shows Have 0/1, Status MISSING, Get via "Drop"; the side panel is titled "Goal item" with the boss drop as the current card and "Buy on the Auction House" as the alternative; "Use buying route" works and "Default route" restores it.
- [ ] Dashboard: the goal row says "Missing: 1 <item>" with the boss on the right and an ITEM badge; Recommended next steps lists "Obtain 1 x <item>" with a Drop badge. Shopping list: the item sits under "Gathering / drops" with "Dropped by <boss>".
- [ ] Loot the item (or buy one): the goal reads "All 1 x <item> on hand", next step "1 x <item> on hand - Mark the goal complete", tracker says the same.
- [ ] `/fp add` for a craftable item still creates a crafting goal; before any profession scan `/fp add` still creates crafting goals and asks for a scan.
- [ ] Disable ForeverDungeonJournal: the goal still plans (AtlasLoot or AH route), `/fp vendors` says "DungeonJournal: not installed", no errors in `/fp errors`.
- [ ] Gathering only when someone can: a goal needing Ruined Leather Scraps on a character without Skinning and with no skinner alt shows a BUY next step (the tree card reads "Skinning ... no character has Skinning", cost column "no gatherer"). Log a skinner alt once (or learn Skinning): the step becomes GATHER ("Gather - <alt>" when it is an alt) and the detail names who has the skill and their level.

### 14. 0.8.0 Auction House prices and CraftWise (verified in game by the author, 2026-10-18)
- [ ] Status bar shows "AH prices: cached scan - <age>" with Auctionator enabled and a scan done; `/fp prices` prints the same plus the vendor count. Disable Auctionator: "AH prices: Auctionator not installed", no errors.
- [ ] `/fp prices 2589` (Linen Cloth) prints "Auction House: <price> each (<age>), 7-day average ..., N listed - cheapest"; with a recorded vendor that is cheaper, the vendor line comes first and the AH line is listed under it.
- [ ] Requirements table: Unit price / Subtotal filled for AH-priced materials, "Buy all missing" total, footer "CraftWise route: <total>"; "Open CraftWise >" switches to the CraftWise tab.
- [ ] CraftWise tab: CACHED badge and "AH scan <age>"; three cards with totals; RECOMMENDED on the cheapest; the hybrid card lists Buy / Craft / Use owned; the breakdown rows show Buy (AH), Craft path, Hybrid, Choice and a freshness dot (green under 3 h, amber under 24 h, red after; "vendor" for fixed prices; "no price" when unknown).
- [ ] Find a goal where buying an intermediate beats crafting it (its AH price below its reagents' prices): the Choice column says Buy, "Use this plan" applies it, the tree row now says AH, the shopping list moves the intermediate to Auction House, the tracker's next step changes, and the button reads "Plan in use". My Goals > Route shows "CraftWise hybrid - <total>"; picking "Default routes" clears it, "Buy all materials" buys every craftable component.
- [ ] Dependency Tree: Est. cost column shows price x missing for bought/vendor rows, "-" for crafted ones; the Auction House card shows the cost.
- [ ] Dashboard CraftWise panel: total, "Hybrid plan - saves <amount>", three rows, "Cached scan - <age>", Compare opens the tab for that goal. With no prices: "No price data" and the AH status text.
- [ ] Rescan at the Auction House: prices and ages update after `/reload` or the next refresh without reloading ForeverPath.

### 15. 0.8.1 auto-complete and celebration (verified in game by the author, 2026-10-18)
- [ ] `/fp celebrate test` shows the toast at the top of the screen (gold border, icon, "GOAL COMPLETE", name, detail line); it fades after about six seconds; clicking it opens My Goals.
- [ ] Add "Craft 1x <something cheap>" and craft it: the goal flips to Completed within a second of the item landing in your bags, the level-up sound plays, chat says "Goal complete: Crafted 1x ...", the toast appears, the goal counter on the sidebar and the Dashboard "done" count update.
- [ ] Craft 2 of an intermediate that another goal consumes (bolts for a bag): the bolt goal completes even if the bag is crafted straight after.
- [ ] A goal for an item you already own some of: only the amount gained since the goal was added counts (check `target.baseline` in the saved variables if in doubt).
- [ ] Reopen a completed goal from My Goals > Completed: it does not re-complete until you gain the quantity again.
- [ ] `/fp celebrate off`: completion still happens, silently. `/fp celebrate auto off`: nothing completes by itself; Mark complete still works.
- [ ] Existing goals from 0.8.0 do not complete on login just because the item is in your bags.

### 16. 0.8.2 affordability (verified in game by the author, 2026-10-18)
- [ ] Shopping list: the second summary cell reads "Yes" with "<cost> of your <gold>" when you carry enough; set a goal whose materials cost more than you carry: "With alts' gold - short X here; alts hold Y" when an alt's snapshot covers it, else "No - short X across the account". Rows show + / ~ / ! before the cost and the tooltip explains it.
- [ ] Tick a row as bought: it drops out of the remaining cost and the verdict updates. "Send to chat" prints "Cost: ..." under the header line.
- [ ] Crafting footer: "Buy all missing: <total> - affordable" or "- short X".

### 17. 0.9.0 attunement goals (verified in game by the author, 2026-10-18)
- [ ] With Attune enabled: Attunements in the sidebar (no longer a preview); the picker lists your faction's raids then dungeons; `/fp attunements` prints each with a percentage and next step.
- [ ] Pick Onyxia's Lair (or any chain you have started): done steps show green nodes and DONE, the current step a gold ring and CURRENT with the right quest name and zone, later steps LOCKED; the header percentage matches Attune's own view. Quest names should match the in-game quest log (they come from Attune's locale table).
- [ ] A chain you have finished shows 100%, "Attuned", and the Current step panel says "Attuned".
- [ ] "+ Add goal" creates "Complete attunement: <name>" (badge ATTUNEMENT) and turns into "Goal added"; My Goals > Attunement segment adds by typing part of the name; `/fp attune <name>` does the same and opens the screen.
- [ ] Dashboard: the goal row says "Next: Quest: <step> - <zone>" and "N of M steps"; Recommended Next lists the step with its type as the badge. Tracker shows the percentage and the next step. Opening the goal from anywhere lands on the Attunements screen; the Crafting screen explains the hand-off.
- [ ] Turn in a chain quest: within a second the timeline advances (no /reload). Finish a chain: the goal completes with an "Attunement complete" toast.
- [ ] Kill / talk / use steps: done once Attune records them (its survey), or once a later quest is done.
- [ ] Disable Attune: the screen explains, `/fp attune` refuses politely, existing attunement goals show "API unavailable" without errors.

### 18. 0.10.0 recipe catalogue (verified in game by the author, 2026-10-18)
- [ ] `/fp catalogue` prints "Recipe catalogue: 2336 recipes, 292 combines ..." with the client build; `/fp status` ends with the same line. Loading the 540 KB data file causes no visible hitch at login and no Lua error.
- [ ] `/fp recipe 17193` (Sulfuron Hammer) prints "Blacksmithing 300 (yellow 325, grey 350) ... taught by Plans: Sulfuron Hammer" and the seven reagents; `/fp recipe sulfuras, hand` prints the combine. Compare three recipes you know with their in-game tooltips (reagents and counts must match exactly).
- [ ] `/fp add sulfuras, hand` on a character with no Blacksmithing: a crafting goal; the Crafting screen shows the hero chips "Combine - anyone can" and the tree: Sulfuras (Combine) > Sulfuron Hammer (route AH, option card "Recipe not learned: no Blacksmithing on this account") and Eye of Sulfuras ("No route (soulbound)" unless DungeonJournal names Ragnaros). Shopping list: the eye under Gathering / drops with "Soulbound", never under Auction House.
- [ ] Same goal on (or with a snapshot of) a blacksmith at 300: the hammer row reads "Craft - Blacksmithing (<name>, needs plans)" or "(learn, needs plans)" for yourself; its children start with Plans: Sulfuron Hammer (shopping list "Recipe: teaches Sulfuron Hammer") followed by the reagents; Dashboard next step names the plans or the biggest material gap. A blacksmith at 250 reads "needs Blacksmithing 300; <name> has 250".
- [ ] An item with a trainer recipe nobody has (e.g. a Tailoring bolt on a non-tailor): the goal is a crafting goal, the chip says "Recipe not learned - no Tailoring on this account", the route is the AH, and the option card lists the reagents. Learn the recipe: after a profession-window scan the goal plans normally (recorded recipe wins).
- [ ] `/fp add <a BoE drop with no recipe>` (e.g. a green world drop): an obtain goal, as before. `/fp add 2589` (Linen Cloth): "Obtain 1x Linen Cloth".
- [ ] Combine of three Lesser Astral Essence (10998) into Greater: `/fp add 11082`: "Combine" route with 2 x Lesser Astral Essence per craft (the used essence is spent). Craft it: the goal completes with the usual toast.
- [ ] Names: a goal added by id for an item this client has never seen shows the catalogue name immediately, then the client's (identical) name once loaded; quality colour matches.
- [ ] CraftWise on a soulbound craft (hammer when you can craft it): the Buy card has no price; craft and hybrid are computed from the reagents plus the plans.

### 19. 0.10.1 trainer recorder (verified in game by the author, 2026-10-18)
- [ ] `/fp status` lists "Trainer window API: available". Before any visit, `/fp trainers` says none recorded.
- [ ] Open a profession trainer (e.g. a Tailoring trainer in a capital): while the window is open the list shows available, too-advanced and already-known recipes (the filters were switched on); on close the filters are back to what they were. No Lua error.
- [ ] `/fp trainers` lists the trainer with zone and recipe count; `/fp recipe <a recipe that trainer teaches>` prints "trainer <name> (<zone>)" and the required skill matches the trainer window exactly. Compare three recipes, including one above your skill and one you already know.
- [ ] A goal for a trainer recipe above your skill now reads "needs <profession> <rank>; <you> has <skill>" instead of being treated as learnable; at or above the rank the route is the craft and the message names the trainer and zone.
- [ ] Log in on an alt: the requirements recorded by the first character are there (`/fp trainers`), and the alt's planner uses them.
- [ ] Open a class trainer: nothing is recorded (`/fp trainers` unchanged). Open a riding trainer: nothing is recorded.
- [ ] With `/fp debug` on, the chat shows "Recorded trainer <name> (<zone>): N recipes" once per open, not in a loop.
- [ ] 0.10.3 raw materials: a goal that needs Medium Leather (Dark Leather Cloak) on a leatherworker who knows the "Medium Leather" and "Light Leather" refines: the tree stops at Medium Leather (no Light Leather or scraps rows), "Recommended next" says "Obtain 8 x Medium Leather" with badge "Gather - Skinning" when someone has Skinning, "Buy" otherwise; the node's craft card reads "Gathering material: refining the tier below is off by default". "Use crafting route" on it expands to Light Leather only; Light Leather in turn stays a leaf. Bolts still expand into cloth, Copper Bar into Copper Ore, Cured Light Hide into hide and salt.
- [ ] 0.10.2 train step: a goal for a trainer recipe you have the profession for but not the recipe shows, under the item in the Dependency Tree, a book-icon row "Train - <trainer> (<zone>)" with "needs <profession> <rank>" and the training cost (or "Train - <profession> trainer" before a visit); selecting it shows where to train. The shopping list has it under "To learn" with the cost counted in the total and the affordability verdict; "Send to chat" prints the "Train ..." line; ticking it marks it done. CraftWise lists "Train: <recipe>" with choice Train and adds the cost to craft and hybrid, not buy. The Dashboard never lists the step as a missing material.

### 20. 0.11.0 learn-recipe and reach-skill goals (not yet run in game)

- [ ] `/fp learn bolt of woolen cloth` on a character without Tailoring: the goal says you lack the profession; with Tailoring below the requirement it says "Needs Tailoring N" and the Dashboard's next step is "Reach Tailoring N".
- [ ] A learn goal for a trainer recipe shows a single "Train" row in the Dependency Tree and "Train: ..." on the shopping list; after visiting the trainer the row names the trainer, zone and cost.
- [ ] A learn goal for a pattern recipe (`/fp learn sulfuron hammer`) plans the pattern as the item to get with its sources; with the pattern in your bags it says to read it.
- [ ] Learning the recipe (train it, or read the pattern) completes the goal with the "Recipe learned" toast.
- [ ] My Goals: the Recipe segment adds by name; the Skill segment takes "Tailoring 225" (or just the profession for the next cap).
- [ ] `/fp skill tailoring` on a character whose Tailoring window has been recorded: the Crafting hero shows "Tailoring N / cap", the message lists the recipes with their skill ranges and craft counts, the Dependency Tree shows the skill root with one "Craft for skill" row per recipe and the reagents below, the Requirements tab and the shopping list hold only reagents (never the outputs), CraftWise prices the craft path.
- [ ] The Dashboard's next step is "Craft N x <recipe> (skill a-b)" once the first recipe's reagents are on hand, "Obtain ..." otherwise.
- [ ] Every skill-up moves the hero bar and the tracker; reaching the target completes the goal with the "Skill reached" toast.
- [ ] A target above the cap says the cap must be raised; a profession whose window was never recorded asks for it.

### 21. 0.12.0 quest goals and the Quests screen (not yet run in game)

- [ ] The Quests screen lists dungeon quests (ForeverDungeonJournal) and attunement quests (Attune) by instance, plus every quest in your log under its zone; levels are coloured like the default UI; the footer shows "Quest log N / 20".
- [ ] Clicking a quest shows level, place and giver, the objective text (or live objectives with bars when the quest is in your log), the prerequisite chain with done marks, reward icons and text.
- [ ] A quest in your log: Link puts the quest link in the chat box, Watch adds it to the objective tracker.
- [ ] `/fp quest leaders of the fang` (or the Quest segment on My Goals) adds the goal; the Dashboard's next step says which prerequisite to pick up first and from whom; the tracker shows the same.
- [ ] Accepting, progressing and turning in quests of the chain updates the goal within a second (no `/reload`); turning in the final quest completes the goal with the "Quest complete" toast.
- [ ] With an obtain goal for a quest reward (e.g. Slick Deviate Leggings), the By goal tab lists Deviate Hides under that goal and the details say "1 missing for ...".
- [ ] A quest the addons do not know: `/fp quest <name>` finds it in your log; a quest id nobody knows shows "Quest <id>" until the client loads its title.

### 22. 0.13.0 Equipment screen (not yet run in game)

- [ ] The Equipment screen lists all seventeen slots with icons, names and the average item level; the header says which GearQuest spec the hunts are for.
- [ ] A slot whose equipped item is GearQuest's top pick shows "Best in slot"; a slot with a better pick shows "Upgrade found"; empty slots show "Empty".
- [ ] Clicking a slot shows the equipped item, the target card with GearQuest's best pick (source and zone), the stat comparison with green and red deltas, and the other options with "+ Goal" buttons.
- [ ] "+ Goal for target" adds a crafting or obtain goal; the slot row then shows the goal line with its progress and the strip's "Upgrades planned" count rises; "Open goal" opens it on Crafting.
- [ ] The obtain goal for a GearQuest quest reward or vendor item shows that source ("Quest reward: ...", "Vendor: ...") on the Crafting screen and the Dashboard.
- [ ] "Upgrades only" dims the other slots; "Source: Vendors" limits the picks; both survive a `/reload`.
- [ ] Equipping a different item updates the screen within a second.
- [ ] Without GearQuest Forever the screen still shows what is worn and the goals, and says hunts are unavailable.

### 23. 0.14.0 reputation goals and the Reputations screen (not yet run in game)

- [ ] The Reputations screen lists your factions under the client's headers with the standing and a bar through it; the footer counts factions and goals.
- [ ] Clicking a faction shows the standing, the "into it" numbers, the target segment defaulting to the next standing, the reputation still needed, the dungeon quests that give reputation (with their state) and the items the target standing unlocks (needs AtlasLoot's Factions module; the first open loads it).
- [ ] "+ Add goal" creates the goal; the Dashboard's next step names an open quest that gives reputation, or the amount still needed; the tracker shows the standing.
- [ ] Earning reputation moves the goal's bar within a second; reaching the standing completes it with the "Reputation reached" toast.
- [ ] `/fp rep argent dawn exalted` and the Reputation segment on My Goals add goals; `/fp reps` lists factions.
- [ ] An obtain goal for an item a reputation vendor sells (e.g. Pattern: Argent Boots) shows "Reputation reward: Argent Dawn (Honored)" as its source, marked unavailable with the reason until the standing is reached.
- [ ] (0.15.1) With a reputation goal open, the Quests screen's "By goal" tab lists every open dungeon quest that gives that faction reputation under the goal; the quest panel says "+N <faction> reputation for <goal>"; `/fp quests` lists them.

### 24. 0.15.0 enchant goals (not yet run in game)

- [ ] Open the Enchanting window: `/fp status` reports the profession with "(N enchants)" and the Crafting screen's enchant goals show "Known" for enchants you have. If the client's schematic for an enchant carries no `recipeType`, the catalogue flag still records it (check `/fp recipe` is unaffected).
- [ ] Shift-click an enchant in the Enchanting window with the ForeverPath window open: the link lands in the focused input (or the header search) and Enter adds "Cast 1x Enchant ..." (the status bar says "Recipe link received"). Shift-clicking an item recipe adds a goal for the item it makes.
- [ ] `/fp enchant crusader 2` and the Enchant segment on My Goals (with the stepper for the cast count) add goals; the Crafting screen shows the Enchanting line, the Known / Not learned chip, "0 of 2 casts", the reagents table, and the tree with the enchant as the root ("2 casts", "Cast - Enchanting").
- [ ] An enchant you do not know shows the formula (with its sources) or "Visit an Enchanting trainer"; after a trainer visit it names the trainer and the required skill.
- [ ] Casting the enchant (on your own gear or a trade window) moves the goal to "1 of 2 casts" within a second; the second cast completes it with the "Enchant applied" toast. A cast by someone else, or a different spell, does not count.
- [ ] `/fp skill enchanting` plans enchants you know (reagents only, nothing to buy for the enchant itself); the dashboard says "Cast N x Enchant ..." once the reagents are in the bags.
- [ ] Engineering tinkers (Tinker: Nitro Boosts) behave as enchants.

### 25. 0.16.0 type-ahead and unmet factions (not yet run in game)

- [ ] On My Goals, pick a kind and type two or more characters: a popup lists matches with a note on the right (Item, "Tailoring recipe", "You are at 150", "Neutral", "Not met yet", a dungeon name); clicking one adds the goal and clears the input. The popup hides when the input loses focus or a kind is picked.
- [ ] Reputation: "cenarion ex" suggests "Cenarion Circle - Exalted" marked "Not met yet" for a character who has never met them; the goal plans from Neutral 0 (2000 for a druid) and the Reputations panel copes with it. Once the faction appears in your pane the live standing takes over.
- [ ] The header search suggests a few of every kind and opens the goal's screen on a pick.
- [ ] Narrow the window: the New Goal bar puts the kind segment on a second row instead of pushing the input off the panel; widen it and the bar returns to one row.
- [ ] `/fp status` reports "N in the client's faction table".
- [ ] (0.16.2) Item kind, type "storm": the popup lists "Storm..." items first but also names with "storm" later in them (and boss drops from ForeverDungeonJournal, GearQuest gear once your class module is loaded), eight at most.
- [ ] (0.16.1) With the Auction House open on Auctionator's Shopping tab, Shift-click a shopping-list row: Auctionator searches for the item and the status bar says "<item> linked". With a chat box open the link lands there instead. With neither, the link is printed to chat. The same works on the crafting requirements, the tree, the dashboard, the tracker and the Equipment screen; a plain click still does what it did.

### 26. 0.17.0 questlines (not yet run in game)

- [ ] On a shaman, add "Rage of the Storm" as an item goal (type it on My Goals; it is a GearQuest / Attune name). The crafting hero shows "Quest reward: The Tempest's Weapons" and "Call of Air - N of 8 steps"; the next step names the first chain quest and its zone; the dashboard, tracker and My Goals row carry it. On a non-shaman the goal still says "Reward from The Tempest's Weapons" with no chain.
- [ ] Talk to the quest giver of the chain's next quest: as the quest window opens, `/fp status` counts one more quest with facts, and from then on the next step says "from <NPC> in <zone>"; "Set waypoint" appears on the hero and pins the giver on the map (the minimap tracks it). Check the pin lands where the NPC stands (positions are recorded at the moment the window opens).
- [ ] Accept a quest with item objectives (Storm, Earth, and Fire: the four totems): the quest's items appear on the requirement rows, the tree (below the reward) and the shopping list within a second; names that the client has not shown yet resolve once the first one drops. Kill counters never become items.
- [ ] `/fp quest the tempest's weapons`: the chain is printed with [x] / [>] markers, the giver and the items. `/fp quest` for a quest in the log prints "Needs: N x <item> (have/need)".
- [ ] Quests screen, select a chain quest: the side panel lists the numbered chain steps, "Bring N x" lines and the giver in the meta line; the Waypoint button shows only when a position is known and pins the giver, or the turn-in once the quest is ready.
- [ ] Turn a quest in: the reward window records the turn-in NPC; the chain moves to the next quest; the last turn-in completes the quest goal as before, and the item goal completes when the reward lands in the bags.
- [ ] An attunement whose chain has either/or starts (Call of Air from two givers) shows both until one is done, then only the taken one.
- [ ] Log in on an alt: the facts learned on the first character are there (account-wide).
- [ ] (0.17.3) Attunements screen, Call of Air: click Storm, Earth, and Fire. The side panel reads "Step 6 of 8" with state, pick-up, turn-in, the four "Bring: 5 x ..." lines with your bag counts and the drop zones; "Waypoint" pins Prate Cloudseer; "Quests >" opens the quest on the Quests screen. Click the same step again to return to the current step. A quest in your log lists its live objectives.
- [ ] (0.17.2) With the totems on the requirements table and the shopping list, every source tag ends inside the Source column (an ellipsis cuts long ones, the full text is in the row tooltip); the note under Rage of the Storm says "Two-Handed Maces".
- [ ] (0.17.1) Before any quest window has been opened, "Rage of the Storm" as a goal already says "Pick up Call of Air from Searn Firewarder in Orgrimmar" (or Xanis Flameweaver / Eldrun Stormbreaker), `/fp status` says "12 quests shipped", and the Quests side panel for Storm, Earth, and Fire lists "Bring 5 x Twisted ... Totem" with "Drop: ..." sources on the shopping list. Check the shipped pins against where the NPCs stand (Prate Cloudseer, Rau Cliffrunner, Veyric Thunderhame, Bath'rah the Windwatcher) and report any that are off.

### 27. 0.18.0 classic data (not yet run in game)

- [ ] Install both folders from the zip. After `/reload`, `/fp status` shows "Classic data: 4143 quests, 2216 NPCs, 313 objects from CMaNGOS classic-db ec4f5961". The AddOns list shows "ForeverPath Classic Data" as load-on-demand. If it says "not loaded", report the reason in brackets.
- [ ] `/fp quest the forgotten pools` (or any classic quest outside the dungeon journal): the goal names the giver and zone, "Set waypoint" pins them, and `/fp quest` prints "(classic data)". Check a few pins against where the NPCs actually stand on Forever; Forever moved some.
- [ ] A classic chain: add the last quest of a chain you have not started (for example a Horde "Leaders of the Fang" without the journal, or any class quest). The goal walks the chain from its first quest, with the items each quest asks for on the shopping list.
- [ ] A reputation goal (e.g. Stormwind, Darkspear Trolls): the Reputations screen and the Quests screen list classic quests that reward it, for your faction only.
- [ ] Item search and the Quests screen still behave, and login is not noticeably slower (the data is about 1 MB of Lua).
- [ ] (0.19.0) A vendor reagent you have never seen at a merchant (e.g. Coarse Thread, Fine Thread) has a price on the shopping list and a "Buy from <vendor> ... (classic data)" source; visiting a merchant that sells it replaces both.
- [ ] (0.19.0) A trainer-taught recipe you have never seen at a trainer: the learn-recipe goal names the classic trainer, zone, required skill and cost; visiting a trainer replaces it.
- [ ] (0.19.0) An item goal for a mob drop (e.g. a leather or a cloth) lists "Dropped by ..." with zone, chance and level; a herb or ore lists "Gathered from <node>" and says who has the skill; a rare green lists the drop for information but the route stays the Auction House.
- [ ] Disable "ForeverPath Classic Data" in the AddOns list: ForeverPath still loads, `/fp status` says the data is not loaded, and everything Forever-specific still works.

### 28. 0.20.0 loot learner and item names (not yet run in game)

- [ ] Kill and loot a few mobs: `/fp status` counts items and sources; `/fp sources <item>` (or the item's source tags) shows "Dropped by <mob> - <zone> - seen N times in M loots on Forever" first. Check the mob's name is right when it was not your target (it comes from classic data then).
- [ ] Skin a corpse you looted: the leather lists "Skinned from <mob>". Mine or pick a node: "Looted from <node>". Fish: "Fished in <zone>".
- [ ] Area loot (several corpses in one window) counts each corpse.
- [ ] Type a Forever-only item name you have never seen (a GearQuest pick, a new dungeon drop) on My Goals: it is found. An item nobody has data for says "New in Forever".
- [ ] Report whether `GetLootSourceInfo` returns GUIDs on Forever (if not, nothing is learned and the status stays at 0).

### 29. 0.21.0 farming, zones, training (not yet run in game)

- [ ] An item goal for a mob drop: the dashboard's next step starts "~N kills of <mob>"; the shopping list row note shows the zone and the estimate; "Sort: Zone" groups rows by zone.
- [ ] `/fp train`: your professions with the recipes you can train now (trainer, zone, cost) and the next ones; recipes you know are left out once the profession window has been opened.

### Reporting
Include: client build (`/dump GetBuildInfo()`), `/fp status` output, the step
that failed, chat output with `/fp debug` enabled, and `/fp errors`.
