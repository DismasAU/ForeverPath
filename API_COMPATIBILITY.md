# API compatibility: World of Warcraft: Forever

## Target client

| Fact | Value | Evidence |
|---|---|---|
| Product folder | `_classic_beta_` (executable `WowB.exe`) | Local install `D:\Blizzard Games\World of Warcraft\_classic_beta_`; `.build.info` product `wow_classic_beta` |
| Build at time of writing | 1.60.1.70450 | `.build.info` on this machine (2026-10-17) |
| TOC `## Interface` | `16001` | Local `Config.wtf` (`engineSurveyPatch "16001"`), every Forever addon installed locally, Warcraft Wiki TOC table, forever-addon-kit, Atraeau/WoW-Addons |
| TOC filename suffix | `_Camelot.toc` (`_Forever` listed as alias) | Warcraft Wiki TOC format page; ProfessionMaster and EllesmereUI ship `*_Camelot.toc` |
| Engine | Retail 12.x based (`WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`), all modern `C_*` namespaces | forever-addon-kit findings; `forever_api.json` (6,045 functions, 269 namespaces) |
| Legacy globals | `GetItemInfo`, `GetItemCount`, `GetContainerItemInfo`, `GetContainerNumSlots`, `GetTradeSkillInfo`, `GetCraftInfo`, `GetAddOnMetadata` are **absent** | Absent from both API dumps |
| SavedVariables | Written and **read back** on the current build | Account-wide `Attune.lua` holds data for four characters played on different days; `Auctionator.lua` grows between consecutive writes. The forever-addon-kit report that SVs were never loaded dates from build 69893 (2026-09-17) and no longer matches observed behaviour |
| Unknown events | `RegisterEvent` with an unknown event name **throws** | forever-addon-kit; ForeverPath wraps every registration in `pcall` |
| `ReloadUI()` | Protected | forever-addon-kit; ForeverPath never calls it |
| Error cap | Client stops delivering Lua errors after 100 per session | forever-addon-kit; ForeverPath rate-limits its own error output |

Sources used offline:

- `D:\Blizzard Games\World of Warcraft\_classic_beta_\Interface\AddOns\*` (ProfessionMaster 7.0.24, Auctionator 341, EllesmereUI 9.5.x, GearQuestForever 0.5.6, ForeverDungeonJournal 1.6.3, AtlasLoot Forever)
- https://github.com/Thunderz96/forever-addon-kit (`data/forever_api.json`, build 69893)
- https://github.com/Atraeau/WoW-Addons (`types/WowForeverAPI.lua`, generated from the client's APIDocumentation, build 70170)
- https://warcraft.wiki.gg/wiki/TOC_format, API_C_TradeSkillUI.GetRecipeSchematic, API_C_TradeSkillUI.GetRecipeInfo, API_GetProfessions

"Verified: dump" below means the function appears in the client API dumps.
"Verified: usage" means a Forever addon installed locally calls it on this
client. Behaviour (return values, timing) is only verified where stated.

## Functions used

