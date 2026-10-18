-- Where an item comes from, aggregated from the sources that are available on
-- this client without any external service:
--   1. vendors recorded from merchant windows (VendorProvider),
--   2. item class heuristics (Data/ItemClasses.lua): herbs are picked, ore is
--      mined, leather is skinned, cloth drops from humanoids,
--   3. ForeverDungeonJournal's boss loot, shared loot and dungeon quest
--      rewards (Forever-specific data, read from its namespace at runtime),
--   4. AtlasLootClassic's dungeon and raid loot tables, when that addon is
--      installed and enabled (read at runtime, never copied).
-- Everything is returned as resolver hints: { kind, label, detail, ... }.
local _, ns = ...

local Compat = ns.Compat
local Log = ns.Log
local Events = ns.Events

local SourceProvider = {
  atlas = { state = "idle", index = {}, modules = { "AtlasLootClassic_DungeonsAndRaids" } },
  journal = { state = "idle", index = {}, items = 0 },
}
ns.SourceProvider = SourceProvider

SourceProvider.MAX_ATLAS_ENTRIES = 3
SourceProvider.MAX_JOURNAL_ENTRIES = 3
SourceProvider.JOURNAL_GLOBAL = "ForeverDungeonJournal_NS"

---------------------------------------------------------------------------
-- ForeverDungeonJournal bridge
---------------------------------------------------------------------------
-- The journal keeps its data in a global namespace:
--   DB[dungeonName] = { bosses = { { name, npcID, trash, loot = { { itemID, name, slot, quality, mobName } } } },
--                       quests = { { id, name, faction, rewardChoice, rewardItems = { { itemID, name, quality } } } } }
--   SHARED_BY_BOSS[dungeonName][bossName] = { { itemID, name, slot, quality } }
function SourceProvider.HasDungeonJournal()
  local fdj = _G[SourceProvider.JOURNAL_GLOBAL]
  return type(fdj) == "table" and type(fdj.DB) == "table"
end

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
  local fdj = _G[SourceProvider.JOURNAL_GLOBAL]
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
                kind = "drop", instance = dungeonName, npcID = boss.npcID, trash = boss.trash == true,
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
            if type(entry) == "table" and addJournalEntry(index, entry[1], { kind = "drop", instance = dungeonName, boss = tostring(bossName), shared = true }, cap) then
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
                kind = "quest", instance = dungeonName, quest = quest.name or "?", questID = quest.id,
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
  for _ in pairs(index) do items = items + 1 end
  SourceProvider.journal.index = index
  SourceProvider.journal.items = items
  return added
end

-- Indexes the journal once per session, the first time a source is asked for.
function SourceProvider.BuildJournalIndex()
  local journal = SourceProvider.journal
  if journal.state ~= "idle" then return journal.state end
  if not SourceProvider.HasDungeonJournal() then return journal.state end
  local ok, added = pcall(SourceProvider.IndexDungeonJournal)
  if ok then
    journal.state = "ready"
    Log.Debug("Indexed DungeonJournal: %d loot and quest entries for %d items", added, journal.items)
  else
    journal.state = "failed"
    Log.Debug("DungeonJournal index failed: %s", tostring(added))
  end
  return journal.state
end

