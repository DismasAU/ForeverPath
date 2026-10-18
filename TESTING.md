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

### Reporting
Include: client build (`/dump GetBuildInfo()`), `/fp status` output, the step
that failed, chat output with `/fp debug` enabled, and `/fp errors`.
