-- Equipment: what is worn in every slot, the item stats and levels the client
-- reports, and the upgrade hunts GearQuest Forever ships for the player's
-- class, spec, faction and level band (read through ns.GearQuestBridge).
local _, ns = ...

local Compat = ns.Compat
local Util = ns.Util
local Log = ns.Log
local Events = ns.Events
local Routes = ns.DependencyResolver.Routes

local EquipmentProvider = {}
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

-- Source filter groups for the screen.
EquipmentProvider.SourceGroups = {
  { key = "any", label = "Any" },
  { key = "quest", label = "Quests", types = { quest_reward = true } },
  { key = "vendor", label = "Vendors", types = { vendor = true } },
  { key = "dungeon", label = "Dungeons", types = { boss_drop = true, raid_trash = true, rare_npc = true } },
  { key = "crafted", label = "Crafted", types = { profession = true } },
  { key = "drop", label = "Drops", types = { world_drop = true, container = true, object_drop = true, fishing = true } },
}

local call = Util.SafeCall

function EquipmentProvider.IsAvailable()
  return type(_G.GetInventoryItemID) == "function"
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
  local facts = itemID and ns.GearQuestBridge.Facts(itemID)
  return facts and tonumber(facts.ilvl) or nil
end

-- { ilvl, armor, str, ... } for a link or id; empty when nothing is known.
function EquipmentProvider.Stats(linkOrID)
  local out = {}
  if not linkOrID then return out end
  local raw = Compat.GetItemStats(linkOrID)
  if type(raw) == "table" then
    for mod, value in pairs(raw) do
      local key = MOD_TO_KEY[mod]
      if key and tonumber(value) then out[key] = tonumber(value) end
    end
  end
  if next(out) == nil then
    local itemID = type(linkOrID) == "number" and linkOrID or tonumber(tostring(linkOrID):match("item:(%d+)"))
    for key, value in pairs(ns.GearQuestBridge.ScoredStats(itemID) or {}) do
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
      local info = ns.ItemProvider.GetItem(worn.itemID) or {}
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
  local GQ = ns.GearQuestBridge
  local slot = EquipmentProvider.SlotByKey[slotKey]
  local classFile = Compat.PlayerClass()
  local entries = slot and GQ.Entries(classFile)
  if not entries then return {} end
  local spec = GQ.Spec()
  local faction = Compat.PlayerFaction()
  local level = Compat.PlayerLevel()
  local group
  for _, g in ipairs(EquipmentProvider.SourceGroups) do if g.key == (opts.source or "any") then group = g end end
  local best = {}
  for _, entry in ipairs(entries) do
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
    local facts = GQ.Facts(candidate.itemID)
    local info = ns.ItemProvider.GetItem(candidate.itemID) or {}
    local entry = candidate.entry
    candidate.name = info.name or (facts and facts.name) or ("Item " .. candidate.itemID)
    candidate.quality = info.quality or (facts and facts.quality)
    candidate.icon = info.icon
    candidate.ilvl = EquipmentProvider.ItemLevel(info.link or candidate.itemID) or (facts and tonumber(facts.ilvl)) or entry.minLevel
    candidate.reqLevel = facts and tonumber(facts.reqLevel) or nil
    candidate.sourceType = entry.sourceType or (facts and facts.sourceType) or "unsourced"
    candidate.sourceLabel = GQ.SourceLabels[candidate.sourceType] or candidate.sourceType
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

---------------------------------------------------------------------------
-- The whole picture
---------------------------------------------------------------------------
-- What is worn and what GearQuest would hunt, per slot. Which goal serves a
-- slot is GoalService.Equipment's business. opts.source filters candidates.
-- Returns { slots = { { slot, equipped, candidates, best, upgrade } },
--           averageIlvl, hasGearQuest, spec, specLabel }
function EquipmentProvider.Analyze(opts)
  opts = opts or {}
  local byKey, list = EquipmentProvider.Equipped()
  local hasGQ = ns.GearQuestBridge.IsAvailable()
  local spec, specLabel = ns.GearQuestBridge.Spec()
  local result = { slots = {}, averageIlvl = EquipmentProvider.AverageItemLevel(list), hasGearQuest = hasGQ, spec = spec, specLabel = specLabel }
  for _, slot in ipairs(EquipmentProvider.SLOTS) do
    local worn = byKey[slot.key]
    local candidates = hasGQ and EquipmentProvider.Candidates(slot.key, { source = opts.source }) or {}
    local best
    for _, candidate in ipairs(candidates) do
      if not best and candidate.itemID ~= worn.itemID then best = candidate end
    end
    local upgrade = "none"
    if worn.itemID and candidates[1] and candidates[1].itemID == worn.itemID then
      upgrade = "bis"
    elseif best and (not worn.itemID or (best.ilvl or 0) >= (worn.ilvl or 0)) then
      upgrade = "upgrade"
    elseif not worn.itemID then
      upgrade = "empty"
    end
    result.slots[#result.slots + 1] = { slot = slot, equipped = worn, candidates = candidates, best = best, upgrade = upgrade }
  end
  return result
end

function EquipmentProvider.StatusLine()
  if not EquipmentProvider.IsAvailable() then
    return "Equipment: the inventory API (GetInventoryItemID) is unavailable on this client."
  end
  local _, list = EquipmentProvider.Equipped()
  local worn = 0
  for _, entry in ipairs(list) do if entry.itemID then worn = worn + 1 end end
  local _, label = ns.GearQuestBridge.Spec()
  return string.format("Equipment: %d of %d slots filled, average item level %s; upgrade hunts %s.", worn, #list, tostring(EquipmentProvider.AverageItemLevel(list)),
    ns.GearQuestBridge.IsAvailable() and ("from GearQuest Forever" .. (label and (" (" .. label .. ")") or "")) or "unavailable (GearQuest Forever not installed)")
end

local function changed(reason)
  ns.GearQuestBridge.ResetCache()
  Events.Debounce("equipment-updated", 0.5, function()
    Events.Fire("FP_EQUIPMENT_UPDATED", reason)
  end)
end

function EquipmentProvider.Init()
  ns.ItemProvider.RegisterNameSource(ns.GearQuestBridge.ItemNames)
  if not EquipmentProvider.IsAvailable() then
    Log.Debug("GetInventoryItemID missing; equipment provider disabled")
    return
  end
  Events.RegisterWoW("PLAYER_EQUIPMENT_CHANGED", function() changed("equipment") end)
  Events.RegisterWoW("UNIT_INVENTORY_CHANGED", function(unit)
    if unit == "player" then changed("inventory") end
  end)
end
