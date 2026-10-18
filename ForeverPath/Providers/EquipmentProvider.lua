-- Equipment: what is worn in every slot, the item stats and levels the client
-- reports, and the upgrade hunts GearQuest Forever ships for the player's
-- class, spec, faction and level band.
--
-- GearQuest Forever (_G.GearQuest) expands its generated per-class tables into
-- GQ.Data.entries: { itemId, slot ("Head", "Back", "MainHand", "SecondaryHand",
-- "Ranged", "Finger", "Trinket", ...), minLevel, maxLevel, curatedRank (1 =
-- best), pipelineScore, classes = { WARRIOR = true }, specs = { arms = true }
-- | nil, factions = { Alliance = true } | nil, sourceType, instructions, zone,
-- npc, questName, profession, reqRep }. The per-class item facts (name,
-- quality, ilvl, reqLevel) sit in GQ.Data.<class>ItemFacts tables. Both are
-- read as data; the class file is loaded through GQ.Data:EnsureClassLoaded.
local _, ns = ...

local Compat = ns.Compat
local Util = ns.Util
local Log = ns.Log
local Events = ns.Events

local EquipmentProvider = { factsCache = {} }
ns.EquipmentProvider = EquipmentProvider

EquipmentProvider.LEVEL_GRACE = 5

-- Display order (the handoff's two columns), inventory slot ids, GearQuest
-- slot names and the item equip locations that land in each.
EquipmentProvider.SLOTS = {
  { key = "Head", id = 1, label = "Head", gq = "Head", inv = { INVTYPE_HEAD = true } },
  { key = "Neck", id = 2, label = "Neck", gq = "Neck", inv = { INVTYPE_NECK = true } },
  { key = "Shoulder", id = 3, label = "Shoulder", gq = "Shoulder", inv = { INVTYPE_SHOULDER = true } },
  { key = "Back", id = 15, label = "Back", gq = "Back", inv = { INVTYPE_CLOAK = true } },
  { key = "Chest", id = 5, label = "Chest", gq = "Chest", inv = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
  { key = "Wrist", id = 9, label = "Wrist", gq = "Wrist", inv = { INVTYPE_WRIST = true } },
  { key = "Hands", id = 10, label = "Hands", gq = "Hands", inv = { INVTYPE_HAND = true } },
  { key = "Waist", id = 6, label = "Waist", gq = "Waist", inv = { INVTYPE_WAIST = true } },
  { key = "Legs", id = 7, label = "Legs", gq = "Legs", inv = { INVTYPE_LEGS = true } },
  { key = "Feet", id = 8, label = "Feet", gq = "Feet", inv = { INVTYPE_FEET = true } },
  { key = "Finger1", id = 11, label = "Finger 1", gq = "Finger", inv = { INVTYPE_FINGER = true } },
  { key = "Finger2", id = 12, label = "Finger 2", gq = "Finger", inv = { INVTYPE_FINGER = true } },
  { key = "Trinket1", id = 13, label = "Trinket 1", gq = "Trinket", inv = { INVTYPE_TRINKET = true } },
  { key = "Trinket2", id = 14, label = "Trinket 2", gq = "Trinket", inv = { INVTYPE_TRINKET = true } },
  { key = "MainHand", id = 16, label = "Main hand", gq = "MainHand", inv = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true } },
  { key = "OffHand", id = 17, label = "Off hand", gq = "SecondaryHand", inv = { INVTYPE_WEAPON = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true } },
  { key = "Ranged", id = 18, label = "Ranged", gq = "Ranged", inv = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true } },
}
EquipmentProvider.SlotByKey = {}
for _, slot in ipairs(EquipmentProvider.SLOTS) do EquipmentProvider.SlotByKey[slot.key] = slot end

