# Handoff: ForeverPath — WoW: Forever addon UI

## Overview
ForeverPath is a progression-planning addon for World of Warcraft: Forever. The player picks a goal (craft an item, finish an attunement, reach a reputation tier). The addon shows what is needed, what the player already has, what is missing, where to get it, what it should cost (CraftWise), and the next practical step.

This package covers 11 screens/states (01–08 and 12–14) plus a component sheet, a design-system reference and layout/implementation notes (09–11). Full-resolution renders of every slide (3840 × 2160) are in `screenshots/`.

## About the design files
The files in `design/` are **design references built in HTML**. They show the intended look and content. They are not production code. Rebuild the UI in the target environment:

- **Primary target:** a WoW addon (Lua + FrameXML / XML templates). Use frames, textures, FontStrings, ScrollBox (or FauxScrollFrame on older clients), GameTooltip and saved variables.
- **If you are building clickable mockups first** (for example a web prototype), use any component framework, but keep the structure below so it maps 1:1 to WoW frames later.

To view the references, open `design/ForeverPath Mockups.dc.html` in a browser (keep all files in the same folder). Use the arrow keys to move between slides.

`design/component-helpers.js` is the generator that produced the markup. It's the clearest single source for exact component styles: `panel`, `btn`, `tabs`, `seg`, `table`, `tree`, `bar`, `badge`, `tag`, `chip`, `cb`, `counter`, `money`, `icon`, `header`, `sidebar`, `status`, `win`. Read it for exact values.

## Fidelity
**High fidelity.** Colours, type sizes, spacing, row heights and content are final for v1. Two exceptions:
- **Icons:** the item and class icons are original placeholder art (simple SVG glyphs on a radial tile). In the addon, use the real in-game icons (`GetItemIcon(itemID)` / `C_Item.GetItemIconByID`, and the class icon atlas). Keep the 1 px quality-coloured inner border.
- **Fonts:** Marcellus (headings) and Alegreya Sans (body/data) stand in for the client fonts. Either bundle them in the addon's `Fonts/` folder, or map Marcellus → `Fonts\FRIZQT__.TTF` and Alegreya Sans → `Fonts\ARIALN.TTF`.

The window is authored at **1000 × 700 at UI scale 1.0**. The slides show it scaled 1.32× over an illustrative backdrop. Every px value below is at 1.0.

---

## Design tokens

### Colours
| Token | Hex | Use |
|---|---|---|
| bg | `#171714` | Window body |
| panel | `#24231F` | Panels |
| raised | `#302D26` | Selected/hovered row |
| sidebar | `#1C1B18` | Sidebar, table header, panel footers |
| inset | `#0E0E0C` | Inputs, bar tracks (`#0D0D0B`) |
| statusbar | `#11110E` | Bottom status bar |
| bronze | `#8F7140` | Window border, header bottom border |
| bronze-dim | `#6E5A36` | Control borders, selected-row outline, tab border |
| line | `#3A3529` | Panel border, dividers |
| line-dark | `#4A4335` | Input border, tag border, tree guides `#5F5543` |
| gold | `#D7B66A` | Headings, primary accent, current step |
| gold-light | `#F3DFA6` | Active nav/tab text |
| text | `#E8DFCC` | Primary text |
| text-2 | `#A9A18E` | Labels and metadata |
| text-3 | `#7D745F` | Disabled, separators, inactive nav icons |
| ok | `#64AE76` | Have / complete / fresh data |
| partial | `#D9A441` | Partial / in progress / aging data (3–24 h) |
| missing | `#D67A62` | Missing / blocker / stale data (>24 h) |
| info | `#6F9FCA` | Links, snapshot data, alt-related info |

Item quality colours (item names only): Poor `#9D9D9D`, Common `#F2EEE6`, Uncommon `#1EFF00`, Rare `#3B8EEA`, Epic `#B048F8`. Quality inner borders on icons: common `#6B6352`, uncommon `#1F8F12`, rare `#2A6FC0`, epic `#7A2AB8`.
Class colours: Warrior `#C79C6E`, Druid `#FF7D0A`, Hunter `#ABD473`.
Coin dots: gold `#E6C25A`, silver `#C3C8CC`, copper `#C07A45`. In-game, use `GetCoinTextureString`.

