-- Loot learner: what actually drops on Forever, recorded as you loot.
--
-- Every loot window (LOOT_READY) is read slot by slot: the item, the
-- quantity and the source (GetLootSourceInfo: the corpse's or object's
-- GUID; area loot lists several). Each source is stored account-wide in
-- ForeverPathDB.lootSeen:
--   ["c:<npcID>"] / ["o:<objectID>"] / ["f:<zone>"] = {
--     name, kind ("creature" | "object" | "fishing"), zone, mapID, x, y,
--     looted = number of corpses / nodes / casts looted,
--     items = { [itemID] = { times, quantity } },
--     skinned = { [itemID] = { times, quantity } },   -- a corpse looted a second time
--     seenAt }
-- These observations are Forever's own data, so SourceProvider lists them
-- before ForeverDungeonJournal, AtlasLoot and classic-db, and a classic
-- source for the same creature is dropped in their favour.
local _, ns = ...

local Compat = ns.Compat
local Util = ns.Util
local Log = ns.Log
local Events = ns.Events

local LootLearner = { counted = {}, index = nil }
ns.LootLearner = LootLearner

LootLearner.MAX_HINTS = 3

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h, i, j = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h, i, j end
  return nil
end

function LootLearner.IsAvailable()
  return type(_G.GetNumLootItems) == "function" and type(_G.GetLootSlotLink) == "function"
end

function LootLearner.Store()
  if not ns.db then return nil end
  ns.db.lootSeen = ns.db.lootSeen or {}
  return ns.db.lootSeen
end

-- "Creature-0-1-2-3-116-0000ABCD" -> "creature", 116. Pure.
function LootLearner.ParseGUID(guid)
  if type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if not kind then return nil end
  if kind == "Creature" or kind == "Vehicle" then return "creature", tonumber(id) end
  if kind == "GameObject" then return "object", tonumber(id) end
  return nil
end

local function itemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hitem:(%d+)") or link:match("^item:(%d+)"))
end

local function sourceName(kind, id, guid)
  if kind == "creature" then
    local target = call(_G.UnitGUID, "target")
    if target == guid then
      local name = call(_G.UnitName, "target")
      if type(name) == "string" and name ~= "" then return name end
    end
    local npc = ns.ClassicDB and ns.ClassicDB.Npc(id)
    return npc and npc.name or nil
  end
  local object = ns.ClassicDB and ns.ClassicDB.Object(id)
  return object and object.name or nil
end

local function place()
  local mapID, x, y = Compat.PlayerPosition and Compat.PlayerPosition()
  local zone = call(_G.GetZoneText)
  return mapID, x and math.floor(x * 1000 + 0.5) / 1000 or nil, y and math.floor(y * 1000 + 0.5) / 1000 or nil,
    type(zone) == "string" and zone ~= "" and zone or nil
end

local function bump(list, itemID, quantity)
  local entry = list[itemID]
  if not entry then entry = { times = 0, quantity = 0 } list[itemID] = entry end
  entry.times = entry.times + 1
  entry.quantity = entry.quantity + (quantity or 1)
end

-- Reads the open loot window. Returns the number of items recorded.
function LootLearner.ReadLoot()
  if not LootLearner.IsAvailable() then return 0 end
  local store = LootLearner.Store()
  if not store then return 0 end
  local fishing = call(_G.IsFishingLoot) == true
  local mapID, x, y, zone = place()
  local recorded = 0
  local touched = {}
  local slots = tonumber(call(_G.GetNumLootItems)) or 0
  for slot = 1, slots do
    local itemID = itemIDFromLink(call(_G.GetLootSlotLink, slot))
    if itemID then
      local sources = { call(_G.GetLootSourceInfo, slot) }
      if fishing then
        sources = { "fishing:" .. tostring(zone or mapID or "?"), select(3, call(_G.GetLootSlotInfo, slot)) or 1 }
      end
      for i = 1, #sources, 2 do
        local guid, quantity = sources[i], tonumber(sources[i + 1]) or 1
        local kind, id = LootLearner.ParseGUID(guid)
        local key
        if fishing then
          kind, key = "fishing", "f:" .. tostring(zone or mapID or "?")
        elseif kind == "creature" then
          key = "c:" .. id
        elseif kind == "object" then
          key = "o:" .. id
        end
        local seenKey = key and (tostring(guid) .. "#" .. itemID)
        if key and not LootLearner.counted[seenKey] then
          LootLearner.counted[seenKey] = true
          local entry = store[key]
          if not entry then
            entry = { kind = kind, items = {}, skinned = {}, looted = 0 }
            store[key] = entry
          end
          entry.name = entry.name or (fishing and zone) or sourceName(kind, id, guid)
          entry.zone, entry.mapID, entry.x, entry.y = zone or entry.zone, mapID or entry.mapID, x or entry.x, y or entry.y
          entry.seenAt = Util.Now()
          -- A corpse looted again after its first loot window: skinning (or herb / ore on a corpse).
          local first = LootLearner.counted[tostring(guid)]
          if not first or first == LootLearner.session then
            if not first then
              LootLearner.counted[tostring(guid)] = LootLearner.session
              entry.looted = entry.looted + 1
            end
            bump(entry.items, itemID, quantity)
          else
            bump(entry.skinned, itemID, quantity)
          end
          touched[guid] = true
          recorded = recorded + 1
        end
      end
    end
  end
  if recorded > 0 then
    LootLearner.index = nil
    Events.Debounce("loot-learned", 0.5, function() Events.Fire("FP_LOOT_LEARNED") end)
  end
  return recorded