-- Client item stat keys -> short keys, in display order.
EquipmentProvider.STATS = {
  { key = "ilvl", label = "Item level" },
  { key = "armor", label = "Armor", mod = "ITEM_MOD_ARMOR" },
  { key = "dps", label = "DPS", mod = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" },
  { key = "str", label = "Strength", mod = "ITEM_MOD_STRENGTH_SHORT" },
  { key = "agi", label = "Agility", mod = "ITEM_MOD_AGILITY_SHORT" },
  { key = "sta", label = "Stamina", mod = "ITEM_MOD_STAMINA_SHORT" },
  { key = "int", label = "Intellect", mod = "ITEM_MOD_INTELLECT_SHORT" },
  { key = "spi", label = "Spirit", mod = "ITEM_MOD_SPIRIT_SHORT" },
  { key = "ap", label = "Attack power", mod = "ITEM_MOD_ATTACK_POWER_SHORT" },
  { key = "sp", label = "Spell power", mod = "ITEM_MOD_SPELL_POWER_SHORT" },
  { key = "heal", label = "Healing", mod = "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
  { key = "crit", label = "Crit", mod = "ITEM_MOD_CRIT_RATING_SHORT" },
  { key = "hit", label = "Hit", mod = "ITEM_MOD_HIT_RATING_SHORT" },
  { key = "mp5", label = "Mana / 5s", mod = "ITEM_MOD_MANA_REGENERATION_SHORT" },
  { key = "fireRes", label = "Fire resistance", mod = "ITEM_MOD_FIRE_RESISTANCE" },
  { key = "natureRes", label = "Nature resistance", mod = "ITEM_MOD_NATURE_RESISTANCE" },
  { key = "frostRes", label = "Frost resistance", mod = "ITEM_MOD_FROST_RESISTANCE" },
  { key = "shadowRes", label = "Shadow resistance", mod = "ITEM_MOD_SHADOW_RESISTANCE" },
  { key = "arcaneRes", label = "Arcane resistance", mod = "ITEM_MOD_ARCANE_RESISTANCE" },
}
local MOD_TO_KEY = {}
for _, stat in ipairs(EquipmentProvider.STATS) do if stat.mod then MOD_TO_KEY[stat.mod] = stat.key end end
-- GearQuest's scoredStats keys already match the short keys above.

EquipmentProvider.SourceLabels = {
  vendor = "Vendor", quest_reward = "Quest", boss_drop = "Dungeon drop", raid_trash = "Raid trash", world_drop = "World drop",
  rare_npc = "Rare mob", profession = "Crafted", container = "Container", object_drop = "Object", fishing = "Fishing",
  mail = "Mail", special = "Special", unsourced = "Unknown source",
}
-- Source filter groups for the screen.
EquipmentProvider.SourceGroups = {
  { key = "any", label = "Any" },
  { key = "quest", label = "Quests", types = { quest_reward = true } },
  { key = "vendor", label = "Vendors", types = { vendor = true } },
  { key = "dungeon", label = "Dungeons", types = { boss_drop = true, raid_trash = true, rare_npc = true } },
  { key = "crafted", label = "Crafted", types = { profession = true } },
  { key = "drop", label = "Drops", types = { world_drop = true, container = true, object_drop = true, fishing = true } },
}

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
  return nil
end

function EquipmentProvider.IsAvailable()
  return type(_G.GetInventoryItemID) == "function"
end

local function gearQuest()
  local gq = _G.GearQuest
  if type(gq) == "table" and type(gq.Data) == "table" then return gq end
  return nil
end

function EquipmentProvider.HasGearQuest()
  return gearQuest() ~= nil
end

function EquipmentProvider.ClassFile()
  local _, classFile = call(UnitClass, "player")
  return type(classFile) == "string" and classFile or nil
end

function EquipmentProvider.Faction()
  local faction = call(UnitFactionGroup, "player")
  return type(faction) == "string" and faction or nil
end

function EquipmentProvider.PlayerLevel()
  return tonumber(call(UnitLevel, "player")) or 0
end

-- GearQuest's idea of the player's spec (talents, or the player's pick), and its label.
function EquipmentProvider.Spec()
  local gq = gearQuest()
  if not gq or type(gq.Spec) ~= "table" then return nil end
  local classFile = EquipmentProvider.ClassFile()
  local ok, spec = pcall(function() return gq.Spec:GetDisplaySpec(classFile) end)
  if not ok or type(spec) ~= "string" then return nil end
  local label = spec
  local ok2, text = pcall(function() return gq.Spec:GetSpecLabel(spec, classFile) end)
  if ok2 and type(text) == "string" then label = text end
  return spec, label
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- Item level from the client (detailed info, then item info), else GearQuest's facts.
function EquipmentProvider.ItemLevel(linkOrID)
  if not linkOrID then return nil end
  local cItem = type(C_Item) == "table" and C_Item or {}
  local level = call(cItem.GetDetailedItemLevelInfo, linkOrID)
  if tonumber(level) and level > 0 then return level end
  if Compat.GetItemInfo then
    local _, _, _, ilvl = call(Compat.GetItemInfo, linkOrID)
    if tonumber(ilvl) and ilvl > 0 then return ilvl end
  end
  local itemID = type(linkOrID) == "number" and linkOrID or tonumber(tostring(linkOrID):match("item:(%d+)"))
  local facts = itemID and EquipmentProvider.Facts(itemID)
  return facts and tonumber(facts.ilvl) or nil
end

-- { ilvl, armor, str, ... } for a link or id; empty when nothing is known.
function EquipmentProvider.Stats(linkOrID)
  local out = {}
  if not linkOrID then return out end
  local cItem = type(C_Item) == "table" and C_Item or {}
  local raw = call(cItem.GetItemStats, linkOrID)
  if type(raw) ~= "table" and type(_G.GetItemStats) == "function" then
    local legacy = {}
    local ok, result = pcall(_G.GetItemStats, linkOrID, legacy)
    if ok and (type(result) == "table" or next(legacy)) then raw = type(result) == "table" and result or legacy end
  end
  if type(raw) == "table" then
    for mod, value in pairs(raw) do
      local key = MOD_TO_KEY[mod]
      if key and tonumber(value) then out[key] = tonumber(value) end
    end
  end
  if next(out) == nil then
    local itemID = type(linkOrID) == "number" and linkOrID or tonumber(tostring(linkOrID):match("item:(%d+)"))
    local gq = gearQuest()
    local scored = gq and type(gq.Data.scoredStats) == "table" and itemID and gq.Data.scoredStats[itemID] or nil
    for key, value in pairs(type(scored) == "table" and scored or {}) do
      if tonumber(value) then out[key] = tonumber(value) end
    end
  end
  out.ilvl = EquipmentProvider.ItemLevel(linkOrID)
  return out
end

-- Slot keys an item can go in (from its equip location); {} when unknown.
function EquipmentProvider.SlotKeysFor(itemID)
  local keys = {}
  if not Util.IsPositiveInt(itemID) or not Compat.GetItemInfoInstant then return keys end
  local _, _, _, equipLoc = call(Compat.GetItemInfoInstant, itemID)
  if type(equipLoc) ~= "string" or equipLoc == "" then return keys end
  for _, slot in ipairs(EquipmentProvider.SLOTS) do
    if slot.inv[equipLoc] then keys[#keys + 1] = slot.key end
  end
  return keys
end

-- What is worn: { [key] = { slot, itemID, link, name, quality, icon, ilvl } } plus the ordered list.
function EquipmentProvider.Equipped()
  local byKey, list = {}, {}
  for _, slot in ipairs(EquipmentProvider.SLOTS) do
    local itemID = call(_G.GetInventoryItemID, "player", slot.id)
    local worn = { slot = slot, itemID = tonumber(itemID) }
    if worn.itemID then
      worn.link = call(_G.GetInventoryItemLink, "player", slot.id)
      local info = ns.ItemProvider and ns.ItemProvider.GetItem(worn.itemID) or {}
      worn.name, worn.quality, worn.icon = info.name, info.quality, info.icon
      worn.link = worn.link or info.link
      worn.ilvl = EquipmentProvider.ItemLevel(worn.link or worn.itemID)
    end
    byKey[slot.key] = worn
    list[#list + 1] = worn
  end
  return byKey, list
end

-- The client's equipped average when it has one, else the mean over the slots (empty = 0).
function EquipmentProvider.AverageItemLevel(list)
  local avg, equipped = call(_G.GetAverageItemLevel)
  local value = tonumber(equipped) or tonumber(avg)
  if value and value > 0 then return math.floor(value * 10 + 0.5) / 10 end
  local total, count = 0, 0
  for _, worn in ipairs(list or {}) do
    if worn.slot.key ~= "OffHand" or worn.itemID then
      total = total + (worn.ilvl or 0)
      count = count + 1
    end
  end
  if count == 0 then return 0 end
  return math.floor(total / count * 10 + 0.5) / 10
end

---------------------------------------------------------------------------
-- GearQuest hunts
---------------------------------------------------------------------------
-- GearQuest's item facts for an item (name, quality, ilvl, reqLevel, sourceType...).
function EquipmentProvider.Facts(itemID)
  local cached = EquipmentProvider.factsCache[itemID]
  if cached ~= nil then return cached or nil end
  local gq = gearQuest()
  local found = false
  if gq then
    for key, tbl in pairs(gq.Data) do
      if type(key) == "string" and type(tbl) == "table" and key:find("Facts") then
        local row = tbl[itemID]
        if type(row) == "table" and row.sourceType then
          found = row
          break
        end
      end
    end
  end
  EquipmentProvider.factsCache[itemID] = found
  return found or nil
end

-- Every item name in GearQuest's loaded facts tables, for name search.
function EquipmentProvider.ItemNames()
  local names = {}
  local gq = gearQuest()
  if not gq or type(gq.Data) ~= "table" then return names end
  for key, tbl in pairs(gq.Data) do
    if type(key) == "string" and type(tbl) == "table" and key:find("Facts") then
      for itemID, row in pairs(tbl) do
        if tonumber(itemID) and type(row) == "table" and type(row.name) == "string" and row.name ~= "" then
          names[tonumber(itemID)] = row.name
        end
      end
    end
  end
  return names
end

local function ensureClass(gq, classFile)
  if not classFile or type(gq.Data.EnsureClassLoaded) ~= "function" then return type(gq.Data.entries) == "table" end
  local ok, loaded = pcall(function() return gq.Data:EnsureClassLoaded(classFile) end)
  if ok and loaded then EquipmentProvider.factsCache = {} end
  return type(gq.Data.entries) == "table"
end

local function entryMatches(entry, classFile, spec, faction, level)
  if type(entry) ~= "table" or not entry.itemId then return false end
  if entry.classes and classFile and not entry.classes[classFile] then return false end
  if entry.specs and spec and not entry.specs[spec] then return false end
  if entry.factions and faction and not entry.factions[faction] then return false end
  if level < (entry.minLevel or 1) then return false end
  if level > (entry.maxLevel or level) + EquipmentProvider.LEVEL_GRACE then return false end
  return true
end

-- GearQuest's picks for one slot, best first:
--   { itemID, entry, rank, score, ilvl, name, quality, sourceType, sourceLabel, instructions, zone, npc, questName, profession, reqRep }
-- opts.source = a SourceGroups key ("any" default), opts.limit.
function EquipmentProvider.Candidates(slotKey, opts)
  opts = opts or {}
  local slot = EquipmentProvider.SlotByKey[slotKey]
  local gq = gearQuest()
  if not slot or not gq then return {} end
  local classFile = EquipmentProvider.ClassFile()
  if not ensureClass(gq, classFile) then return {} end
  local spec = EquipmentProvider.Spec()
  local faction = EquipmentProvider.Faction()
  local level = EquipmentProvider.PlayerLevel()
  local group
  for _, g in ipairs(EquipmentProvider.SourceGroups) do if g.key == (opts.source or "any") then group = g end end
  local best = {}
  for _, entry in ipairs(gq.Data.entries) do
    if entry.slot == slot.gq and entryMatches(entry, classFile, spec, faction, level) and (not group or not group.types or group.types[entry.sourceType]) then
      local current = best[entry.itemId]
      local rank = tonumber(entry.curatedRank) or 99
      if not current or rank < current.rank or (rank == current.rank and (tonumber(entry.pipelineScore) or 0) > (current.score or 0)) then
        best[entry.itemId] = { itemID = entry.itemId, entry = entry, rank = rank, score = tonumber(entry.pipelineScore) or 0 }
      end
    end
  end
  local out = {}
  for _, candidate in pairs(best) do
    local facts = EquipmentProvider.Facts(candidate.itemID)
    local info = ns.ItemProvider and ns.ItemProvider.GetItem(candidate.itemID) or {}
    local entry = candidate.entry
    candidate.name = info.name or (facts and facts.name) or ("Item " .. candidate.itemID)
    candidate.quality = info.quality or (facts and facts.quality)
    candidate.icon = info.icon
    candidate.ilvl = EquipmentProvider.ItemLevel(info.link or candidate.itemID) or (facts and tonumber(facts.ilvl)) or entry.minLevel
    candidate.reqLevel = facts and tonumber(facts.reqLevel) or nil
    candidate.sourceType = entry.sourceType or (facts and facts.sourceType) or "unsourced"
    candidate.sourceLabel = EquipmentProvider.SourceLabels[candidate.sourceType] or candidate.sourceType
    candidate.instructions = entry.instructions or (facts and facts.instructions)
    candidate.zone, candidate.npc, candidate.questName, candidate.profession, candidate.reqRep = entry.zone, entry.npc, entry.questName, entry.profession, entry.reqRep
    out[#out + 1] = candidate
  end
  table.sort(out, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.score ~= b.score then return a.score > b.score end
    if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
    return a.itemID < b.itemID
  end)
  if opts.limit and #out > opts.limit then
    for i = #out, opts.limit + 1, -1 do out[i] = nil end
  end
  return out
end

-- Source hints for the resolver from GearQuest's facts: where a piece of
-- gear comes from (vendor and npc, quest and zone, boss or world drop).
function EquipmentProvider.Hints(itemID)
  local facts = EquipmentProvider.Facts(itemID)
  if not facts then return {} end
  local kind
  local t = facts.sourceType
  if t == "vendor" then kind = "vendor"
  elseif t == "quest_reward" then kind = "quest"
  elseif t == "boss_drop" or t == "raid_trash" or t == "rare_npc" or t == "world_drop" then kind = "drop"
  elseif t == "container" or t == "object_drop" or t == "fishing" then kind = "gather"
  else return {} end
  local label = EquipmentProvider.SourceLabels[t] or t
  if kind == "vendor" and facts.npc then label = "Vendor: " .. facts.npc end
  if kind == "quest" and facts.questName then label = "Quest reward: " .. facts.questName end
  local detail = facts.instructions
  if facts.zone and not (detail and detail:find(facts.zone, 1, true)) then detail = (detail and (detail .. " ") or "") .. "(" .. facts.zone .. ")" end
  return { { kind = kind, label = label, detail = detail, name = facts.npc, zone = facts.zone, quest = facts.questName, source = "GearQuest", gearQuest = true } }
end

---------------------------------------------------------------------------
-- The whole picture
---------------------------------------------------------------------------
-- opts.source (filter), opts.goals (open goals), opts.views (goalID -> view)
-- Returns { slots = { { slot, equipped, candidates, best, status, goal, goalView, goalItemID } },
--           averageIlvl, upgradesPlanned, trackedGoals, hasGearQuest, spec, specLabel }
function EquipmentProvider.Analyze(opts)
  opts = opts or {}
  local byKey, list = EquipmentProvider.Equipped()
  local goals = opts.goals or {}
  local goalSlots = {}
  local tracked = 0
  for _, goal in ipairs(goals) do
    if goal.target and goal.target.itemID and (goal.type == "CRAFT_ITEM" or goal.type == "OBTAIN_ITEM") then
      local keys = EquipmentProvider.SlotKeysFor(goal.target.itemID)
      if #keys > 0 then
        tracked = tracked + 1
        local placed = false
        for _, key in ipairs(keys) do
          if not placed and not goalSlots[key] then
            goalSlots[key] = goal
            placed = true
          end
        end
        if not placed then goalSlots[keys[1]] = goalSlots[keys[1]] or goal end
      end
    end
  end
  local hasGQ = EquipmentProvider.HasGearQuest()
  local spec, specLabel = EquipmentProvider.Spec()
  local result = { slots = {}, averageIlvl = EquipmentProvider.AverageItemLevel(list), trackedGoals = tracked, upgradesPlanned = 0, hasGearQuest = hasGQ, spec = spec, specLabel = specLabel }
  for _, slot in ipairs(EquipmentProvider.SLOTS) do
    local worn = byKey[slot.key]
    local candidates = hasGQ and EquipmentProvider.Candidates(slot.key, { source = opts.source }) or {}
    local best
    for _, candidate in ipairs(candidates) do
      if not best and candidate.itemID ~= worn.itemID then best = candidate end
    end
    local status = "none"
    local goal = goalSlots[slot.key]
    if worn.itemID and candidates[1] and candidates[1].itemID == worn.itemID then
      status = "bis"
    elseif best and (not worn.itemID or (best.ilvl or 0) >= (worn.ilvl or 0)) then
      status = "upgrade"
    elseif not worn.itemID then
      status = "empty"
    end
    if goal then result.upgradesPlanned = result.upgradesPlanned + 1 end
    result.slots[#result.slots + 1] = {
      slot = slot, equipped = worn, candidates = candidates, best = best, status = status,
      goal = goal, goalView = goal and opts.views and opts.views[goal.id] or nil, goalItemID = goal and goal.target.itemID or nil,
    }
  end
  return result
end

function EquipmentProvider.Status()
  if not EquipmentProvider.IsAvailable() then
    return "Equipment: the inventory API (GetInventoryItemID) is unavailable on this client."
  end
  local _, list = EquipmentProvider.Equipped()
  local worn = 0
  for _, entry in ipairs(list) do if entry.itemID then worn = worn + 1 end end
  local spec, label = EquipmentProvider.Spec()
  return string.format("Equipment: %d of %d slots filled, average item level %s; upgrade hunts %s.", worn, #list, tostring(EquipmentProvider.AverageItemLevel(list)),
    EquipmentProvider.HasGearQuest() and ("from GearQuest Forever" .. (label and (" (" .. label .. ")") or "")) or "unavailable (GearQuest Forever not installed)")
end

local function changed(reason)
  EquipmentProvider.factsCache = {}
  Events.Debounce("equipment-updated", 0.5, function()
    Events.Fire("FP_EQUIPMENT_UPDATED", reason)
  end)
end

function EquipmentProvider.Init()
  if ns.ItemProvider and ns.ItemProvider.RegisterNameSource then ns.ItemProvider.RegisterNameSource(EquipmentProvider.ItemNames) end
  if not EquipmentProvider.IsAvailable() then
    Log.Debug("GetInventoryItemID missing; equipment provider disabled")
    return
  end
  Events.RegisterWoW("PLAYER_EQUIPMENT_CHANGED", function() changed("equipment") end)
  Events.RegisterWoW("UNIT_INVENTORY_CHANGED", function(unit)
    if unit == "player" then changed("inventory") end
  end)
end