### Typography
| Role | Font | Size | Notes |
|---|---|---|---|
| Window title | Marcellus | 18 | gold |
| Tagline | Alegreya Sans | 9 | caps, +0.12em, text-2 |
| Item hero name | Marcellus | 22 | quality colour |
| Goal name | Marcellus | 15 | |
| Panel heading | Marcellus | 12 | caps, +0.08em, gold |
| Big numbers | Marcellus | 17–27 | tabular |
| Body | Alegreya Sans | 13 | line-height 1.3 |
| Secondary | Alegreya Sans | 12 / 11.5 | text-2 |
| Data label / table header | Alegreya Sans Bold | 10.5 | caps, +0.08em, text-2 |
| Badge | Alegreya Sans Bold | 10 | caps, +0.06em |
| Notes under names | Alegreya Sans | 10.5 | text-2 |
All numbers use tabular lining figures.

### Spacing and sizes
- Window 1000 × 700, min 820 × 560, max 1400 × 960.
- Header 46 px. Sidebar 142 px. Status bar 24 px.
- Content padding 12 px top/bottom, 14 px left/right. Gap between panels 10 px.
- Panel: header 28 px, body padding 10 px.
- Row heights: compact list 30–31, table 34–40, tree 38, tracker 20, nav 31.
- Controls: buttons 24 px tall with 10 px horizontal padding. Inputs 24. Tabs 25 (27 when active). Segments 22. Badges and tags 16.
- Icons: 16 (tracker), 18–22 (lists), 24–28 (tables/tree), 36–42 (goal rows), 64 (hero).
- Border radius 0 everywhere, except circular portraits/nodes and tooltips (3 px).

### Frames and effects
- **Window:** 1 px `#8F7140` border, then rings of 1 px `#000`, 2 px `#2A251C` and 1 px `#000`. Drop shadow `0 24px 70px rgba(0,0,0,.8)`. Small 7 px bronze diamond rivets at the four corners.
- **Panel:** 1 px `#3A3529` border, then 1 px `#000` outer ring, and an inset 1 px top highlight `rgba(255,255,255,.03)`. Header gradient `#2C2A24 → #24231F`, with a 1 px black bottom border and a 1 px `rgba(255,255,255,.04)` line under it (an engraved divider).
- **Button (default):** gradient `#3A352B → #24211C`, 1 px `#6E5A36` border, text `#E8DFCC`.
- **Button (primary):** gradient `#6A5224 → #3E2E12`, 1 px `#D7B66A` border, text `#FBEBC0`.
- **Close button:** gradient `#6A2418 → #3A120C`, 1 px bronze border.
- **Selected row:** bg `#302D26` with an inset 1 px `#6E5A36` outline.
- **Missing row tint:** `rgba(214,122,98,.07)`. **Partial row tint:** `rgba(217,164,65,.045)`.
- **Progress bar:** track `#0D0D0B` with 1 px `#3D382D` border. Vertical gradient fill (for example gold `#D7B66A → #8A6A2A`, ok `#64AE76 → #2F6A3E`). Black tick marks every 10 %.
- **Recommended card:** bg `#2B2619`, 1 px gold border, glow `0 0 16px rgba(215,182,106,.14)`. A gold "RECOMMENDED" tab at top right.
- **Tooltip:** bg `rgba(9,10,18,.96)`, 1 px `#7A7A86` border, 3 px radius, section headers `#FFD100`. Matches GameTooltip.

---

## Shell (shared by screens 01–07)
- **Header (46 px, gradient `#2E2B25 → #1F1E1A`, bronze bottom border).** From left to right:
  - Compass emblem: 30 px circle with a gold diamond.
  - "ForeverPath" title with the tagline "Your World. Your Goals. Your Path."
  - A divider, then the character name in class colour with "Level 60 Warrior · Stormhold".
  - A flexible spacer, then the active-goal pill (22 px icon, "ACTIVE GOAL" label, goal name, 42 %, ▼). Clicking it opens the goal switcher.
  - Search field (176 px).
  - Settings button (24 px).
  - Close button (24 px).