end

-- A loot window closing ends that window's session: the next window on the
-- same corpse is a second loot (skinning).
function LootLearner.CloseLoot()
  LootLearner.session = (LootLearner.session or 0) + 1
end

-- itemID -> { { key, entry, times, quantity, skinned } }, built on demand.
local function buildIndex()
  local index = {}
  for key, entry in pairs(LootLearner.Store() or {}) do
    for itemID, seen in pairs(entry.items or {}) do
      index[itemID] = index[itemID] or {}
      table.insert(index[itemID], { key = key, entry = entry, times = seen.times, quantity = seen.quantity })
    end
    for itemID, seen in pairs(entry.skinned or {}) do
      index[itemID] = index[itemID] or {}
      table.insert(index[itemID], { key = key, entry = entry, times = seen.times, quantity = seen.quantity, skinned = true })
    end
  end
  for _, list in pairs(index) do
    table.sort(list, function(a, b)
      local ra = a.times / math.max(1, a.entry.looted or 1)
      local rb = b.times / math.max(1, b.entry.looted or 1)
      if ra ~= rb then return ra > rb end
      return a.key < b.key
    end)
  end
  LootLearner.index = index
  return index
end

-- Resolver hints for what this account has looted (learned = true).
function LootLearner.ItemHints(itemID)
  local out = {}
  local list = (LootLearner.index or buildIndex())[tonumber(itemID) or 0]
  for i, seen in ipairs(list or {}) do
    if i > LootLearner.MAX_HINTS then break end
    local entry = seen.entry
    local id = tonumber(seen.key:match("^%a:(%d+)$"))
    local name = entry.name or ((entry.kind == "creature" and "NPC " or "Object ") .. tostring(id or seen.key))
    local looted = math.max(1, entry.looted or 1)
    local kind, label, short, skill
    if entry.kind == "fishing" then
      kind, skill, label, short = "gather", "Fishing", "Fished in " .. name, "Fish: " .. name
    elseif seen.skinned then
      kind, skill, label, short = "gather", "Skinning", "Skinned from " .. name, "Skin: " .. name
    elseif entry.kind == "object" then
      kind, label, short = "drop", "Looted from " .. name, "Loot: " .. name
    else
      kind, label, short = "drop", "Dropped by " .. name, "Drop: " .. name
    end
    out[#out + 1] = {
      kind = kind, skill = skill, learned = true, boss = entry.kind == "creature" and name or nil, npcID = entry.kind == "creature" and id or nil,
      mapID = entry.mapID, x = entry.x, y = entry.y, zone = entry.zone, label = label, short = short,
      chance = math.floor(seen.times * 10000 / looted + 0.5),
      detail = string.format("%s - seen %d time%s in %d loot%s on Forever", entry.zone or "?", seen.times, seen.times == 1 and "" or "s",
        looted, looted == 1 and "" or "s"),
    }
  end
  return out
end

function LootLearner.Count()
  local sources, items = 0, {}
  for _, entry in pairs(LootLearner.Store() or {}) do
    sources = sources + 1
    for itemID in pairs(entry.items or {}) do items[itemID] = true end
    for itemID in pairs(entry.skinned or {}) do items[itemID] = true end
  end
  return sources, Util.Count(items)
end

function LootLearner.Status()
  if not LootLearner.IsAvailable() then return "Loot learner: the loot window API is unavailable on this client." end
  local sources, items = LootLearner.Count()
  return string.format("Loot learner: %d item%s seen from %d creature%s, object%s and fishing spot%s on this account.", items, items == 1 and "" or "s",
    sources, sources == 1 and "" or "s", sources == 1 and "" or "s", sources == 1 and "" or "s")
end

function LootLearner.Init()
  LootLearner.session = 1
  Events.RegisterWoW("LOOT_READY", function() LootLearner.ReadLoot() end)
  Events.RegisterWoW("LOOT_OPENED", function() LootLearner.ReadLoot() end)
  Events.RegisterWoW("LOOT_CLOSED", function() LootLearner.CloseLoot() end)
  Log.Debug("%s", LootLearner.Status())
end
