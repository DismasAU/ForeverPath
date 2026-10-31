-- Questie bridge: reads Questie's quest database at runtime when Questie is
-- installed and loaded (read-only; nothing is copied or stored).
--
-- Questie keeps its data behind its module loader:
--   QuestieLoader:ImportModule("QuestieDB") with
--     GetQuest(questID)  -> { name, questLevel, requiredLevel, requiredRaces,
--                             requiredClasses, startedBy = { npcs, objects, items },
--                             finishedBy = { npcs, objects }, objectives,
--                             preQuestSingle (any of), preQuestGroup (all of),
--                             sourceItemId, nextQuestInChain, zoneOrSort }
--     GetNPC(npcID)      -> { name, minLevel, maxLevel, rank, spawns =
--                             { [areaID] = { { x, y }, ... } } (percent), friendly }
--     GetObject(id), GetItem(itemID) (questRewards = { questID, ... })
--   QuestieLoader:ImportModule("ZoneDB"):GetUiMapIdByAreaId(areaID)
-- Questie's Forever port is maintained by its own team, so its facts rank
-- above CMaNGOS classic-db and below everything Forever-specific (learned
-- facts, the shipped catalogue, ForeverDungeonJournal, Attune). Entries come
-- back in QuestProvider's entry shape with source = "questie".
local _, ns = ...

local Log = ns.Log
local Util = ns.Util
local Compat = ns.Compat

local QuestieBridge = { entries = {} }
ns.QuestieBridge = QuestieBridge

local ALLIANCE_BITS = { 1, 4, 8, 64, 1024 }      -- Human, Dwarf, Night Elf, Gnome, Draenei
local HORDE_BITS = { 2, 16, 32, 128, 512 }        -- Orc, Undead, Tauren, Troll, Blood Elf

local function module(name)
  local loader = _G.QuestieLoader
  if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
  local mod = Util.SafeCall(loader.ImportModule, loader, name)
  if type(mod) == "table" then return mod end
  return nil
end

local function db()
  local q = module("QuestieDB")
  if q and type(q.GetQuest) == "function" and type(q.GetNPC) == "function" then return q end
  return nil
end

function QuestieBridge.IsAvailable()
  return db() ~= nil
end

function QuestieBridge.Reset()
  QuestieBridge.entries = {}
end

local function hasBit(mask, bit)
  return mask and bit and math.floor(mask / bit) % 2 == 1
end

local function sideOf(races)
  races = tonumber(races) or 0
  if races == 0 then return "Both" end
  local a, h = false, false
  for _, bit in ipairs(ALLIANCE_BITS) do if hasBit(races, bit) then a = true end end
  for _, bit in ipairs(HORDE_BITS) do if hasBit(races, bit) then h = true end end
  if a and not h then return "Alliance" end
  if h and not a then return "Horde" end
  return "Both"
end

local function callQuestie(q, fn, ...)
  if type(q[fn]) ~= "function" then return nil end
  -- QuestieDB mixes "." and ":" methods; GetQuest takes the id first, GetNPC / GetObject / GetItem take self.
  local result
  if fn == "GetQuest" then
    result = Util.SafeCall(q[fn], ...)
  else
    result = Util.SafeCall(q[fn], q, ...)
  end
  if type(result) == "table" then return result end
  return nil
end

local function list(t)
  local out = {}
  for _, v in ipairs(type(t) == "table" and t or {}) do
    if tonumber(v) then out[#out + 1] = tonumber(v) end
  end
  return #out > 0 and out or nil
end

-- A place from a Questie NPC or object: the first spawn on a zone map.
local function place(thing)
  if type(thing) ~= "table" or type(thing.name) ~= "string" then return nil end
  local zoneDB = module("ZoneDB")
  local result = { name = thing.name, questie = true }
  for areaID, coords in pairs(type(thing.spawns) == "table" and thing.spawns or {}) do
    local first = type(coords) == "table" and coords[1]
    if type(first) == "table" and tonumber(first[1]) and tonumber(first[2]) then
      local uiMapID
      if zoneDB and type(zoneDB.GetUiMapIdByAreaId) == "function" then
        uiMapID = tonumber((Util.SafeCall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaID)))
      end
      if uiMapID then
        result.mapID, result.x, result.y = uiMapID, first[1] / 100, first[2] / 100
        result.zone = ns.ClassicDB.ZoneName(uiMapID) or result.zone
        if not result.zone and type(C_Map) == "table" and type(C_Map.GetMapInfo) == "function" then
          local info = Util.SafeCall(C_Map.GetMapInfo, uiMapID)
          result.zone = type(info) == "table" and info.name or nil
        end
        break
      end
    end
  end
  result.label = result.name .. (result.zone and (" - " .. result.zone) or "")
  return result
end