- **Sidebar (142 px, `#1C1B18`).** Nav items 31 px tall: Dashboard, My Goals (count 3), Crafting. Then a divider and a "PREVIEW MODULES" label, followed by Equipment, Quests, Reputations, Attunements, Characters. The active item has a `#6E5A36` border, gradient `#3A3428 → #2A2720` and gold-light text. The footer shows "3 active goals / 11 completed".
- **Status bar (24 px, `#11110E`).** Status dot + "Bags & bank synced · 12s ago", dot + "AH prices: cached scan · 2h 14m old", alert "Heart of Fire: only 2 listings seen" in missing red, a spacer, "ForeverPath 0.9.2 · CraftWise 0.4", and a resize grip.
- **Content area:** flex column with 10 px gaps. Background `#171714` with a faint 4 px dot texture.

## Screens

### 01 Main Dashboard (nav: Dashboard)
Purpose: show at a glance what the addon does, the goals, the blockers and the next step.
- **Character strip (panel, no header):** 46 px portrait (class crest), name and race/class, then four stat cells separated by engraved dividers: Blacksmithing 290/300 (gold bar), Mining 300/300 (green bar), Gold on hand 214g 36s, Goals "3 active · 11 done".
- **Two-column grid below it:** `1fr | 268px`.
  - **Left, "Active Goals" panel** (flexes to fill; header link "Manage goals ›"). Three goal rows (bg `#1C1B18`, 1 px `#33302A`). Each row has a 42 px icon, the name, a type badge, the % on the right, an 8 px bar and a detail line:
    1. Emberforged Greatsword (Rare blue) · Crafting · 42 % · "Missing: 12 Thorium Bar, 3 Essence of Fire, 2 Heart of Fire, +2 more" · Est. 31g 62s
    2. Onyxia's Lair Attunement · Attunement · 55 % · "Current: step 7 of 11 · Jail Break! · Blackrock Depths" · Group quest
    3. Thorium Brotherhood · Revered · Reputation · 62 % (green bar) · "Honored · 7,440 / 12,000" · 4,560 to go
  - **Left, "Recommended Next" panel.** Three numbered steps (24 px circle numerals), each with a title, a detail line and a trailing badge or amount:
    1. Smelt 6 Thorium Ore at a forge · +6 THORIUM BAR
    2. Buy 3 Essence of Fire and 2 Heart of Fire · 23g 20s
    3. Mail 1 Rugged Hide to Miravelle to cure · ALT
  - **Right, "Missing Materials" panel.** Rows 31 px: 22 px icon, name and source, red ×count. Contents: Thorium Bar ×12, Essence of Fire ×3, Heart of Fire ×2, Cured Rugged Hide ×2, Elemental Flux ×2, Rugged Hide ×1, Dark Iron Ore ×16. Footer: "Open shopping list ›".
  - **Right, "CraftWise" panel (226 px).** 25 px total "31g 62s" with "Hybrid plan · saves 46g 38s" in green. Key-value rows: Buy finished item 78g 00s, Buy all materials 49g 42s, Hybrid · recommended 31g 62s (gold). Footer: cached-scan dot and a Compare button.

### 02 Crafting Goal Details (nav: Crafting)
- **Breadcrumb:** "My Goals › Crafting › Emberforged Greatsword", with "Show in tracker" (checked) and "Remove goal" on the right.
- **Hero panel:** 64 px icon. Name 22 px in rare blue. "Two-Hand Sword · Item Level 63 · Binds when equipped". Chips: ✓ Blacksmithing 285 · you have 290, ✓ Plans known, • Anvil and forge required. Quantity stepper (− 1 +). Completion block: 42 %, a 10 px bar, "15 of 36 reagents in your bags".
- **Tabs:** Requirements (active), Dependency Tree, CraftWise, Notes. On the right: "Include alts' bags" checkbox and a "Sort: Missing" dropdown.
- **Requirements table** (rows 40 px). Columns: Material | Need 40 | Have 40 | Missing 54 | Unit price 74 | Subtotal 74 | Source 150. Have is coloured green, amber or red.

  | Material | Need | Have | Missing | Unit price | Subtotal | Source |
  |---|---|---|---|---|---|---|
  | Thorium Bar | 20 | 8 | 12 | 1g 20s | 14g 40s | ⚒ Smelt, AH |
  | Cured Rugged Hide | 2 | 0 | 2 | 5g 75s | 11g 50s | ⚒ Alt: Miravelle, AH |
  | Essence of Fire | 4 | 1 | 3 | 6g 50s | 19g 50s | AH, Drop |
  | Heart of Fire | 2 | 0 | 2 | 1g 85s | 3g 70s | AH, Drop |
  | Elemental Flux | 2 | 0 | 2 | 16s | 32s | Vendor |
  | Star Ruby | 2 | 2 | ✓ | 3g 10s | — | In bags |
  | Rugged Leather | 4 | 4 | ✓ | 45s | — | In bags |

  Footer: "Buy all missing: 49g 42s", "CraftWise route: 31g 62s", buttons "Open CraftWise ›" (primary) and "Add to shopping list".
