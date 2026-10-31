-- Where an item comes from, aggregated from what is available on this client
-- without any external service: recorded vendors and loot (the learners),
-- ForeverDungeonJournal and AtlasLoot (read at runtime, never copied), the
-- quest catalogue, GearQuest Forever, reputation vendors, CMaNGOS classic-db
-- (ns.ClassicDB) and the item class heuristic (Data/ItemClasses.lua).
-- Everything is returned as resolver hints: { kind, label, detail, ... }, in
-- the order the comment on SourceProvider.Sources gives - that order is the
-- contract.
local _, ns = ...
local Routes = ns.DependencyResolver.Routes

local Compat = ns.Compat
local Log = ns.Log
local Util = ns.Util
local Events = ns.Events

local SourceProvider = {
  atlas = { state = "idle", index = {}, modules = { "AtlasLootClassic_DungeonsAndRaids" } },
  journal = { state = "idle", index = {}, items = 0 },
}
ns.SourceProvider = SourceProvider

SourceProvider.MAX_ATLAS_ENTRIES = 3
SourceProvider.MAX_JOURNAL_ENTRIES = 3
---------------------------------------------------------------------------
-- ForeverDungeonJournal sources (read through ns.DungeonJournal)
---------------------------------------------------------------------------
local function addJournalEntry(index, itemID, entry, cap)
  if type(itemID) ~= "number" or itemID <= 0 then return false end
  local list = index[itemID]
  if not list then
    list = {}
    index[itemID] = list
  end
  local same = 0
  for _, existing in ipairs(list) do
    if existing.kind == entry.kind then
      same = same + 1
      if existing.boss == entry.boss and existing.instance == entry.instance and existing.quest == entry.quest then
        return false
      end
    end
  end
  if same >= cap then return false end
  list[#list + 1] = entry
  return true
end

-- Walks the journal's tables into journal.index[itemID] = { entries }.
function SourceProvider.IndexDungeonJournal()
  local fdj = ns.DungeonJournal.Get()
  local index, added = {}, 0
  local cap = SourceProvider.MAX_JOURNAL_ENTRIES
  for dungeonName, dungeon in pairs(fdj.DB) do
    if type(dungeonName) == "string" and type(dungeon) == "table" then
      for _, boss in ipairs(type(dungeon.bosses) == "table" and dungeon.bosses or {}) do
        if type(boss) == "table" and type(boss.loot) == "table" then
          for _, entry in ipairs(boss.loot) do
            if type(entry) == "table" then
              local mob = type(entry[5]) == "string" and entry[5] or nil
              local record = {
                kind = Routes.DROP, instance = dungeonName, npcID = boss.npcID, trash = boss.trash == true,
                boss = boss.trash and (mob or "trash mobs") or (boss.name or "?"),
              }
              if addJournalEntry(index, entry[1], record, cap) then added = added + 1 end
            end
          end
        end
      end
      local shared = type(fdj.SHARED_BY_BOSS) == "table" and fdj.SHARED_BY_BOSS[dungeonName] or nil
      if type(shared) == "table" then
        for bossName, list in pairs(shared) do
          for _, entry in ipairs(type(list) == "table" and list or {}) do
            if type(entry) == "table" and addJournalEntry(index, entry[1], { kind = Routes.DROP, instance = dungeonName, boss = tostring(bossName), shared = true }, cap) then
              added = added + 1
            end
          end
        end
      end
      for _, quest in ipairs(type(dungeon.quests) == "table" and dungeon.quests or {}) do
        if type(quest) == "table" and type(quest.rewardItems) == "table" then
          for _, reward in ipairs(quest.rewardItems) do
            if type(reward) == "table" then
              local record = {
                kind = Routes.QUEST, instance = dungeonName, quest = quest.name or "?", questID = quest.id,
                choice = quest.rewardChoice == true, faction = quest.faction, pickup = quest.pickup,
              }
              if addJournalEntry(index, reward[1], record, cap) then added = added + 1 end
            end
          end
        end
      end
    end
  end
  local items = 0
  items = items + Util.Count(index)
  SourceProvider.journal.index = index
  SourceProvider.journal.items = items
  return added
end

-- Indexes the journal once per session, the first time a source is asked for.
function SourceProvider.BuildJournalIndex()
  local journal = SourceProvider.journal
  if journal.state ~= "idle" then return journal.state end
  if not ns.DungeonJournal.IsAvailable() then return journal.state end
  local ok, added = Log.Capture(SourceProvider.IndexDungeonJournal)
  if ok then
    journal.state = "ready"
    Log.Debug("Indexed DungeonJournal: %d loot and quest entries for %d items", added, journal.items)
  else
    journal.state = "failed"
    -- Visible in /fp errors: the drop and quest sources it feeds are missing.
    Log.Error("DungeonJournal index failed: %s", tostring(added))
  end
  return journal.state
end

function SourceProvider.JournalSources(itemID)
  if SourceProvider.journal.state == "idle" then
    SourceProvider.BuildJournalIndex()
  end
  local out = {}
  for _, entry in ipairs(SourceProvider.journal.index[itemID] or {}) do
    if entry.kind == Routes.QUEST then
      out[#out + 1] = {
        kind = Routes.QUEST, quest = entry.quest, questID = entry.questID, instance = entry.instance,
        choice = entry.choice, faction = entry.faction, pickup = entry.pickup, journal = true,
        label = "Quest reward: " .. entry.quest,
        detail = entry.instance .. (entry.choice and " - choose on turn-in" or "")
          .. ((entry.faction and entry.faction ~= "Both") and (" - " .. entry.faction) or "") .. " (DungeonJournal)",
      }
    else
      out[#out + 1] = {
        kind = Routes.DROP, boss = entry.boss, instance = entry.instance, npcID = entry.npcID,
        trash = entry.trash, shared = entry.shared, journal = true,
        label = "Dropped by " .. entry.boss,
        detail = entry.instance .. (entry.shared and " - shared loot" or "") .. " (DungeonJournal)",
      }
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Item class heuristics
---------------------------------------------------------------------------
-- Item class and subclass: the client first, the catalogue (which carries
-- them for every item a recipe touches) when the client has not cached the item.
function SourceProvider.ItemClass(itemID)
  if Compat.GetItemInfoInstant then
    local classID, subclassID = select(6, Util.SafeCall(Compat.GetItemInfoInstant, itemID))
    if type(classID) == "number" then return classID, subclassID end
  end
  local catalogue = ns.Data.Recipes
  if catalogue and catalogue.ItemClass then
    return catalogue.ItemClass(itemID)
  end
  return nil
end

function SourceProvider.ClassHint(itemID)
  local classID, subclassID = SourceProvider.ItemClass(itemID)
  if type(classID) ~= "number" then return nil end
  return ns.Data.ItemClasses.Lookup(classID, subclassID)
end

-- Every recipe (recorded or catalogue) that makes itemID.
local function recipesFor(itemID)
  local out = {}
  do
    for _, candidate in ipairs(ns.ProfessionProvider.FindRecipesForItem(itemID) or {}) do
      out[#out + 1] = candidate.recipe
    end
  end
  local catalogue = ns.Data.Recipes
  if catalogue and catalogue.Lookup then
    for _, recipe in ipairs(catalogue.Lookup(itemID) or {}) do out[#out + 1] = recipe end
  end
  return out
end

-- A gathering material is its own thing even when a recipe can refine a
-- lower tier into it: Medium Leather is skinned, not made from Light Leather
-- that was made from scraps; a greater essence is disenchanted or bought,
-- not combined by default. True when the item has a gathering class hint and
-- every recipe producing it is such a refinement: one reagent type, of the
-- same gathering kind, by a profession other than the gathering skill itself
-- (smelting ore into bars is Mining's own work and stays a craft).
function SourceProvider.IsRawMaterial(itemID)
  local hint = SourceProvider.ClassHint(itemID)
  if not hint or hint.kind ~= Routes.GATHER or not hint.skill then return false end
  local recipes = recipesFor(itemID)
  if #recipes == 0 then return true end
  for _, recipe in ipairs(recipes) do
    if recipe.professionName == hint.skill then return false end
    local kinds, first = 0, nil
    for _, reagent in ipairs(recipe.reagents or {}) do
      if reagent.itemID ~= first then
        kinds = kinds + 1
        first = reagent.itemID
      end
    end
    if kinds ~= 1 then return false end
    local sub = SourceProvider.ClassHint(recipe.reagents[1].itemID)
    if not sub or sub.kind ~= Routes.GATHER or sub.skill ~= hint.skill then return false end
  end
  return true
end

-- Characters that have a gathering skill, this character first, then the
-- snapshotted alts: { { name, skillLevel, isCurrent } }.
function SourceProvider.GatherersFor(skill)
  if not skill then return {} end
  return ns.CharacterProvider.WithProfession(skill)
end

-- A gathering hint is only a route when someone can actually gather: it is
-- annotated with who has the skill, or marked unavailable (still shown as
-- information, never recommended).
function SourceProvider.QualifyGatherHint(hint)
  if not hint or hint.kind ~= Routes.GATHER or not hint.skill then return hint end
  local who = SourceProvider.GatherersFor(hint.skill)
  if #who > 0 then
    local first = who[1]
    hint.gatherers = who
    hint.gatherer = (not first.isCurrent) and first.name or nil
    hint.detail = (hint.detail or "") .. " - " .. (first.isCurrent and "you have" or (first.name .. " has")) .. " " .. hint.skill
      .. (first.skillLevel and (" (" .. first.skillLevel .. ")") or "")
  else
    hint.unavailable = true
    hint.detail = (hint.detail or "") .. " - no character has " .. hint.skill
  end
  return hint
end

---------------------------------------------------------------------------
-- AtlasLoot bridge
---------------------------------------------------------------------------

-- One drop entry for itemID, at most MAX_ATLAS_ENTRIES per item, no
-- duplicate boss in the same instance. Returns whether it was added.
local function addAtlasEntry(index, itemID, instance, boss)
  local list = index[itemID]
  if not list then
    list = {}
    index[itemID] = list
  end
  if #list >= SourceProvider.MAX_ATLAS_ENTRIES then return false end
  for _, existing in ipairs(list) do
    if existing.boss == boss.name and existing.instance == instance then return false end
  end
  list[#list + 1] = { instance = instance, boss = boss.name or "?", npcID = boss.npcID }
  return true
end

-- Walks one loaded AtlasLoot module into index[itemID] = { { instance, boss, npcID } }.
function SourceProvider.IndexAtlasModule(storage)
  local index = SourceProvider.atlas.index
  local added = 0
  for _, content in ns.AtlasLoot.Contents(storage) do
    local instance = ns.AtlasLoot.ContentName(content)
    for _, boss in ipairs(content.items) do
      for _, itemID in ipairs(ns.AtlasLoot.ItemIDs(boss)) do
        if addAtlasEntry(index, itemID, instance, boss) then added = added + 1 end
      end
    end
  end
  return added
end

-- Loads the AtlasLoot loot modules on demand and indexes them once per
-- session. The state ends "ready" once every module is indexed or known to
-- be missing; it stays "loading" only while AtlasLoot is still loading one.
function SourceProvider.BuildAtlasIndex()
  local atlas = SourceProvider.atlas
  if atlas.state ~= "idle" or not ns.AtlasLoot.IsAvailable() then
    return atlas.state
  end
  atlas.state = "loading"
  local pending = #atlas.modules
  local function done()
    pending = pending - 1
    if pending <= 0 then
      atlas.state = "ready"
      Events.Fire("FP_SOURCES_UPDATED", "atlasloot")
    end
  end
  for _, moduleName in ipairs(atlas.modules) do
    ns.AtlasLoot.Load(moduleName, function(storage)
      if not storage then
        Log.Debug("AtlasLoot module %s is not available", moduleName)
      else
        local ok, added = Log.Capture(SourceProvider.IndexAtlasModule, storage)
        if ok then
          Log.Debug("Indexed AtlasLoot module %s: %d loot entries", moduleName, added)
        else
          Log.Error("AtlasLoot index failed for %s: %s", moduleName, tostring(added))
        end
      end
      done()
    end)
  end
  return atlas.state
end

function SourceProvider.AtlasSources(itemID)
  local atlas = SourceProvider.atlas
  if atlas.state == "idle" then
    SourceProvider.BuildAtlasIndex()
  end
  local out = {}
  for _, entry in ipairs(atlas.index[itemID] or {}) do
    out[#out + 1] = {
      kind = Routes.DROP, boss = entry.boss, instance = entry.instance, npcID = entry.npcID, atlasloot = true,
      label = "Dropped by " .. entry.boss,
      detail = entry.instance .. " (AtlasLoot)",
    }
  end
  return out
end

---------------------------------------------------------------------------
-- Aggregate
---------------------------------------------------------------------------
-- Resolver hints for itemID, most certain first. Callers take hints[1] as
-- the route, so this order is the contract:
--   1. recorded vendors (own, then shared)
--   2. loot learned on Forever (LootLearner)
--   3. boss drops: DungeonJournal, then AtlasLoot bosses the journal lacks
--   4. journal quest rewards
--   5. quest catalogue drops (items a curated quest asks for)
--   6. GearQuest Forever, minus vendors/quests already listed
--   7. reputation vendors (unavailable below the standing)
--   8. classic-db: drops, gathering, vendors (skipped when one is recorded)
--   9. the class heuristic - only for items no recipe makes, or that a
--      recipe merely refines from a lower tier
--  10. nothing found and the item is new in Forever: an unavailable
--      "New in Forever" hint that says why
function SourceProvider.Sources(itemID)
  local out = {}
  for _, hint in ipairs(Log.Try(ns.VendorProvider.ItemHints, itemID) or {}) do out[#out + 1] = hint end
  -- What actually dropped on Forever comes before every database.
  for _, hint in ipairs(Log.Try(ns.LootLearner.ItemHints, itemID) or {}) do
    if hint.kind == Routes.GATHER then hint = SourceProvider.QualifyGatherHint(hint) end
    out[#out + 1] = hint
  end
  local quests, bosses = {}, {}
  for _, hint in ipairs(SourceProvider.JournalSources(itemID)) do
    if hint.kind == Routes.QUEST then
      quests[#quests + 1] = hint
    else
      out[#out + 1] = hint
      bosses[string.lower(hint.boss or "")] = true
    end
  end
  for _, hint in ipairs(SourceProvider.AtlasSources(itemID)) do
    if not bosses[string.lower(hint.boss or "")] then out[#out + 1] = hint end
  end
  for _, hint in ipairs(quests) do out[#out + 1] = hint end
  -- The quest catalogue says where the items a curated quest asks for drop.
  for _, hint in ipairs(Log.Try(ns.QuestFactsProvider.ItemHints, itemID, ns.QuestProvider.Name) or {}) do out[#out + 1] = hint end
  -- GearQuest Forever knows where leveling gear comes from (vendor and npc,
  -- quest and zone, boss or world drop); it fills in what nothing above did.
  for _, hint in ipairs(Log.Try(ns.GearQuest.ItemHints, itemID) or {}) do
    local duplicate = false
    for _, existing in ipairs(out) do
      if existing.kind == hint.kind and (existing.kind == Routes.VENDOR and existing.name == hint.name or existing.kind == Routes.QUEST and existing.quest == hint.quest) then duplicate = true end
    end
    if not duplicate then out[#out + 1] = hint end
  end
  -- Reputation vendors (AtlasLoot's faction tables): a vendor option that
  -- is unavailable until the standing is reached.
  for _, hint in ipairs(Log.Try(ns.ReputationProvider.ItemHints, itemID) or {}) do out[#out + 1] = hint end
  -- Classic-era sources behind the Forever ones.
  local classicSkills = {}
  local CDB = ns.ClassicDB
  if CDB.IsAvailable() then
    local names = {}
    local recordedVendor = false
    for _, existing in ipairs(out) do
      if existing.boss then names[string.lower(existing.boss)] = true end
      if existing.kind == Routes.VENDOR then recordedVendor = true end
    end
    local _, classID = Compat.PlayerClass()
    for _, hint in ipairs(Log.Try(CDB.ItemHints, itemID, { skipVendors = recordedVendor, skipNames = names, classID = classID }) or {}) do
      if hint.kind == Routes.GATHER then
        hint = SourceProvider.QualifyGatherHint(hint)
        if hint.skill then classicSkills[hint.skill] = true end
      end
      out[#out + 1] = hint
    end
  end
  -- The class heuristic is for raw materials: an item a recipe makes keeps
  -- it only when that recipe merely refines a lower tier of the same thing.
  if #recipesFor(itemID) == 0 or SourceProvider.IsRawMaterial(itemID) then
    local hint = SourceProvider.QualifyGatherHint(SourceProvider.ClassHint(itemID))
    if hint and not (hint.skill and classicSkills[hint.skill]) then out[#out + 1] = hint end
  end
  -- Nothing at all, and the item is Forever's own: say why.
  if #out == 0 and CDB.IsAvailable() and CDB.IsNewInForever(itemID) then
    out[#out + 1] = { kind = Routes.DROP, unavailable = true, newInForever = true, label = "New in Forever", short = "New in Forever",
      detail = "not in the classic data; loot it once (or open a merchant that sells it) and ForeverPath remembers where it came from" }
  end
  return out
end

-- Chat-friendly description used by /fp sources.
function SourceProvider.Describe(itemID)
  local lines = {}
  for _, hint in ipairs(SourceProvider.Sources(itemID)) do
    lines[#lines + 1] = string.format("%s: %s%s", ns.DependencyResolver.RouteLabels[hint.kind] or hint.kind, hint.label or "?", hint.detail and (" - " .. hint.detail) or "")
  end
  return lines
end

-- Short "where it comes from" tags for a plan material ({ itemID, missing,
-- ownedBank, altSources }), at most one per kind: in bags, bank, a recipe,
-- an alt's bags, a vendor, a drop / gathering / quest source, an alt crafter.
function SourceProvider.MaterialTags(material)
  local tags = {}
  if material.missing == 0 then
    tags[#tags + 1] = "In bags"
  end
  if material.ownedBank and material.ownedBank > 0 then
    tags[#tags + 1] = "Bank"
  end
  local recipe = ns.ProfessionProvider.FindRecipesForItem(material.itemID)[1]
  if recipe then
    tags[#tags + 1] = recipe.learned and ("Craft - " .. (recipe.recipe.professionName or "?")) or "Recipe not learned"
  end
  local alt = (material.altSources or {})[1]
  if alt then
    tags[#tags + 1] = string.format("Alt: %s (%d)", alt.name, alt.count)
  end
  local hints = SourceProvider.Sources(material.itemID)
  for _, hint in ipairs(hints) do
    if hint.kind == Routes.VENDOR then
      tags[#tags + 1] = "Vendor: " .. (hint.name or "?")
      break
    end
  end
  for _, hint in ipairs(hints) do
    if (hint.kind == Routes.GATHER or hint.kind == Routes.DROP or hint.kind == Routes.QUEST) and not hint.unavailable then
      tags[#tags + 1] = hint.gatherer and (hint.label .. " - " .. hint.gatherer) or (hint.short or hint.label)
      break
    end
  end
  local crafter = ns.CharacterProvider.AltCrafters(material.itemID)[1]
  if crafter then
    tags[#tags + 1] = "Craft - Alt: " .. crafter.name
  end
  if #tags == 0 then
    tags[1] = "Unknown source"
  end
  return tags
end

-- Human-readable state of the optional data addons, for /fp vendors.
function SourceProvider.StatusInfo()
  local status = {}
  status.atlasloot = ns.AtlasLoot.IsAvailable() and ("installed, index " .. SourceProvider.atlas.state) or "not installed"
  if ns.DungeonJournal.IsAvailable() then
    local state = SourceProvider.BuildJournalIndex()
    status.journal = state == "ready" and string.format("installed, %d items indexed", SourceProvider.journal.items) or ("installed, index " .. state)
  else
    status.journal = "not installed"
  end
  return status
end

function SourceProvider.StatusLine()
  local status = SourceProvider.StatusInfo()
  return string.format("Item sources: AtlasLoot %s; DungeonJournal %s", status.atlasloot, status.journal)
end

function SourceProvider.Init()
  ns.ItemProvider.RegisterNameSource(ns.DungeonJournal.ItemNames)
end