| Function | Where | Verified | Notes |
|---|---|---|---|
| `C_Item.GetItemInfo(itemID)` | ItemProvider | dump, usage (83 files) | Returns nil until item data is cached |
| `C_Item.GetItemInfoInstant(itemID)` | ItemProvider | dump, usage | Used for icon and existence; nil for unknown IDs |
| `C_Item.DoesItemExistByID(itemID)` | ItemProvider | dump | Preferred existence check |
| `C_Item.RequestLoadItemDataByID(itemID)` | ItemProvider | dump, usage | Completion via `ITEM_DATA_LOAD_RESULT` |
| `C_Item.IsItemDataCachedByID` | Compat | dump | Resolved, currently unused |
| `C_Item.GetItemIconByID` | Compat | dump | Resolved, currently unused |
| `C_Item.GetItemCount(itemID, includeBank)` | InventoryProvider | dump, usage | Fallback when container scanning is unavailable; also used to infer a "client reported" bank count (**semantics with the bank closed unverified**) |
| `C_Container.GetContainerNumSlots(bag)` | InventoryProvider | dump, usage | |
| `C_Container.GetContainerItemInfo(bag, slot)` | InventoryProvider | dump, usage | Returns `ContainerItemInfo` table (`itemID`, `stackCount`) |
| `C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character)` | InventoryProvider | dump, usage (EllesmereUIBags) | Returns bag indices (6..14) for bank tabs; scanned only while the bank is open |
| `C_TradeSkillUI.GetAllRecipeIDs()` | ProfessionProvider | dump (kit), usage (ProfessionMaster) | Only meaningful while a profession window is open; falls back to `GetFilteredRecipeIDs` |
| `C_TradeSkillUI.GetRecipeInfo(recipeID)` | ProfessionProvider | dump, usage | `learned` flag |
| `C_TradeSkillUI.GetRecipeSchematic(recipeID, false)` | ProfessionProvider | dump, usage (Auctionator) | `outputItemID`, `quantityMin/Max`, `reagentSlotSchematics[].reagents[].itemID`, `quantityRequired`, `reagentType`. **Whether it returns full data while the window is closed is unverified**; the provider keeps cached data when the live answer has no reagent slots |
| `C_TradeSkillUI.GetChildProfessionInfo()` / `GetBaseProfessionInfo()` | ProfessionProvider | dump, usage (ProfessionMaster) | `professionID`, `parentProfessionID`, `professionName`, `skillLevel`, `maxSkillLevel` |
| `C_TradeSkillUI.IsNPCCrafting / IsTradeSkillGuild / IsTradeSkillLinked` | ProfessionProvider | dump, usage | Skip non-player data sources |
| `C_TradeSkillUI.OpenTradeSkill(skillLineID)` | ProfessionProvider (`/fp scan`) | dump | **Unverified from addon code on Forever**; failure falls back to manual opening |
| `C_TradeSkillUI.CloseTradeSkill()` | ProfessionProvider | dump | Only after ForeverPath opened the window itself |
| `GetProfessions()` / `GetProfessionInfo(index)` | ProfessionProvider | dump (both listed), usage (ProfessionMaster) | Slot layout and whether First Aid occupies a slot **unverified**; all six slots are read defensively |
| `C_AddOns.GetAddOnMetadata` | Bootstrap | dump, usage | Version string |
| `C_Timer.After` | Events, providers | dump | Debounce and chunked scans |
| `InCombatLockdown` | Events | dump | Defers `/fp scan` window opening |
| `hooksecurefunc`, `ChatFrameUtil.InsertLink` / `ChatEdit_InsertLink` | SearchBox | dump (`ChatEdit_InsertLink`), usage (Auctionator hooks both) | Shift-click capture |
| `GetCurrentKeyBoardFocus` | SearchBox | dump | Do not steal links typed into chat |
| `GetBuildInfo` | Compat | dump | Interface detection |
| `CreateFrame`, templates `BackdropTemplate`, `UIPanelButtonTemplate`, `UIPanelCloseButton`, `InputBoxTemplate`, `UIPanelScrollFrameTemplate` | UI | usage (12-75 Forever addon files each) | |
| `Frame:SetResizeBounds` | MainFrame | usage (12 files); falls back to `SetMinResize` | |
| `GameTooltip:SetItemByID` | Widgets | Retail API | Guarded with pcall; falls back to a plain name tooltip |
| `Enum.CraftingReagentType.Basic` (=1), `Enum.BankType.Character` (=0), `Enum.BagIndex.ReagentBag` (=5) | Compat | `Enum.BagIndex` in dump; the other two from Retail 12.x docs | Fallback constants used when the enum is missing |

## 0.14.0

Reputation goals read (behind `pcall`):

| Function | Used for | Evidence |
|---|---|---|
| `C_Reputation.GetNumFactions()`, `GetFactionDataByIndex(i)` (`name`, `factionID`, `reaction`, `currentStanding`, `currentReactionThreshold`, `nextReactionThreshold`, `isHeader`, `isHeaderWithRep`, `isCollapsed`), `GetFactionDataByID(id)` | standings and groups | EllesmereUIForeverEssentials, Attune |
| Legacy `GetFactionInfo(i)` / `GetFactionInfoByID(id)` tuples | fallback | Attune keeps both paths |
| `FACTION_STANDING_LABEL1..8` | standing names (English fallback built in) | EllesmereUI |