- **Hover state shown:** the Heart of Fire row is highlighted, with a GameTooltip listing its sources (AH listings with price age, drop locations, characters that own it).

### 03 Recursive Dependency Tree (nav: Crafting)
- **Toolbar:** "▾ Expand all", "▸ Collapse all", Show segment [All | Unresolved only], and a legend (Have / Partial / Missing / ⚒ Craftable / AH Purchasable).
- **Tree panel** (flex). Columns: Component | Have 44 | Status 70 | Get via 104 | Est. cost 62. Rows are 38 px. Each depth level adds an 18 px guide column with 1 px `#5F5543` lines and elbows. The vertical line stops at mid-row on the last child. Each row has a chevron (▾/▸), an icon (28 at depth 0, 24 below), the name, ×qty and a note line.
  ```
  Emberforged Greatsword ×1        —      [42%]     ⚒ Blacksmithing   31g 62s
  ├ Thorium Bar ×20  (selected)    8/20   Partial   ⚒ Smelt, AH       5g 70s
  │ └ Thorium Ore ×12              6/12   Partial   AH, Mine          5g 70s
  ├ Cured Rugged Hide ×2           0/2    Missing   ⚒ Alt, AH         2g 40s
  │ ├ Rugged Hide ×2               1/2    Partial   AH, Skin          2g 40s
  │ └ Refined Deeprock Salt ×2     2/2    Have      In bags           —
  ├ Essence of Fire ×4             1/4    Partial   AH, Drop          19g 50s
  ├ Heart of Fire ×2               0/2    Missing   AH, Drop          3g 70s
  ├ Elemental Flux ×2              0/2    Missing   Vendor            32s
  ├ Star Ruby ×2                   2/2    Have      In bags           —
  └ Rugged Leather ×4              4/4    Have      In bags           —
  ```
  Footer: "3 of 10 dependencies resolved", progress bar, unresolved cost 31g 62s.
- **Selected Node panel (252 px):** Thorium Bar, 8 / 20 with "12 missing" and a bar. Under "Ways to get 12 more", three option cards; the best one has a gold border and a BEST badge:
  - Smelt from Thorium Ore · 5g 70s (best)
  - Buy on AH · 14g 40s
  - Mine Thorium veins · no gold cost
  Then "Also used by: Ironvein Bracers ×10", and buttons "Use smelting route" (primary) and "Link".

### 04 CraftWise Cost Comparison (nav: Crafting)
- **Top bar:** item icon, name and quantity, a CACHED badge, "AH scan 2h 14m ago · Ironforge" and a "Rescan at Auction House" button.
- **Three strategy cards** (equal columns, 304 px tall):
  - **Buy finished item, 78g 00s.** Lowest listing 78g 00s, average of the last 7 scans 84g 50s, availability "Low · 3 listed" (red), expenditure 78g 00s. Footer: "46g 38s more than Hybrid".
  - **Craft item, 49g 42s.** Missing materials 49g 42s, owned contribution 29g 80s in bags, profession Blacksmithing 285 ✓, total 49g 42s. Footer: "17g 80s more than Hybrid".
  - **Hybrid strategy, 31g 62s (RECOMMENDED).**
    - Buy: 6 Thorium Ore, 3 Essence of Fire, 2 Heart of Fire, 2 Elemental Flux.
    - Craft: smelt 12 Thorium Bar; Miravelle cures 2 Rugged Hide.
    - Use owned: 8 Thorium Bar, 2 Star Ruby, 4 Rugged Leather, 2 Deeprock Salt.
    - Footer: "Saves 46g 38s (59%)" and a "Use this plan" primary button.