function QuestieBridge.PlaceOf(npcIDs, objectIDs)
  local q = db()
  if not q then return nil end
  for _, id in ipairs(npcIDs or {}) do
    local p = place(callQuestie(q, "GetNPC", id))
    if p then return p end
  end
  for _, id in ipairs(objectIDs or {}) do
    local p = place(callQuestie(q, "GetObject", id))
    if p then return p end
  end
  return nil
end

-- A quest in QuestProvider's entry shape (cached), or nil.
function QuestieBridge.Quest(questID)
  questID = tonumber(questID)
  if not questID then return nil end
  local cached = QuestieBridge.entries[questID]
  if cached ~= nil then return cached or nil end
  local q = db()
  local raw = q and callQuestie(q, "GetQuest", questID)
  if not raw or type(raw.name) ~= "string" then
    QuestieBridge.entries[questID] = false
    return nil
  end
  local startedBy = type(raw.startedBy) == "table" and raw.startedBy or {}
  local finishedBy = type(raw.finishedBy) == "table" and raw.finishedBy or {}
  local objectives = type(raw.objectives) == "table" and raw.objectives or {}
  local items = {}
  for _, o in ipairs(type(objectives[3]) == "table" and objectives[3] or {}) do
    if type(o) == "table" and tonumber(o[1]) then items[#items + 1] = { itemID = tonumber(o[1]), count = 1 } end
  end
  local kills = {}
  for _, o in ipairs(type(objectives[1]) == "table" and objectives[1] or {}) do
    if type(o) == "table" and tonumber(o[1]) then kills[#kills + 1] = { id = tonumber(o[1]), count = 1 } end
  end
  -- preQuestSingle: any one of them; preQuestGroup: every one of them.
  local prerequisites = {}
  local single = list(raw.preQuestSingle)
  if single then prerequisites[#prerequisites + 1] = single end
  for _, id in ipairs(list(raw.preQuestGroup) or {}) do prerequisites[#prerequisites + 1] = { id } end
  local giver = QuestieBridge.PlaceOf(list(startedBy[1]), list(startedBy[2]))
  local entry = {
    id = questID, name = raw.name, level = tonumber(raw.questLevel), requires = tonumber(raw.requiredLevel),
    faction = sideOf(raw.requiredRaces), classMask = tonumber(raw.requiredClasses) or 0,
    instance = (giver and giver.zone) or "Questie", location = giver and giver.zone or nil,
    objective = type(raw.objectivesText) == "table" and raw.objectivesText[1] or nil,
    rewards = {}, rewardChoice = false, source = "questie", questie = true,
    prerequisites = #prerequisites > 0 and prerequisites or nil, followUp = tonumber(raw.nextQuestInChain),
    providedItem = tonumber(raw.sourceItemId),
    starterNpcs = list(startedBy[1]), starterObjects = list(startedBy[2]), starterItem = list(startedBy[3]) and list(startedBy[3])[1] or nil,
    enderNpcs = list(finishedBy[1]), enderObjects = list(finishedBy[2]),
    items = items, kills = kills, reputation = {},
  }
  QuestieBridge.entries[questID] = entry
  return entry
end

function QuestieBridge.Giver(questID)
  local entry = QuestieBridge.Quest(questID)
  return entry and QuestieBridge.PlaceOf(entry.starterNpcs, entry.starterObjects) or nil
end

function QuestieBridge.Turnin(questID)
  local entry = QuestieBridge.Quest(questID)
  return entry and QuestieBridge.PlaceOf(entry.enderNpcs, entry.enderObjects) or nil
end

-- The bridges' shared contract (as ClassicDB.Eligible): can a character of
-- this faction and classID take the entry? nil means the player's.
function QuestieBridge.Eligible(entry, faction, classID)
  if not entry then return false end
  faction = faction or Compat.PlayerFaction()
  if entry.faction and entry.faction ~= "Both" and faction and entry.faction ~= faction then return false end
  return Util.ClassAllowed(entry.classMask, classID or select(2, Compat.PlayerClass()))
end

-- Quests Questie says reward itemID that a character of this faction and
-- class can take (entries), like ClassicDB.QuestsRewarding.
function QuestieBridge.QuestsRewarding(itemID, faction, classID)
  local q = db()
  local item = q and callQuestie(q, "GetItem", tonumber(itemID))
  local out = {}
  for _, questID in ipairs(item and list(item.questRewards) or {}) do
    local entry = QuestieBridge.Quest(questID)
    if entry and QuestieBridge.Eligible(entry, faction, classID) then out[#out + 1] = entry end
  end
  return out
end

function QuestieBridge.StatusLine()
  if not _G.QuestieLoader then return "Questie: not installed (optional: its Forever port adds quest givers and chains)." end
  if not QuestieBridge.IsAvailable() then return "Questie: installed, but its quest database is not ready." end
  return "Questie: quest database available (givers, turn-ins, chains; behind Forever data, ahead of classic data)."
end

function QuestieBridge.Init()
  QuestieBridge.Reset()
  Log.Debug("%s", QuestieBridge.StatusLine())
end