Event: `UPDATE_FACTION`. The standing thresholds (Neutral 0, Friendly
3000, Honored 9000, Revered 21000, Exalted 42000) are the classic values
and are used only to compute "reputation still needed"; the client's own
`currentReactionThreshold` / `nextReactionThreshold` drive the bars.
AtlasLootClassic_Factions is loaded through `AtlasLoot.Loader:LoadModule`
like the dungeon module and read from `ItemDB.Storage`.

## 0.13.0

The Equipment screen reads (all behind `pcall`):

| Function | Used for | Evidence |
|---|---|---|
| `GetInventoryItemID("player", slot)`, `GetInventoryItemLink("player", slot)` | what is worn | GearQuestForever, EllesmereUI |
| `C_Item.GetDetailedItemLevelInfo(link)`, then the 4th return of item info | item level | EllesmereUI |
| `C_Item.GetItemStats(link)`, legacy `GetItemStats(link, table)` | stat comparison | GearQuestForever (uses both) |
| `GetAverageItemLevel()` | the strip's average (falls back to a mean over the slots) | EllesmereUI |
| `GetItemInfoInstant` 4th return (equip location) | which slot an item or goal fits | GearQuestForever |

Events: `PLAYER_EQUIPMENT_CHANGED`, `UNIT_INVENTORY_CHANGED`. GearQuest
Forever is read through `_G.GearQuest` (`Data.entries`, the
`<class>ItemFacts` tables, `Data.scoredStats`, `Data:EnsureClassLoaded`,
`Spec:GetDisplaySpec`, `Spec:GetSpecLabel`), never written; its class
module must be enabled for the player's class, as GearQuest itself requires.

## 0.12.0

Quest goals and the Quests screen read `C_QuestLog` (all behind `pcall`,
each absent function degrades to "unknown"):

| Function | Used for | Evidence |
|---|---|---|
| `C_QuestLog.IsQuestFlaggedCompleted`, `IsOnQuest` | completed / in log (already used for attunements) | Attune, RXPGuides, ForeverDungeonJournal |
| `C_QuestLog.IsComplete(questID)` | ready to turn in | EllesmereUIQuestTracker, RXPGuides |
| `C_QuestLog.GetNumQuestLogEntries()`, `GetInfo(index)` | the log with its zone headers (`title`, `questID`, `level`, `isHeader`) | EllesmereUIQuestTracker, RXPGuides |
| `C_QuestLog.GetLogIndexForQuestID(questID)` | log index for `GetInfo` and `GetQuestLink` | EllesmereUIQuestTracker |
| `C_QuestLog.GetQuestObjectives(questID)` | objectives (`text`, `finished`, `numFulfilled`, `numRequired`) | RXPGuides |
| `C_QuestLog.GetTitleForQuestID(questID)`, `RequestLoadQuestByID(questID)`, event `QUEST_DATA_LOAD_RESULT` | titles of quests not in the log | RXPGuides, ForeverDungeonJournal |
| `C_QuestLog.AddQuestWatch(questID)` | the Watch button | Retail API; guarded |
| `C_QuestLog.GetMaxNumQuestsCanAccept()` | log capacity (falls back to 20) | Retail API; guarded |
| `GetQuestLink(logIndex)` | the Link button | ForeverDungeonJournal |

Events: `QUEST_ACCEPTED`, `QUEST_TURNED_IN`, `QUEST_LOG_UPDATE` (already
used), plus `QUEST_REMOVED` and `QUEST_DATA_LOAD_RESULT`. Static quest data
comes from `ForeverDungeonJournal_NS.DB[...].quests`, `QUEST_PREREQ_CHAINS`,
`QUEST_START_MAPS`, `FOREVER_QUEST_XP_FALLBACK` and `Attune_Data.quests` /
`questGivers` / `questRewards`, read as data and never written.

## 0.11.0