- **Breakdown table** (27 px rows). Columns: Component | Buy (AH) | Craft path | Hybrid | Choice | Price data. The price-data column uses a freshness dot: green under 3 h, amber 3–24 h, red over 24 h, blue for a fixed vendor price. Heart of Fire is "2 days · stale". The total row shows 49g 42s vs 31g 62s.
- **Footnote:** illustrative prices from the player's last scan, not live.

### 05 Material Shopping List (nav: Crafting)
- **Header row:** "Shopping List" plus three goal chips with checkboxes (Emberforged Greatsword ×1, Ironvein Bracers ×2, Thorium Brotherhood turn-ins), and "Send to chat".
- **Summary strip:**
  - Estimated total: 71g 64s
  - Auction House: 6 items · 71g 00s
  - Vendor: 1 item · 64s (marked bought)
  - Materials in hand: 23 / 90 units (26 % bar)
- **Filter tabs:** All · 9, Auction House · 6, Vendors · 1, Gathering · 3, Craftable · 2. Plus a sort dropdown.
- **Table** (35 px rows). Columns: ☐ | Material | Total | Owned | Reserved | Missing | Est. cost | Get from.

  | Material | Total | Owned | Reserved | Missing | Est. cost | Get from |
  |---|---|---|---|---|---|---|
  | Dark Iron Ore | 20 | 4 | — | 16 | 24g 00s | AH · 1g 50s ea, Mine |
  | Thorium Ore | 22 | 6 | — | 16 | 15g 20s | AH · 95s ea, Mine |
  | Essence of Fire | 4 | 1 | — | 3 | 19g 50s | AH |
  | Star Ruby | 4 | 3 | 1 | 2 | 6g 20s | AH |
  | Heart of Fire | 2 | 0 | — | 2 | 3g 70s | AH, Drop |
  | Rugged Hide | 2 | 1 | — | 1 | 2g 40s | AH, Skin |
  | Thorium Bar | 30 | 8 | — | 22 | via ore | ⚒ Smelt |
  | Cured Rugged Hide | 2 | 0 | — | 2 | via alt | ⚒ Miravelle |
  | Elemental Flux | 4 | 0 | — | 4 | 64s | Vendor (checked, 50 % opacity, name struck through) |

  Footer note: "Reserved = owned, but held for a paused goal". Button: "Clear bought".

### 06 Attunement Planner (nav: Attunements)
- **Header panel:** amulet icon, "Onyxia's Lair Attunement", "Raid attunement · Alliance quest chain · Level 60 · reward: Drakefire Amulet". Chips: ✓ Seal of Ascension owned, ✕ Blood of the Black Dragon Champion, • No reputation requirement. Progress: 6 of 11 steps, 55 %.
- **Quest Chain panel (262 px):** a vertical timeline with 38 px rows.
  - Done steps: 16 px green filled node with ✓ and a green connector.
  - Current step: 18 px gold ring with a dot and a glow; the row is highlighted and carries a CURRENT badge.
  - Remaining steps: 14 px hollow `#6B6352` node and a `#4A4335` connector.
  - Steps:
    1. Dragonkin Menace
    2. The True Masters
    3. Marshal Windsor
    4. Abandoned Hope
    5. A Crumpled Up Note
    6. A Shred of Hope
    7. **Jail Break! (current)**
    8. Stormwind Rendezvous
    9. The Great Masquerade
    10. The Dragon's Eye
    11. Drakefire Amulet
  - Quest names come from memory of the Classic chain. **Verify them against WoW: Forever data.**
- **Current Step panel:** the step title and description, two objective checkboxes, chips (Group quest · 5 players / Blackrock Depths / Quest in log), and buttons Show on map and Link quest.
- **Prerequisites panel:** this uses the **same tree component as screen 03** (column headers Requirement / Effort):
  - Drakefire Amulet
    - Steps 7–10
    - Blood of the Black Dragon Champion
      - General Drakkisath
        - Seal of Ascension (Have)
    - Reputation (Not needed)