function SourceProvider.JournalSources(itemID)
  if SourceProvider.journal.state == "idle" then
    SourceProvider.BuildJournalIndex()
  end
  local out = {}
  for _, entry in ipairs(SourceProvider.journal.index[itemID] or {}) do
    if entry.kind == "quest" then
      out[#out + 1] = {
        kind = "quest", quest = entry.quest, questID = entry.questID, instance = entry.instance,
        choice = entry.choice, faction = entry.faction, pickup = entry.pickup, journal = true,
        label = "Quest reward: " .. entry.quest,
        detail = entry.instance .. (entry.choice and " - choose on turn-in" or "")
          .. ((entry.faction and entry.faction ~= "Both") and (" - " .. entry.faction) or "") .. " (DungeonJournal)",
      }
    else
      out[#out + 1] = {
        kind = "drop", boss = entry.boss, instance = entry.instance, npcID = entry.npcID,
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
    local ok, _, _, _, _, _, classID, subclassID = pcall(Compat.GetItemInfoInstant, itemID)
    if ok and type(classID) == "number" then return classID, subclassID end
  end
  local catalogue = ns.Data and ns.Data.Recipes
  if catalogue and catalogue.ItemClass then
    return catalogue.ItemClass(itemID)
  end
  return nil
end

function SourceProvider.ClassHint(itemID)
  if not ns.Data or not ns.Data.ItemClasses then return nil end
  local classID, subclassID = SourceProvider.ItemClass(itemID)
  if type(classID) ~= "number" then return nil end
  return ns.Data.ItemClasses.Lookup(classID, subclassID)
end

-- Every recipe (recorded or catalogue) that makes itemID.
local function recipesFor(itemID)
  local out = {}
  if ns.ProfessionProvider and ns.ProfessionProvider.FindRecipesForItem then
    for _, candidate in ipairs(ns.ProfessionProvider.FindRecipesForItem(itemID) or {}) do
      out[#out + 1] = candidate.recipe
    end
  end
  local catalogue = ns.Data and ns.Data.Recipes
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
  if not hint or hint.kind ~= "gather" or not hint.skill then return false end
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
    if not sub or sub.kind ~= "gather" or sub.skill ~= hint.skill then return false end
  end
  return true
end

-- Characters that have a gathering skill, this character first, then the
-- snapshotted alts: { { name, skillLevel, isCurrent } }.
function SourceProvider.GatherersFor(skill)
  if not skill or not ns.CharacterProvider or not ns.CharacterProvider.WithProfession then return {} end
  return ns.CharacterProvider.WithProfession(skill)
end

-- A gathering hint is only a route when someone can actually gather: it is
-- annotated with who has the skill, or marked unavailable (still shown as
-- information, never recommended).
function SourceProvider.QualifyGatherHint(hint)
  if not hint or hint.kind ~= "gather" or not hint.skill then return hint end
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
function SourceProvider.HasAtlasLoot()
  local atlas = _G.AtlasLoot
  return type(atlas) == "table" and type(atlas.ItemDB) == "table" and type(atlas.ItemDB.Storage) == "table"
end

local function contentName(content)
  if type(content.GetName) == "function" then
    local ok, name = pcall(content.GetName, content, true)
    if ok and type(name) == "string" then return name end
  end
  return type(content.name) == "string" and content.name or "?"
end

-- Walks one loaded AtlasLoot module's storage into index[itemID] = { { instance, boss, npcID } }.
function SourceProvider.IndexAtlasModule(moduleName)
  local storage = _G.AtlasLoot.ItemDB.Storage[moduleName]
  if type(storage) ~= "table" then return 0 end
  local index = SourceProvider.atlas.index
  local added = 0
  for key, content in pairs(storage) do
    if type(key) == "string" and key ~= "__atlaslootdata" and type(content) == "table" and type(content.items) == "table" then
      local instance = contentName(content)
      for _, boss in ipairs(content.items) do
        if type(boss) == "table" then
          for dif, items in pairs(boss) do
            if type(dif) == "number" and type(items) == "table" then
              for _, entry in ipairs(items) do
                local itemID = type(entry) == "table" and entry[2] or nil
                if type(itemID) == "number" and itemID > 0 then
                  local list = index[itemID]
                  if not list then
                    list = {}
                    index[itemID] = list
                  end
                  local duplicate = false
                  for _, existing in ipairs(list) do
                    if existing.boss == boss.name and existing.instance == instance then duplicate = true end
                  end
                  if not duplicate and #list < SourceProvider.MAX_ATLAS_ENTRIES then
                    list[#list + 1] = { instance = instance, boss = boss.name or "?", npcID = boss.npcID }
                    added = added + 1
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return added
end

-- Loads the AtlasLoot loot modules on demand and indexes them once per session.
function SourceProvider.BuildAtlasIndex()
  local atlas = SourceProvider.atlas
  if atlas.state ~= "idle" or not SourceProvider.HasAtlasLoot() then
    return atlas.state
  end
  atlas.state = "loading"
  local pending = #atlas.modules
  local function finish(moduleName)
    local ok, added = pcall(SourceProvider.IndexAtlasModule, moduleName)
    if ok then
      Log.Debug("Indexed AtlasLoot module %s: %d loot entries", moduleName, added)
    else
      Log.Debug("AtlasLoot index failed for %s: %s", moduleName, tostring(added))
    end
    pending = pending - 1
    if pending <= 0 then
      atlas.state = "ready"
      Events.Fire("FP_SOURCES_UPDATED", "atlasloot")
    end
  end
  local loader = _G.AtlasLoot.Loader
  for _, moduleName in ipairs(atlas.modules) do
    local result
    if type(loader) == "table" and type(loader.LoadModule) == "function" then
      local ok, state = pcall(loader.LoadModule, loader, moduleName, finish, true)
      result = ok and state or nil
    end
    if result ~= true and result ~= "InCombat" and type(_G.AtlasLoot.ItemDB.Storage[moduleName]) == "table" then
      -- Already loaded (LoadModule returned a state) or loader unavailable: index what is there.
      finish(moduleName)
    elseif result ~= true and result ~= "InCombat" and result ~= nil then
      finish(moduleName) -- module missing/disabled: nothing to index, but do not block
    end
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
      kind = "drop", boss = entry.boss, instance = entry.instance, npcID = entry.npcID, atlasloot = true,
      label = "Dropped by " .. entry.boss,
      detail = entry.instance .. " (AtlasLoot)",
    }
  end
  return out
end

---------------------------------------------------------------------------
-- Aggregate
---------------------------------------------------------------------------
-- Resolver hints for itemID, cheapest/most certain first: vendors, then boss
-- drops (DungeonJournal first, AtlasLoot entries for the same boss folded
-- in), then quest rewards, then the class heuristic (skipped when a recipe
-- is recorded for the item, because then crafting is the real source).
function SourceProvider.Sources(itemID)
  local out = {}
  if ns.VendorProvider then
    for _, hint in ipairs(ns.VendorProvider.Sources(itemID)) do out[#out + 1] = hint end
  end
  local quests, bosses = {}, {}
  for _, hint in ipairs(SourceProvider.JournalSources(itemID)) do
    if hint.kind == "quest" then
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
  -- GearQuest Forever knows where leveling gear comes from (vendor and npc,
  -- quest and zone, boss or world drop); it fills in what nothing above did.
  if ns.EquipmentProvider and ns.EquipmentProvider.Hints then
    local ok, hints = pcall(ns.EquipmentProvider.Hints, itemID)
    for _, hint in ipairs(ok and hints or {}) do
      local duplicate = false
      for _, existing in ipairs(out) do
        if existing.kind == hint.kind and (existing.kind == "vendor" and existing.name == hint.name or existing.kind == "quest" and existing.quest == hint.quest) then duplicate = true end
      end
      if not duplicate then out[#out + 1] = hint end
    end
  end
  -- Reputation vendors (AtlasLoot's faction tables): a vendor option that
  -- is unavailable until the standing is reached.
  if ns.ReputationProvider and ns.ReputationProvider.Hints then
    local ok, hints = pcall(ns.ReputationProvider.Hints, itemID)
    for _, hint in ipairs(ok and hints or {}) do out[#out + 1] = hint end
  end
  -- The class heuristic is for raw materials: an item a recipe makes keeps
  -- it only when that recipe merely refines a lower tier of the same thing.
  if #recipesFor(itemID) == 0 or SourceProvider.IsRawMaterial(itemID) then
    local hint = SourceProvider.QualifyGatherHint(SourceProvider.ClassHint(itemID))
    if hint then out[#out + 1] = hint end
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

-- Human-readable state of the optional data addons, for /fp vendors.
function SourceProvider.Status()
  local status = {}
  status.atlasloot = SourceProvider.HasAtlasLoot() and ("installed, index " .. SourceProvider.atlas.state) or "not installed"
  if SourceProvider.HasDungeonJournal() then
    local state = SourceProvider.BuildJournalIndex()
    status.journal = state == "ready" and string.format("installed, %d items indexed", SourceProvider.journal.items) or ("installed, index " .. state)
  else
    status.journal = "not installed"
  end
  return status
end

function SourceProvider.Init()
  Events.On("FP_SOURCES_UPDATED", function()
    if ns.UI and ns.UI.MainFrame then ns.UI.MainFrame.RequestRefresh() end
  end)
end