No new API calls. Learn-recipe goals complete through the existing
`NEW_RECIPE_LEARNED` handling and profession scans; reach-skill goals read
the skill from `GetProfessionInfo` (skill level, max skill level and the
icon, now kept for the goal) and re-check on `SKILL_LINES_CHANGED`, which
the client fires on every skill-up. Recipe thresholds come from the
catalogue (`TrivialSkillLineRankLow` / `High`); the skill-up chance uses the
classic rule (certain below the yellow threshold, linear to zero at grey),
which is not verifiable from the client and may differ from the server's.

## 0.10.1

| API | Use | Status |
|---|---|---|
| `GetNumTrainerServices()`, `GetTrainerServiceInfo(i)` | trainer lines; the service type ("available", "unavailable", "used", "header") is read from the second return, with the third accepted as fallback | Verified: usage (EllesmereUIQoL and Leatrix Plus read the type as the second return on this client) |
| `GetTrainerServiceCost(i)` | training cost in copper | Verified: usage (EllesmereUIQoL, Leatrix Plus) |
| `GetTrainerServiceSkillReq(i)` | required skill name and rank | **Not verified** on Forever (no local addon calls it); called behind pcall, nothing is recorded without it |
| `GetTrainerServiceItemLink(i)` | spell id of the line from its `enchant:`/`spell:` link | **Not verified** on Forever; without it lines are matched by recipe name against the catalogue within the required profession |
| `GetTrainerServiceTypeFilter(t)`, `SetTrainerServiceTypeFilter(t, on)` | show unavailable and used lines for the visit, restore on close | Verified: usage (RXPGuides); behind pcall |
| `IsTradeskillTrainer()` | skip class trainers | Verified: usage (RXPGuides); when absent only profession skills are kept |
| `TRAINER_SHOW`, `TRAINER_UPDATE`, `TRAINER_CLOSED` | record on open and update, restore filters on close | Verified: usage (Leatrix Plus, RXPGuides); registered with pcall |

## 0.10.0

No new in-game API. The recipe catalogue is built offline from the client's
database files, which is a different kind of dependency:

| Source | Use | Status |
|---|---|---|
| CASC store `D:\Blizzard Games\World of Warcraft\Data` (product `wow_classic_beta`, build 1.60.1.70450) | DB2 tables `SkillLine`, `SkillLineAbility`, `SpellReagents`, `SpellEffect`, `SpellName`, `SpellMisc`, `ItemEffect`, `ItemXItemEffect`, `ItemSparse`, `Item` by file data id (WoWDBDefs manifest) | Read by `tools/DbExtract` with CascLib (WoW-Tools/CascLib at commit 3f8be478, patched: the Forever root manifest has blocks with no locale flags, which the unpatched library rejects) and DBCD 2.3.1 with WoWDBDefs layouts; every table decoded on 2026-10-18 |
| `_classic_beta_\Cache\ADB\enUS\DBCache.bin` | server hotfixes applied on top of the tables | Applied with DBCD.IO's `HotfixReader`; on this build it added 13 `SpellEffect`, 4 `SpellName`, 4 `SpellMisc`, 4,776 `ItemSparse` rows and removed 38 `Item` rows |
| `SkillLineAbility.MinSkillLineRank` | required skill | Is 1 for almost every recipe on this build; the real requirement is `ItemSparse.RequiredSkillRank` of the plans / pattern (used when one exists). Trainer requirements are server-side and stay unknown |
| `ItemSparse` coverage | item names, quality, binding | Partial: 575 of 4,687 referenced items had no row at extraction (the server streams rows into the hotfix cache as items are seen). Names for those come from `C_Item` at runtime as before |
| Spell icon file data ids (`SpellMisc.SpellIconFileDataID`) | recipe icons | Shipped in the catalogue; `SetTexture(fileDataID)` works on the 12.x engine but is **not yet verified** on Forever (icons fall back to the item's icon when unused) |

## 0.9.0

| API | Use | Status |
|---|---|---|
| `C_QuestLog.IsQuestFlaggedCompleted(questID)` (fallback `IsQuestFlaggedCompleted`) | attunement quest steps | Attune itself uses the same pair on this build; `Compat.IsQuestFlaggedCompleted` picks whichever exists |
| `C_QuestLog.IsOnQuest(questID)` | "in your log" / pick-up steps | Attune uses it on this build; nil-safe when absent |
| `UnitFactionGroup("player")`, `UnitLevel("player")` | faction filter, level steps | standard |
| `QUEST_TURNED_IN`, `QUEST_LOG_UPDATE`, `QUEST_ACCEPTED`, `PLAYER_LEVEL_UP` | re-check attunement goals | registered with pcall; debounced 1 s |
| `_G.Attune_Data`, `_G.AttuneLang`, `_G.Attune_DB.toons[<name>].done` | chains, quest names, survey of kills/interactions | Attune 16001-29's own globals, read-only; the toon key is matched by character name (Attune keys it "First Last"), guarded by type checks |

## 0.8.1

| API | Use | Status |
|---|---|---|
| `PlaySound(SOUNDKIT.LEVELUP, "Master")` (fallback kit id 888) | completion fanfare | standard; called behind pcall, silence if missing |
| `UIFrameFadeOut(frame, 0.4, 1, 0)` | toast fade | FrameXML helper; the toast simply hides when it is absent |

## 0.8.0

| API | Use | Status |
|---|---|---|
| `Auctionator.API.v1.GetAuctionPriceByItemID("ForeverPath", itemID)`, `GetAuctionAgeByItemID` | AH price and age | Auctionator's public API (it errors on a bad caller ID, so the adapter always passes the addon name); the installed build is a Forever ("camelot") build with a price database for the realm, so scans work on this client |
| `Auctionator.Database:GetMeanPrice(key, 7)`, `:GetPriceHistory(key)` | 7-day average, last listing count | internal objects, read behind pcall; missing or renamed means only the average/listings disappear |
| `AUCTIONATOR_SAVEDVARS.TimeOfLastBrowseScan` | scan age for freshness | saved variable Auctionator keeps on the account; absent means "no scan yet" |

No new Blizzard API calls. ForeverPath does not scan the Auction House
itself; Auctionator's price database (serialised per realm in its saved
variables) is read only through its API after it has deserialised it.