### 07 Account-Wide Characters (nav: Characters)
- **Info banner** (bg `#1B222A`, 1 px `#4A6A8A`): "Miravelle already has 12 of the required materials." Detail: 6 Thorium Ore, 3 Essence of Fire, 2 Dark Iron Ore, 1 Rugged Hide; saves about 30g 60s. Buttons: Plan mail (primary) and Dismiss.
- **Scope row:** segment [This character | Account-wide] with Account-wide active. Legend: Live / Snapshot / Cached.
- **Three character cards** (equal columns). Each has a header (38 px crest portrait, name in class colour, level/race/class, data badge) and four sections: Professions (bars), Relevant materials (32 px icons with count overlay), Assigned goals, Can craft.
  - **Thandrel** · LIVE · Blacksmithing 290, Mining 300 · Crafter for the Greatsword and Bracers.
  - **Miravelle** · SNAPSHOT · 2H · Leatherworking 255, Skinning 270. Materials needed by an active goal get a 1 px gold outline (offset 1). Assigned "Cure 2 Rugged Hide".
  - **Brakkor** · CACHED · 3 DAYS (amber) · card desaturated (saturate .6) · Enchanting 180, Tailoring 165 · no goals · note "Log in on Brakkor to refresh".

### 08 Compact Goal Tracker (separate frame, not the main window)
- **Size:** 262 px wide. Docked under the minimap in the slide (x ≈ 1528 / 1920 at 1.32×). Draggable.
- **Frame:** bg `rgba(14,14,12,.86)`, 1 px `#3A3529`, soft shadow. No heavy border, so it stays unobtrusive.
- **Header (22 px):** drag grip (dot texture), 12 px emblem, "ForeverPath" (Marcellus 11 gold), pager "‹ 1/3 ›", collapse "–" and expand "□" buttons (15 px). Expand opens the main window on this goal.
- **Body (8 px padding, 6 px gap):**
  - Goal icon (28) with the name and "42% · 7 unresolved"
  - 6 px bar
  - Three requirement rows (20 px): 16 px icon, name, counter
  - "+4 more · 31g 62s to finish"
  - Divider, then "NEXT" (10 px bold gold) and "Smelt 6 Thorium Ore at a forge"
- **Collapsed state:** header only, with the goal name and % inline.
- **Paged state:** goal 2/3 shows the attunement with its current step as NEXT.

### 12 My Goals (nav: My Goals)
- **New goal bar (panel):** "NEW GOAL" label, item-link input ("Shift-click an item link, or type a quest, faction or raid…"), type segment [Item | Quest | Reputation | Attunement], quantity stepper, "+ Add goal" primary button.
- **Goal list panel (flex):** tabs Open · 5 / Completed · 11 with a "Sort: Priority" dropdown. Column header row: # · Goal · Progress · Est. cost · ◉ (tracked).
  - Grid per row: `8px grip | 12px priority # | 32px icon | 1fr name block | 92px progress | 58px cost | 14px tracked checkbox | 6px ⋮ menu`, column gap 8, row height 52.
  - Name block: name 13.5/500 in quality colour; second line = type badge (14 px tall, 9 px text) and a sub line (11.5, text-2).
  - Group headers (26 px, `#1C1B18`, ▾ chevron): ACTIVE 3, QUEUED 1, PAUSED 1. Paused rows at 62 % opacity. Selected row uses the standard selected style.
  - Rows:
    1. Emberforged Greatsword · 42 % · 31g 62s · tracked
    2. Onyxia's Lair Attunement · 55 % · tracked
    3. Thorium Brotherhood · Revered · 62 % · 24g 00s · tracked
    4. Ironvein Bracers ×2 (queued) · 20 % · 9g 50s
    5. Truesilver Band (paused, reserving 1 Star Ruby) · 30 % · 12g 10s
  - Footer: "Drag rows to set priority" and "◉ = in tracker".
- **Goal Settings panel (252 px):** selected goal header, then labelled fields: Quantity stepper, Priority dropdown, Status segment [Active | Queued | Paused], Count materials from [This character | Account], Route dropdown ("CraftWise Hybrid · 31g 62s"). Checkboxes: Show in tracker, Reserve owned materials, Alert when ready to craft. Footer buttons: Mark complete, Delete (missing-red text).
- **Behaviour:** drag reorders priority; Recommended Next and the tracker pager follow this order. Queued goals count toward the shopping list. Paused goals keep reserved materials out of other goals' "owned" counts.

