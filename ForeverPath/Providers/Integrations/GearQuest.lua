-- GearQuest Forever adapter: detection, the player's spec as GearQuest sees
-- it, its upgrade entries and per-item facts, and source hints built from
-- those facts. The one place that reads _G.GearQuest.
--
-- GearQuest Forever (_G.GearQuest) expands its generated per-class tables into
-- GQ.Data.entries: { itemId, slot ("Head", "Back", "MainHand", "SecondaryHand",
-- "Ranged", "Finger", "Trinket", ...), minLevel, maxLevel, curatedRank (1 =
-- best), pipelineScore, classes = { WARRIOR = true }, specs = { arms = true }
-- | nil, factions = { Alliance = true } | nil, sourceType, instructions, zone,
-- npc, questName, profession, reqRep }. The per-class item facts (name,
-- quality, ilvl, reqLevel) sit in GQ.Data.<class>ItemFacts tables, and
-- GQ.Data.scoredStats[itemID] holds stat totals. All are read as data; the
-- class file is loaded through GQ.Data:EnsureClassLoaded.
local _, ns = ...

local Compat = ns.Compat
local Util = ns.Util
local Routes = ns.DependencyResolver.Routes

local GearQuest = { factsCache = {} }
ns.GearQuest = GearQuest

-- Display names of GearQuest's source types.
GearQuest.SourceLabels = {
  vendor = "Vendor", quest_reward = "Quest", boss_drop = "Dungeon drop", raid_trash = "Raid trash", world_drop = "World drop",
  rare_npc = "Rare mob", profession = "Crafted", container = "Container", object_drop = "Object", fishing = "Fishing",
  mail = "Mail", special = "Special", unsourced = "Unknown source",
}

local function addon()
  local gq = _G.GearQuest
  if type(gq) == "table" and type(gq.Data) == "table" then return gq end
  return nil
end

function GearQuest.IsAvailable()
  return addon() ~= nil
end

-- Item facts are cached per session; a class load or gear change drops them.
function GearQuest.ResetCache()
  GearQuest.factsCache = {}
end

-- GearQuest's idea of the player's spec (talents, or the player's pick), and its label.
function GearQuest.Spec()
  local gq = addon()
  if not gq or type(gq.Spec) ~= "table" then return nil end
  local classFile = Compat.PlayerClass()
  local spec = Util.SafeCall(gq.Spec.GetDisplaySpec, gq.Spec, classFile)
  if type(spec) ~= "string" then return nil end
  local label = spec
  local text = Util.SafeCall(gq.Spec.GetSpecLabel, gq.Spec, spec, classFile)
  if type(text) == "string" then label = text end
  return spec, label
end

-- GearQuest's item facts for an item (name, quality, ilvl, reqLevel, sourceType...).
function GearQuest.Facts(itemID)
  local cached = GearQuest.factsCache[itemID]
  if cached ~= nil then return cached or nil end
  local gq = addon()
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
  GearQuest.factsCache[itemID] = found
  return found or nil
end

-- GearQuest's stat totals for an item ({ str = 5, ... }), or nil.
function GearQuest.ScoredStats(itemID)
  local gq = addon()
  local scored = gq and type(gq.Data.scoredStats) == "table" and itemID and gq.Data.scoredStats[itemID] or nil
  return type(scored) == "table" and scored or nil
end

-- Every item name in GearQuest's loaded facts tables, for name search.
function GearQuest.ItemNames()
  local names = {}
  local gq = addon()
  if not gq then return names end
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

-- The upgrade entries for a class (its file loaded first), or nil.
function GearQuest.Entries(classFile)
  local gq = addon()
  if not gq then return nil end
  if classFile and type(gq.Data.EnsureClassLoaded) == "function" then
    if Util.SafeCall(gq.Data.EnsureClassLoaded, gq.Data, classFile) then GearQuest.ResetCache() end
  end
  return type(gq.Data.entries) == "table" and gq.Data.entries or nil
end

local HINT_KINDS = {
  vendor = Routes.VENDOR, quest_reward = Routes.QUEST,
  boss_drop = Routes.DROP, raid_trash = Routes.DROP, rare_npc = Routes.DROP, world_drop = Routes.DROP,
  container = Routes.GATHER, object_drop = Routes.GATHER, fishing = Routes.GATHER,
}

-- Source hints for the resolver from GearQuest's facts: where a piece of
-- gear comes from (vendor and npc, quest and zone, boss or world drop).
function GearQuest.ItemHints(itemID)
  local facts = GearQuest.Facts(itemID)
  local kind = facts and HINT_KINDS[facts.sourceType]
  if not kind then return {} end
  local label = GearQuest.SourceLabels[facts.sourceType] or facts.sourceType
  if kind == Routes.VENDOR and facts.npc then label = "Vendor: " .. facts.npc end
  if kind == Routes.QUEST and facts.questName then label = "Quest reward: " .. facts.questName end
  local detail = facts.instructions
  if facts.zone and not (detail and detail:find(facts.zone, 1, true)) then detail = (detail and (detail .. " ") or "") .. "(" .. facts.zone .. ")" end
  return { { kind = kind, label = label, detail = detail, name = facts.npc, zone = facts.zone, quest = facts.questName, source = "GearQuest", gearQuest = true } }
end