## 0.7.0

| API | Use | Status |
|---|---|---|
| `_G.ForeverDungeonJournal_NS.DB`, `.SHARED_BY_BOSS` | boss loot, trash drops, shared loot, dungeon quest rewards | ForeverDungeonJournal 1.6.3's own namespace (Forever-specific data), read-only and guarded by type checks on every table walked; an index failure is logged and the bridge stays inert. Field layout assumed from its `Data/Dungeons.lua` and `Data/SharedLoot.lua`; a future journal release that changes it only loses the hints |
| AtlasLootClassic_DungeonsAndRaids Forever build | boss drops | the `_Forever.toc` loads `data.lua` (Classic instances) and `data-tbc.lua`; instance names resolve through `ContentProto:GetName`. Forever-only dungeons come from DungeonJournal |

No new Blizzard API calls.

## 0.6.0

| API | Use | Status |
|---|---|---|
| `GetMerchantNumItems()`, `GetMerchantItemLink(i)` | merchant stock | present on this build (Auctionator uses them); unverified by ForeverPath in game |
| `C_MerchantFrame.GetItemInfo(i)` (fallback `GetMerchantItemInfo`) | price, stack, availability, extended cost | same |
| `UnitName("npc")`, `GetZoneText()`, `GetSubZoneText()` | who and where | standard |
| `MERCHANT_SHOW` / `MERCHANT_UPDATE` / `MERCHANT_CLOSED` | scan timing | registered with pcall like every event |
| `C_Item.GetItemInfoInstant` classID/subclassID | item-class heuristics | numbering assumed to match Retail's `Enum.ItemTradeskillSubclass` (Herb 9, Metal & Stone 7, Leather 6, Cloth 5...). Verify with `/fp sources` on known items; if a class comes out wrong, the table in `Data/ItemClasses.lua` is the only place to fix |
| `AtlasLoot.Loader:LoadModule`, `AtlasLoot.ItemDB.Storage` | loot tables | AtlasLootClassic's own API, read-only; guarded by `pcall` and by a type check on every table walked |