### 13 Equipment (nav: Equipment · preview module)
- **Summary strip:** Average item level 57.8, Upgrades planned 4, Tracked as goals 3. Segment [All slots | Upgrades only] and "Source: Any" dropdown.
- **Equipped panel (flex):** two columns of 8 slot rows (1 px black divider between columns; rows stretch to fill, min 43 px). Each row: 30 px icon, slot label (10 px bold caps, text-3), item name in quality colour, then a status:
  - BEST IN SLOT (green badge)
  - UPGRADE FOUND (info badge)
  - or a gold "◆ goal name · state" line under the name when an upgrade is already a goal
  - Slots: Head, Neck, Shoulder, Back, Chest, Wrist, Hands, Waist, Legs, Feet, Finger ×2, Trinket ×2, Two-Hand (selected), Ranged.
- **Slot detail panel (262 px, "Two-Hand"):** Equipped item, then a gold-bordered Target card (crafting goal, 42 %). Stat comparison rows (22 px): label, old, ›, new, green delta. Rows: Item level 52 › 63, DPS, Strength, Stamina, Fire resistance. Note "Illustrative stat values". "Other options for this slot" list with source, ilvl and a "+ Goal" button. Footer: Open goal › (primary), Compare.
- **Data:** equipped items from `GetInventoryItemLink`; candidate upgrades from a static loot/recipe table. Gear names in this mock are fictional.

### 14 Quests (nav: Quests · preview module)
- **Quest list panel (flex):** tabs By zone / By goal / Completed, checkbox "Only quests that feed a goal" (checked).
  - Zone headers are 28 px, bold zone name and count.
  - Quest rows are 40 px, indented 22 px:
    - Quest marker: yellow ! available, yellow ? ready to turn in, blue ! repeatable, grey ! locked.
    - [level] in WoW difficulty colours (yellow #FFD100 at level, green #40C040 lower, grey #9D9D9D trivial).
    - Quest name.
    - 16 px icons of the goals it feeds.
    - Status badge: READY, AVAILABLE, IN LOG, REPEATABLE, LOCKED. Locked rows at 60 % opacity.
  - Footer: "8 quests feed your goals", "Quest log 14 / 20".
- **Quest Details panel (262 px):**
  - Title (Marcellus 16, gold-light) and "Level 55 · Searing Gorge · Foreman Dunrik".
  - Objectives with counters and 5 px bars.
  - Green "Ready to turn in" callout (bg `#1C2A1E`, border `#3E6A48`).
  - Rewards (item icon, coins, reputation).
  - "Feeds your goals" rows explaining the impact (e.g. "Essence of Fire: 3 missing → 2 · saves 6g 50s").
  - Buttons: Show on map, Watch, Link.
- Side-quest names (Embers of the Forge, Thorium Point Supplies, Fires of the Deep, Dark Iron Dealings) are illustrative placeholders.

### 09–11 Reference slides
These show the component sheet (every control and its states), the design-system tokens, the layout diagram and the implementation notes. They mirror this README.

---

## Interactions and behaviour
- **Window:** drag by the header. Resize from the bottom-right grip within the min/max size. Save position and size per character. Close with ✕ or Escape (add to `UISpecialFrames`).
- **Nav:** clicking a sidebar item swaps the content frame. Preview modules can show a "Coming in a later version" empty state if not built.
- **Goal switcher:** the header pill opens a dropdown of active goals. Picking one sets the active goal, which also drives the tracker.
- **Search:** type-ahead dropdown of items, goals and factions (26 px rows, first row highlighted). Accepts shift-clicked item links (hook `ChatEdit_InsertLink` or the EditBox's `OnEditFocusGained` + `HandleModifiedItemClick`).
- **Item rows and icons:** hover shows a GameTooltip (`SetItemByID` or `SetHyperlink`) plus ForeverPath source lines. Shift-click links the item. Right-click opens a sources menu.
- **Tree:** click a chevron to expand or collapse; click a row to select it and fill the Selected Node panel. Expand all / Collapse all buttons. The "Unresolved only" filter hides Have rows (keep the ancestors of unresolved rows).
- **Tables:** sortable by clicking a column header (Missing is the default sort). Rows have fixed heights and virtualised scrolling.
- **Quantity stepper:** recomputes need, missing and costs.
- **CraftWise:** "Use this plan" stores the chosen route per component. The tree, shopping list and tracker NEXT step then follow it.
- **Shopping list:** goal chips toggle which goals feed the list. Filter tabs. The bought checkbox dims the row (opacity .5) and strikes the name through. "Send to chat" prints the list to the player's own chat frame (no auto-whispers).
- **Tracker:** collapse/expand, page between goals, drag. Grows up to 6 requirement rows.
- **Loading and unknown states:** unknown price shows a grey "? / n" counter and "No price data — open the Auction House to scan". Bag scanning shows an amber dot with "Scanning bags… 64%". Indeterminate bars use a diagonal stripe pattern.
- **No automation:** ForeverPath only suggests. Buying, crafting, mailing and grouping stay manual (and protected actions need hardware events anyway).

## State and data
- `goals[]`: `{id, type: 'craft'|'attunement'|'reputation', targetItemID|chainID|factionID, qty, paused, route{}}`
- `activeGoalId`, plus tracker state `{shown, collapsed, page, point}`
- `inventory[charKey]`: `{items{itemID: count}, updatedAt, source: 'live'|'snapshot'}`, saved on `BAG_UPDATE_DELAYED`, bank events and `PLAYER_LOGOUT`
- `prices{itemID: {min, avg7, listings, scannedAt}}`, filled only from the player's own AH scans
- `recipes{itemID: {profession, skill, reagents[{itemID, qty}], known}}`, a static data table plus `IsSpellKnown` / trade skill scans
- `sources{itemID: [{type: 'AH'|'Vendor'|'Drop'|'Mine'|'Skin'|'Craft', detail}]}`, static data
- **Derived values (recompute on change):** the dependency tree (recursive expansion with owned amounts subtracted top-down), missing quantities, cheapest route per node (buy vs craft vs alt), goal %, consolidated shopping list with reserved amounts, the recommended next steps.
- **Freshness:** < 3 h fresh (green), 3–24 h aging (amber), > 24 h stale (red).

## Implementation notes (WoW frames)
- **Tree guides:** one 1 px texture per guide column, positioned from a flat row list that carries depth and isLast flags. Fallback: indentation plus an elbow glyph.
- **Long lists:** ScrollBox with a data provider and a fixed row template (FauxScrollFrame on older clients).
- **Gradients and bevels:** a single 9-slice backdrop (BackdropTemplate) plus one tiled stone texture. Skip per-panel gradients if they cost too much.
- **Coins:** `GetCoinTextureString`.
- **Fonts:** bundle the fonts or fall back to FRIZQT__/ARIALN as above.
- **APIs:** names refer to current WoW clients. Confirm availability on WoW: Forever.

## Example data (keep consistent)
- **Character:** Thandrel, Level 60 Human Warrior, realm Stormhold, Blacksmithing 290, Mining 300, 214g 36s.
- **Alts:** Miravelle (52 Night Elf Druid, LW 255 / Skinning 270, snapshot 2 h); Brakkor (38 Dwarf Hunter, Enchanting 180 / Tailoring 165, cached 3 days).
- **Goals:** Emberforged Greatsword 42 %, Onyxia's Lair Attunement 55 %, Thorium Brotherhood Revered 62 %.
- **Totals:** Greatsword buy-finished 78g 00s, buy-all-mats 49g 42s, hybrid 31g 62s (saves 46g 38s). Shopping list 71g 64s.
- Emberforged Greatsword and Ironvein Bracers are fictional items. All prices are illustrative.

## Assets
- The icons are original placeholder SVG glyphs (see the `G` map in `component-helpers.js`). Replace them with in-game icon textures.
- The gameplay backdrop (`Game Backdrop.dc.html`) is an illustrative CSS scene, used only for the mockup slides. It is not part of the addon.

## Files
- `screenshots/`: 14 PNG renders at 3840 × 2160 (2×), one per slide, numbered to match the sections above
- `design/ForeverPath Mockups.dc.html`: all 11 slides (open in a browser; needs the other files in the same folder)
- `design/Game Backdrop.dc.html`: illustrative game backdrop used by the slides
- `design/deck-stage.js`, `design/support.js`: viewer runtime for the HTML references only
- `design/component-helpers.js`: the generator functions with exact component styles and icon glyphs