Open question: does `GetMerchantItemLink` return a full item link at
`MERCHANT_SHOW` on Forever, or only after item data loads? The recorder
scans again 0.5 s later and on `MERCHANT_UPDATE` to cover both.

## 0.5.0

No new API calls. "Send to chat" writes to the default chat frame through the
addon's own print path (no `SendChatMessage`), so nothing is sent to other
players.

## 0.4.1

Observed in game: alt snapshots taken at login+1 s and at logout had no
professions, while the live character showed them. Either `GetProfessions()`
returns nothing until some time after `PLAYER_ENTERING_WORLD` on this build,
or it returns nothing during `PLAYER_LOGOUT`. Open question: which one.
`/fp snapshot` prints the source it used so this can be pinned down; the
snapshot now retries on `SKILL_LINES_CHANGED` and 8 s after entering the
world and keeps the last non-empty list.

## 0.4.0

Reads only `UnitName/UnitLevel/UnitClass/UnitRace("player")`, `GetRealmName`,
`GetMoney` (all present in 0.2.0's header) and the `PLAYER_LOGOUT` event for
the final snapshot. The alt card portrait uses the class-icon sheet
`Interface\TargetingFrame\UI-Classes-Circles` with `CLASS_ICON_TCOORDS`,
guarded in case the global is absent on Forever (the icon then shows the
whole sheet; report it and it becomes an atlas lookup).

## 0.3.0

No new API calls. The dependency tree is pure Lua over data already recorded
(recipes, learned flags, bag/bank counts). Its one in-game dependency is
whether sub-recipes are *recorded*: a reagent's recipe is only known after its
profession window has been opened once, which is why the checklist asks for
both professions to be recorded first.

## Added in 0.2.0 (UI rebuild; in use in game since 0.2.1)

| Function / asset | Where | Verified | Notes |
|---|---|---|---|
| `CreateFont`, `Font:SetFont`, `FontString:SetFontObject` | Theme, Widgets | dump (`CreateFont`) | Fonts `Fonts\FRIZQT__.TTF`, `Fonts\ARIALN.TTF` (client fonts; handoff fallback mapping) |
| `Texture:SetGradient("VERTICAL", CreateColor, CreateColor)` | Widgets | Retail 10.x API; guarded, falls back to a flat average colour | |
| `Texture:SetRotation`, `SetVertexColor`, `SetColorTexture` | Widgets | Retail API; `SetRotation` guarded | Arrows, diamonds, rivets |
| `Frame:SetResizeBounds(minW, minH, maxW, maxH)` | MainFrame | 10.x API; falls back to `SetMinResize`/`SetMaxResize` | |
| `EditBox:SetTextInsets`, `SetNumeric`, `SetFontObject` | Widgets | Retail API | |
| `UnitName`, `UnitLevel`, `UnitClass`, `UnitRace`, `GetRealmName`, `GetMoney` | MainFrame, Dashboard | dump (`UnitName`, `UnitClass`, `UnitLevel`, `GetRealmName`, `GetMoney`) | All guarded with `type(...) == "function"` |
| `RAID_CLASS_COLORS` | MainFrame | Retail global table; guarded | Class-coloured character name |
| `SetPortraitTexture(texture, "player")` | Dashboard | Retail API; pcall-guarded | Character strip portrait |
| `C_CurrencyInfo.GetCoinTextureString` / `GetCoinTextureString` | Widgets.Money | Either may be absent; falls back to coloured text | |
| `ScrollFrame:SetVerticalScroll`, `GetVerticalScroll`, `EnableMouseWheel` | Widgets.ScrollArea | Retail API | Custom scroll area, no Blizzard scroll template |
| Textures `Interface\Buttons\WHITE8X8`, `Interface\ChatFrame\ChatFrameExpandArrow`, `Interface\Buttons\UI-CheckBox-Check`, `Interface\Common\UI-Searchbox-Icon`, `Interface\ChatFrame\UI-ChatIM-SizeGrabber-*` | Widgets | Standard Retail textures | A missing texture renders blank, never errors |

Unicode glyphs from the handoff (check marks, chevrons, bullets) are not
drawn as text because the client fonts lack them; arrows and checks use the
textures above and ASCII stands in elsewhere.

## Events used

All verified present in the Forever API event list (Atraeau docs, build 70170):
`ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_ENABLED`,
`BAG_UPDATE_DELAYED`, `BANKFRAME_OPENED`, `BANKFRAME_CLOSED`,
`PLAYERBANKSLOTS_CHANGED`, `BANK_TABS_CHANGED`, `TRADE_SKILL_LIST_UPDATE`,
`TRADE_SKILL_SHOW`, `TRADE_SKILL_DATA_SOURCE_CHANGED`, `NEW_RECIPE_LEARNED`, `QUEST_REMOVED`, `QUEST_DATA_LOAD_RESULT`, `PLAYER_EQUIPMENT_CHANGED`, `UNIT_INVENTORY_CHANGED`, `UPDATE_FACTION`,
`ITEM_DATA_LOAD_RESULT`, `GET_ITEM_INFO_RECEIVED`.

Not used because they do not exist on this client: `TRADE_SKILL_UPDATE`,
`CRAFT_SHOW`, `CRAFT_UPDATE`, `PLAYERBANKBAGSLOTS_CHANGED`.

## Deliberately not used

- Legacy tradeskill API (`GetTradeSkillInfo`, `GetTradeSkillReagentInfo`,
  `GetCraftInfo`): absent on Forever. `Compat.hasLegacyTradeSkill` records
  whether it exists, but no code path uses it.
- `SetUserPlaced` / layout cache: the window saves its own anchor and size.
- `ReloadUI()`: protected on Forever.

## Verified in game (2026-10-17, build 1.60.1.70450)

The TESTING.md checklist passed with no Lua errors. Confirmed by that run:
the addon loads on interface 16001; `C_TradeSkillUI` recording works when a
profession window is open (Leatherworking recorded, schematics carried
`outputItemID`, reagent item IDs and quantities); `C_Item` name, icon and
quality data loads for goal items and reagents; `C_Container` bag counts match
the bags; the window, goals, quantity controls and slash commands behave as
designed; SavedVariables persist across reloads. Opening the bank fired
`BANKFRAME_OPENED` and the `C_Bank.FetchPurchasedBankTabIDs` scan ran without
error (inventory note switched to "bank open, live"); the tab was empty, so
bank stack counting itself is still unexercised. Question 6 below is therefore
answered as far as "no error"; whether contents are readable at that instant
is open until a bank holding reagents is tested.

## Open questions (function-level, not individually answered)

Every feature through 0.10.4 has been used in game by the author, so the
code paths that depend on these calls behave acceptably with their guards
and fallbacks in place. What has not been recorded is which branch each call
takes, so the questions below stay open as documentation of where a fallback
may be doing the work. `/fp status`, `/fp snapshot` and `/fp debug` print
the answers when someone wants to settle them.

1. Does `C_TradeSkillUI.GetRecipeSchematic` return reagent slots for a recipe
   whose profession window is closed? If yes, plans are always live. If not,
   plans use the cached scan (the UI says so).
2. Does `C_TradeSkillUI.OpenTradeSkill(skillLineID)` open the window from
   addon code without a hardware event? If not, `/fp scan` prints a message and
   the player opens windows manually.
3. Does `C_Item.GetItemCount(itemID, true)` include bank contents while the
   bank is closed? If yes, the "client reported" bank source appears before the
   first bank visit; if not, bank counts appear only after a visit.
4. Do `GetProfessions()` slots match Retail (prof1, prof2, archaeology,
   fishing, cooking) and is there a sixth First Aid slot on Forever?
5. Are the profession IDs reported by `GetChildProfessionInfo` the same values
   as `skillLine` from `GetProfessionInfo`? `/fp scan` matches by ID first and
   by name second.
6. Does `BANKFRAME_OPENED` fire before bank tab contents are readable?
   ForeverPath scans on the event and again 0.5 s later.
7. Is `Enum.CraftingReagentType.Basic` still `1` on Forever? Untyped slots are
   treated as basic as a safety net.

`/fp status` prints the detected capabilities; `/fp debug` logs scan details.
